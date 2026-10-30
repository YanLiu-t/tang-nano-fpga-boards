/*
 * game_hal.h - shared HAL for the Tang Nano 4K "C owns the game" firmware.
 *
 * The Verilog/fabric is GAME-AGNOSTIC and only provides:
 *   - 640x480@60 video out of a 320x240x8bpp INDEXED framebuffer in HyperRAM
 *     which the fabric upscales 2x in BOTH directions (1 byte = 1 pixel = 1
 *     palette index, stored LINEARLY: byte index = y*HOR_PIXELS + x, and a
 *     128-byte block may therefore span a row boundary);
 *   - a 16-entry RGB333 palette - the ONLY place in the design where an
 *     actual colour exists (index -> {B,G,R});
 *   - 5 generic rectangles overlaid in the pixel path, each written as
 *     {x, y, w, h, colour index, enable} in LOW-RESOLUTION pixels;
 *   - an 8-key 74HC165 shift register (pressed = 0).
 *
 * EVERYTHING ELSE lives in the game's own C file: object shapes and counts,
 * the rules, every coordinate, the AI, and the MEANING of each of the 8 keys.
 *
 * A game file includes this header, implements  game_pixel(x,y)  (what the
 * framebuffer should hold at each pixel - background + anything baked into
 * memory), defines main(), and drives the 5 rectangles for whatever moves.
 *
 * The framebuffer is TRIPLE buffered by the fabric (front / middle / back), so
 * the M3 renders into a buffer that is neither visible nor about to become
 * visible, and a game never has to wait for a flip:
 *
 *     r = buf_begin();          // buffer the fabric hands over
 *     ... draw into it with draw_rect() / draw_full() ...
 *     buf_post(r);              // hand it back -> visible next frame
 *
 * Because each buffer is revisited only every THIRD frame, any delta-render
 * state ("what does THIS buffer already contain") must be kept per buffer -
 * see the games' old_*[3] / dirty[3] arrays. One shared copy of that state
 * would leave ghosts, exactly like single buffering did.
 */
#ifndef GAME_HAL_H
#define GAME_HAL_H

#include "gw1ns4c.h"
#include "delay.h"

/* ------------------------------------------------------------------ */
/* Screen geometry                                                     */
/* ------------------------------------------------------------------ */
#define HOR_PIXELS      320
#define VER_PIXELS      240
#define BLOCK_BYTES     128
#define FRAME_BLOCKS    ((HOR_PIXELS * VER_PIXELS) / BLOCK_BYTES)   /* 600 */

/* ------------------------------------------------------------------ */
/* APB2 register map (matches src/apb_fb_reg.v)                        */
/* ------------------------------------------------------------------ */
#define GAME_APB_BASE   (APB2MASTER1_BASE)      /* 0x40002400           */

#define REG_KEY         0x04    /* RO keys, pressed = 0                 */
#define REG_HP          0x08    /* RO bit0 = HyperRAM init done         */
#define REG_FRAME       0x0C    /* RO [7:0] 60 Hz display frame counter */
#define REG_FB_BLK      0x24    /* WO [12:0] target 128-byte block      */
#define REG_FB_DATA     0x28    /* WO one 4-pixel word (toggles req)    */
#define REG_FB_STATUS   0x2C    /* RO bit0 = ack sync                   */
#define REG_BUF_POST    0x30    /* WO [1:0] buffer just finished        */
#define REG_BUF_DISP    0x34    /* RO [1:0] buffer being scanned (0..2) */
#define REG_FB_READY    0x38    /* WO toggle: first whole frame is up   */
#define REG_BUF_FREE    0x3C    /* RO [1:0] buffer to render into next  */
#define REG_PAL_INDEX   0x50    /* WO [7:0] index for the next PAL_DATA */
#define REG_PAL_DATA    0x54    /* WO 0x00RRGGBB -> pal[idx], idx++     */
#define REG_SPR_BANK    0x40    /* WO bit0: 0 -> rect 0..3, 1 -> 4..7   */
#define REG_BEEP        0x5C    /* WO any write -> start the collision tone */
#define SPR_BASE        0x80    /* WO + 0x20*n + 4*field, rectangle n<4 */

