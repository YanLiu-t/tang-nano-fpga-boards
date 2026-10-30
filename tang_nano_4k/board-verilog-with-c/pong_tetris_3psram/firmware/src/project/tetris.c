/*
 * tetris.c - Tetris, implemented ENTIRELY in C on top of the game-agnostic
 * fabric (same HAL as pong.c; build THIS file instead of pong.c).
 *
 * Division of labour, exactly as for Pong:
 *   fabric : 640x480@60 out of a 320x240x8bpp INDEXED framebuffer (upscaled
 *            2x in both directions), 16-entry palette, 5 generic rectangles,
 *            8-key shift register, and a TRIPLE-buffered display. Nothing else.
 *   this C : the playfield and the settled blocks, the FALLING piece, the
 *            HOLD / NEXT panels and the landing preview / ghost - ALL baked
 *            into the framebuffer, because every one of them is now a SHADED
 *            cell (a bright highlight in its top-left corner) and a fabric
 *            rectangle can only fill a flat colour. Plus all seven shapes,
 *            rotation, collision, gravity, line clearing, scoring, and the
 *            SIDE PANELS that the reference screen shows: HOLD + SCORE dW+
 *            LEVEL + LINES down the left edge and a three-deep NEXT strip
 *            across the top right.
 *
 * THE SHADED CELL - what "not a flat colour" means here
 *   The palette is 16 entries FIXED IN VERILOG (palette_ram.v, raddr =
 *   pix_idx[3:0]) and GW1NSR-4C has no register headroom left to widen it, so
 *   the shading cannot come from more colourws. It comes from GEOMETRY instead:
 *   every cell is drawn as the piece's own colour with a bright triangle in its
 *   top-left corner (index 1, white), on the diagonal - which reads as a bevel
 *   and a specular highlight - while its last row and last column stay the
 *   background colour, i.e. the dark seam that separates one little square from
 *   the next. One cell, one function: cell_body().
 *
 *   Because the falling piece is baked with the VERY SAME cell as a settled
 *   block, locking is pixel-identical and needs no repaint of its own - which is
 *   what makes baking it affordable (it is the two or three blocks of the box
 *   it vacated, staged through piece_sync()).
 *
 * All coordinates below are in the LOW-RESOLUTION 320x240 space: the fabric
 * doubles them for you, so nothing here ever mentions 640x480.
 *
 * KEYBOARD: the eight keys keep the SAME meaning they have in the reference
 *   firmware, so every key does here what it does there. The playing cluster
 *   K1..K4 = register bits 0..3, laid out left to right as K1, K2, K3, K4:
 *   K1 left, K3 right, K2 (up) rotates clockwise, K4 (down) soft-drops.
 *   K5 slams the piece down (hard drop), K6 swaps it with the HOLD slot,
 *   K7 rotates counter-clockwise and K8 pauses. After a top-out the GAME OVER
 *   words flash for a moment and then give way to PRESS TO CONTINUE, which
 *   blinks in the same place; ANY key then starts a fresh game.
 *   read_keys() returns a mask that is 1 for a pressed key regardless of the
 *   register's polarity (it is auto-calibrated at boot).
 * Remap by editing the #defines below only - nothing else depends on it.
 */
#include "game_hal.h"

/* ------------------------------------------------------------------ */
/* Keys: register bit n of the 74HC165 chain. read_keys() masks each bit */
/* to 1 while pressed; the bit assignments below match the reference     */
/* firmware exactly.                                                     */
/*   K1 = move left (held, DAS)     K3 = move right (held, DAS)          */
/*   K2 = rotate CW (press)         K4 = soft drop (held)                */
/*   K5 = hard drop (press)         K6 = hold / swap (press, once/piece) */
/*   K7 = rotate CCW (press)        K8 = pause toggle                    */
/* Remap by editing these #defines only - nothing else depends on them. */
/* ------------------------------------------------------------------ */
#define KEY_LEFT        0       /* K1  move left                   */
#define KEY_ROT_CW      1       /* K2  rotate clockwise            */
#define KEY_RIGHT       2       /* K3  move right                  */
#define KEY_SOFT_DROP   3       /* K4  drop one row while held     */
#define KEY_HARD_DROP   4       /* K5  slam down + lock            */
#define KEY_HOLD        5       /* K6  hold / swap the piece       */
#define KEY_ROT_CCW     6       /* K7  rotate counter-clockwise    */
#define KEY_PAUSE       7       /* K8  pause toggle                */
#define KEYS_USED       8       /* bits 0..7 are all read          */

/* ------------------------------------------------------------------ */
/* Palette (16 x RGB444). Every value is nibble-aligned (only the high  */
/* nibble of each byte survives: level = byte >> 4). The layout matches */
/* the reference screen: one background, a blue field with a lighter    */
/* grid, a bright border, near-black panel interiors, white text, and   */
/* the seven tetromino colours.                                         */
/* ------------------------------------------------------------------ */
#define IDX_BG0         0               /* screen background            */
#define IDX_HILITE      1               /* every cell's highlight corner */
#define IDX_FIELD       2               /* field interior               */
#define IDX_GRID        3               /* field grid lines             */
#define IDX_BLACK       4               /* (unused now - the banner has no box) */
#define IDX_BORDER      5               /* field / panel outlines       */
#define IDX_I           6
#define IDX_O           7
#define IDX_T           8
#define IDX_S           9
#define IDX_Z           10
#define IDX_J           11
#define IDX_L           12
#define IDX_TEXT        14              /* labels + values              */
#define IDX_PANEL_BG    15              /* HOLD / NEXT box interior     */
#define PIECE_BASE      IDX_I           /* board value = PIECE_BASE + type */

static const uint32_t tetris_pal[16] = {
    0x081030u,   /* 0  background (behind the well and the panels)       */
    0xF0F0F0u,   /* 1  block highlight - the bright top-left corner that
                        makes every cell read as a bevelled little square  */
    0x101040u,   /* 2  field interior                                    */
    0x202058u,   /* 3  grid                                               */
    0x000000u,   /* 4  pure black (unused now)                            */
    0xC0C8E0u,   /* 5  border / box outline                              */
    0x00E0E0u,   /* 6  I    cyan                                          */
    0xE0E000u,   /* 7  O    yellow                                        */
    0xA000E0u,   /* 8  T    purple                                        */
    0x00C030u,   /* 9  S    green                                         */
    0xE02020u,   /* 10 Z    red                                           */
    0x2050E0u,   /* 11 J    blue                                          */
    0xE08000u,   /* 12 L    orange                                        */
    0x505878u,   /* 13 unused (dim)                                       */
    0xF0F0F0u,   /* 14 text                                               */
    0x181828u    /* 15 HOLD / NEXT box interior                           */
};

/* ------------------------------------------------------------------ */
/* Geometry (all in C - the fabric knows none of it), in 320x240 pixels.*/
/* Cells are a touch wider than tall (9 x 8), which is what makes the   */
/* 10 x 20 well come out the same shape as the reference screen.        */
/* ------------------------------------------------------------------ */
#define COLS            10
#define ROWS            20
#define CELLX           9
#define CELLY           8
#define X0              120     /* well interior: x 120 .. 209                 */
#define Y0              46      /*                 y  46 .. 205                 */
#define BORDER          2       /* field outline thickness                      */
#define PB              2       /* panel box outline thickness                  */

/* --- HOLD box (top-left) --- */
#define HX0             42
#define HY0             54
#define HW              46
#define HH              22
#define HCELL           8

/* --- NEXT strip (top-right): three pieces side by side --- */
#define NX0             218
#define NY0             54
#define NW              96
#define NH              22
#define NCELL           7
#define NSLOT           30
#define NBX0            (NX0 + PB + 1)      /* first slot's left edge */

/* --- Text anchors (label top-left corners; values are scaled 2x) --- */
#define HLX             44
#define HLY             44
#define NLX             218
#define NLY             44
#define SLX             12
#define SLY             82
#define SVX             44
#define SVY             94
#define LLX             12
#define LLY             114
#define LVX             44
#define LVY             126
#define ILX             12
#define ILY             146
#define IVX             44
#define IVY             158

#define VAL_W           72      /* widest value row (6 digits, scale 2)  */
#define VAL_H           14      /* tallest value row (7 px, scale 2)     */

/* --- GAME OVER banner / PRESS TO CONTINUE prompt (baked text; game_pixel) ---
   The topped-out screen used to flash a flat hardware bar (100x20 px). The
   bar is gone and so is the black box that briefly replaced it: the banner is
   now the WORDS ALONE, drawn in RED straight over the well with NOTHING behind
   them, using the same 5x7 font the labels use, at 3x - nine glyphs on a
   6*3 px grid = 162x21 px, centred in the well. The words then give way, in
   the same band, to PRESS TO CONTINUE at 2x. Any pixel that is not a lit
   glyph keeps whatever the field/panel would put there, so neither string
   ever covers the picture. */
#define GO_STR          "GAME OVER"
#define GO_N            9
#define GO_SC           3
#define GO_W            (GO_N * 6 * GO_SC)                   /* 162 */
#define GO_H            (7 * GO_SC)                          /* 21  */
#define GO_X            (X0 - (GO_W - COLS * CELLX) / 2)     /* 84  */
#define GO_Y            (Y0 + (ROWS * CELLY - GO_H) / 2)     /* 115 */

/* --- the PRESS TO CONTINUE prompt, which replaces the banner in place ---
   After the GAME OVER words have flashed for GO_HOLD frames they go out and
   the SAME band carries PRESS TO CONTINUE instead, blinking the same way,
   until any key starts a new game. Seventeen glyphs at 2x are 204 px wide,
   wider than the well, so the prompt is centred ON THE WELL exactly as the
   GAME OVER words are: the two share one centre and the words appear to turn
   into the prompt in place. Same rule as the banner - red glyph pixels only,
   nothing painted behind them. */
#define PC_STR          "PRESS TO CONTINUE"
#define PC_N            17
#define PC_SC           2
#define PC_W            (PC_N * 6 * PC_SC)                    /* 204 */
#define PC_H            (7 * PC_SC)                          /* 14  */
#define PC_X            (X0 + (COLS * CELLX - PC_W) / 2)      /* 63  */
#define PC_Y            (GO_Y + (GO_H - PC_H) / 2)            /* 118 */

/* The banner's ONE rect: the union of both strings, so a blink flip OR the
   phase turn-over each cost a single repaint of this box. The prompt is the
   wider of the two and PC_Y sits inside GO_Y..GO_Y+GO_H-1, so it bounds it. */
#define BAN_X           PC_X
#define BAN_Y           GO_Y
#define BAN_W           PC_W
#define BAN_H           GO_H

#define GO_HOLD          96             /* frames the GAME OVER words flash before
                                           the prompt takes their place. The blink
                                           is 16 lit + 16 dark = one 32-frame
                                           cycle (see blink_cnt in the main loop),
                                           so 96 = exactly THREE flashes          */
#define GO_GUARD         60             /* frames the prompt must be up before
                                           any key may start a new game (~1 s)*/

#define GRAV_FRAMES     2               /* fall one row every ~0.033 s @ L0 */
#define DAS_INITIAL     3               /* frames held before auto-repeat   */
#define DAS_REPEAT      1               /* frames between repeats           */
#define SOFT_REPEAT     2               /* frames per row while K4 held     */

#define LINES_PER_LEVEL 3       /* lines to clear for the next level */

/* ------------------------------------------------------------------ */
/* Tetromino shapes: the 4 cells of rotation 0, in a 4x4 box. Rotations */
/* are generated by rotating (x,y) -> (3-y, x) and normalising.        */
/* ------------------------------------------------------------------ */
typedef struct { int8_t x, y; } Cell;

static const Cell piece0[7][4] = {
    { {0,1},{1,1},{2,1},{3,1} },   /* I */
    { {1,0},{2,0},{1,1},{2,1} },   /* O */
    { {1,0},{0,1},{1,1},{2,1} },   /* T */
    { {1,0},{2,0},{0,1},{1,1} },   /* S */
    { {0,0},{1,0},{1,1},{2,1} },   /* Z */
    { {0,0},{0,1},{1,1},{2,1} },   /* J */
    { {2,0},{0,1},{1,1},{2,1} }    /* L */
};

