/*
 * pong.c - Pong, implemented ENTIRELY in C on top of the game-agnostic fabric.
 *
 * The fabric only knows 640x480@60, a 320x240x8bpp indexed framebuffer (which
 * it upscales 2x itself), a 16-entry palette and 5 generic rectangles (see
 * game_hal.h). This file owns:
 *   - the background / court / score (baked into the framebuffer),
 *   - the three moving objects (two paddles + ball), each driven as one of
 *     the hardware rectangles,
 *   - every coordinate (all in LOW-RESOLUTION 320x240 pixels), the physics,
 *     the AI, the scoring rules,
 *   - which of the 8 keys does what.
 *
 * Build this file INSTEAD of tetris.c (both define main()).
 */
#include "game_hal.h"

/* ------------------------------------------------------------------ */
/* Keys: bit index of the 74HC165 chain. Remap here at will.           */
/* ------------------------------------------------------------------ */
/* key_down(n) is bit n = board KEY(n+1).  The vertical key pair the player
   uses sits on register bits 5 and 6; on this board they came out inverted,
   so bit 6 raises the paddle and bit 5 lowers it.  K5 (bit 4) resets at any
   time.  After a game ends the GAME OVER words give way to PRESS TO CONTINUE
   and ANY of the eight keys starts a fresh match. */
#define KEY_P1_UP       6
#define KEY_P1_DOWN     5
#define KEY_RESET       4       /* K5 */

/* ------------------------------------------------------------------ */
/* Palette indices (16 entries). The colours themselves are written     */
/* below; the fabric has no built-in colour.                            */
/* ------------------------------------------------------------------ */
#define IDX_SKY0        0       /* sky zenith                          */
#define IDX_SKY1        1
#define IDX_SKY2        2
#define IDX_SKY3        3
#define IDX_BLACK       4       /* (unused now - the banner has no box)  */
#define IDX_CTR         5       /* the centre line (was the sun's yellow) */
#define IDX_HILL        6       /* (unused now - the hills are gone)    */
#define IDX_LINE        7       /* (unused now)                         */
#define IDX_GROUND      8
#define IDX_GROUND_DK   9       /* (unused now)                         */
#define IDX_SCORE       10
#define IDX_SCORE_DIM   11
#define IDX_P1          12
#define IDX_OVER        13      /* the GAME OVER words (was the unused P1 light) */
#define IDX_P2          14
#define IDX_BALL        15

/* The background is two flat fields: one sky colour, one ground colour. The
   old five-band sky gradient lives on in the palette above but only its
   middle entry is used - a band boundary is a line across the whole screen
   and the picture is not allowed to have any. */
#define IDX_SKY         IDX_SKY2

/* RGB444: only the HIGH NIBBLE of each byte survives (level = byte >> 4),
   so every value below is nibble-aligned - one hex digit per channel.
   The background itself only uses the centre line and the middle-sky entry now
   (see IDX_SKY); the rest of the sky gradient and the old hill/horizon/grass
   shades are kept because the palette is loaded as a whole, with one
   exception: entry 13 was the last one nobody drew with and it carries the
   GAME OVER words - red glyphs drawn straight over the scene, no box. Entry 5
   held the sun's warm yellow and now carries the centre line. */
static const uint32_t pong_pal[16] = {
    0x081030u,   /* 0  sky zenith    deep blue      */
    0x0A2050u,   /* 1  sky upper     blue           */
    0x0A2050u,   /* 2  sky middle    blue            */
    0x1050A0u,   /* 3  sky lower     light blue     */
    0x000000u,   /* 4  black         (unused now)   */
    0xA0B0C0u,   /* 5  centre line   pale grey      */
    0x205040u,   /* 6  hills         dark green     */
    0x70F0A0u,   /* 7  horizon line  pale green     */
    0x20A030u,   /* 8  ground        grass green    */
    0x106020u,   /* 9  ground deep   dark green     */
    0xF0D000u,   /* 10 score         bright gold    */
    0x706000u,   /* 11 score dim     dark gold      */
    0x00D0F0u,   /* 12 P1            cyan           */
    0xE02020u,   /* 13 red           GAME OVER text */
    0xF06020u,   /* 14 P2            orange-red     */
    0xF0F0C0u    /* 15 ball          warm white     */
};

/* ------------------------------------------------------------------ */
/* Geometry / physics (all in C - the fabric knows none of this).      */
/* Everything is in LOW-RESOLUTION pixels (320x240); the fabric doubles */
/* both axes on the way to the monitor.                                */
/* ------------------------------------------------------------------ */
#define DIGIT_SCALE     3
#define DIGIT_W         (3 * DIGIT_SCALE + 1)      /* 10 */
#define DIGIT_H         (5 * DIGIT_SCALE + 1)      /* 16 */
#define DIGIT_Y         6