static inline uint32_t apb_read(uint32_t off)
{
    return *(volatile uint32_t *)(GAME_APB_BASE + off);
}

static inline void apb_write(uint32_t off, uint32_t val)
{
    *(volatile uint32_t *)(GAME_APB_BASE + off) = val;
}

/* ------------------------------------------------------------------ */
/* Keys: 8 bits, bit n = key n+1, pressed = 0. Which key does what is  */
/* decided by the game's own #defines - the fabric has no opinion.     */
/* ------------------------------------------------------------------ */
static inline int key_down(int n)
{
    return (apb_read(REG_KEY) & (1u << n)) == 0u;
}

/* ------------------------------------------------------------------ */
/* Collision tone. The fabric has NO tone hardware (its register budget */
/* is full on GW1NSR-4C); it just fans REG_BEEP's bit out to the buzzer */
/* pin. The firmware's SysTick ISR flips this bit at the tone frequency */
/* - see beep_start() / SysTick_Handler in the game file.               */
/* ------------------------------------------------------------------ */
static inline void beep_set(int level)
{
    apb_write(REG_BEEP, (uint32_t)(level ? 1u : 0u));
}

/* ------------------------------------------------------------------ */
/* Colour palette (16 x RGB444). C writes 0x00RRGGBB; the hardware     */
/* keeps the TOP NIBBLE of each channel (level = byte >> 4, 0..15) and */
/* expands it back to 8 bits. So write nibble-aligned values only,     */
/* e.g. 0x00D0F0 - a plain 8-bit value like 0x141A3C would lose 4 bits */
/* per channel and come out too dark.                                  */
/* ------------------------------------------------------------------ */
static void pal_load(const uint32_t *tbl, int n)
{
    int i;
    apb_write(REG_PAL_INDEX, 0u);
    for (i = 0; i < n; i++)
        apb_write(REG_PAL_DATA, tbl[i] & 0xFFFFFFu);   /* auto-increment */
}

/* ------------------------------------------------------------------ */
/* Generic rectangles. Rectangle n (0..7) covers x in [sx, sx+sw) and   */
/* y in [sy, sy+sh). Higher n paints over lower n, so write the         */
/* back-most object first. The address window 0x80..0xFF only reaches   */
/* rectangles 0..3; REG_SPR_BANK selects which half the next writes go  */
/* to, so every access must set the bank first (n >> 2).                */
/*                                                                      */
/* The fabric stores the EXCLUSIVE right/bottom EDGES, not w/h: the     */
/* per-pixel hit test compares directly against them so it needs no     */
/* adder, which is what let NS grow to 8 on this CLS-bound part.        */
/* spr_box() converts (w,h) -> (x+w, y+h) for the caller.               */
/* ------------------------------------------------------------------ */
#define SPR_F_X     0           /* x0                            */
#define SPR_F_Y     1           /* y0                            */
#define SPR_F_XE    2           /* x1 = x0 + w  (exclusive)      */
#define SPR_F_YE    3           /* y1 = y0 + h  (exclusive)      */
#define SPR_F_C     4

static void spr_box(int n, int x, int y, int w, int h, int colour, int enable)
{
    uint32_t b = SPR_BASE + 0x20u * (uint32_t)(n & 3);   /* word-aligned slot */
    apb_write(REG_SPR_BANK, (uint32_t)(n >> 2) & 1u);
    apb_write(b + 4u * SPR_F_X,  (uint32_t)x);
    apb_write(b + 4u * SPR_F_Y,  (uint32_t)y);
    apb_write(b + 4u * SPR_F_XE, (uint32_t)(x + w));
    apb_write(b + 4u * SPR_F_YE, (uint32_t)(y + h));
    apb_write(b + 4u * SPR_F_C,
              (uint32_t)(((enable ? 1u : 0u) << 8) | ((uint32_t)colour & 0xFu)));
}