static void piece_cells(int type, int rot, Cell out[4])
{
    Cell c[4];
    int i, k;
    for (i = 0; i < 4; i++) c[i] = piece0[type][i];
    if (type != 1) {                            /* O never rotates */
        for (k = 0; k < rot; k++) {
            Cell t[4];
            for (i = 0; i < 4; i++) { t[i].x = (int8_t)(3 - c[i].y); t[i].y = c[i].x; }
            for (i = 0; i < 4; i++) c[i] = t[i];
        }
    }
    {   /* normalise to the top-left of the bounding box (stable rotation) */
        int8_t mnx = 9, mny = 9;
        for (i = 0; i < 4; i++) {
            if (c[i].x < mnx) mnx = c[i].x;
            if (c[i].y < mny) mny = c[i].y;
        }
        for (i = 0; i < 4; i++) { c[i].x -= mnx; c[i].y -= mny; }
    }
    for (i = 0; i < 4; i++) out[i] = c[i];
}

/* ------------------------------------------------------------------ */
/* State                                                               */
/* ------------------------------------------------------------------ */
static uint8_t board[ROWS][COLS];      /* 0 = empty, else a PIECE_BASE+type */
static int   cur_type, cur_rot, cur_x, cur_y;
static Cell  cur_cells[4];
static int   pmax_x, pmax_y;           /* the falling piece's own bounding box,
                                          in cells - the cheap box reject in
                                          front of the four-cell loop, exactly
                                          as ghost_w/ghost_h are for the ghost */
static int   nextq[3];                 /* the next three piece types        */
static int   hold_type;                /* -1 = empty (no key bound yet)     */
static int   hold_used;
static uint32_t score;
static int   lines_cleared;
static int   level;
static int   game_over;
static int   paused;                   /* K6/K7/K8 freeze the game (toggle) */
static int   go_shown;                 /* 1 = the baked GAME OVER banner is lit
                                          in this blink phase (see game_pixel) */
static int   go_phase;                 /* 0 = the GAME OVER words are up,
                                          1 = the PRESS TO CONTINUE prompt is  */
static int   go_frames;                /* frames since the top-out began       */
static int   ban_state;                /* last banner CONTENT pushed into the
                                          buffers: (go_shown | go_phase << 1).
                                          -1 = nothing is drawn there yet, which
                                          is what forces the first repaint     */
static int   blink_cnt;                /* free-running frame counter every blink
                                          phase is derived from (the banner, and
                                          the pause icon in publish_sprites)   */
static int   running;                  /* 0 = idle screen, 1 = playing */
static int   spawn_delay;              /* frames the just-locked piece stays
                                          the "current" piece: it is still in
                                          the board (a locked block draws the
                                          same pixels), so those frames exist
                                          only to let the baked block reach all
                                          three buffers before the next piece
                                          starts replacing it                 */
static int   ghost_on;                 /* 1 = landing preview is baked into the
                                          framebuffers right now              */
static int   ghost_row;                /* its landing row, in cell units      */
static int   ghost_w, ghost_h;         /* its bounding box, in cells          */
static int   gbx1 = -1, gby1, gbx2, gby2;  /* pixel bbox it was last baked at */
static int   gbt = -1, gbro, gbrow, gbcol; /* what it was: type, rotation,
                                              landing row and column        */
static int   pcb1 = -1, pby1, pcb2, pby2;  /* the FALLING piece: the pixel bbox
                                              piece_sync() last baked it at  */
static int   pbt = -1, pbro, pbx, pby;     /* ...and the type, rotation and cell
                                              x/y it was baked for. The SHAPE
                                              has to be part of the test: a
                                              rotation can leave the box where
                                              it was (an O turning, or a T
                                              turned inside its own 3x2) yet
                                              move the cells within it       */
static int   grav_cnt, das_dir, das_cnt, soft_cnt;
static uint32_t rng_state = 0x1234ABCDu;

/* Install a set of cells AND the bounding box that belongs to them. EVERY
   change of shape has to come through here. pmax_x / pmax_y are not just a
   centring aid: game_pixel() rejects with that box before it walks the four
   cells, and piece_sync() repaints exactly that box, so a box left behind by
   the PREVIOUS rotation clips the piece's own drawing - rotating to a taller
   shape used to lose its bottom row, and where that missing cell landed inside
   the ghost, the ghost's hollow interior was painted over it too, i.e. a bite
   taken out of BOTH the piece and the landing preview. */
static void set_cells(const Cell c[4])
{
    int i, w = 0, h = 0;
    for (i = 0; i < 4; i++) {
        cur_cells[i] = c[i];
        if (c[i].x > w) w = c[i].x;
        if (c[i].y > h) h = c[i].y;
    }
    pmax_x = w;
    pmax_y = h;
}

/* ------------------------------------------------------------------ */
/* Sound. REG_BEEP's bit is fanned straight to the buzzer pin with no   */
/* fabric tone hardware, so the firmware's SysTick ISR flips the bit    */
/* every half-period of the current note - a clean square wave.         */
/*                                                                      */
/* There is ONE voice: exactly one thing can sound at a time, so the    */
/* rule is the arcade machine's. The music owns the buzzer; a one-shot  */
/* effect TAKES it away for its whole length and then hands it back,    */
/* and the music picks up on the note it was cut off in rather than     */
/* starting over. The line-clear glissando is the effect that rule      */
/* exists for: the music goes SILENT for the whole run, so the clear is */
/* unmistakable, and comes back the moment the run is over.             */
/*                                                                      */
/* The line-clear run is also the ONE thing here that does NOT get the  */
/* articulation gate (see GATE_TICKS below): short fast notes read as a */
/* glissando already, whereas the sustained notes of the music and the  */
/* jingle ran into each other with no gap and came out as one buzz.     */
/* ------------------------------------------------------------------ */
#define FCPU        27000000UL     /* M3 core clock (27 MHz board crystal) */

/* 30 kHz, not 20: a half-period is an integer count of ISR ticks, so the
   pitch error is +-1/(2*half), and at 20 kHz the tune's top octave was
   audibly out - G5 came out 833 Hz and A5 909 Hz, 3 to 6% sharp, i.e.
   most of a semitone on the melody's most exposed notes. At 30 kHz every
   note of both tunes lands within ~2%. */
#define SND_RATE    30000UL        /* SysTick interrupts per second        */

/* note frequencies (Hz, integer - close enough for a buzzer); the sharps
   are needed by the line-clear glissando run and by the game-over theme's
   chromatic turn, and E3 by its closing fall */
#define N_B3  247
#define N_E3  165
#define N_CS4 277
#define N_D4  294
#define N_E4  330
#define N_FS4 370
#define N_G4  392
#define N_GS4 415
#define N_A4  440
#define N_AS4 466
#define N_B4  494
#define N_C5  523
#define N_CS5 554
#define N_D5  587
#define N_DS5 622
#define N_E5  659
#define N_F5  698
#define N_FS5 740
#define N_G5  784
#define N_GS5 831
#define N_A5  880
#define N_AS5 932
#define N_B5  988
#define N_C6 1047
#define N_E6 1319

/* a note = half-period in ticks (0 = rest) + duration in ticks */
typedef struct { uint16_t half; uint16_t ticks; } Note;

/* The half-period is the only place intonation is decided, so it ROUNDS:
   dividing straight down is what put G5 at 833 Hz instead of 784.
   Durations count 16ths of a beat at SND_BPM so the tune keeps its own
   rhythm instead of drifting, which a fixed ms per note type does. */
#define SND_BPM     140
#define T16         ((uint32_t)((SND_RATE * 60u) / ((uint32_t)SND_BPM * 16u)))

#define NOTE(f, n)   { (uint16_t)((SND_RATE + (f)) / (2u * (f))), \
                       (uint16_t)(T16 * (n)) }      /* n = 16ths of a beat */
#define REST(n)      { 0, (uint16_t)(T16 * (n)) }

/* Background music: Korobeiniki - the classic tetromino theme, and the one
   the machine itself plays. These are its eight opening bars, i.e. the
   phrase everyone knows. At 140 BPM that is 32 beats = 13.7 s, the "10-15 s
   of repetition" asked for, and it loops on a resolution (bars 4 and 8 both
   land on A), so the seam never sounds cut off. */
static const Note bgm[] = {
    /* 1 */ NOTE(N_E5,16), NOTE(N_B4,8),  NOTE(N_C5,8),
            NOTE(N_D5,16), NOTE(N_C5,8),  NOTE(N_B4,8),
    /* 2 */ NOTE(N_A4,16), NOTE(N_A4,8),  NOTE(N_C5,8),
            NOTE(N_E5,16), NOTE(N_D5,8),  NOTE(N_C5,8),
    /* 3 */ NOTE(N_B4,24), NOTE(N_C5,8),
            NOTE(N_D5,16), NOTE(N_E5,16),
    /* 4 */ NOTE(N_C5,16), NOTE(N_A4,16), NOTE(N_A4,16), REST(16),
    /* 5 */ NOTE(N_D5,24), NOTE(N_F5,8),
            NOTE(N_A5,16), NOTE(N_G5,8),  NOTE(N_F5,8),
    /* 6 */ NOTE(N_E5,24), NOTE(N_C5,8),
            NOTE(N_E5,16), NOTE(N_D5,8),  NOTE(N_C5,8),
    /* 7 */ NOTE(N_B4,16), NOTE(N_B4,8),  NOTE(N_C5,8),
            NOTE(N_D5,16), NOTE(N_E5,16),
    /* 8 */ NOTE(N_C5,16), NOTE(N_A4,16), NOTE(N_A4,16), REST(16),
};

/* Line clear: a pianist's glissando. A real one is a rapid run over
   separate keys rather than a bend, so on a one-bit buzzer a run IS the
   effect: thirteen chromatic steps C5..C6 at ~53 ms each, ~0.7 s in all. */
static const Note fx_line[] = {
    NOTE(N_C5,2),  NOTE(N_CS5,2), NOTE(N_D5,2),  NOTE(N_DS5,2),
    NOTE(N_E5,2),  NOTE(N_F5,2),  NOTE(N_FS5,2), NOTE(N_G5,2),
    NOTE(N_GS5,2), NOTE(N_A5,2),  NOTE(N_AS5,2), NOTE(N_B5,2),
    NOTE(N_C6,2),
};

/* Level up: the Super Mario Bros. COIN - the two-note "ding" the ? block
   makes when Mario bumps a coin out of it, B5 up to the higher E6, ~0.27 s
   in all. It is queued to play the MOMENT the line-clear glissando above
   finishes (see sound_fx_after), so the two never overlap: the run reads as
   "lines gone", the ding as "level up". Bright and short, in a register the
   glissando has already left, so it cannot be mistaken for its last notes. */
static const Note fx_level[] = {
    NOTE(N_B5,3), NOTE(N_E6,7),
};

/* Game over: the SUPER MARIO BROS. "Game Over" screen theme - the slow,
   mournful phrase Koji Kondo wrote for the screen that comes up once the
   player's lives have run out. NOT the short "player down" jingle that
   plays on every single lost life (that one is a quick rising/falling
   flourish); this is the longer dirge that follows it, and nothing here is
   a note of the background music.
   Twelve notes in three gestures: a held high C with its fifth and third,
   a chromatic turn down around A (A B A G# A# G#), then a drop that settles
   on a LOW held G over the low E. At 140 BPM these 200 16ths-of-a-beat run
   ~5.4 s, and a REST(24) rounds the phrase out to ~6 s - the "first six
   seconds" asked for - then it LOOPS, because the topped-out screen stays up
   until the player starts a new game and a one-shot would leave them in
   silence. A close approximation of the original, not a note-for-note
   transcription. */
static const Note fx_over[] = {
    /* the opening gesture: a high C, its fifth, and its third */
    NOTE(N_C5,24), NOTE(N_G4,24), NOTE(N_E4,16),
    /* the chromatic turn around A, one key at a time */
    NOTE(N_A4,12), NOTE(N_B4,12), NOTE(N_A4,12),
    NOTE(N_GS4,12), NOTE(N_AS4,12), NOTE(N_GS4,12),
    /* the closing fall: down to the low E and a long held G over it */
    NOTE(N_G4,8),  NOTE(N_E3,8),  NOTE(N_G4,48),
    REST(24),                  /* the pause that makes the loop land on ~6 s */
};

#define BGM_N   ((uint16_t)(sizeof(bgm)      / sizeof(bgm[0])))
#define FXL_N   ((uint16_t)(sizeof(fx_line)  / sizeof(fx_line[0])))
#define LVL_N   ((uint16_t)(sizeof(fx_level) / sizeof(fx_level[0])))
#define OVR_N   ((uint16_t)(sizeof(fx_over)  / sizeof(fx_over[0])))

#define SM_IDLE 0               /* nothing on the buzzer                  */
#define SM_BGM  1               /* the music                              */
#define SM_FX   2               /* a one-shot that stole the buzzer       */
#define SM_OVER 3               /* the topped-out jingle, looped          */