#define PADDLE_W        5
#define PADDLE_H        50
#define PADDLE_MAX      (VER_PIXELS - PADDLE_H - 2)     /* 188 */
#define P1_X            5
/* Mirrors P1_X: 320 - 5 - PADDLE_W = 310, i.e. the same 10-output-pixel
   margin on the right as the left paddle has on the left. */
#define P2_X            310
#define BALL_HALF       3                               /* 7x7 ball */

#define P1_STEP         6
#define AI_STEP         6
#define AI_REACT_X      (HOR_PIXELS - 80)               /* 240 */
#define TICKS_PER_RENDER 1
#define BALL_VX0        2
#define BALL_VY0        2
#define MAX_VX          5
#define MAX_VY          3
#define RESPAWN_FRAMES  40
#define WIN_SCORE       15

/* The centre line: the classic Pong net down the middle of the field. It is
   2px wide (CTR_X-1 and CTR_X) so it reads at the same scale as the 5px
   paddles, and dashed 8 source rows on / 8 off. Both row parities are present
   inside an 8-row dash, so the read engine's row-pair interleave shows each
   dash solid - no doubling. */
#define CTR_X           (HOR_PIXELS / 2)

/* mirror points used when the ball bounces off a paddle: 2*M - x reflects the
   ball clear of the paddle without ever landing back inside it */
#define P1_MIRROR       (2 * (P1_X + PADDLE_W + BALL_HALF))   /* 26 */
#define P2_MIRROR       (2 * (P2_X - BALL_HALF - 1))          /* 612 */

/* Digit columns: two 2-digit groups centred at x=114 and x=206, symmetric
   about the middle of the 320-pixel line. Pitch 12 = glyph width 10 + 2 gap,
   so each group is 22 wide and starts 11 left of its centre. */
static const int32_t digit_x[4] = { 103, 115, 195, 207 };
/* 5x3 glyphs, one bit per pixel, bit index = row + col*5 (col 0 = left).
   Digit 1 is just a bare vertical column (bits 5..9 = col 1, rows 0..4); the
   flag and base serif it used to carry are gone again, as requested. */
static const uint16_t font5x3[10] = {
    0x7E3F, 0x03E0, 0x5EBD, 0x7EB5, 0x7C87,
    0x76B7, 0x76BF, 0x7C21, 0x7EBF, 0x7EB7
};

/* ------------------------------------------------------------------ */
/* State                                                               */
/* ------------------------------------------------------------------ */
static int32_t p1_pos, p2_pos;
static int32_t ball_x, ball_y;
static int32_t vx, vy;
static int32_t s1, s2;
static int32_t game_over;
static int32_t digit_dim;
static int32_t rally;
static int32_t respawn_wait;
static int32_t serve_dir = 1;
static int32_t await_start;     /* 1 = ball held at centre until the player presses a paddle key */
static int32_t go_phase;        /* 0 = the GAME OVER words are up,
                                   1 = the PRESS TO CONTINUE prompt is       */
static int32_t go_frames;       /* frames since the game ended (drives the
                                   words -> prompt turn-over and the guard)  */

/* Per-buffer last-rendered score, so the delta render knows what each     */
/* of the THREE framebuffers already holds. A shared copy would leave      */
/* ghosts: a buffer is only revisited every third frame.                   */
static int32_t old_s1[3] = { -1, -1, -1 }, old_s2[3] = { -1, -1, -1 };
static int32_t old_dim[3] = { -1, -1, -1 };
/* The GAME OVER banner is a baked picture with a blink phase of its own, so
   it needs the same per-buffer last-rendered memory as the score. What is
   remembered is a CONTENT key, not just the blink: (go_shown | go_phase<<1),
   so the phase turn-over repaints the band exactly like a blink flip does. */
static int32_t old_go[3] = { -1, -1, -1 };

/* ------------------------------------------------------------------ */
/* Sound. REG_BEEP's bit is fanned straight to the buzzer pin with no   */
/* fabric tone hardware, so the firmware's SysTick ISR flips the bit    */
/* every half-period of the current note - a clean square wave.         */
/*                                                                      */
/* There is ONE voice: exactly one thing can sound at a time, so the    */
/* rule is the arcade machine's. The music owns the buzzer; a one-shot  */
/* effect TAKES it away for the whole of its length and then hands it   */
/* back, and the music picks up on the note it was cut off in rather    */
/* than starting over. The paddle hit is the effect that rule exists    */
/* for: the music goes SILENT for the whole blip, so the hit is         */
/* unmistakable on its own, and comes back the moment the blip is over. */
/* ------------------------------------------------------------------ */
#define FCPU        27000000UL     /* M3 core clock (27 MHz board crystal) */