/* Like spr_box(), but with a DASH flag (bit 9). A dashed rectangle is painted
   on a 2x2 checkerboard, so its fill reads as dotted/dashed instead of solid. */
static void spr_box_d(int n, int x, int y, int w, int h, int colour, int enable, int dash)
{
    uint32_t b = SPR_BASE + 0x20u * (uint32_t)(n & 3);   /* word-aligned slot */
    apb_write(REG_SPR_BANK, (uint32_t)(n >> 2) & 1u);
    apb_write(b + 4u * SPR_F_X,  (uint32_t)x);
    apb_write(b + 4u * SPR_F_Y,  (uint32_t)y);
    apb_write(b + 4u * SPR_F_XE, (uint32_t)(x + w));
    apb_write(b + 4u * SPR_F_YE, (uint32_t)(y + h));
    apb_write(b + 4u * SPR_F_C,
              (uint32_t)(((dash   ? 1u : 0u) << 9) |
                         ((enable ? 1u : 0u) << 8) |
                         ((uint32_t)colour & 0xFu)));
}

static void spr_off(int n)
{
    apb_write(REG_SPR_BANK, (uint32_t)(n >> 2) & 1u);
    apb_write(SPR_BASE + 0x20u * (uint32_t)(n & 3) + 4u * SPR_F_C, 0u);
}

/* ------------------------------------------------------------------ */
/* Framebuffer write (level handshake, see apb_fb_reg.v):              */
/* write FB_BLK once, then exactly 32 words; poll the ack bit after    */
/* each word so the fabric can never be overrun.                       */
/* ------------------------------------------------------------------ */
static uint32_t fb_req_expected;

static inline void fb_word(uint32_t data)
{
    uint32_t timeout = 0x200000u;
    fb_req_expected ^= 1u;
    apb_write(REG_FB_DATA, data);
    while (((apb_read(REG_FB_STATUS) & 1u) != fb_req_expected) && --timeout)
        ;
}

/* One 128-byte block of the LINEAR framebuffer: buf[0..127] are consecutive
   frame bytes starting at linear offset blk*128. 128 does not divide 320, so a
   block generally SPANS a row boundary - the C side never has to care. */
static void fb_block(uint32_t blk, const uint8_t *buf)
{
    int k;
    apb_write(REG_FB_BLK, blk);
    for (k = 0; k < 32; k++) {
        uint32_t w = ((uint32_t)buf[4 * k]     << 24) |
                     ((uint32_t)buf[4 * k + 1] << 16) |
                     ((uint32_t)buf[4 * k + 2] <<  8) |
                     ((uint32_t)buf[4 * k + 3]);
        fb_word(w);
    }
}

/* ------------------------------------------------------------------ */
/* Composing. The game implements game_pixel(x, y) -> palette index;    */
/* the helpers turn that into framebuffer writes.                       */
/*                                                                      */
/* A repaint runs in TWO PHASES, and that is the whole reason it is     */
/* affordable. FIRST the pixels of a whole BATCH of blocks are computed */
/* into a RAM staging area - no APB traffic at all, so the M3 never     */
/* waits on the fabric. THEN the batch is pushed out block by block.    */
/*                                                                      */
/* The write window is the scarce resource: in steady state the fabric  */
/* only releases a write burst inside the vertical blanking interval    */
/* (~1.4 ms of every 16.7 ms display frame), and ONE window opens per   */
/* frame, so the M3 spends the active-video period waiting for its next */
/* ack. Computing one block costs 128 game_pixel() calls - several      */
/* times what pushing its 32 words back costs - and doing BOTH per      */
/* block leaves most of that window idle. Measured, that fits ~12       */
/* blocks into a frame, which is why a piece-sized repaint used to      */
/* stall the game for ~7 frames. Batched, the compute happens outside   */
/* the window and the SAME window takes 100+ blocks.                    */
/*                                                                      */
/* That is also why a repaint must be ONE transaction: every rect of a  */
/* frame's dirty set goes into the same batch, so a spawn (the NEXT     */
/* strip AND the landing preview) costs one window, not one per rect.   */
/* So: paint_begin() ... paint_rect() per dirty rect ... paint_end().   */
/* ------------------------------------------------------------------ */
static uint8_t game_pixel(int x, int y);       /* implemented by the game */