static const Note *snd_seq;
static uint16_t snd_len, snd_pos;
static uint32_t snd_left;        /* ticks left in the current note        */
static uint32_t snd_half;        /* current note half-period ticks         */
static uint32_t snd_half_left;   /* ticks until the next buzzer flip       */
static uint8_t  snd_level;
static uint8_t  snd_mode;
static uint16_t snd_gap;         /* ticks of silence at a resume seam       */

/* Where the music was when a one-shot took the buzzer away: the note and what
   was left of it. The carrier is deliberately NOT restored mid-cycle - the
   seam gets a gap and a clean start instead (see snd_after_fx). */
static uint16_t r_pos;
static uint32_t r_left, r_half, r_half_left;
static uint8_t  r_valid;

/* A one-shot queued to follow the one-shot that is playing right now - a
   single slot, because the game only ever chains one thing (the level-up
   ding after the line-clear run). It is not part of the music resume, so a
   new tune or the game-over theme simply forgets it. */
static const Note *snd_next_seq;
static uint16_t snd_next_len;
static uint8_t  snd_next_valid;

/* The buzzer register is a plain LEVEL that the fabric keeps between writes
   (apb_fb_reg.v: beep_trig <= pwdata[0], no auto-clear), so writing the value
   it already holds does nothing except burn an APB write - and rests and idle
   used to write 0 thirty thousand times a second. Mirror the pin here and
   only touch the register when it actually has to move. */
static uint8_t beep_lvl;

static void beep_out(int level)
{
    uint8_t v = (uint8_t)(level ? 1u : 0u);
    if (v != beep_lvl) {
        beep_lvl = v;
        beep_set((int)v);
    }
}

/* Articulation. A one-bit buzzer has no volume envelope, so notes running
   straight into one another read as one continuous buzz - that is what the
   music sounded like. Hold the level at 0 over the last ~13 ms of every note
   in the music and the jingle, which separates them without touching the
   tune. The cut is deferred to the end of the half-cycle in progress, so the
   waveform stops on a zero crossing instead of mid-cycle (which is a click,
   and the old code's per-note cut landed mid-cycle). The line-clear run is
   EXEMPT: its notes are short and fast, its whole point is the continuous
   glissando, and it already reads clearly. */
#define GATE_TICKS  400         /* ~13 ms at SND_RATE */

static void snd_begin(const Note *seq, uint16_t len)
{
    snd_seq = seq; snd_len = len;
    snd_pos = 0;
    snd_level = 0;
    snd_half = seq[0].half;
    snd_left = seq[0].ticks;
    snd_half_left = snd_half;
    beep_out(0);
}

/* The music, from the top. */
static void sound_start_bgm(void)
{
    r_valid = 0;                     /* a fresh tune is not a resume        */
    snd_next_valid = 0;              /* ...and it drops any queued one-shot */
    snd_mode = SM_BGM;
    snd_begin(bgm, BGM_N);
}

/* The topped-out jingle, from the top; the ISR loops it in place. */
static void sound_over(void)
{
    r_valid = 0;
    snd_next_valid = 0;
    snd_mode = SM_OVER;
    snd_begin(fx_over, OVR_N);
}

/* A one-shot effect: it owns the buzzer for its whole length, which is what
   makes the line-clear glissando audible on its own with the music silent
   underneath. A second effect while one is already playing just replaces it
   and keeps the ORIGINAL resume point. */
static void sound_fx(const Note *seq, uint16_t len)
{
    if (snd_mode == SM_BGM) {
        r_pos = snd_pos; r_left = snd_left; r_half = snd_half;
        r_half_left = snd_half_left;
        r_valid = 1;
    }
    snd_mode = SM_FX;
    snd_begin(seq, len);
}

/* Queue a one-shot to start the moment the effect already on the buzzer ends,
   so the two play back to back instead of the second cutting the first off.
   If nothing is playing it just plays it now. This is how the level-up ding
   follows the line-clear run without a gap and without overlap. */
static void sound_fx_after(const Note *seq, uint16_t len)
{
    if (snd_mode == SM_FX) {
        snd_next_seq   = seq;
        snd_next_len   = len;
        snd_next_valid = 1;
        return;
    }
    sound_fx(seq, len);
}

/* Called from the ISR when a one-shot runs out: hand the buzzer back. */
static void snd_after_fx(void)
{
    if (snd_next_valid) {
        /* a queued one-shot takes the buzzer next; no resume fiddling - the
           music is still parked in r_valid and will get its seam when the
           LAST of the chain finishes */
        snd_next_valid = 0;
        snd_begin(snd_next_seq, snd_next_len);
        /* Same seam gap as the music resume below, for the same reason: the
           first one-shot's last note was cut mid-cycle, so start on a period
           boundary from level 0 after a silent gate. It also separates the
           two effects, which is the point of queuing rather than chaining
           them inside one table. */
        snd_gap = GATE_TICKS;
        return;
    }
    if (r_valid) {
        r_valid  = 0;
        snd_mode = SM_BGM;
        snd_seq  = bgm;
        snd_len  = BGM_N;
        snd_pos  = r_pos;
        snd_left = r_left;
        snd_half = r_half;
        snd_half_left = r_half_left;
        /* Resume seam. Hold silence for one gate before the music comes back
           and start the carrier on a period boundary from level 0: without
           this the effect's last note ran straight into the resumed one at
           whatever phase it had been cut in, and the restored level could
           disagree with the pin by half a period, so the first flip was a
           write that changed nothing and the low half stretched. That click
           is what was heard as noise the moment the music reappeared. ~13 ms
           is not heard as a pause, but the seam stops being audible. */
        snd_level = 0;
        snd_half_left = snd_half;
        snd_gap = GATE_TICKS;
        return;
    }
    snd_mode = SM_IDLE;
    snd_seq  = 0;
    beep_out(0);
}

static void sound_init(void)
{
    r_valid  = 0;
    snd_mode = SM_IDLE;
    snd_seq  = 0;
    snd_gap  = 0;
    beep_lvl = 0;                    /* reset matches the pin's power-up 0 */
    SysTick->CTRL = 0u;
    SysTick->LOAD = (uint32_t)(FCPU / SND_RATE) - 1u;
    SysTick->VAL  = 0u;
    SysTick->CTRL = SysTick_CTRL_CLKSOURCE_Msk |
                    SysTick_CTRL_TICKINT_Msk   |
                    SysTick_CTRL_ENABLE_Msk;
}

void SysTick_Handler(void)
{
    uint32_t half;

    if (!snd_seq) { beep_out(0); return; }

    /* Resume seam (see snd_after_fx): hold silence, and FREEZE the resumed
       note while the gap counts out - its remaining ticks must not burn. */
    if (snd_gap) { --snd_gap; beep_out(0); return; }

    if (--snd_left == 0u) {
        snd_pos++;
        if (snd_pos >= snd_len) {
            if (snd_mode == SM_FX) {   /* one-shot over -> music resumes */
                snd_after_fx();
                return;
            }
            snd_pos = 0;               /* music and jingle loop in place */
        }
        snd_half      = snd_seq[snd_pos].half;
        snd_left      = snd_seq[snd_pos].ticks;
        snd_half_left = snd_half;
        if (snd_mode != SM_FX) snd_level = 0;  /* FX keeps its own edge */
        beep_out(0);
        return;
    }

    half = snd_half;
    if (half == 0u) { beep_out(0); return; }   /* rest */

    /* Articulation / anti-click gate - see GATE_TICKS. Only the music and the
       jingle hold a note long enough to need it; the glissando run does not.
       The level drops to 0 when the half-cycle in progress ends, not the
       instant the gate opens, so the waveform stops on a zero crossing. */
    if (snd_mode != SM_FX && snd_left <= GATE_TICKS) {
        if (--snd_half_left == 0u) { snd_half_left = half; snd_level = 0; }
        beep_out((int)snd_level);
        return;
    }

    if (--snd_half_left == 0u) {
        snd_level ^= 1u;
        /* MUSIC ONLY: a 25% duty pulse instead of a square. A 50% square puts
           a lot of its energy in the 3rd harmonic, and that is what made the
           tune read as harsh on a buzzer; holding the pin high for only half
           the half-period drops that harmonic ~3 dB. Same period, so the
           pitch and the rhythm are untouched - this is the Game Boy's own
           pulse timbre. The effects keep the square: the line-clear run is
           already approved as it sounds, and the jingle is short and low. */
        if (snd_mode == SM_BGM) {
            uint32_t hi = (half + 1u) >> 1;
            snd_half_left = snd_level ? hi : (half + hi);
        } else {
            snd_half_left = half;
        }
        beep_out((int)snd_level);
    }
}

/* Delta-render: what changed since each framebuffer was last rendered, kept
   as up to NINE INDEPENDENT rectangles per buffer instead of one.

   DS_FIELD : the playfield itself - a settled block, a line clear.
   DS_PANEL : the NEXT strip and the HOLD box (both at the top, same rows).
   DS_GHOST : the landing preview - the OLD box unioned with the NEW one.
   DS_GHOST2: the landing preview when its old and new boxes are far apart.
   DS_PIECE, DS_PIECE2: the FALLING piece, tracked exactly like the ghost
              (see piece_sync()): a small step is one unioned rect, a HOLD
              swap - which can throw the piece from the bottom of the well
              back to the top - is two rects instead of one ~200-block box.
   DS_SCORE, DS_LEVEL, DS_LINES: the three value rows, kept apart.

   Independence is what keeps a repaint cheap, and the block count of a rect
   IS the stall it costs (see the batch note in game_hal.h; one write window
   opens per frame, so the whole dirty set of a frame is drawn as ONE
   transaction). Unioned into one rect these regions would have to span from
   the NEXT strip down to the bottom of the well - ~370 blocks. Three cuts
   matter, and the FIRST one is the one that matters most, because it happens
   on every single piece:
     * a rect is the UNION of everything marked into its slot before the
       buffer is painted, and one buffer is painted only every third frame.
       A lock marks the piece's box at the BOTTOM of the well, and the spawn
       one frame later marks the NEXT strip at the TOP RIGHT - on the same
       slot their union is a ~300-block box across the whole screen, and the
       spawn_delay sequence guarantees the two land on the same buffers. They
       are separate slots (DS_FIELD / DS_PANEL) so that never happens.
     * the ghost's wipe and redraw share ONE slot, unioned. As two slots a
       horizontal step cost two ~40-block rects instead of one ~43-block
       union - and a horizontal step is what the DAS auto-repeat pays EVERY
       frame while a key is held, which is exactly where a lagging repaint
       reads as "the keys are late". They are only marked apart (DS_GHOST2)
       when the two boxes share neither x nor y: a HOLD swap can move the
       ghost to the far side of the well at a different height, where their
       union would be one huge diagonal box spanning half the field.
     * the three value rows are marked separately. They sit in one 194-block
       column, but a hard drop only moves SCORE, and a line clear leaves LEVEL
       alone unless it actually rolled over - so the level and lines rows no
       longer ride along on every score change.

   The display is TRIPLE buffered and only ONE buffer is handed to the M3 per
   display frame, so a change has to be remembered separately for EACH of the
   three buffers: the rect is unioned into all three and each buffer clears
   its own slots the next time the M3 renders into it. A single shared copy
   would repaint the same buffer three times and leave the other two with the
   old content - i.e. exactly the ghosting single buffering used to show. */
#define DS_FIELD        0
#define DS_PANEL        1
#define DS_GHOST        2
#define DS_GHOST2       3
#define DS_SCORE        4
#define DS_LEVEL        5
#define DS_LINES        6
#define DS_PIECE        7
#define DS_PIECE2       8
#define DS_BANNER       9               /* the baked GAME OVER text - its own
                                          slot, so a blink phase can never
                                          UNION itself into the (much bigger)
                                          field rect and blow the repaint up */
#define DIRTY_SLOTS     10

typedef struct {
    int x1[DIRTY_SLOTS], y1[DIRTY_SLOTS];
    int x2[DIRTY_SLOTS], y2[DIRTY_SLOTS];
    int pend;                       /* bit k = slot k holds a rect to repaint */
} Dirty;
static Dirty dirty[3];