/* 30 kHz, not 20: a half-period is an integer count of ISR ticks, so the
   pitch error is +-1/(2*half), and at 20 kHz the tune's top octave came out
   audibly sharp (G5 as 833 Hz instead of 784). */
#define SND_RATE    30000UL        /* SysTick interrupts per second        */

/* note frequencies (Hz, integer - close enough for a buzzer); the sharps are
   needed by the game-over theme's chromatic turn, and E3 by its closing fall */
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

/* a note = half-period in ticks (0 = rest) + duration in ticks */
typedef struct { uint16_t half; uint16_t ticks; } Note;

/* The half-period is the only place intonation is decided, so it ROUNDS:
   dividing straight down is what put the top octave sharp. Durations count
   16ths of a beat at SND_BPM so a tune keeps its own rhythm instead of
   drifting, which a fixed ms per note type does. */
#define SND_BPM     140
#define T16         ((uint32_t)((SND_RATE * 60u) / ((uint32_t)SND_BPM * 16u)))

#define NOTE(f, n)   { (uint16_t)((SND_RATE + (f)) / (2u * (f))), \
                       (uint16_t)(T16 * (n)) }      /* n = 16ths of a beat */
#define REST(n)      { 0, (uint16_t)(T16 * (n)) }

/* Background music: Korobeiniki - the classic tetromino theme, and the one
   the machine itself plays. This is the SAME tune (and the same eight bars)
   the tetris build uses - "background music unchanged". At 140 BPM that is
   32 beats = 13.7 s, and it loops on a resolution (bars 4 and 8 both land on
   A), so the seam never sounds cut off. */
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

/* Paddle hit: a bright DESCENDING blip in the top register - C6, B5, AS5,
   6/6/8 sixteenths, about 0.54 s in all. The previous one sat in the bass
   (E4-D4-B3) to stay clear of the melody, but a one-bit buzzer drives a small
   speaker poorly down there: 250-330 Hz comes out weak and muddy, so the hit
   never really landed and what was heard was the music coming straight back.
   The melody tops out at A5 (880 Hz) - see bgm - so placing the hit at
   C6/B5/AS5 keeps it clear of the music by construction AND in the band the
   buzzer is efficient in, which is what makes it read as a sharp impact now.
   It falls rather than rises, so it cannot be taken for a rising phrase, and
   nothing here is a note of the music. */
static const Note fx_hit[] = {
    NOTE(N_C6,6), NOTE(N_B5,6), NOTE(N_AS5,8),
};

/* Game over: the SUPER MARIO BROS. "Game Over" screen theme - the slow,
   mournful phrase Koji Kondo wrote for the screen that comes up once the
   player's lives have run out. NOT the short "player down" jingle that plays
   on every lost life (a quick rising/falling flourish); this is the longer
   dirge that follows it, and nothing here is a note of the background music.
   Twelve notes in three gestures: a held high C with its fifth and third, a
   chromatic turn down around A (A B A G# A# G#), then a drop that settles on
   a LOW held G over the low E. At 140 BPM these 200 16ths-of-a-beat run
   ~5.4 s, and a REST(24) rounds the phrase out to ~6 s - the "first six
   seconds" asked for - then it LOOPS, because the losing screen stays up
   until the player starts a new game and a one-shot would leave them in
   silence. This is the SAME theme the tetris build uses. A close
   approximation, not a note-for-note transcription. */
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

#define BGM_N   ((uint16_t)(sizeof(bgm)     / sizeof(bgm[0])))
#define HIT_N   ((uint16_t)(sizeof(fx_hit)  / sizeof(fx_hit[0])))
#define OVR_N   ((uint16_t)(sizeof(fx_over) / sizeof(fx_over[0])))

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
static uint8_t  snd_fx_end;      /* the one-shot is out of notes but the pin
                                    is high: finish the half-cycle first    */

/* Where the music was when a one-shot took the buzzer away: the note and what
   was left of it. The carrier is deliberately NOT restored mid-cycle - the
   seam gets a gap and a clean start instead (see snd_after_fx). */
static uint16_t r_pos;
static uint32_t r_left, r_half, r_half_left;
static uint8_t  r_valid;

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
   straight into one another read as one continuous buzz. Hold the level at 0
   over the last ~13 ms of every note in the music and the jingle, which
   separates them without touching the tune. The cut is deferred to the end of
   the half-cycle in progress, so the waveform stops on a zero crossing instead
   of mid-cycle (which is a click). The hit is EXEMPT: its notes are 160 to
   214 ms of bright tone meant to ring, and a gate would eat into a note. */