#define STAGE_BLOCKS    80      /* 80 x 128 B = 10 KB of the 16 KB RAM */
static uint8_t  stage[STAGE_BLOCKS * BLOCK_BYTES];
static uint16_t stage_blk[STAGE_BLOCKS];
static int      stage_n;

/* Compute block blk into the next staging slot. The linear byte range is
   walked with an incrementing x/y instead of a divide per pixel, so the two
   divides happen once per BLOCK instead of 128 times - that alone is a third
   of the compute cost, and it runs for every block of every repaint. */
static void stage_block(int blk)
{
    int lin = blk * BLOCK_BYTES;
    int x = lin % HOR_PIXELS, y = lin / HOR_PIXELS;
    uint8_t *dst = stage + stage_n * BLOCK_BYTES;
    int j;
    stage_blk[stage_n] = (uint16_t)blk;
    for (j = 0; j < BLOCK_BYTES; j++) {
        dst[j] = (lin < HOR_PIXELS * VER_PIXELS) ? game_pixel(x, y) : 0;
        lin++;
        if (++x == HOR_PIXELS) { x = 0; y++; }
    }
    stage_n++;
}

/* Push the staged batch out. Only this part ever waits on the fabric, so it
   is the part the vblank window pays for. */
static void paint_flush(void)
{
    int i;
    for (i = 0; i < stage_n; i++)
        fb_block((uint32_t)stage_blk[i], stage + i * BLOCK_BYTES);
    stage_n = 0;
}

static void paint_begin(void)
{
    stage_n = 0;
}

/* Stage every block the rect (x1,y1)-(x2,y2) ACTUALLY touches; an over-full
   batch is flushed as it fills, so an arbitrarily large rect still works.

   Walking only the linear index range [b0, b1] is not enough. A block is a
   128-byte run of the LINEAR framebuffer and 128 does not divide 320, so a
   block spans a row boundary in general (at most two rows deep, since
   128 < 320). A rect that only reaches part of a row - and every rect a game
   marks does, the well itself is 90 px and a piece box is ~40 px - therefore
   sits inside a linear span that contains a lot of blocks it never touches:
   a 36x16 piece box spans ~39 blocks linearly but really reaches ~22, and
   every staged block costs a full 128 game_pixel() calls on top of its share
   of the write window. That overrun is what makes the spawn frame take two
   display frames instead of one (the frame the next piece appears on), which
   is exactly the window a key press falls into and is not seen until the
   piece has already fallen - i.e. the input reads as late.

   So the walk decides per block whether one of its two row segments overlaps
   the rect and skips it otherwise. A skipped block already holds exactly the
   bytes its overwrite would write (the staging IS game_pixel of the whole
   block, and a block the rect misses recomputes byte for byte what is in the
   buffer), so dropping it changes nothing on screen - only the compute bill. */