/* Union (x1,y1)-(x2,y2) into slot k of every buffer. */
static void mark_dirty_slot(int k, int x1, int y1, int x2, int y2)
{
    int i;
    if (k < 0 || k >= DIRTY_SLOTS) return;
    if (x1 < 0) x1 = 0;
    if (y1 < 0) y1 = 0;
    if (x2 > HOR_PIXELS - 1) x2 = HOR_PIXELS - 1;
    if (y2 > VER_PIXELS - 1) y2 = VER_PIXELS - 1;
    if (x1 > x2 || y1 > y2) return;
    for (i = 0; i < 3; i++) {
        if (!(dirty[i].pend & (1 << k))) {
            dirty[i].x1[k] = x1; dirty[i].y1[k] = y1;
            dirty[i].x2[k] = x2; dirty[i].y2[k] = y2;
            dirty[i].pend |= 1 << k;
        } else {
            if (x1 < dirty[i].x1[k]) dirty[i].x1[k] = x1;
            if (y1 < dirty[i].y1[k]) dirty[i].y1[k] = y1;
            if (x2 > dirty[i].x2[k]) dirty[i].x2[k] = x2;
            if (y2 > dirty[i].y2[k]) dirty[i].y2[k] = y2;
        }
    }
}

static void mark_dirty(int x1, int y1, int x2, int y2)
{
    mark_dirty_slot(DS_FIELD, x1, y1, x2, y2);
}

static int rnd7(void)
{
    rng_state = rng_state * 1103515245u + 12345u;
    return (int)((rng_state >> 16) % 7u);
}

/* ------------------------------------------------------------------ */
/* 5x7 font, column-encoded (byte = one column, bit 0 = top row).       */
/* Indices 0..9 = '0'..'9', 10..35 = 'A'..'Z'.                           */
/* ------------------------------------------------------------------ */
static const uint8_t font5x7[36][5] = {
    {0x3E,0x51,0x49,0x45,0x3E}, /* 0 */
    {0x00,0x42,0x7F,0x40,0x00}, /* 1 */
    {0x42,0x61,0x51,0x49,0x46}, /* 2 */
    {0x21,0x41,0x45,0x4B,0x31}, /* 3 */
    {0x18,0x14,0x12,0x7F,0x10}, /* 4 */
    {0x27,0x45,0x45,0x45,0x39}, /* 5 */
    {0x3C,0x4A,0x49,0x49,0x30}, /* 6 */
    {0x01,0x71,0x09,0x05,0x03}, /* 7 */
    {0x36,0x49,0x49,0x49,0x36}, /* 8 */
    {0x06,0x49,0x49,0x29,0x1E}, /* 9 */
    {0x7E,0x11,0x11,0x11,0x7E}, /* A */
    {0x7F,0x49,0x49,0x49,0x36}, /* B */
    {0x3E,0x41,0x41,0x41,0x22}, /* C */
    {0x7F,0x41,0x41,0x22,0x1C}, /* D */
    {0x7F,0x49,0x49,0x49,0x41}, /* E */
    {0x7F,0x09,0x09,0x09,0x01}, /* F */
    {0x3E,0x41,0x49,0x49,0x7A}, /* G */
    {0x7F,0x08,0x08,0x08,0x7F}, /* H */
    {0x00,0x41,0x7F,0x41,0x00}, /* I */
    {0x20,0x40,0x41,0x3F,0x01}, /* J */
    {0x7F,0x08,0x14,0x22,0x41}, /* K */
    {0x7F,0x40,0x40,0x40,0x40}, /* L */
    {0x7F,0x02,0x0C,0x02,0x7F}, /* M */
    {0x7F,0x04,0x08,0x10,0x7F}, /* N */
    {0x3E,0x41,0x41,0x41,0x3E}, /* O */
    {0x7F,0x09,0x09,0x09,0x06}, /* P */
    {0x3E,0x41,0x51,0x21,0x5E}, /* Q */
    {0x7F,0x09,0x19,0x29,0x46}, /* R */
    {0x46,0x49,0x49,0x49,0x31}, /* S */
    {0x01,0x01,0x7F,0x01,0x01}, /* T */
    {0x3F,0x40,0x40,0x40,0x3F}, /* U */
    {0x1F,0x20,0x40,0x20,0x1F}, /* V */
    {0x3F,0x40,0x38,0x40,0x3F}, /* W */
    {0x63,0x14,0x08,0x14,0x63}, /* X */
    {0x03,0x04,0x78,0x04,0x03}, /* Y */
    {0x61,0x51,0x49,0x45,0x43}  /* Z */
};

static int glyph_index(char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'A' && c <= 'Z') return 10 + (c - 'A');
    return -1;
}

/* decimal, most-significant first; returns the digit count. */
static int fmt_u32(char *b, uint32_t v)
{
    char t[10];
    int n = 0, i;
    do { t[n++] = (char)('0' + (int)(v % 10u)); v /= 10u; } while (v && n < 10);
    for (i = 0; i < n; i++) b[i] = t[n - 1 - i];
    b[n] = 0;
    return n;
}

/* Is (px,py) a lit pixel of the n-character string s drawn at (x0,y0)?
   sc = integer scale (1 or 2). Cheap early-outs keep a full-screen repaint
   affordable: the glyph grid is 6*sc wide per character, 7*sc tall. */
static int text_scan(int px, int py, int x0, int y0, const char *s, int n,
                     uint8_t col, int sc, uint8_t *out)
{
    int gx = px - x0, gy = py - y0;
    int ci, bit, gi;
    if (gx < 0 || gy < 0 || gy >= 7 * sc) return 0;
    if (gx >= n * 6 * sc) return 0;
    ci  = gx / (6 * sc);
    bit = (gx % (6 * sc)) / sc;
    if (bit >= 5) return 0;
    gi = glyph_index(s[ci]);
    if (gi < 0) return 0;
    if (font5x7[gi][bit] & (1 << (gy / sc))) { *out = col; return 1; }
    return 0;
}

/* All baked text: the five static labels plus the three live values.

   The VALUES are formatted ONCE, when they change (refresh_values(), called
   from the three mark_*_dirty() helpers and at boot), NOT once per pixel:
   fmt_u32() runs a division per digit and game_pixel() used to run it three
   times for every pixel of a value row, so a single SCORE repaint spent far
   more time turning numbers into digits than pushing the whole frame at the
   fabric. That was the dominant stall behind the laggy input.

   The y band each element lives in is dispatched on FIRST: the bands never
   overlap, so every pixel leaves after a compare or two instead of running
   five string scans. */
static char sv_buf[12]; static int sv_n = 1;
static char lv_buf[12]; static int lv_n = 1;
static char iv_buf[12]; static int iv_n = 1;

static void refresh_values(void)
{
    sv_n = fmt_u32(sv_buf, score);
    lv_n = fmt_u32(lv_buf, (uint32_t)level);
    iv_n = fmt_u32(iv_buf, (uint32_t)lines_cleared);
}

static int text_at(int x, int y, uint8_t *out)
{
    if (y <  HLY          || y > IVY + 7 * 2 - 1) return 0;   /* 44..171 */
    if (y <  HLY + 7)                                            /* HOLD/NEXT */
        return text_scan(x, y, HLX, HLY, "HOLD", 4, IDX_TEXT, 1, out) ||
               text_scan(x, y, NLX, NLY, "NEXT", 4, IDX_TEXT, 1, out);
    if (y <  SLY) return 0;
    if (y <  SLY + 7)
        return text_scan(x, y, SLX, SLY, "SCORE", 5, IDX_TEXT, 1, out);
    if (y <  SVY) return 0;
    if (y <  SVY + 7 * 2)
        return text_scan(x, y, SVX, SVY, sv_buf, sv_n, IDX_TEXT, 2, out);
    if (y <  LLY) return 0;
    if (y <  LLY + 7)
        return text_scan(x, y, LLX, LLY, "LEVEL", 5, IDX_TEXT, 1, out);
    if (y <  LVY) return 0;
    if (y <  LVY + 7 * 2)
        return text_scan(x, y, LVX, LVY, lv_buf, lv_n, IDX_TEXT, 2, out);
    if (y <  ILY) return 0;
    if (y <  ILY + 7)
        return text_scan(x, y, ILX, ILY, "LINES", 5, IDX_TEXT, 1, out);
    if (y <  IVY) return 0;
    return text_scan(x, y, IVX, IVY, iv_buf, iv_n, IDX_TEXT, 2, out);
}

/* Centred origin of a normalised piece inside the box (bx,by,bw,bh). */
static void piece_origin(const Cell *c, int bx, int by, int bw, int bh,
                         int cw, int ch, int *ox, int *oy)
{
    int i, mx = 0, my = 0;
    for (i = 0; i < 4; i++) {
        if (c[i].x > mx) mx = c[i].x;
        if (c[i].y > my) my = c[i].y;
    }
    *ox = bx + (bw - (mx + 1) * cw) / 2;
    *oy = by + (bh - (my + 1) * ch) / 2;
}

/* The HOLD and NEXT shapes are BAKED into the framebuffer, and game_pixel()
   runs once per pixel of every repaint - so their cells and centred origins
   are computed ONCE, here, whenever the queue or the hold slot changes,
   instead of for every pixel. That keeps a NEXT-strip repaint cheap.

   The per-cell ABSOLUTE pixel corners and the piece's own bounding box are
   cached too, so the per-pixel test is a handful of integer compares with no
   multiply and no loop over cells for the pixels that miss a piece - which is
   most of the strip. A NEXT repaint happens on EVERY spawn. */
static Cell hold_cells[4];
static int  hold_ox, hold_oy;
static int  hold_cx[4], hold_cy[4];
static int  hold_bx1, hold_by1, hold_bx2, hold_by2;
static Cell next_cells[3][4];
static int  next_ox[3], next_oy[3];
static int  next_cx[3][4], next_cy[3][4];
static int  next_bx1[3], next_by1[3], next_bx2[3], next_by2[3];

/* Fill the absolute corners + the bounding box of a piece's four cells. */
static void cells_abs(const Cell *c, int ox, int oy, int cw, int ch,
                      int *acx, int *acy, int *bx1, int *by1, int *bx2, int *by2)
{
    int i, mx = 0, my = 0;
    for (i = 0; i < 4; i++) {
        acx[i] = ox + c[i].x * cw;
        acy[i] = oy + c[i].y * ch;
        if (c[i].x > mx) mx = c[i].x;
        if (c[i].y > my) my = c[i].y;
    }
    *bx1 = ox;              *by1 = oy;
    *bx2 = ox + (mx + 1) * cw - 1;
    *by2 = oy + (my + 1) * ch - 1;
}

static void refresh_hold(void)
{
    if (hold_type < 0) return;
    piece_cells(hold_type, 0, hold_cells);
    piece_origin(hold_cells, HX0 + PB, HY0 + PB, HW - 2 * PB, HH - 2 * PB,
                 HCELL, HCELL, &hold_ox, &hold_oy);
    cells_abs(hold_cells, hold_ox, hold_oy, HCELL, HCELL, hold_cx, hold_cy,
              &hold_bx1, &hold_by1, &hold_bx2, &hold_by2);
}

static void refresh_next(void)
{
    int k;
    for (k = 0; k < 3; k++) {
        if (nextq[k] < 0) continue;
        piece_cells(nextq[k], 0, next_cells[k]);
        piece_origin(next_cells[k], NBX0 + k * NSLOT, NY0 + PB, NSLOT,
                     NH - 2 * PB, NCELL, NCELL, &next_ox[k], &next_oy[k]);
        cells_abs(next_cells[k], next_ox[k], next_oy[k], NCELL, NCELL,
                  next_cx[k], next_cy[k],
                  &next_bx1[k], &next_by1[k], &next_bx2[k], &next_by2[k]);
    }
}

/* ------------------------------------------------------------------ */
/* The SHADED CELL - one little square of a block, and the ONLY place  */
/* a block's pixels are decided, so the falling piece, a settled block,*/
/* HOLD and NEXT are guaranteed to be painted identically.            */
/*                                                                     */
/* The cell's own colour for the body, a bright white HIGHLIGHT in the */
/* top-left corner cut on the diagonal (lx + ly < cw/2, i.e. a corner  */
/* triangle about half the cell wide) so the square reads as bevelled  */
/* with a specular highlight, and the half-plane test is one add and   */
/* one compare - cheap enough to run for every pixel of a repaint.     */
/* The caller owns the seam: a cell's last COLUMN and last ROW are left*/
/* to whatever is behind (the field, or a panel's interior), which is  */
/* exactly the dark 1px gap that separates one little square from the  */
/* next.                                                               */
/* ------------------------------------------------------------------ */
static uint8_t cell_body(int lx, int ly, int cw, uint8_t base)
{
    return (lx + ly < (cw >> 1)) ? (uint8_t)IDX_HILITE : base;
}