#define GATE_TICKS  400         /* ~13 ms at SND_RATE */

/* How long the music stands off after the hit has finished before it comes
   back (see snd_after_fx). GATE_TICKS is only long enough to hide the seam
   click, and even the old tenth of a second put the music right down on the
   tail of the hit, so the hit could not be heard as a thing of its own. A
   quarter of a second of real silence is what lets the hit land; the music
   then picks up on exactly the note it was cut off in. */
#define RESUME_GAP  8000        /* ~267 ms at SND_RATE */

/* Start a sequence. carry = 0 (the music, the jingle): from silence, level 0
   and the pin forced low. carry = 1 (the hit): ADOPT the level the pin is
   already at and let the carrier run straight on, so taking the buzzer over
   mid-cycle does not jump the waveform - that jump is a click, and it is
   what the first moment of every hit used to sound like. */
static void snd_begin(const Note *seq, uint16_t len, int carry)
{
    snd_seq = seq; snd_len = len;
    snd_pos = 0;
    snd_gap = 0;                     /* a fresh sequence clears any seam   */
    snd_fx_end = 0;
    snd_half = seq[0].half;
    snd_left = seq[0].ticks;
    snd_half_left = snd_half;
    if (carry) {
        snd_level = beep_lvl;        /* carry the wave on, pin untouched   */
    } else {
        snd_level = 0;
        beep_out(0);
    }
}

/* The music, from the top. */
static void sound_start_bgm(void)
{
    r_valid = 0;                     /* a fresh tune is not a resume        */
    snd_mode = SM_BGM;
    snd_begin(bgm, BGM_N, 0);
}

/* The losing jingle, from the top; the ISR loops it in place. */
static void sound_over(void)
{
    r_valid = 0;
    snd_mode = SM_OVER;
    snd_begin(fx_over, OVR_N, 0);
}

/* A one-shot effect: it owns the buzzer for its whole length, which is what
   makes the hit audible on its own with the music silent underneath. A second
   effect while one is already playing just replaces it and keeps the ORIGINAL
   resume point. */
static void sound_fx(const Note *seq, uint16_t len)
{
    if (snd_mode == SM_BGM) {
        r_pos = snd_pos; r_left = snd_left; r_half = snd_half;
        r_half_left = snd_half_left;
        r_valid = 1;
    }
    snd_mode = SM_FX;
    snd_begin(seq, len, 1);          /* carry the wave on across the swap  */
}

/* Called from the ISR when a one-shot runs out: hand the buzzer back. */
static void snd_after_fx(void)
{
    if (r_valid) {
        r_valid  = 0;
        snd_mode = SM_BGM;
        snd_seq  = bgm;
        snd_len  = BGM_N;
        snd_pos  = r_pos;
        snd_left = r_left;
        snd_half = r_half;
        snd_half_left = r_half_left;
        /* Resume seam. Hold silence for RESUME_GAP and start the carrier on a
           period boundary from level 0: without the gap the effect's last note
           ran straight into the resumed one, so the hit was buried under the
           music and read as a click rather than as a hit. The gap is what lets
           the hit be heard by itself; the restarted carrier is what keeps the
           seam from clicking. */
        snd_level = 0;
        snd_half_left = snd_half;
        snd_gap = RESUME_GAP;
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

    /* The one-shot is out of notes but the carrier happens to be HIGH: let
       the half-cycle in progress finish first, so the buzzer always leaves
       the effect on a zero crossing. Cutting the pin the instant the last
       tick ran out put an edge where the waveform's own rhythm has none,
       which is heard as a click exactly when the music comes back. */
    if (snd_fx_end) {
        if (snd_half_left == 0u || --snd_half_left == 0u) {
            snd_fx_end = 0;
            snd_level  = 0;
            beep_out(0);
            snd_after_fx();
        } else {
            beep_out((int)snd_level);
        }
        return;
    }

    if (--snd_left == 0u) {
        snd_pos++;
        if (snd_pos >= snd_len) {
            if (snd_mode == SM_FX) {   /* one-shot over -> music resumes */
                if (snd_level) { snd_fx_end = 1; return; }   /* see above */
                snd_after_fx();
                return;
            }
            snd_pos = 0;               /* music and jingle loop in place */
        }
        snd_half      = snd_seq[snd_pos].half;
        snd_left      = snd_seq[snd_pos].ticks;
        snd_half_left = snd_half;
        /* The music and the jingle drop to 0 across a note boundary; their
           notes are long enough to have been ended by the articulation gate
           already, so this is belt and braces. The one-shot does NOT: forcing
           the pin to 0 there cut the wave mid-cycle at every note of the hit
           (a click each time) and cost the following note its first
           half-cycle, which is why the hit sounded thin. It carries on
           instead, as an unbroken run. */
        if (snd_mode != SM_FX) { snd_level = 0; beep_out(0); }
        return;
    }

    half = snd_half;
    if (half == 0u) { beep_out(0); return; }   /* rest */

    /* Articulation / anti-click gate - see GATE_TICKS. Only the music and the
       jingle hold a note long enough to need it; the short hit does not.
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
           pulse timbre. The hit and the jingle keep the square: the hit is
           short and high, and the jingle is low and short. */
        if (snd_mode == SM_BGM) {
            uint32_t hi = (half + 1u) >> 1;
            snd_half_left = snd_level ? hi : (half + hi);
        } else {
            snd_half_left = half;
        }
        beep_out((int)snd_level);
    }
}