static void paint_rect(int x1, int y1, int x2, int y2)
{
    int b0, b1, b;
    if (x1 < 0) x1 = 0;
    if (y1 < 0) y1 = 0;
    if (x2 > HOR_PIXELS - 1) x2 = HOR_PIXELS - 1;
    if (y2 > VER_PIXELS - 1) y2 = VER_PIXELS - 1;
    if (x1 > x2 || y1 > y2) return;
    b0 = (y1 * HOR_PIXELS + x1) / BLOCK_BYTES;
    b1 = (y2 * HOR_PIXELS + x2) / BLOCK_BYTES;
    for (b = b0; b <= b1; b++) {
        int lin = b * BLOCK_BYTES;              /* first byte of the block   */
        int top = lin / HOR_PIXELS;             /* the row it starts in      */
        int xl  = lin - top * HOR_PIXELS;       /* ...and its x in that row  */
        int last = lin + BLOCK_BYTES - 1;       /* last byte (<= H*V - 1)    */
        int bot = last / HOR_PIXELS;
        int xr  = last - bot * HOR_PIXELS;      /* valid only when bot==top  */
        int hit;

        hit = (top >= y1 && top <= y2 && xl <= x2 &&
               ((bot == top) ? xr : HOR_PIXELS - 1) >= x1);
        if (!hit && bot != top)
            hit = (bot >= y1 && bot <= y2 && xr >= x1);   /* starts at x = 0 */
        if (!hit) continue;

        if (stage_n == STAGE_BLOCKS) paint_flush();
        stage_block(b);
    }
}

static void paint_end(void)
{
    paint_flush();
}

/* One rect on its own (same block set a per-block loop would touch). */
static void draw_rect(int x1, int y1, int x2, int y2)
{
    paint_begin();
    paint_rect(x1, y1, x2, y2);
    paint_end();
}

/* The whole frame, used once per buffer at power-up while the fabric still
   has its write bypass on (see top.v). */
static void draw_full(void)
{
    draw_rect(0, 0, HOR_PIXELS - 1, VER_PIXELS - 1);
}

/* ------------------------------------------------------------------ */
/* Triple-buffer pacing (see the header comment)                       */
/* ------------------------------------------------------------------ */
static inline int buf_begin(void)
{
    return (int)(apb_read(REG_BUF_FREE) & 3u);
}

static inline void buf_post(int r)
{
    apb_write(REG_BUF_POST, (uint32_t)r & 3u);
}

static inline int buf_disp(void)
{
    return (int)(apb_read(REG_BUF_DISP) & 3u);
}

static void wait_frame(void)
{
    uint32_t f0 = apb_read(REG_FRAME) & 0xFFu;
    uint32_t guard = 0x800000u;     /* same idea for the frame pacer       */
    while ((apb_read(REG_FRAME) & 0xFFu) == f0)
        if (--guard == 0u)
            return;
}

/* ------------------------------------------------------------------ */
/* Boot: load the palette, wait for HyperRAM, fill ALL THREE buffers    */
/* with the initial scene, and release the output blank. Returns the    */
/* buffer to render into on the first loop iteration.                   */
/* ------------------------------------------------------------------ */
static int video_boot(const uint32_t *pal, int npal)
{
    uint32_t done  = 0u;            /* bit i set = buffer i holds a scene  */
    uint32_t guard = 0x100000u;     /* bounded: never hang if PSRAM is down */
    int r = 0;

    delay_init();
    delay_ms(10);
    pal_load(pal, npal);
    while (!(apb_read(REG_HP) & 1u))
        ;

    /* The fabric only hands back a NEW free buffer once the previous one has
       been posted, and at power-up it is still showing whichever buffer it
       started on - so keep filling until all three hold the initial scene.
       The waits are also what make the handshake safe: BUF_FREE crosses two
       clock domains, and reading it in the same instant as the post would
       return the PREVIOUS index. One display frame of separation is far more
       than the ~100 ns the synchronisers need. */
    while (done != 7u && --guard) {
        r = buf_begin();
        if (!(done & (1u << r))) {
            draw_full();
            done |= 1u << r;
        }
        buf_post(r);
        wait_frame();
        wait_frame();
    }

    apb_write(REG_FB_READY, 1u);    /* stop blanking the HDMI output  */
    return buf_begin();
}

#endif /* GAME_HAL_H */