/* The INNER BOX of a field cell. A field cell is 9 x 8 and the field's own
   grid rule (the empty-field case of game_pixel()) draws a 1px line down its
   first COLUMN and a 2px line along its first two ROWS, which leaves an 8 x 6
   inner box. A block fills exactly that box and nothing else, so a block is
   the same size as the background cell it stands in, sits exactly where that
   cell's inner box is, and its right and bottom edges are FLUSH with the cell.
   What separates one little square from the next is the cell's own grid band,
   i.e. a line in the very place the empty field draws one.

   The 1px / 2px asymmetry is forced by the display, not chosen: the read
   engine streams every SOURCE ROW PAIR twice, so a 1px HORIZONTAL line comes
   out as two thin lines and only a 2px band is one solid line. A 1px VERTICAL
   line has no such trap (see the empty-field rule below).
   The arguments are relative to the inner box (0..7 by 0..5). */
static uint8_t cell_body_f(int lx, int ly, uint8_t base)
{
    return (lx + ly < 4) ? (uint8_t)IDX_HILITE : base;
}

/* Is (x,y) inside one of four cells whose absolute top-left corners are
   (acx[i],acy[i]) and whose size is cw x ch? If it is, *out receives the very
   cell_body() colour that cell would have - so a HOLD or NEXT piece gets the
   same highlight and the same bottom/right seam as the block it stands for.
   Returns 0 on the seam pixels, which the caller then leaves as the panel's
   own background colour. */
static int cell_shade_abs(const int *acx, const int *acy, int cw, int ch,
                          int x, int y, uint8_t base, uint8_t *out)
{
    int i;
    for (i = 0; i < 4; i++) {
        if (x >= acx[i] && x < acx[i] + cw && y >= acy[i] && y < acy[i] + ch) {
            int lx = x - acx[i], ly = y - acy[i];
            if (lx == cw - 1 || ly == ch - 1) return 0;
            *out = cell_body(lx, ly, cw, base);
            return 1;
        }
    }
    return 0;
}

/* Is cell (c,r) part of the GHOST (the landing preview)? c/r are the field's
   cell coordinates, exactly as game_pixel() computes them. The ghost sits at
   ghost_row + the piece's own cell offsets, at the column the piece is at. */
static int ghost_cell(int c, int r)
{
    int i;
    for (i = 0; i < 4; i++)
        if (c == cur_x + cur_cells[i].x && r == ghost_row + cur_cells[i].y)
            return 1;
    return 0;
}

/* ------------------------------------------------------------------ */
/* What the framebuffer holds at (x,y): the background, the playfield + */
/* its border, the FALLING piece, the GHOST (landing preview), the HOLD */
/* and NEXT panels (outline + the piece shapes) and all the text.      */
/*                                                                      */
/* ALL of the blocks are baked now - the falling piece included -      */
/* because a fabric rectangle can only fill a FLAT colour and every    */
/* cell now carries a highlight (see cell_body()). Baking is what lets */
/* the falling piece and a settled block be painted by one and the same*/
/* function call, so locking changes nothing on screen.                */
/*                                                                      */
/* ORDER MATTERS, and it is the order the old sprite layering had:      */
/* falling piece -> ghost -> settled block -> grid line. The piece must */
/* win over the ghost (the sprite used to be painted over it, and a     */
/* piece one row above its landing row overlaps the ghost's top row),   */
/* and a settled cell must win over the grid: the block fills the cell's */
/* INNER BOX with its own colour and leaves the cell's own grid band to  */
/* the GRID, so it reads as a complete, bevel-finished little square      */
/* exactly the size of a background cell while the field's lines stay     */
/* where they were - a block is a background cell, painted.               */
/* ------------------------------------------------------------------ */
static uint8_t game_pixel(int x, int y)
{
    uint8_t col;

    /* ---- GAME OVER / PRESS TO CONTINUE banner (top priority). The WORDS
       ALONE, in RED (IDX_Z): there is NO box behind them, so a pixel that is
       not a lit glyph falls through to whatever the well/panel/background holds
       there and the banner never covers the picture. It blinks; while go_shown
       is 0 it is simply not there. Which string is up is go_phase: the GAME
       OVER words first, then the prompt in the same band. ---- */
    if (game_over && go_shown) {
        if (go_phase == 0) {
            if (x >= GO_X && x < GO_X + GO_W && y >= GO_Y && y < GO_Y + GO_H &&
                text_scan(x, y, GO_X, GO_Y, GO_STR, GO_N, IDX_Z, GO_SC, &col))
                return col;
        } else if (x >= PC_X && x < PC_X + PC_W &&
                   y >= PC_Y && y < PC_Y + PC_H &&
                   text_scan(x, y, PC_X, PC_Y, PC_STR, PC_N, IDX_Z, PC_SC, &col))
            return col;
    }

    /* ---- playfield interior ---- */
    if (x >= X0 && x < X0 + COLS * CELLX && y >= Y0 && y < Y0 + ROWS * CELLY) {
        int gx = x - X0, gy = y - Y0;
        /* gx is known non-negative here, so the division runs through the
           compiler's unsigned magic-multiply form (one multiply + shift)
           instead of the slower sign-corrected signed one. */
        int c = (int)((unsigned)gx / (unsigned)CELLX);
        int lx = gx - c * CELLX;
        int r = gy >> 3;                       /* CELLY == 8 */
        int ly = gy & 7;

        /* The FALLING piece: four baked cells, each the same shaded square a
           settled block draws (cell_body()). The cheap box reject in front of
           the four-cell loop is what keeps a full-field repaint (a line clear)
           from paying for that loop on every single pixel. */
        if (running && !game_over &&
            r >= cur_y && r <= cur_y + pmax_y &&
            c >= cur_x && c <= cur_x + pmax_x) {
            int i;
            for (i = 0; i < 4; i++) {
                if (c == cur_x + cur_cells[i].x && r == cur_y + cur_cells[i].y) {
                    /* The BODY wins outright: the very shaded square a settled
                       block draws (cell_body()), which is what makes locking
                       free. The cell's own grid band is NOT returned here,
                       although a block does leave exactly that band to the
                       field's grid: the ghost sits on the row this piece is
                       falling to, so a tall piece shares its bottom cells with
                       the ghost's TOP cells, and a band painted in the grid
                       colour would cut the ghost's frame open right where the
                       piece covers it - a gap that came and went with the
                       piece's height. The band falls THROUGH instead: the
                       ghost tints it if its frame runs through this cell, and
                       the grid rule below paints it as the field's own line
                       otherwise (a piece can never share a cell with a settled
                       block, so nothing else has a claim on it). */
                    if (lx != 0 && ly > 1)
                        return cell_body_f(lx - 1, ly - 2,
                                           (uint8_t)(PIECE_BASE + cur_type));
                    break;
                }
            }
        }

        /* The ghost: the landing preview, drawn as the very cells the piece
           will occupy, and drawn the way the BACKGROUND draws a cell - it tints
           that cell's grid band (its first column and its first two rows, the
           field's own 1px / 2px line) in the piece's own colour and leaves the
           8 x 6 inner box exactly as the empty field has it (IDX_FIELD).

           That is what makes the preview the same size and shape as a
           background cell: its lines sit ON the grid lines - they used to sit
           on the cells' own last column / last two rows, a pixel or two off
           them, which is what made the preview read as a different-sized tile
           than the field it sat in - and the cell's grid band, not a seam on a
           body's edge, is what separates the shape's little squares, in the
           very place the field's grid has a line. No band of the shape's own
           cells is left un-tinted, so there is no hairline gap inside the
           preview either.

           The outer frame closes like this, and EVERY band it uses is one of
           the field's own grid bands (1px vertical / 2px horizontal), never a
           pixel of the shape's own box, so the frame can neither drift off the
           grid nor make its cells a different size from the field's:
             * a ghost cell tints its OWN left column and top two rows - that
               is its left edge, its top edge, and the separators to a ghost
               cell left of / above it;
             * the RIGHT edge is the left column of the cell just PAST the shape,
               and the BOTTOM edge is the top two rows of the cell one row down -
               both drawn by that neighbour, which is why the guard below reaches
               one cell past the shape and does NOT insist the neighbour be
               empty. The neighbour is a field grid band either way; where it is
               a settled block, that block's own grid band is the line the field
               draws there, and the tint simply lands ON it (the ghost is
               evaluated before the settled block, so the tint wins).
           At the floor the bottom edge needs no tint at all: the well's own
           bottom border IS that line, and the last cell's inner box runs right
           down to it, exactly as for every other row.

           The one place nothing else can draw is the concave corner of a STEP:
           where the shape runs one cell up-left of this cell but not up, not
           left and not here, the right edge of that shape cell (drawn in this
           cell's own left column) and its bottom edge (drawn in this cell's own
           top two rows) meet, and the corner between them would be left empty -
           the little gap a staircase step used to show. Fill it whichever
           neighbours carry those two edges, empty or settled: they carry them
           either way, and asking for an empty neighbour is what used to switch
           the fill off exactly where the ghost rested on the stack - the reason
           the gap came and went from one frame to the next.

           The width of those bands is the field's, not a style of its own: 1px
           vertically, 2px horizontally, exactly as the background grid (see the
           empty-field rule below). */
        if (ghost_on &&
            c >= cur_x && c <= cur_x + ghost_w + 1 &&
            r >= ghost_row && r <= ghost_row + ghost_h + 1) {
            int g  = ghost_cell(c, r);          /* this cell is the shape's  */
            int gl = ghost_cell(c - 1, r);      /* the cell to its left is  */
            int gb = ghost_cell(c, r - 1);      /* the cell above it is     */
            uint8_t ink = (uint8_t)(PIECE_BASE + cur_type);

            if (lx == 0 && (g || gl)) return ink;      /* left edge + separators */
            if (ly <= 1 && (g || gb)) return ink;      /* top edge + separators  */
            if (lx == 0 && ly <= 1 && ghost_cell(c - 1, r - 1)) return ink;
            if (g && board[r][c] == 0) return IDX_FIELD;/* the cell's inner box   */
        }

        {
            uint8_t v = board[r][c];
            if (v) {
                /* The block, byte for byte what the falling piece bakes into
                   the same cell (see cell_body_f()): its own colour in the
                   cell's 8 x 6 inner box - the very box the empty field fills
                   with IDX_FIELD, so a block is exactly the size of the
                   background cell it stands in - and the cell's own grid band
                   (its first column / two rows) left to the GRID, so the
                   field's lines stay exactly where they were and two
                   neighbouring blocks are separated by the field's own line
                   instead of by a dark notch. */
                if (lx == 0 || ly <= 1) return IDX_GRID;
                return cell_body_f(lx - 1, ly - 2, v);
            }
        }
        /* Empty field: its grid. The column rule is 1px (lx 0) and the row rule
           is 2px (ly 0 and 1), and that asymmetry is forced by the display
           pipeline, not chosen.

           The read engine streams each SOURCE ROW PAIR twice (rd_copy in
           top.v), so the raster's rows are  R0,R1,R0,R1,R2,R3,R2,R3... : one
           source row lands in EVERY OTHER output row. A 1px horizontal line
           therefore comes out as TWO thin lines with a row of the field between
           them - exactly the "one row, two horizontal lines" this whole grid
           started from. Only a band spanning the WHOLE pair (both 2p and 2p+1)
           fills four consecutive output rows and reads as one solid line, so
           2px is the thinnest a SINGLE horizontal line can be drawn here.

           Horizontally there is no such trap - each framebuffer byte is just
           shown as two adjacent output pixels - so at 1px the column rule
           already reads as one clean line, half the output width it had at 2px.
           With 1px + 2px every cell is exactly 8 x 6 of interior, identical for
           the empty field, for a settled block (see cell_body_f()) and for the
           ghost, and the well's own edge is a grid line of that same width, so
           no cell can come out a different size from any other. */
        if (lx == 0 || ly <= 1) return IDX_GRID;
        return IDX_FIELD;
    }
    /* ---- field outline ---- */
    /* The well's edge is a GRID line, not a bright ring bolted on OUTSIDE the
       first cells. The left and top edges ARE the outermost cells' own grid
       band, drawn by the rule above; only the right and bottom edges are left,
       both exactly one grid line thick - 1px on the right, 2px at the bottom,
       the field's own 1px / 2px widths. The IDX_BORDER ring that used to sit
       here, just outside the first cells' band, made those edge lines twice as
       thick as every inner line (ring + band on the left and top) and a bright
       colour the inner lines do not use, which is what made the outer cells -
       and, because its bottom edge is the bright one, the last row - read as
       smaller than the rest of the background. */
    if (x == X0 + COLS * CELLX && y >= Y0 && y < Y0 + ROWS * CELLY) {
        /* This line IS the line the ghost's own right edge falls on whenever
           its outermost column is the field's last one: the edge rule draws a
           shape cell's right edge in the next cell's first column, and one
           cell past that column there is only this border. Left as the
           border's grid colour the ghost's frame would come out cut off
           against the wall, so tint the STRETCH of the line the shape really
           reaches - and only that stretch - in the ghost's colour. Nothing
           moves: the same 1px line, in the same place, so no cell changes
           size. The wall has no cell to the right, so the interior corner
           rule is mirrored here: a ghost cell one row UP in the last column
           runs its right edge across this line and its bottom edge across the
           next row's first two rows, a corner that only closes if the cell
           below is a ghost too. Carry that corner onto the wall. */
        int rr = (y - Y0) >> 3;
        if (ghost_on && (ghost_cell(COLS - 1, rr) ||
                         (((y - Y0) & 7) <= 1 && rr >= 1 &&
                          ghost_cell(COLS - 1, rr - 1))))
            return (uint8_t)(PIECE_BASE + cur_type);
        return IDX_GRID;
    }
    if (y >= Y0 + ROWS * CELLY && y < Y0 + ROWS * CELLY + 2 &&
        x >= X0 && x <= X0 + COLS * CELLX) {
        /* And this is the line the ghost's bottom edge uses when it rests on
           the floor - 2px, the field's own horizontal width, exactly what the
           edge would have had one row down in the field. The pixel past the
           last column counts as that column's corner, where its right edge and
           its bottom edge meet and the frame has to stay closed. One cell in
           the same seam appears between a ghost cell's bottom edge and the
           right edge of the column to its left - the floor is the one place
           that edge is NOT drawn, so close it here. */
        int bc = (int)((unsigned)(x - X0) / (unsigned)CELLX);
        int lxb = (x - X0) - bc * CELLX;
        if (bc >= COLS) {
            if (ghost_on && ghost_cell(COLS - 1, ROWS - 1))
                return (uint8_t)(PIECE_BASE + cur_type);
            return IDX_GRID;
        }
        if (ghost_on && (ghost_cell(bc, ROWS - 1) ||
                         (lxb == 0 && bc >= 1 && ghost_cell(bc - 1, ROWS - 1))))
            return (uint8_t)(PIECE_BASE + cur_type);
        return IDX_GRID;
    }

    /* ---- HOLD box ---- */
    if (x >= HX0 && x < HX0 + HW && y >= HY0 && y < HY0 + HH) {
        if (x < HX0 + PB || x >= HX0 + HW - PB ||
            y < HY0 + PB || y >= HY0 + HH - PB)
            return IDX_BORDER;
        if (running && hold_type >= 0 &&
            x >= hold_bx1 && x <= hold_bx2 &&
            y >= hold_by1 && y <= hold_by2 &&
            cell_shade_abs(hold_cx, hold_cy, HCELL, HCELL, x, y,
                           (uint8_t)(PIECE_BASE + hold_type), &col))
            return col;
        return IDX_PANEL_BG;
    }

    /* ---- NEXT strip (three pieces) ---- */
    if (x >= NX0 && x < NX0 + NW && y >= NY0 && y < NY0 + NH) {
        int k;
        if (x < NX0 + PB || x >= NX0 + NW - PB ||
            y < NY0 + PB || y >= NY0 + NH - PB)
            return IDX_BORDER;
        if (running) {
            for (k = 0; k < 3; k++) {
                if (nextq[k] < 0) continue;
                if (x >= next_bx1[k] && x <= next_bx2[k] &&
                    y >= next_by1[k] && y <= next_by2[k] &&
                    cell_shade_abs(next_cx[k], next_cy[k], NCELL, NCELL, x, y,
                                   (uint8_t)(PIECE_BASE + nextq[k]), &col))
                    return col;
            }
        }
        return IDX_PANEL_BG;
    }

    /* ---- labels + live values ---- */
    if (text_at(x, y, &col)) return col;

    /* ---- the well's frame ---- */
    /* The well is the dark playfield, and OUTSIDE its own edge lines it wears a
       flat egg-white ring, the way the panels wear theirs (IDX_BORDER). The ring
       is a band of its OWN, in the margin the well already has: it starts where
       the well's edge line ends - 1px past its right line, 2px past its bottom
       one (the field's own 1px / 2px widths), 2px outside its first column and
       its first row - and it is BORDER thick all the way round, corners
       included.

       It shares no pixel with anything the well draws, the ghost included, and
       that is the whole point. A frame lying ON the well's edge is what used to
       be here, and there it had to give way whenever the ghost's own edge
       landed on it (or it clipped the ghost) - the frame came out bitten, one
       piece of it lost to the ghost's colour. Off the edge, in its own band,
       nothing inside the well can reach these pixels, so the frame is always
       whole and so is the ghost: the ghost's dashes run right up to the well's
       edge line and the ring carries on, untouched, just past it.

       Checked LAST, after the labels, so it cannot cover any of them, and it
       changes no coordinate of the well or of a single cell. */
    if (x >= X0 - BORDER && x <= X0 + COLS * CELLX + BORDER &&
        y >= Y0 - BORDER && y <= Y0 + ROWS * CELLY + 1 + BORDER &&
        (x < X0 || x > X0 + COLS * CELLX ||
         y < Y0 || y > Y0 + ROWS * CELLY + 1))
        return IDX_BORDER;

    return IDX_BG0;                    /* one flat background colour */
}