/* ------------------------------------------------------------------ */
/* GAME OVER banner + PRESS TO CONTINUE prompt. The words only - RED    */
/* glyphs baked into the framebuffer, with NOTHING behind them: every   */
/* pixel that is not a lit glyph keeps whatever the sky/sun/score would  */
/* put there, so neither string ever covers the picture. Baking is used */
/* rather than the five hardware rectangles because a rectangle fills   */
/* one flat colour and they are already the paddles and the ball.       */
/* The GAME OVER words (5x7 font at 3x: nine glyphs on a 6*3 px grid =  */
/* 162x21 px) flash for a moment, then give way - in the SAME band - to */
/* PRESS TO CONTINUE (2x, 204x14 px), which blinks until any key starts */
/* a fresh game.                                                        */
/* ------------------------------------------------------------------ */
#define GO_STR          "GAME OVER"
#define GO_N            9
#define GO_SC           3
#define GO_W            (GO_N * 6 * GO_SC)              /* 162 */
#define GO_H            (7 * GO_SC)                     /* 21  */
#define GO_X            ((HOR_PIXELS - GO_W) / 2)       /* 79  */
#define GO_Y            ((VER_PIXELS - GO_H) / 2)       /* 109 */

#define PC_STR          "PRESS TO CONTINUE"
#define PC_N            17
#define PC_SC           2
#define PC_W            (PC_N * 6 * PC_SC)              /* 204 */
#define PC_H            (7 * PC_SC)                     /* 14  */
#define PC_X            ((HOR_PIXELS - PC_W) / 2)       /* 58  */
#define PC_Y            (GO_Y + (GO_H - PC_H) / 2)      /* 112 */

/* ONE rect for the band: the union of both strings, so a blink flip OR the
   phase turn-over each cost a single repaint. The prompt is wider than the
   words and PC_Y sits inside GO_Y..GO_Y+GO_H-1, so it bounds the union. */
#define BAN_X           PC_X
#define BAN_Y           GO_Y
#define BAN_W           PC_W
#define BAN_H           GO_H

#define GO_HOLD          96     /* frames the GAME OVER words flash before the
                                   prompt takes their place. The blink is 16 lit
                                   + 16 dark = one 32-frame cycle (see blink_cnt
                                   in the main loop), so 96 = exactly THREE
                                   flashes (~1.6 s)                         */
#define GO_GUARD         60     /* frames the prompt must be up before any key
                                   may start a new game (~1 s)             */

static int go_shown;            /* 1 = the banner's lit phase is what the
                                   framebuffer holds, 0 = its dark phase   */
static uint32_t blink_cnt;      /* free-running frame counter the GAME OVER
                                   blink phases are derived from (reset when
                                   a game ends, so the banner starts lit)   */

/* 5x7 font, column-encoded (byte = one column, bit 0 = top row).       */
/* Indices 0..9 = '0'..'9', 10..35 = 'A'..'Z'.                           */
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

/* Is (px,py) a lit pixel of the n-character string s drawn at (x0,y0)?
   sc = integer scale. The glyph grid is 6*sc wide per character, 7*sc tall;
   a blank between words falls out of it as an unlit pixel. */
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

/* ------------------------------------------------------------------ */
/* What the framebuffer holds at (x,y): background + baked score + the  */
/* GAME OVER banner.                                                    */
/* The ball and BOTH paddles are NOT here - they are hardware          */
/* rectangles, so nothing has to be erased when they move.             */
/*                                                                     */
/* SOLID FILLS ONLY                                                    */
/*   The whole field is ONE flat palette entry (blue), plus the dashed     */
/*   centre line and the baked score digits - pure flat fills, exactly like */
/*   the two paddles. A hard boundary between two different colours would   */
/*   draw a line across the screen, and dithering reads as a fringe of      */
/*   grain under the fabric's 2x nearest-neighbour upscale, so both are     */
/*   gone.                                                                   */
/* ------------------------------------------------------------------ */

static uint8_t game_pixel(int x, int y)
{
    uint8_t col;

    /* ---- GAME OVER / PRESS TO CONTINUE banner, top priority. The words are
       RED (IDX_OVER) and NOTHING ELSE: there is no box behind them, so a pixel
       that is not a lit glyph falls through to the sky. The banner never covers
       the picture. The whole banner blinks: while go_shown is 0 it is simply
       not there. Which string is up is go_phase - the GAME OVER words first,
       then the prompt in the same band. --- */
    if (game_over && go_shown) {
        if (go_phase == 0) {
            if (x >= GO_X && x < GO_X + GO_W &&
                y >= GO_Y && y < GO_Y + GO_H &&
                text_scan(x, y, GO_X, GO_Y, GO_STR, GO_N, IDX_OVER, GO_SC, &col))
                return col;
        } else if (x >= PC_X && x < PC_X + PC_W &&
                   y >= PC_Y && y < PC_Y + PC_H &&
                   text_scan(x, y, PC_X, PC_Y, PC_STR, PC_N, IDX_OVER, PC_SC, &col))
            return col;
    }

    if (y >= DIGIT_Y && y < DIGIT_Y + DIGIT_H) {
        int d, row = (y - DIGIT_Y) / DIGIT_SCALE;
        for (d = 0; d < 4; d++) {
            if (x >= digit_x[d] && x < digit_x[d] + DIGIT_W) {
                int col = (x - digit_x[d]) / DIGIT_SCALE;
                int val = (d == 0) ? s1 / 10 : (d == 1) ? s1 % 10 :
                          (d == 2) ? s2 / 10 : s2 % 10;
                if (row < 5 && col < 3 &&
                    (font5x3[val] & (1u << (row + col * 5))))
                    return (uint8_t)(digit_dim ? IDX_SCORE_DIM : IDX_SCORE);
                break;                       /* off pixel -> sky */
            }
        }
    }
    /* The centre line (the "net"), drawn straight over the flat sky. */
    if (x >= CTR_X - 1 && x <= CTR_X && ((y >> 3) & 1) == 0)
        return IDX_CTR;
    return IDX_SKY;                          /* whole field one flat blue */
}

/* ------------------------------------------------------------------ */
/* Rules / physics                                                     */
/* ------------------------------------------------------------------ */
static void game_reset(void)
{
    p1_pos = 95; p2_pos = 95;
    ball_x = 160; ball_y = 120;
    vx = BALL_VX0; vy = BALL_VY0;
    s1 = 0; s2 = 0;
    game_over = 0; digit_dim = 0;
    go_shown = 0;                   /* a fresh board carries no banner */
    go_phase = 0;                   /* ...and it starts on the words, not
                                       the prompt                            */
    go_frames = 0;
    /* A fresh game does NOT serve until the player presses a paddle key: the
       ball sits still at centre with the score locked at 0:00. This is what
       stops the AI from running up 0:02 on an idle player the moment the
       picture appears. */
    await_start = 1;
    rally = 0; respawn_wait = 0; serve_dir = 1;
}

static void ball_speed_up(void)
{
    int32_t m;
    if (rally < 63) rally++;
    m = BALL_VX0 + (rally >> 1); if (m > MAX_VX) m = MAX_VX;
    vx = (vx < 0) ? -m : m;
    m = BALL_VY0 + (rally >> 2); if (m > MAX_VY) m = MAX_VY;
    vy = (vy < 0) ? -m : m;
}