/* ------------------------------------------------------------------ */
/* Rules                                                               */
/* ------------------------------------------------------------------ */
static int cells_valid(int px, int py, const Cell c[4])
{
    int i;
    for (i = 0; i < 4; i++) {
        int bx = px + c[i].x, by = py + c[i].y;
        if (bx < 0 || bx >= COLS || by >= ROWS) return 0;
        if (by >= 0 && board[by][bx]) return 0;
    }
    return 1;
}

/* The live values are three separate rows, so each one is marked on its own:
   a hard drop moves SCORE only and a line clear moves LINES (and LEVEL only
   when it rolls over), and repainting the other two rows as well used to cost
   six times the blocks of the row that had actually changed.

   Each of these ALSO re-formats the three value strings, so the digit
   conversion happens once per change instead of once per repainted pixel. */
static void mark_score_dirty(void)
{
    refresh_values();
    mark_dirty_slot(DS_SCORE, SVX, SVY, SVX + VAL_W - 1, SVY + VAL_H - 1);
}

static void mark_level_dirty(void)
{
    refresh_values();
    mark_dirty_slot(DS_LEVEL, LVX, LVY, LVX + VAL_W - 1, LVY + VAL_H - 1);
}

static void mark_lines_dirty(void)
{
    refresh_values();
    mark_dirty_slot(DS_LINES, IVX, IVY, IVX + VAL_W - 1, IVY + VAL_H - 1);
}

/* the NEXT strip changed -> repaint the rows the shapes can actually reach.
   The interior is 18 rows tall, but every shape is drawn at rotation 0, is at
   most two cells (14 rows) tall, and is centred - so rows NY0+PB+2 .. NY0+NH-PB-3
   are the only ones that ever carry ink, and marking all 18 rows costs ~10
   extra blocks on EVERY piece. */
#define NINY0           (NY0 + PB + 2)
#define NINY1           (NY0 + NH - PB - 3)

static void mark_next_dirty(void)
{
    mark_dirty_slot(DS_PANEL, NX0 + PB, NINY0, NX0 + NW - PB - 1, NINY1);
}

/* the HOLD slot changed -> its interior must be repainted */
static void mark_hold_dirty(void)
{
    mark_dirty_slot(DS_PANEL, HX0 + PB, HY0 + PB,
                    HX0 + HW - PB - 1, HY0 + HH - PB - 1);
}

static int grav_frames(void);          /* defined below; used at spawn */

/* Put piece type t at the top-centre spawn position and start its fall.
   Shared by the queue spawn and by HOLD bringing a piece back into play. */
static void place_piece(int t)
{
    cur_type = t;
    cur_rot = 0;
    cur_y = 0;
    piece_cells(cur_type, cur_rot, cur_cells);

    /* Centre the piece by its own bounding box, so every shape appears in the
       middle of the well at the very top instead of at a fixed column - the
       box itself, which the per-pixel test in game_pixel() rejects with and
       piece_sync() repaints, is set here too. */
    set_cells(cur_cells);
    cur_x = (COLS - (pmax_x + 1)) / 2;

    /* Pre-charge the fall timer so a brand-new piece steps down on its very
       first frame on screen instead of waiting out a whole gravity period. */
    grav_cnt = grav_frames() - 1;
    if (!cells_valid(cur_x, cur_y, cur_cells)) {
        game_over = 1;
        sound_over();              /* music -> the game-over theme */
        /* Start the game-over screen: the words come up lit in THIS frame, and
           ban_state is pre-set to what the main loop will compute next frame
           (go_shown 1, phase 0) so that frame does not repaint the same band
           a second time. */
        go_phase  = 0;
        go_frames = 0;
        blink_cnt = 0;
        go_shown  = 1;
        ban_state = 1;
        mark_dirty_slot(DS_BANNER, BAN_X, BAN_Y,
                        BAN_X + BAN_W - 1, BAN_Y + BAN_H - 1);
    }
}

/* Take the next piece off the queue. This is the ONLY place the per-piece
   hold guard is cleared - exactly as in the reference firmware, so a piece
   that came out of the HOLD slot cannot be held again immediately. */
static void spawn(void)
{
    int t = nextq[0];

    nextq[0] = nextq[1];
    nextq[1] = nextq[2];
    nextq[2] = rnd7();
    refresh_next();                    /* re-centre the baked shapes          */
    mark_next_dirty();                 /* the strip is baked, so a shift repaints it */

    place_piece(t);
    hold_used = 0;
}

/* ------------------------------------------------------------------ */
/* State reset for a fresh game.                                       */
/* ------------------------------------------------------------------ */
static void init_game(void)
{
    int r, c, i;
    for (r = 0; r < ROWS; r++)
        for (c = 0; c < COLS; c++)
            board[r][c] = 0;
    game_over = 0;
    paused = 0;
    go_shown = 0;                      /* the fresh board carries no banner */
    go_phase = 0;                      /* ...and it starts on the words, not
                                          the prompt                            */
    go_frames = 0;
    ban_state = -1;                    /* nothing drawn in the banner band yet
                                          after this repaint, so the next
                                          top-out repaints it from scratch    */
    spawn_delay = 0;
    ghost_on = 0;                      /* nothing of the old ghost is left in
                                          the buffers once the fresh board is
                                          painted - see the restart repaint */
    gbx1 = -1;
    gbt = -1;
    pcb1 = -1;                         /* ...and the old piece's baked box */
    pbt = -1;
    grav_cnt = das_dir = das_cnt = 0;
    soft_cnt = 0;
    score = 0;
    lines_cleared = 0;
    level = 0;
    hold_type = -1;
    hold_used = 0;
    refresh_values();                  /* the fresh 0 / 0 / 0 value rows */
    for (i = 0; i < 3; i++) dirty[i].pend = 0;
    for (i = 0; i < 3; i++) nextq[i] = rnd7();
    spawn();
}

static int try_move(int dx, int dy)
{
    if (cells_valid(cur_x + dx, cur_y + dy, cur_cells)) {
        cur_x += dx; cur_y += dy;
        return 1;
    }
    return 0;
}

/* dir = +1 clockwise, -1 counter-clockwise. */
static void do_rotate(int dir)
{
    Cell nc[4];
    int nr = (cur_rot + (dir > 0 ? 1 : 3)) & 3;
    piece_cells(cur_type, nr, nc);
    if (cells_valid(cur_x, cur_y, nc)) {
        set_cells(nc);                 /* cells AND their box, never one alone */
        cur_rot = nr;
    }
}

/* score for clearing 1..4 rows at once (multiplied by level+1) */
static const uint16_t line_score[5] = { 0, 100, 300, 500, 800 };