static void game_tick(void)
{
    if (respawn_wait > 0) {
        if (--respawn_wait == 0) {
            rally = 0;
            ball_x = 160; ball_y = 120;
            vx = (serve_dir > 0) ? BALL_VX0 : -BALL_VX0;
            vy = BALL_VY0;
        }
        return;
    }
    if (game_over)
        return;

    ball_y += vy;
    if (ball_y < BALL_HALF) {
        ball_y = 2 * BALL_HALF - ball_y; vy = -vy; ball_speed_up();
    }
    if (ball_y > VER_PIXELS - 1 - BALL_HALF) {
        ball_y = 2 * (VER_PIXELS - 1 - BALL_HALF) - ball_y; vy = -vy; ball_speed_up();
    }

    /* horizontal motion in <=2 px sub-steps so the ball can never tunnel
       through a paddle even at MAX_VX */
    {
        int32_t remain = vx;
        while (remain != 0) {
            int32_t step = remain;
            if (step >  2) step =  2;
            if (step < -2) step = -2;
            ball_x += step;
            remain -= step;

            if (vx < 0 && ball_x > (P1_X - BALL_HALF) &&
                ball_x < (P1_X + PADDLE_W + BALL_HALF) &&
                ball_y > p1_pos - 2 && ball_y < p1_pos + PADDLE_H + 2) {
                ball_x = P1_MIRROR - ball_x; vx = -vx; ball_speed_up();
                sound_fx(fx_hit, HIT_N); break;
            }
            if (vx > 0 && ball_x > (P2_X - BALL_HALF) &&
                ball_x < (P2_X + PADDLE_W + BALL_HALF) &&
                ball_y > p2_pos - 2 && ball_y < p2_pos + PADDLE_H + 2) {
                ball_x = P2_MIRROR - ball_x; vx = -vx; ball_speed_up();
                sound_fx(fx_hit, HIT_N); break;
            }
            if (ball_x < 2 || ball_x > (HOR_PIXELS - 2))
                break;
        }
    }

    if (ball_x < 3) {
        s2++;
        if (s2 >= WIN_SCORE) { game_over = 1; blink_cnt = 0; go_shown = 1;
                               go_phase = 0; go_frames = 0;
                               sound_over(); }
        else { ball_x = 350; ball_y = 350; rally = 0;
               serve_dir = -serve_dir; respawn_wait = RESPAWN_FRAMES; }
    } else if (ball_x > HOR_PIXELS - 3) {
        s1++;
        if (s1 >= WIN_SCORE) { game_over = 1; blink_cnt = 0; go_shown = 1;
                               go_phase = 0; go_frames = 0;
                               sound_over(); }
        else { ball_x = 350; ball_y = 350; rally = 0;
               serve_dir = -serve_dir; respawn_wait = RESPAWN_FRAMES; }
    }
}

/* ------------------------------------------------------------------ */
/* Publish the three rectangles the game uses: two paddles at 0/1 and  */
/* the ball at 2, so the ball paints over the paddles.                 */
/* ------------------------------------------------------------------ */
static void publish_sprites(void)
{
    /* The ball is ONE plain square rectangle, exactly like the two paddles -
       rounding it off with extra overlapping rectangles only produced ragged
       steps where they crossed under the overlay priority rule. */
    spr_box(0, P1_X, (int)p1_pos, PADDLE_W, PADDLE_H, IDX_P1, 1);
    spr_box(1, P2_X, (int)p2_pos, PADDLE_W, PADDLE_H, IDX_P2, 1);
    spr_box(2, (int)(ball_x - BALL_HALF), (int)(ball_y - BALL_HALF),
            2 * BALL_HALF + 1, 2 * BALL_HALF + 1, IDX_BALL, 1);
}

/* Delta render of the baked score into buffer r. */
static void render(int r)
{
    int32_t ps1 = old_s1[r], ps2 = old_s2[r], pdim = old_dim[r];
    if (s1 != ps1 || s2 != ps2 || digit_dim != pdim) {
        int d;
        for (d = 0; d < 4; d++) {
            int32_t val  = (d == 0) ? s1 / 10 : (d == 1) ? s1 % 10 :
                           (d == 2) ? s2 / 10 : s2 % 10;
            int32_t pval = (d == 0) ? ps1 / 10 : (d == 1) ? ps1 % 10 :
                           (d == 2) ? ps2 / 10 : ps2 % 10;
            if (val != pval || digit_dim != pdim)
                draw_rect(digit_x[d], DIGIT_Y,
                          digit_x[d] + DIGIT_W - 1, DIGIT_Y + DIGIT_H - 1);
        }
        ps1 = s1; ps2 = s2; pdim = digit_dim;
    }
    old_s1[r] = ps1; old_s2[r] = ps2; old_dim[r] = pdim;

    /* Banner: repaint only when THIS buffer's CONTENT differs from what it
       already holds - one 204x21 band repaint per blink flip or phase
       turn-over, not per frame. The key carries the phase as well as the
       blink, so the words -> prompt switch repaints it exactly like a flip. */
    {
        int32_t gkey = (int32_t)((uint32_t)go_shown | ((uint32_t)go_phase << 1));
        if (gkey != old_go[r]) {
            draw_rect(BAN_X, BAN_Y, BAN_X + BAN_W - 1, BAN_Y + BAN_H - 1);
            old_go[r] = gkey;
        }
    }
}

/* ------------------------------------------------------------------ */
int main(void)
{
    uint32_t prev_keys = 0xFFFFFFFFu;
    uint32_t reset_hold = 0;
    int r;

    game_reset();
    video_boot(pong_pal, 16);       /* palette, fill all 3 buffers, unblank */

    /* Arm the SysTick beeper. It must happen AFTER video_boot: boot's
       delay_ms() reprograms SysTick itself. It starts SILENT - the
       background music only comes on when the player presses up (see the
       await_start branch below), which is the "press up -> music" rule.  */
    sound_init();

    old_s1[0] = old_s1[1] = old_s1[2] = s1;
    old_s2[0] = old_s2[1] = old_s2[2] = s2;
    old_dim[0] = old_dim[1] = old_dim[2] = digit_dim;
    old_go[0] = old_go[1] = old_go[2] = go_shown;

    /* Seed the key-edge baseline from the settled read, NOT 0xFFFFFFFF. If the
       74HC165 chain reports any bit low on the first frame (it can while it
       settles after config/reset), the old init would turn that into a phantom
       press edge, clearing await_start and letting the AI score immediately -
       the "score already up on boot" symptom. */
    prev_keys = apb_read(REG_KEY);

    while (1) {
        /* 60 Hz tick. It also separates buf_post() from the next buf_begin()
           by a whole frame, which is what makes reading BUF_FREE safe across
           its clock-domain crossing. */
        wait_frame();
        r = buf_begin();            /* the buffer the fabric is NOT showing  */

        uint32_t keys_now = apb_read(REG_KEY);
        uint32_t press_edge = (~keys_now) & prev_keys;
        prev_keys = keys_now;

        if (press_edge & (1u << KEY_RESET)) {
            if (reset_hold == 0) { game_reset(); sound_start_bgm();
                                   reset_hold = 12; }
        }
        if (reset_hold) reset_hold--;

        /* Serve only once the player touches a paddle key. Until then the
           ball is held at centre and the score stays locked at 0:00 - the
           game must not auto-start and let the AI score on an idle player. */
        if (await_start &&
            (press_edge & ((1u << KEY_P1_UP) | (1u << KEY_P1_DOWN)))) {
            await_start = 0;
            /* The player has started: the background music comes on here.
               Guarded so a paddle key pressed again later does not cut the
               tune back to its first bar - and after K5 the music is already
               running, so this is a no-op for that case. */
            if (snd_mode != SM_BGM) sound_start_bgm();
            respawn_wait = RESPAWN_FRAMES;   /* short ready pause, then serve */
        }

        if (!game_over && !await_start) {
            if (key_down(KEY_P1_UP))   p1_pos -= P1_STEP;
            if (key_down(KEY_P1_DOWN)) p1_pos += P1_STEP;
            if (p1_pos < 0) p1_pos = 0;
            if (p1_pos > PADDLE_MAX) p1_pos = PADDLE_MAX;

            if (ball_x > AI_REACT_X && vx > 0) {
                if (ball_y < p2_pos + 15)      p2_pos -= AI_STEP;
                else if (ball_y > p2_pos + 35) p2_pos += AI_STEP;
                if (p2_pos < 0) p2_pos = 0;
                if (p2_pos > PADDLE_MAX) p2_pos = PADDLE_MAX;
            }

            {
                int t;
                for (t = 0; t < TICKS_PER_RENDER; t++)
                    game_tick();
            }
        } else if (game_over) {
            /* The game-over screen runs in two phases, both baked (see
               game_pixel) and both blinking: the GAME OVER words for GO_HOLD
               frames, then PRESS TO CONTINUE in the same band until any key
               starts a fresh game. */
            if (++blink_cnt >= 32) { blink_cnt = 0; digit_dim ^= 1; }
            go_frames++;
            if (go_phase == 0 && go_frames >= GO_HOLD) {
                go_phase = 1;
                blink_cnt = 0;          /* the prompt comes up lit */
            }
            /* The banner blinks at half the rate of the score dim: lit for the
               first half of each 32-frame span, gone for the second half. */
            go_shown = (blink_cnt < 16);

            /* Once the PRESS TO CONTINUE prompt has been up for GO_GUARD
               frames ANY key starts a new game. The guard stops the
               panic-mash that lost the match - or the key still being held
               from it - from skipping the screen before it can be read. */
            if (go_phase == 1 && go_frames >= GO_HOLD + GO_GUARD &&
                (press_edge & 0xFFu)) {
                game_reset();
                sound_start_bgm();      /* fresh game -> restart the music */
                reset_hold = 12;        /* K5's own debounce, reused here */
            }
        }

        publish_sprites();
        render(r);
        buf_post(r);                /* hand the finished buffer back */
    }
}