static void lock_piece(void)
{
    int i, r, c, cleared = 0, maxrow = 0, minrow = ROWS;
    int mincol = COLS, maxcol = 0;
    int top = ROWS, last_clear = -1, bottom;

    for (i = 0; i < 4; i++) {
        int bx = cur_x + cur_cells[i].x;
        int by = cur_y + cur_cells[i].y;
        board[by][bx] = (uint8_t)(PIECE_BASE + cur_type);
        if (by > maxrow) maxrow = by;
        if (by < minrow) minrow = by;
        if (bx > maxcol) maxcol = bx;
        if (bx < mincol) mincol = bx;
    }

    /* topmost row holding any block BEFORE the shift: rows above it are plain
       field colour both before and after, so they never need repainting */
    for (r = 0; r < ROWS; r++) {
        for (c = 0; c < COLS; c++) if (board[r][c]) break;
        if (c < COLS) { top = r; break; }
    }

    /* clear every completed row, shifting everything above down one */
    for (r = ROWS - 1; r >= 0; ) {
        int full = 1;
        for (c = 0; c < COLS; c++) if (!board[r][c]) { full = 0; break; }
        if (full) {
            int rr;
            last_clear = r;
            for (rr = r; rr > 0; rr--)
                for (c = 0; c < COLS; c++) board[rr][c] = board[rr - 1][c];
            for (c = 0; c < COLS; c++) board[0][c] = 0;
            cleared++;
        } else {
            r--;
        }
    }

    /* No line cleared -> only the piece's own cells changed, so repaint just
       its bounding box (~1-4 cells). If a line DID clear, only the rows between
       the topmost block that existed before the shift and the lowest cleared
       row can differ. Scores/lines/level only move when a line clears. */
    if (cleared == 0) {
        mark_dirty(X0 + mincol * CELLX,             Y0 + minrow * CELLY,
                   X0 + (maxcol + 1) * CELLX - 1,   Y0 + (maxrow + 1) * CELLY - 1);
    } else {
        bottom = (last_clear > maxrow) ? last_clear : maxrow;
        mark_dirty(X0, Y0 + top * CELLY,
                   X0 + COLS * CELLX - 1,           Y0 + (bottom + 1) * CELLY - 1);
        sound_fx(fx_line, FXL_N);   /* glissando; the music ducks out */

        score        += (uint32_t)line_score[cleared] * (uint32_t)(level + 1);
        if (score > 999999u) score = 999999u;
        lines_cleared += cleared;
        {
            int lv0 = level;
            level = lines_cleared / LINES_PER_LEVEL;
            if (level != lv0) {                 /* only when it rolled over */
                mark_level_dirty();
                /* the level-up ding, queued to sound the instant the
                   glissando above finishes, never on top of it */
                sound_fx_after(fx_level, LVL_N);
            }
        }
        mark_score_dirty();
        mark_lines_dirty();
    }

    spawn_delay = 1;                   /* hold the next piece back for exactly
                                          ONE more frame. The locked cells are
                                          already in the board and the piece is
                                          still the current one, and a board cell
                                          draws the SAME pixels a piece cell does
                                          (see cell_body()), so that frame repaints
                                          nothing and the block simply stays put;
                                          the next piece - with its ghost - then
                                          appears the very next frame           */
    grav_cnt = 0;
    soft_cnt = 0;
}

/* gravity gets faster with the level, down to one row per frame */
static int grav_frames(void)
{
    int g = GRAV_FRAMES - level;
    return (g < 1) ? 1 : g;
}

/* K6 = HOLD. Swap the falling piece with the hold slot; usable once per
   piece (hold_used is cleared only by spawn()). If the slot is empty the
   falling piece is stashed and the next queue piece comes in instead. */
static void do_hold(void)
{
    int t;

    if (hold_used) return;

    if (hold_type < 0) {                 /* slot empty: stash + pull next */
        hold_type = cur_type;
        refresh_hold();
        mark_hold_dirty();
        spawn();                         /* clears hold_used...            */
        hold_used = 1;                   /* ...but this piece has held now */
        return;
    }

    t = hold_type;                       /* real swap                    */
    hold_type = cur_type;
    refresh_hold();
    mark_hold_dirty();
    place_piece(t);
    hold_used = 1;
}

/* K5 = hard drop: slide the piece straight down to its landing row, pay 2
   points per row slammed (as the reference firmware does), then lock it. */
static void do_hard_drop(void)
{
    int d = 0;

    while (cells_valid(cur_x, cur_y + d + 1, cur_cells)) d++;
    cur_y += d;
    if (d > 0) {
        score += (uint32_t)(2 * d);
        if (score > 999999u) score = 999999u;
        mark_score_dirty();
    }
    lock_piece();
}

/* ------------------------------------------------------------------ */
/* Publish rectangles                                                  */
/*                                                                     */
/* The falling piece used to be FOUR rectangles, one little square per */
/* cell - it cannot be any more, because a rectangle fills ONE FLAT    */
/* colour and a cell now carries a highlight. It is baked into the     */
/* framebuffer instead and kept in step by piece_sync(), with          */
/* game_pixel() drawing it as the very same shaded cell a settled      */
/* block draws.                                                        */
/*                                                                     */
/* That leaves the object table dark for the whole of a normal game -  */
/* which is why nothing here has to run on the fall path at all. The   */
/* GAME OVER banner is baked text too (see game_pixel), so the ONLY    */
/* hardware overlay left is the pause icon: two plain vertical bars -  */
/* exactly what a flat rectangle is good at - sitting on top of the    */
/* field without a single byte of framebuffer traffic.                 */
/* ------------------------------------------------------------------ */

static void publish_sprites(void)
{
    if (game_over) {
        /* The topped-out banner is BAKED text now (see game_pixel), so the
           object table carries nothing at all: the bar that used to flash
           through rectangle 0 is gone, and the other four were off anyway. */
        spr_off(0); spr_off(1); spr_off(2); spr_off(3); spr_off(4);
        return;
    }

    if (paused) {
        /* blinking "||" pause icon: two vertical bars, a shape that cannot be
           confused with anything the baked well can show */
        spr_off(2); spr_off(3); spr_off(4);
        if (blink_cnt < 16) {
            spr_box(0, 150, 97, 14, 45, IDX_I, 1);
            spr_box(1, 170, 97, 14, 45, IDX_I, 1);
        } else {
            spr_off(0); spr_off(1);
        }
        return;
    }

    /* A normal frame paints NOTHING through the object table: the piece and
       both panels are baked. The two writes just make sure the overlays are
       off on the first frame after a game-over / pause, where they were on. */
    spr_off(0);
    spr_off(1);
}

/* ------------------------------------------------------------------ */
/* Ghost / landing preview                                             */
/*                                                                     */
/* The ghost is BAKED into the framebuffer - one small hollow frame per */
/* cell - because the fabric's five rectangles cannot draw an outline   */
/* and four of them are already used by the falling piece.             */
/*                                                                     */
/* It is normally free: its landing row depends on the piece's COLUMN  */
/* and on the stack, NOT on how far the piece has fallen, so a piece    */
/* dropping straight down leaves it exactly where it is and this whole  */
/* function does nothing at all. Only a horizontal move, a rotation, a  */
/* HOLD swap, a spawn or a stack change moves it - and then its old and  */
/* new bounding boxes are unioned into ONE dirty rect (slot DS_GHOST)    */
/* that both wipes the old frame and bakes the new one.                 */
/*                                                                     */
/* Every one of those transitions which turns the ghost OFF or moves it */
/* has to mark the bbox it was last drawn at, or the old frame stays    */
/* baked into the buffers as a phantom.                                */
/* ------------------------------------------------------------------ */
static void ghost_sync(void)
{
    int i, mx = 0, my = 0, mn = 9, dy, was = ghost_on;
    int on = 0, x1 = 0, y1 = 0, x2 = 0, y2 = 0;

    if (running && !game_over && !paused && spawn_delay == 0) {
        for (i = 0; i < 4; i++) {
            if (cur_cells[i].x > mx) mx = cur_cells[i].x;
            if (cur_cells[i].y > my) my = cur_cells[i].y;
            if (cur_cells[i].y < mn) mn = cur_cells[i].y;
        }
        dy = cur_y;
        while (cells_valid(cur_x, dy + 1, cur_cells)) dy++;
        if (dy > cur_y) {                  /* already resting -> nothing to show */
            on         = 1;
            ghost_row  = dy;
            ghost_w    = mx;
            ghost_h    = my;
            x1 = X0 + cur_x * CELLX;
            /* the box starts at the piece's topmost INK row, not at ghost_row:
               the flat I holds all four cells in its second row, so a box that
               always started at ghost_row would repaint a whole blank row -
               half its own block count - on every horizontal step. */
            y1 = Y0 + (dy + mn) * CELLY;
            /* The ghost is drawn as the shape's OWN cells with their grid bands
               tinted (see game_pixel()), and its outer right / bottom edge is
               the grid band of the cell just PAST the shape - the first
               COLUMN of the cell to its right and the first two rows of the
               cell below. So the box has to reach one cell further on both
               axes, and into that cell (1px right, 2px down - the field's own
               line widths): it is the shape's cell grid, the same 9 x 8 box the
               falling piece and a settled block occupy, plus that lip on the
               right and at the bottom. The 1px of slack on x is simply one
               pixel the box does not need, which keeps this a single formula
               for both axes. (A block resting against the ghost takes the edge
               back inside the shape's own cells, which is inside this box
               anyway.) */
            x2 = X0 + (cur_x + mx + 1) * CELLX + 1;
            y2 = Y0 + (dy + my + 1) * CELLY + 1;
        }
    }
    ghost_on = on;

    /* Unchanged - which is the normal case, and the whole reason this costs
       nothing while the piece just falls. The shape has to be identified by
       TYPE + ROTATION, not by its bounding box: two different rotations of one
       piece can share a box (a T is 3x2 both ways up), and a box-only test would
       then leave the old shape baked into the framebuffers. */
    if (on && was && cur_type == gbt && cur_rot == gbro &&
        ghost_row == gbrow && cur_x == gbcol)
        return;

    /* Wipe the old box and draw the new one. Normally through ONE rect - their
       UNION: a horizontal step (what the DAS auto-repeat repaints every frame
       while a key is held) moves the ghost one column, so the boxes overlap and
       the union is barely bigger than either of them, costing HALF of two
       separate ~40-block rects. They only go to two rects when they share
       neither x nor y, i.e. a diagonal jump - which is what a HOLD swap can do
       when the held piece lands on the far side of the well at a different
       height. There a union would be one ~200-block box across the field. */
    {
        int near = (x1 <= gbx2 && gbx1 <= x2) || (y1 <= gby2 && gby1 <= y2);

        if (gbx1 >= 0 && on && near) {
            int ux1 = (gbx1 < x1) ? gbx1 : x1;
            int uy1 = (gby1 < y1) ? gby1 : y1;
            int ux2 = (gbx2 > x2) ? gbx2 : x2;
            int uy2 = (gby2 > y2) ? gby2 : y2;
            mark_dirty_slot(DS_GHOST, ux1, uy1, ux2, uy2);
        } else {
            if (gbx1 >= 0) mark_dirty_slot(DS_GHOST,  gbx1, gby1, gbx2, gby2);
            if (on)        mark_dirty_slot(DS_GHOST2, x1,   y1,   x2,   y2);
        }
    }
    gbx1 = -1;
    if (!on) { gbt = -1; return; }

    gbx1 = x1; gby1 = y1; gbx2 = x2; gby2 = y2;
    gbt = cur_type; gbro = cur_rot; gbrow = ghost_row; gbcol = cur_x;
}

/* ------------------------------------------------------------------ */
/* The falling piece                                                   */
/*                                                                     */
/* The piece is BAKED into the framebuffer now, for the same reason the */
/* ghost is: a fabric rectangle fills ONE FLAT colour, and every cell   */
/* carries a highlight (see cell_body()), so the four little squares it */
/* used to be published as are no longer possible. game_pixel() draws   */
/* it as the very same shaded cell a settled block draws - which is     */
/* what makes LOCKING free: the frame after a lock looks identical      */
/* whether a cell comes from the piece or from the board, so this only  */
/* ever has to repaint the box the piece VACATED.                       */
/*                                                                     */
/* It is free while the piece merely falls, too: a fall is one row, so  */
/* the old and new boxes overlap and their UNION is barely bigger than  */
/* either of them. Boxes that overlap on BOTH axes go through ONE rect  */
/* (DS_PIECE); a HOLD swap or a hard drop can move the piece the length */
/* of the well in a single frame, and those boxes share no row - a      */
/* union would be a thin band down the whole field - so they use the    */
/* second slot (DS_PIECE2) instead.                                     */
/* ------------------------------------------------------------------ */
static void piece_sync(void)
{
    int on = (running && !game_over) ? 1 : 0;
    int x1 = 0, y1 = 0, x2 = 0, y2 = 0;

    if (on) {
        x1 = X0 + cur_x * CELLX;
        y1 = Y0 + cur_y * CELLY;
        x2 = X0 + (cur_x + pmax_x + 1) * CELLX - 1;
        y2 = Y0 + (cur_y + pmax_y + 1) * CELLY - 1;
    }

    /* Unchanged - a worst case is a piece sitting on the stack waiting for
       gravity to fail again, but it also covers a pause and the one frame a
       locked piece is held over before spawn() pulls in the next one. */
    if (on && pcb1 >= 0 && cur_type == pbt && cur_rot == pbro &&
        cur_x == pbx && cur_y == pby)
        return;

    {
        int near = (x1 <= pcb2 && pcb1 <= x2) && (y1 <= pby2 && pby1 <= y2);

        if (pcb1 >= 0 && on && near) {
            int ux1 = (pcb1 < x1) ? pcb1 : x1;
            int uy1 = (pby1 < y1) ? pby1 : y1;
            int ux2 = (pcb2 > x2) ? pcb2 : x2;
            int uy2 = (pby2 > y2) ? pby2 : y2;
            mark_dirty_slot(DS_PIECE, ux1, uy1, ux2, uy2);
        } else {
            if (pcb1 >= 0) mark_dirty_slot(DS_PIECE,  pcb1, pby1, pcb2, pby2);
            if (on)        mark_dirty_slot(DS_PIECE2, x1,   y1,   x2,   y2);
        }
    }
    pcb1 = -1;
    if (!on) { pbt = -1; return; }

    pcb1 = x1; pby1 = y1; pcb2 = x2; pby2 = y2;
    pbt = cur_type; pbro = cur_rot; pbx = cur_x; pby = cur_y;
}

/* ------------------------------------------------------------------ */
/* Key polarity auto-calibration                                       */
/*                                                                     */
/* The REG_KEY bit of a RELEASED key reads 1 or 0 depending purely on  */
/* which bitstream is loaded, and the shipped .fs does not match the    */
/* Verilog's "pressed = 0" comment. Guessing the polarity is what made  */
/* the previous attempts flip the mapping the wrong way. So MEASURE it  */
/* instead: watch each of the EIGHT register bits for the first 16      */
/* frames and take the level each bit held for MOST of them.            */
/*                                                                     */
/* It used to require a bit to be CONSTANT for all 16 frames, with      */
/* anything else left with NO idle level at all. read_keys() can only   */
/* report a press for a bit that is in one of the two masks, so such a  */
/* bit was not "uncertain" - it was DEAD for the whole session: picture */
/* up, panels drawn, press start, and nothing happens for ever. And the */
/* window is a trap, because video_boot() lights the panel up on its    */
/* very last write and key_calibrate() runs immediately after it, so    */
/* the moment the picture appears - the moment one reaches for the      */
/* start key - IS the calibration window. Majority keeps the level the  */
/* bit held while RELEASED, so a key pressed inside the window still    */
/* works, and a single glitched sample cannot kill a key either.        */
/*                                                                      */
/* (Only a key DOWN for the entire window is unmeasurable; releasing it */
/* later then reads as the press. Still: do not hold any key while the  */
/* board powers up or resets.)                                          */
/* ------------------------------------------------------------------ */
static uint32_t key_idle_hi, key_idle_lo;
static const uint32_t KEY_MASK = (1u << KEYS_USED) - 1u;

static void key_calibrate(void)
{
    uint8_t hi_cnt[KEYS_USED];
    int i, b;

    for (b = 0; b < KEYS_USED; b++) hi_cnt[b] = 0;
    for (i = 0; i < 16; i++) {
        uint32_t raw = apb_read(REG_KEY) & KEY_MASK;
        for (b = 0; b < KEYS_USED; b++)
            if (raw & (1u << b)) hi_cnt[b]++;
        wait_frame();
    }

    /* Every bit ends up in exactly ONE of the two masks: there is no such
       thing as a bit with no idle level any more. */
    key_idle_hi = 0u;
    for (b = 0; b < KEYS_USED; b++)
        if (hi_cnt[b] > 8) key_idle_hi |= 1u << b;   /* idles HIGH */
    key_idle_lo = KEY_MASK & ~key_idle_hi;           /* the rest idle LOW */
}

static uint32_t read_keys(void)
{
    /* The 74HC165 shifts for ~5us every 7.4ms; a read landing in that window
       can show transient bits. Reading twice and ANDing keeps only bits that
       are pressed in BOTH reads, which kills those ghosts. */
    uint32_t a  = apb_read(REG_KEY) & KEY_MASK;
    uint32_t b  = apb_read(REG_KEY) & KEY_MASK;
    uint32_t pa = ((~a) & key_idle_hi) | (a & key_idle_lo);
    uint32_t pb = ((~b) & key_idle_hi) | (b & key_idle_lo);
    return pa & pb;
}

/* ------------------------------------------------------------------ */
int main(void)
{
    uint32_t prev_pressed = 0;
    int r;

    running = 0;              /* blank screen until KEY_ROT_CW starts the game */
    refresh_values();            /* the values are baked, so format them first */
    r = video_boot(tetris_pal, 16);
    sound_init();                /* start the SysTick beeper (silent until a tone) */

    /* idle screen: nothing moves. Measure each key bit's idle level (do NOT
       hold a key while the board powers up), then poll the keys EVERY frame so
       the very first KEY_ROT_CW (up) press starts the game at once. The old
       fixed ~1.5 s HDMI-acquire wait used to swallow that first press. */
    spr_off(0); spr_off(1); spr_off(2); spr_off(3); spr_off(4);
    key_calibrate();
    for (;;) {
        uint32_t pressed, press_edge;
        wait_frame();
        pressed      = read_keys();
        press_edge   = pressed & ~prev_pressed;
        prev_pressed = pressed;
        if (press_edge & (1u << KEY_ROT_CW)) {
            init_game();                 /* clears the board, queues the NEXT
                                            strip and spawns the first piece */
            running = 1;
            sound_start_bgm();           /* background music for the playing game */
            break;
        }
        spr_off(0); spr_off(1); spr_off(2); spr_off(3); spr_off(4);
    }

    while (1) {
        uint32_t pressed, press_edge;

        /* 60 Hz tick: the fabric hands over a new free buffer every display
           frame, so pacing on the frame counter also gives the triple-buffer
           handshake (BUF_FREE / BUF_POST cross clock domains) a whole frame to
           settle before buf_begin() is read. */
        wait_frame();
        r = buf_begin();

        pressed   = read_keys();
        press_edge = pressed & ~prev_pressed;   /* single-frame edge: responsive */
        prev_pressed = pressed;

        {
            if (++blink_cnt >= 32) blink_cnt = 0;

            /* The game-over screen runs in TWO phases, both BAKED (see
               game_pixel) and both blinking: the GAME OVER words for GO_HOLD
               frames, then PRESS TO CONTINUE in the same band until any key
               starts a new game. Only a change of CONTENT repaints the band,
               so the blink's two flips and the single turn-over are the only
               frames that touch its rect. */
            if (game_over) {
                int on, key;
                go_frames++;
                if (go_phase == 0 && go_frames >= GO_HOLD) {
                    go_phase = 1;
                    blink_cnt = 0;          /* the prompt comes up lit */
                }
                on       = (blink_cnt < 16);
                go_shown = on;
                key      = on | (go_phase << 1);
                if (key != ban_state) {
                    ban_state = key;
                    mark_dirty_slot(DS_BANNER, BAN_X, BAN_Y,
                                    BAN_X + BAN_W - 1, BAN_Y + BAN_H - 1);
                }
            }

            /* K8 = pause: toggles freeze / resume (ignored while topped out) */
            if (!game_over && (press_edge & (1u << KEY_PAUSE))) paused = !paused;

            if (game_over) {
                /* topped out: while the GAME OVER words are up only the blink
                   runs; once the PRESS TO CONTINUE prompt has been up for
                   GO_GUARD frames ANY key starts a fresh game. The guard stops
                   the very key that topped the game out - or a panic-mash -
                   from skipping the screen before it can be read. */
                if (go_phase == 1 && go_frames >= GO_HOLD + GO_GUARD &&
                    press_edge != 0u) {
                    spr_off(0); spr_off(1); spr_off(2); spr_off(3); spr_off(4);
                    init_game();
                    sound_start_bgm();   /* fresh game -> restart the music */
                    /* wipe the old blocks, panels, score AND the prompt out of
                       ALL THREE buffers; the flat background above never
                       changes, so the repaint starts at the top of the field
                       outline */
                    mark_dirty(0, Y0 - BORDER, HOR_PIXELS - 1, VER_PIXELS - 1);
                }
            } else if (paused) {
                /* frozen: no input, no gravity, no redraw */
            } else {
                /* Spawn FIRST, then run this frame's input and gravity on the
                   piece that just came in: spawn_delay is 1 for exactly one
                   frame after a lock and place_piece() pre-charges the fall
                   timer, so on that one frame the piece both appears AND steps
                   down once, with the keys already live for it. Skipping the
                   input path while a piece was coming in (as it used to) is
                   exactly what made a piece look like it hung at the top of the
                   well before its first fall. A spawn that topped the game out
                   has nothing left to steer, so the rest of the frame is
                   skipped. */
                if (spawn_delay > 0 && --spawn_delay == 0) spawn();
                if (!game_over) {
                    /* left / right: move at once, then auto-repeat after
                       DAS_INITIAL */
                    int dir = (pressed & (1u << KEY_LEFT)) ? -1 :
                              (pressed & (1u << KEY_RIGHT)) ? 1 : 0;
                    if (dir == 0) { das_dir = 0; das_cnt = 0; }
                    else if (dir != das_dir) { das_dir = dir; das_cnt = DAS_INITIAL; try_move(dir, 0); }
                    else if (das_cnt > 0) { das_cnt--; }
                    else { try_move(dir, 0); das_cnt = DAS_REPEAT; }

                    /* K2 = rotate CW, K7 = rotate CCW - one step per press */
                    if (press_edge & (1u << KEY_ROT_CW))  do_rotate(+1);
                    if (press_edge & (1u << KEY_ROT_CCW)) do_rotate(-1);

                    /* K6 = hold / swap the piece (once per piece) */
                    if (press_edge & (1u << KEY_HOLD)) do_hold();

                    /* K5 = hard drop: slam down and lock at once. It ends the
                       piece's turn, so gravity is skipped on the same frame. */
                    if (press_edge & (1u << KEY_HARD_DROP)) {
                        do_hard_drop();
                    } else if (!game_over) {
                        /* gravity, or a faster manual drop while K4 is held. try_move
                           only ever moves the piece when the target cells are free and
                           inside the well, so it can neither pass through a block nor
                           the floor. */
                        if (pressed & (1u << KEY_SOFT_DROP)) {
                            grav_cnt = 0;          /* manual drop re-times the fall */
                            if (++soft_cnt >= SOFT_REPEAT) {
                                soft_cnt = 0;
                                if (!try_move(0, 1)) lock_piece();
                            }
                        } else {
                            soft_cnt = 0;
                            if (++grav_cnt >= grav_frames()) { grav_cnt = 0; if (!try_move(0, 1)) lock_piece(); }
                        }
                    }
                }
            }
        }

        ghost_sync();              /* keep the baked landing preview in step with
                                      the piece - free while it merely falls */
        piece_sync();              /* ...and the piece itself, which is baked
                                      for the same reason the ghost is */

        publish_sprites();

        if (dirty[r].pend) {
            int k, j;
            /* ONE transaction for the whole dirty set: every rect is staged
               into the same batch and the batch is pushed out once, so N rects
               still cost ONE write window rather than N of them.
               A rect already covered by another rect of the same frame is
               dropped: on the frame a piece locks, the playfield rect and the
               ghost's wipe cover exactly the same box, and staging both would
               compute - and push - every block of it twice. */
            paint_begin();
            for (k = 0; k < DIRTY_SLOTS; k++) {
                int drop = 0;
                if (!(dirty[r].pend & (1 << k))) continue;
                for (j = 0; j < DIRTY_SLOTS; j++) {
                    if (j == k || !(dirty[r].pend & (1 << j))) continue;
                    if (dirty[r].x1[k] >= dirty[r].x1[j] &&
                        dirty[r].x2[k] <= dirty[r].x2[j] &&
                        dirty[r].y1[k] >= dirty[r].y1[j] &&
                        dirty[r].y2[k] <= dirty[r].y2[j]) {
                        /* contained - but identical boxes must keep exactly
                           one of the pair, so only the later slot drops */
                        if (j < k ||
                            dirty[r].x1[k] != dirty[r].x1[j] ||
                            dirty[r].x2[k] != dirty[r].x2[j] ||
                            dirty[r].y1[k] != dirty[r].y1[j] ||
                            dirty[r].y2[k] != dirty[r].y2[j]) {
                            drop = 1;
                            break;
                        }
                    }
                }
                if (!drop)
                    paint_rect(dirty[r].x1[k], dirty[r].y1[k],
                               dirty[r].x2[k], dirty[r].y2[k]);
            }
            paint_end();
            dirty[r].pend = 0;
        }

        buf_post(r);
    }
}
