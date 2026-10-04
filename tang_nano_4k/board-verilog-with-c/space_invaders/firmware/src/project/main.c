/*
 * Space Invaders for Tang Nano 4K (GW1NSR-4C) - firmware renders a 160x120
 * monochrome framebuffer through the APB2 bridge, displayed 4x4 up-scaled
 * on the 640x480 HDMI output.
 *
 * 分工 (与 pong 完全相同, Verilog 一行未改):
 *   Verilog 侧只做 3 件事:
 *     显示  framebuffer.v    把 160x120 单色显存 (1bit/px, 32px/词) 4x4 放大成 HDMI
 *     键盘  keyboard_74hc165 采集 74HC165
 *     桥    apb_pong_reg.v   提供显存写口 FB_ADDR / FB_DATA / FB_STATUS
 *   C 侧 (本文件) 拥有每个像素的控制权: 只画"变化"的物体, 用合成器
 *   compose_word() 保证擦除时不会弄脏压在下面的物体。
 *
 * 像素/词格式: 每词 32 像素, bit31 = 该词最左像素。帧缓冲是 160x120
 * 逻辑空间, 词地址 = y*5 + (x>>5)。物体坐标先在 640x480 物理空间,
 * 渲染时才 >>2 映射到逻辑空间 (每 4x4 物理像素 = 1 逻辑像素)。
 *
 * 控制: KEY1 左移 / KEY2 右移 / KEY3 射击 / KEY4 重置
 * 规则: 玩家船在底部, 消灭 4x8 敌阵过关 (下一波更快);
 *       敌人整群移动, 碰边下移, 触底或 3 条命用完则游戏结束;
 *       敌人随机向下射击; 计分 10/20/30/40 按行。
 *       Game Over 时比分闪烁 (CTRL bit0), 与 pong 相同。
 */
#include "gw1ns4c.h"
#include "delay.h"

/* ------------------------------------------------------------------ */
/* APB2 register map (matches apb_pong_reg.v)                          */
/* ------------------------------------------------------------------ */
#define INV_APB_BASE    (APB2MASTER1_BASE)   /* 0x40002400 */

#define REG_CTRL        0x00
#define REG_KEY         0x04
#define REG_FB_ADDR     0x24
#define REG_FB_DATA     0x28
#define REG_FB_STATUS   0x2C

#define CTRL_BLINK      (1u << 0)            /* game over: score blinks */

#define KEY_LEFT        (1u << 0)            /* KEY1 */
#define KEY_RIGHT       (1u << 1)            /* KEY2 */
#define KEY_FIRE        (1u << 2)            /* KEY3 */
#define KEY_RESET       (1u << 3)            /* KEY4 */
#define KEY_PRESSED(k)  (((apb_read(REG_KEY) & (k)) == 0))  /* pressed = 0 */

/* ------------------------------------------------------------------ */
/* Screen geometry (physical 640x480 game space, >>2 to framebuffer)   */
/* ------------------------------------------------------------------ */
#define HOR_PIXELS      640
#define VER_PIXELS      480
#define FB_H_PIXELS     160          /* framebuffer logical space      */
#define FB_V_PIXELS     120
#define WORDS_PER_ROW   (FB_H_PIXELS / 32)               /* 5 */
#define FB_WORDS        (FB_H_PIXELS * FB_V_PIXELS / 32) /* 600 */

#define SHIP_W          40             /* 10 logical px */
#define SHIP_H          20             /*  5 logical px */
#define SHIP_Y          (VER_PIXELS - SHIP_H - 24)      /* 436 */
#define SHIP_STEP       5              /* px per 30 Hz game tick (150 px/s) */

#define ENEMY_W         32             /*  8 logical px */
#define ENEMY_H         24             /*  6 logical px */
#define GRID_DX         40             /* horizontal spacing between cols */
#define GRID_DY         28             /* vertical spacing between rows  */
#define GRID_X0         164            /* grid left edge (centered)      */
#define GRID_Y0         40             /* grid top edge                  */
#define GRID_W          (GRID_DX * 7 + ENEMY_W)          /* 312 */
#define DESCEND         8              /* px dropped on each wall bounce */
#define N_ENEMIES       32             /* 8 cols x 4 rows */

#define PB_W            8              /* player bullet (2 logical px) */
#define PB_H            14
#define PB_SPEED        7              /* px per tick, swept-collision */

#define EB_W            8              /* enemy bullet (2 logical px) */
#define EB_H            14
#define EB_SPEED        6
#define N_EB            4              /* max simultaneous enemy shots */

#define MAX_LIVES       3
#define LIVE_W          20             /* life icons, bottom-left */
#define LIVE_H          10
#define LIVE_X          10
#define LIVE_Y          (VER_PIXELS - LIVE_H - 10)      /* 460 */
#define LIVE_GAP        26
#define INVULN_TICKS    40             /* ~1.3 s of invulnerability after hit */

/* Protective bunkers: 4 destructible shields between the ship and the swarm.
 * Each is a per-pixel bitmap (BUNKER_W x BUNKER_H logical pixels); bullets
 * erase overlapping pixels and deactivate. Positions are physical (x4). */
#define N_BUNKERS       4
#define BUNKER_W        12             /* logical px wide (48 physical) */
#define BUNKER_H        6              /* logical px tall (24 physical) */
#define BUNKER_Y        356            /* physical top edge */
#define BUNKER_X0       128            /* left bunker physical x (centered) */
#define BUNKER_XGAP     112            /* pitch between bunkers          */

/* Score digits: 5x3 font, 4 digits, SMALL (scale 2) at the TOP-RIGHT
 * corner so the enemy swarm never marches through the score area. */
#define DIGIT_SCALE     2
#define DIGIT_W         (3 * DIGIT_SCALE + 1)          /* 7 */
#define DIGIT_H         (5 * DIGIT_SCALE + 1)          /* 11 */
#define DIGIT_Y         1
static const int32_t digit_x[4] = { 127, 135, 143, 151 };   /* right-aligned */

/* Row points, top row = most valuable (classic) */
static const int32_t ENEMY_PTS[4] = { 40, 30, 20, 10 };

static inline uint32_t apb_read(uint32_t off)
{
    return *(volatile uint32_t *)(INV_APB_BASE + off);
}

static inline void apb_write(uint32_t off, uint32_t val)
{
    *(volatile uint32_t *)(INV_APB_BASE + off) = val;
}

/* ------------------------------------------------------------------ */
/* Framebuffer write handshake (LEVEL protocol, see framebuffer.v)     */
/* ------------------------------------------------------------------ */
static uint32_t fb_req_expected;

static void fb_put(uint32_t addr, uint32_t data)
{
    uint32_t timeout;
    apb_write(REG_FB_ADDR, addr);
    fb_req_expected ^= 1u;
    apb_write(REG_FB_DATA, data);
    timeout = 0xFFFFFu;
    while (((apb_read(REG_FB_STATUS) & 1u) != fb_req_expected) && --timeout)
        ;
}

static void fb_clear(void)
{
    uint32_t w;
    for (w = 0; w < FB_WORDS; w++)
        fb_put(w, 0u);
}

/* ------------------------------------------------------------------ */
/* Object model: EVERY object gets its own slot in the compose loop    */
/* (later entries win, so ship/bullets sit on top). The enemy swarm    */
/* and the enemy bullets are indexed arrays, so they must live in      */
/* contiguous slots of a big-enough obx1/oby1/obx2/oby2[N].            */
/* ------------------------------------------------------------------ */
#define OBJ_N   (4 + 3 + N_ENEMIES + N_BUNKERS + 1 + N_EB + 1)   /* 49 */

enum {
    OBJ_S0     = 0,
    OBJ_L0     = 4,        /* life icons: 4..6                            */
    OBJ_EN0    = 7,        /* enemies:    7..38 (i = 7 + enemy_index)     */
    OBJ_SHIELD0= 39,       /* bunkers:    39..42                          */
    OBJ_PB     = 43,       /* player bullet                               */
    OBJ_EB0    = 44,       /* enemy bullets: 44..47                       */
    OBJ_SHIP   = 48        /* player ship (topmost)                       */
};

static int32_t obx1[OBJ_N], oby1[OBJ_N], obx2[OBJ_N], oby2[OBJ_N];
static int32_t digit_val[4];

/* Pixel-art sprites. Each value is one row; bit0 = leftmost column of the
 * sprite (bit N set = column N, where N counts left->right). */
static const uint16_t enemy_sprites[3][6] = {
    { 0x66, 0x3C, 0xFF, 0xBD, 0xA5, 0x42 },   /* crab (top row)     */
    { 0x66, 0x3C, 0xFF, 0xDB, 0x5A, 0x24 },   /* crab variant (mid) */
    { 0x3C, 0x7E, 0xFF, 0xE7, 0xC3, 0x81 }    /* octopus (bottom)   */
};
static const uint16_t ship_sprite[5] = { 0x30, 0x78, 0xFC, 0x3FF, 0x3FF };

/* Bunker: solid block with an arch notched out of the bottom two rows. */
static const uint16_t bunker_sprite[BUNKER_H] = {
    0xFFF, 0xFFF, 0xFFF, 0xFFF, 0xF0F, 0xF0F
};

/* bunker health bitmaps (eroded by bullets) + redraw-dirty flags */
static uint16_t bunker_map[N_BUNKERS][BUNKER_H];
static int32_t  bunker_dirty[N_BUNKERS];

/* 32-bit mask of sprite `sp` (wl x hl logical pixels, top-left at sx0,sy0)
 * for the pixels that fall inside word (xa..xb) on row y. */
static uint32_t sprite_mask(const uint16_t *sp, int32_t wl, int32_t hl,
                            int32_t sx0, int32_t sy0,
                            int32_t xa, int32_t xb, int32_t y)
{
    int32_t x, sx;
    uint16_t row;
    uint32_t m = 0;

    if (y < sy0 || y >= sy0 + hl) return 0;
    if (xb < sx0 || xa >= sx0 + wl) return 0;
    row = sp[y - sy0];
    for (x = xa; x <= xb; x++) {
        sx = x - sx0;
        if (sx < 0 || sx >= wl) continue;
        if (row & (1u << sx))
            m |= 1u << (31 - (x & 31));
    }
    return m;
}

/* Exact copy of the 16-bit digit font from pong_render.v (column-major
 * 3 cols x 5 rows, bit (row + col*5)). */
static const uint16_t font5x3[10] = {
    0x7E3F, /* 0 */
    0x03E0, /* 1 */
    0x5EBD, /* 2 */
    0x7EB5, /* 3 */
    0x7C87, /* 4 */
    0x76B7, /* 5 */
    0x76BF, /* 6 */
    0x7C21, /* 7 */
    0x7EBF, /* 8 */
    0x7EB7  /* 9 */
};

/* 32-bit mask of the pixels of digit `d` that fall inside word (xa..xb)
 * on row y. Returns 0 when the word/row is outside the digit. */
static uint32_t digit_mask(int32_t d, int32_t xa, int32_t xb, int32_t y)
{
    int32_t xoff = digit_x[d];
    int32_t x, lx;
    uint32_t m = 0;
    uint16_t f;

    if (y < DIGIT_Y || y >= DIGIT_Y + 5 * DIGIT_SCALE) return 0;
    if (xb < xoff || xa >= xoff + 3 * DIGIT_SCALE)    return 0;

    f = font5x3[digit_val[d]];
    for (x = xa; x <= xb; x++) {
        lx = x - xoff;
        if (lx < 0 || lx >= 3 * DIGIT_SCALE) continue;
        if (f & (1u << (((y - DIGIT_Y) / DIGIT_SCALE) + (lx / DIGIT_SCALE) * 5)))
            m |= 1u << (31 - (x & 31));
    }
    return m;
}

/* Final 32-bit value of word `w0` (left pixel = w0*32) on row y, built by
 * OR-ing every object's bits in priority order. skip = object to leave out
 * (used for erasing that object's old position without dirtying others). */
static uint32_t compose_word(int32_t w0, int32_t y, int32_t skip)
{
    int32_t xa = w0 << 5;            /* logical x range of this word */
    int32_t xb = xa + 31;
    uint32_t w = 0;
    int32_t i;

    for (i = 0; i < OBJ_N; i++) {
        uint32_t m = 0;
        if (i == skip) continue;
        if (i >= OBJ_S0 && i < OBJ_S0 + 4) {
            m = digit_mask(i - OBJ_S0, xa, xb, y);
        } else if (i >= OBJ_EN0 && i < OBJ_EN0 + N_ENEMIES) {
            /* enemy: a pixel-art sprite, type depends on its row */
            int32_t e, r, st;
            if (obx2[i] < 0) continue;               /* dead enemy */
            e = i - OBJ_EN0;
            r = e >> 3;
            st = (r == 0) ? 0 : (r == 3) ? 2 : 1;
            m = sprite_mask(enemy_sprites[st], ENEMY_W >> 2, ENEMY_H >> 2,
                            obx1[i] >> 2, oby1[i] >> 2, xa, xb, y);
        } else if (i >= OBJ_SHIELD0 && i < OBJ_SHIELD0 + N_BUNKERS) {
            int32_t k = i - OBJ_SHIELD0;
            m = sprite_mask(bunker_map[k], BUNKER_W, BUNKER_H,
                            (BUNKER_X0 + k * BUNKER_XGAP) >> 2, BUNKER_Y >> 2,
                            xa, xb, y);
        } else if (i == OBJ_SHIP) {
            m = sprite_mask(ship_sprite, SHIP_W >> 2, SHIP_H >> 2,
                            obx1[i] >> 2, oby1[i] >> 2, xa, xb, y);
        } else {
            /* lives + bullets: filled rects in 640x480 space, mapped >>2 */
            int32_t a, b;
            int32_t oy1 = oby1[i] >> 2, oy2 = oby2[i] >> 2;
            if (y < oy1 || y > oy2) continue;
            a = (obx1[i] >> 2) > xa ? (obx1[i] >> 2) : xa;
            b = (obx2[i] >> 2) < xb ? (obx2[i] >> 2) : xb;
            if (a > b) continue;
            m = (0xFFFFFFFFu << (31 - (b & 31))) & (0xFFFFFFFFu >> (a & 31));
        }
        w |= m;
    }
    return w;
}

/* Write every word touched by rect (x1,y1)-(x2,y2) with compose(skip). */
static void fill_rect(int32_t x1, int32_t y1, int32_t x2, int32_t y2, int32_t skip)
{
    int32_t wl, wr, w, y;

    /* 640x480 game space -> 160x120 framebuffer (4x4 display) */
    x1 >>= 2; x2 >>= 2; y1 >>= 2; y2 >>= 2;

    if (x1 < 0) x1 = 0;
    if (y1 < 0) y1 = 0;
    if (x2 > FB_H_PIXELS - 1) x2 = FB_H_PIXELS - 1;
    if (y2 > FB_V_PIXELS - 1) y2 = FB_V_PIXELS - 1;
    if (x1 > x2 || y1 > y2) return;

    wl = x1 >> 5;
    wr = x2 >> 5;
    for (y = y1; y <= y2; y++)
        for (w = wl; w <= wr; w++)
            fb_put((uint32_t)(y * WORDS_PER_ROW + w), compose_word(w, y, skip));
}

/* ------------------------------------------------------------------ */
/* Game state                                                          */
/* ------------------------------------------------------------------ */
static int32_t score, lives, wave;
static int32_t ship_x;
static int32_t ship_dir;                     /* -1/0/+1, set by main loop */
static int32_t invader_x, invader_y, dir;    /* group offset + direction  */
static int32_t alive[N_ENEMIES], n_alive;
static int32_t pb_active, pb_x, pb_y;        /* player bullet */
static int32_t eb_active[N_EB], eb_x[N_EB], eb_y[N_EB];
static int32_t invuln;
static int32_t game_over;
static uint32_t rng = 0x12345678u;

/* last rendered positions (sentinels force a full redraw on reset) */
static int32_t prev_ship_x = -1000;
static int32_t prev_ix = -9999, prev_iy = -9999;
static int32_t prev_alive[N_ENEMIES];
static int32_t prev_pb_active, prev_pb_x, prev_pb_y;
static int32_t prev_eb_active[N_EB], prev_eb_x[N_EB], prev_eb_y[N_EB];
static int32_t prev_score = -1, prev_lives = -1;

/* ------------------------------------------------------------------ */
/* Helpers                                                             */
/* ------------------------------------------------------------------ */
static int32_t over(int32_t ax1, int32_t ay1, int32_t ax2, int32_t ay2,
                    int32_t bx1, int32_t by1, int32_t bx2, int32_t by2)
{
    return !(ax2 < bx1 || bx2 < ax1 || ay2 < by1 || by2 < ay1);
}

/* Clear the pixels of bunker k overlapped by the physical rect (x1,y1)-(x2,y2).
 * Returns 1 if anything was removed and marks the bunker dirty for repaint. */
static int32_t erode_bunker(int32_t k, int32_t x1, int32_t y1, int32_t x2, int32_t y2)
{
    int32_t bx  = BUNKER_X0 + k * BUNKER_XGAP;   /* physical left edge */
    int32_t bxw = BUNKER_W << 2;                 /* physical width      */
    int32_t byh = BUNKER_H << 2;                 /* physical height     */
    int32_t lx1, lx2, ly1, ly2, cy;
    uint32_t mask;
    uint16_t old, nw;
    int32_t hit = 0;

    if (x2 < bx || x1 >= bx + bxw || y2 < BUNKER_Y || y1 >= BUNKER_Y + byh)
        return 0;

    lx1 = (x1 > bx ? x1 : bx) - bx;
    lx2 = (x2 < bx + bxw ? x2 : bx + bxw - 1) - bx;
    ly1 = (y1 > BUNKER_Y ? y1 : BUNKER_Y) - BUNKER_Y;
    ly2 = (y2 < BUNKER_Y + byh ? y2 : BUNKER_Y + byh - 1) - BUNKER_Y;

    lx1 >>= 2; lx2 >>= 2; ly1 >>= 2; ly2 >>= 2;
    mask = ((1u << (lx2 - lx1 + 1)) - 1u) << lx1;   /* bit j = column j */
    for (cy = ly1; cy <= ly2; cy++) {
        old = bunker_map[k][cy];
        nw  = (uint16_t)(old & ~mask);
        if (nw != old) { bunker_map[k][cy] = nw; hit = 1; }
    }
    if (hit) bunker_dirty[k] = 1;
    return hit;
}

static int32_t erode_bunkers(int32_t x1, int32_t y1, int32_t x2, int32_t y2)
{
    int32_t k, hit = 0;
    for (k = 0; k < N_BUNKERS; k++)
        if (erode_bunker(k, x1, y1, x2, y2)) hit = 1;
    return hit;
}

static void update_objs(void)
{
    int32_t i, d, r, c;

    for (d = 0; d < 4; d++) {
        obx1[OBJ_S0 + d] = digit_x[d] << 2;
        obx2[OBJ_S0 + d] = (digit_x[d] + DIGIT_W) << 2;
        oby1[OBJ_S0 + d] = DIGIT_Y << 2;
        oby2[OBJ_S0 + d] = (DIGIT_Y + DIGIT_H) << 2;
    }
    digit_val[0] = (score / 1000) % 10;
    digit_val[1] = (score / 100) % 10;
    digit_val[2] = (score / 10) % 10;
    digit_val[3] = score % 10;

    for (d = 0; d < 3; d++) {
        if (d < lives) {
            obx1[OBJ_L0 + d] = LIVE_X + d * LIVE_GAP;
            obx2[OBJ_L0 + d] = LIVE_X + d * LIVE_GAP + LIVE_W;
            oby1[OBJ_L0 + d] = LIVE_Y;
            oby2[OBJ_L0 + d] = LIVE_Y + LIVE_H;
        } else {
            obx1[OBJ_L0 + d] = 0; obx2[OBJ_L0 + d] = -1;
            oby1[OBJ_L0 + d] = 0; oby2[OBJ_L0 + d] = -1;
        }
    }

    for (i = 0; i < N_ENEMIES; i++) {
        if (alive[i]) {
            r = i >> 3; c = i & 7;
            obx1[OBJ_EN0 + i] = GRID_X0 + c * GRID_DX + invader_x;
            oby1[OBJ_EN0 + i] = GRID_Y0 + r * GRID_DY + invader_y;
            obx2[OBJ_EN0 + i] = obx1[OBJ_EN0 + i] + ENEMY_W;
            oby2[OBJ_EN0 + i] = oby1[OBJ_EN0 + i] + ENEMY_H;
        } else {
            obx1[OBJ_EN0 + i] = 0; obx2[OBJ_EN0 + i] = -1;
            oby1[OBJ_EN0 + i] = 0; oby2[OBJ_EN0 + i] = -1;
        }
    }

    if (pb_active) {
        obx1[OBJ_PB] = pb_x - PB_W / 2; obx2[OBJ_PB] = pb_x + PB_W / 2;
        oby1[OBJ_PB] = pb_y;            oby2[OBJ_PB] = pb_y + PB_H;
    } else {
        obx1[OBJ_PB] = 0; obx2[OBJ_PB] = -1;
        oby1[OBJ_PB] = 0; oby2[OBJ_PB] = -1;
    }

    for (i = 0; i < N_EB; i++) {
        if (eb_active[i]) {
            obx1[OBJ_EB0 + i] = eb_x[i] - EB_W / 2; obx2[OBJ_EB0 + i] = eb_x[i] + EB_W / 2;
            oby1[OBJ_EB0 + i] = eb_y[i];            oby2[OBJ_EB0 + i] = eb_y[i] + EB_H;
        } else {
            obx1[OBJ_EB0 + i] = 0; obx2[OBJ_EB0 + i] = -1;
            oby1[OBJ_EB0 + i] = 0; oby2[OBJ_EB0 + i] = -1;
        }
    }

    obx1[OBJ_SHIP] = ship_x;           obx2[OBJ_SHIP] = ship_x + SHIP_W;
    oby1[OBJ_SHIP] = SHIP_Y;           oby2[OBJ_SHIP] = SHIP_Y + SHIP_H;
}

/* Erase old positions and draw new ones in ONE composed pass each. */
static void render(void)
{
    int32_t i;

    update_objs();

    /* ship: single pass over old+new union rect */
    if (ship_x != prev_ship_x) {
        if (prev_ship_x > -100) {
            int32_t ox1 = prev_ship_x, ox2 = prev_ship_x + SHIP_W;
            fill_rect((ox1 < ship_x) ? ox1 : ship_x, SHIP_Y,
                      (ox2 > ship_x + SHIP_W) ? ox2 : ship_x + SHIP_W,
                      SHIP_Y + SHIP_H, -1);
        } else {
            fill_rect(ship_x, SHIP_Y, ship_x + SHIP_W, SHIP_Y + SHIP_H, -1);
        }
        prev_ship_x = ship_x;
    }

    /* enemies: redraw any cell whose sprite moved (grid shift) or whose
     * alive state changed (killed / revived). compose() contributes nothing
     * for dead enemies, so filling the old+new union wipes the corpse. */
    for (i = 0; i < N_ENEMIES; i++) {
        int32_t cur_x = GRID_X0 + (i & 7) * GRID_DX + invader_x;
        int32_t cur_y = GRID_Y0 + (i >> 3) * GRID_DY + invader_y;
        int32_t prv_x = GRID_X0 + (i & 7) * GRID_DX + prev_ix;
        int32_t prv_y = GRID_Y0 + (i >> 3) * GRID_DY + prev_iy;
        int32_t moved = (invader_x != prev_ix || invader_y != prev_iy);
        int32_t chg   = (alive[i] != prev_alive[i]);

        if (!chg && !(alive[i] && moved))
            continue;

        if (alive[i]) {
            int32_t x1 = cur_x, y1 = cur_y, x2 = cur_x + ENEMY_W, y2 = cur_y + ENEMY_H;
            if (prev_alive[i] && prev_ix > -100) {
                if (prv_x < x1) x1 = prv_x;
                if (prv_y < y1) y1 = prv_y;
                if (prv_x + ENEMY_W > x2) x2 = prv_x + ENEMY_W;
                if (prv_y + ENEMY_H > y2) y2 = prv_y + ENEMY_H;
            }
            fill_rect(x1, y1, x2, y2, -1);
        } else {
            /* died: erase the cell it last occupied (and the new cell too
             * if the whole group shifted this same tick - harmless). */
            if (prev_alive[i] && prev_ix > -100)
                fill_rect(prv_x, prv_y, prv_x + ENEMY_W, prv_y + ENEMY_H, -1);
            if (moved)
                fill_rect(cur_x, cur_y, cur_x + ENEMY_W, cur_y + ENEMY_H, -1);
        }
        prev_alive[i] = alive[i];
    }
    prev_ix = invader_x; prev_iy = invader_y;

    /* player bullet: erase old position + draw new position in one pass */
    if (pb_active != prev_pb_active || (pb_active && (pb_x != prev_pb_x || pb_y != prev_pb_y))) {
        int32_t x1 = pb_x - PB_W / 2, x2 = pb_x + PB_W / 2;
        int32_t y1 = 0, y2 = -1;
        if (prev_pb_active) { y1 = prev_pb_y; y2 = prev_pb_y + PB_H; }
        if (pb_active) {
            if (y2 < 0) { y1 = pb_y; y2 = pb_y + PB_H; }
            else {
                if (pb_y < y1) y1 = pb_y;
                if (pb_y + PB_H > y2) y2 = pb_y + PB_H;
            }
        }
        if (y2 >= y1) fill_rect(x1, y1, x2, y2, -1);
    }
    prev_pb_x = pb_x; prev_pb_y = pb_y; prev_pb_active = pb_active;

    /* enemy bullets */
    for (i = 0; i < N_EB; i++) {
        if (eb_active[i] != prev_eb_active[i]) {
            if (eb_active[i])
                fill_rect(eb_x[i] - EB_W / 2, eb_y[i],
                          eb_x[i] + EB_W / 2, eb_y[i] + EB_H, -1);
            else
                fill_rect(prev_eb_x[i] - EB_W / 2, prev_eb_y[i],
                          prev_eb_x[i] + EB_W / 2, prev_eb_y[i] + EB_H, -1);
        } else if (eb_active[i] && (eb_y[i] != prev_eb_y[i])) {
            fill_rect(eb_x[i] - EB_W / 2, (prev_eb_y[i] < eb_y[i]) ? prev_eb_y[i] : eb_y[i],
                      eb_x[i] + EB_W / 2, (prev_eb_y[i] > eb_y[i]) ? prev_eb_y[i] : eb_y[i] + EB_H, -1);
        }
        prev_eb_x[i] = eb_x[i]; prev_eb_y[i] = eb_y[i]; prev_eb_active[i] = eb_active[i];
    }

    /* score digits: redraw only when score changes */
    if (score != prev_score) {
        fill_rect(digit_x[0] << 2, DIGIT_Y << 2,
                  (digit_x[3] + DIGIT_W) << 2, (DIGIT_Y + DIGIT_H) << 2, -1);
        prev_score = score;
    }

    /* life icons: redraw only when lives changes */
    if (lives != prev_lives) {
        fill_rect(LIVE_X, LIVE_Y, LIVE_X + 2 * LIVE_GAP + LIVE_W, LIVE_Y + LIVE_H, -1);
        prev_lives = lives;
    }

    /* bunkers: repaint any bunker eroded by a bullet this tick */
    for (i = 0; i < N_BUNKERS; i++) {
        if (bunker_dirty[i]) {
            fill_rect(BUNKER_X0 + i * BUNKER_XGAP, BUNKER_Y,
                      BUNKER_X0 + i * BUNKER_XGAP + (BUNKER_W << 2),
                      BUNKER_Y + (BUNKER_H << 2), -1);
            bunker_dirty[i] = 0;
        }
    }
}

/* ------------------------------------------------------------------ */
/* Game logic                                                          */
/* ------------------------------------------------------------------ */
static int32_t bullet_hit_enemy(int32_t bx1, int32_t bx2)
{
    int32_t i, r, c, x1, y1;
    int32_t by2 = pb_y + PB_H + PB_SPEED;   /* swept segment (anti-tunnel) */

    for (i = 0; i < N_ENEMIES; i++) {
        if (!alive[i]) continue;
        r = i >> 3; c = i & 7;
        x1 = GRID_X0 + c * GRID_DX + invader_x;
        y1 = GRID_Y0 + r * GRID_DY + invader_y;
        if (over(bx1, pb_y, bx2, by2, x1, y1, x1 + ENEMY_W, y1 + ENEMY_H))
            return i;
    }
    return -1;
}

static void kill_enemy(int32_t e)
{
    alive[e] = 0;
    n_alive--;
    score += ENEMY_PTS[e >> 3];
}

static void spawn_enemy_bullet(void)
{
    int32_t k, tries, c, r;
    uint32_t cnt = 0;

    for (k = 0; k < N_EB; k++)
        if (eb_active[k]) cnt++;
    if (cnt >= N_EB) return;

    /* more shots as the swarm thins out (~1/s at 32 alive, ~2.5/s at 8) */
    rng = rng * 1664525u + 1013904223u;
    if ((rng % (12u + (uint32_t)n_alive / 2u)) != 0) return;

    for (tries = 0; tries < 8; tries++) {
        c = (int32_t)(rng % 8u);
        for (r = 3; r >= 0; r--) {
            if (alive[r * 8 + c]) {
                for (k = 0; k < N_EB; k++) {
                    if (!eb_active[k]) {
                        eb_active[k] = 1;
                        eb_x[k] = GRID_X0 + c * GRID_DX + invader_x + ENEMY_W / 2;
                        eb_y[k] = GRID_Y0 + r * GRID_DY + invader_y + ENEMY_H;
                        return;
                    }
                }
            }
        }
    }
}

static void lose_life(void)
{
    int32_t k;
    lives--;
    invuln = INVULN_TICKS;
    for (k = 0; k < N_EB; k++)
        eb_active[k] = 0;
    if (lives <= 0) {
        lives = 0;
        game_over = 1;
        apb_write(REG_CTRL, CTRL_BLINK);
    }
}

static void enemy_move(void)
{
    int32_t step = wave + (32 - n_alive) / 6;
    if (step > 4) step = 4;

    invader_x += dir * step;
    /* the grid's real left/right edges are GRID_X0 + invader_x ... */
    if (GRID_X0 + invader_x < 8) {
        invader_x = 8 - GRID_X0;
        dir = 1;
        invader_y += DESCEND;
    } else if (GRID_X0 + GRID_W + invader_x > HOR_PIXELS - 8) {
        invader_x = HOR_PIXELS - 8 - GRID_X0 - GRID_W;
        dir = -1;
        invader_y += DESCEND;
    }
}

static int32_t invaded(void)
{
    int32_t i, r;
    for (i = 0; i < N_ENEMIES; i++) {
        if (!alive[i]) continue;
        r = i >> 3;
        if (GRID_Y0 + r * GRID_DY + invader_y + ENEMY_H >= SHIP_Y)
            return 1;
    }
    return 0;
}

static void next_wave(void)
{
    int32_t i, k;

    wave++;
    invader_x = 0; invader_y = 0; dir = 1;
    for (i = 0; i < N_ENEMIES; i++) alive[i] = 1;
    n_alive = N_ENEMIES;
    pb_active = 0;
    for (k = 0; k < N_EB; k++) eb_active[k] = 0;
    invuln = 0;

    /* bunkers stay damaged across waves (classic), but repaint after clear */
    for (k = 0; k < N_BUNKERS; k++) bunker_dirty[k] = 1;

    /* sentinels force a full redraw (mirrors game_reset) */
    prev_ship_x = -1000;
    prev_ix = -9999; prev_iy = -9999;
    for (i = 0; i < N_ENEMIES; i++) prev_alive[i] = 1;
    prev_pb_active = 0; prev_pb_x = 0; prev_pb_y = 0;
    for (k = 0; k < N_EB; k++) {
        prev_eb_active[k] = 0; prev_eb_x[k] = 0; prev_eb_y[k] = 0;
    }
    prev_score = -1; prev_lives = -1;

    fb_clear();
}

static void game_reset(void)
{
    int32_t i, k;

    score = 0;
    lives = MAX_LIVES;
    wave = 0;
    ship_x = (HOR_PIXELS - SHIP_W) / 2;
    invader_x = 0; invader_y = 0; dir = 1;
    for (i = 0; i < N_ENEMIES; i++) alive[i] = 1;
    n_alive = N_ENEMIES;
    pb_active = 0;
    for (k = 0; k < N_EB; k++) eb_active[k] = 0;
    invuln = 0;
    game_over = 0;
    apb_write(REG_CTRL, 0);             /* clear blink */

    /* fresh bunkers: solid blocks ready to absorb shots */
    for (k = 0; k < N_BUNKERS; k++) {
        for (i = 0; i < BUNKER_H; i++)
            bunker_map[k][i] = bunker_sprite[i];
        bunker_dirty[k] = 1;
    }

    /* sentinels force a full redraw on the next render() */
    prev_ship_x = -1000;
    prev_ix = -9999; prev_iy = -9999;
    for (i = 0; i < N_ENEMIES; i++) prev_alive[i] = 1;
    prev_pb_active = 0; prev_pb_x = 0; prev_pb_y = 0;
    for (k = 0; k < N_EB; k++) {
        prev_eb_active[k] = 0; prev_eb_x[k] = 0; prev_eb_y[k] = 0;
    }
    prev_score = -1; prev_lives = -1;

    fb_clear();                          /* clear the whole framebuffer */
}

static void game_tick(void)
{
    int32_t k, e;

    if (game_over)
        return;

    /* player ship movement (dir sampled by the 1 kHz loop) */
    if (ship_dir != 0) {
        ship_x += ship_dir * SHIP_STEP;
        if (ship_x < 8) ship_x = 8;
        if (ship_x > HOR_PIXELS - 8 - SHIP_W) ship_x = HOR_PIXELS - 8 - SHIP_W;
    }

    /* all enemies destroyed -> next wave */
    if (n_alive == 0) {
        next_wave();
        return;
    }

    /* enemy group movement + invasion check */
    enemy_move();
    if (invaded()) {
        game_over = 1;
        apb_write(REG_CTRL, CTRL_BLINK);
        return;
    }

    /* player bullet */
    if (pb_active) {
        int32_t bx1 = pb_x - PB_W / 2, bx2 = pb_x + PB_W / 2;
        int32_t by2 = pb_y + PB_H;      /* old bottom before the move up */
        pb_y -= PB_SPEED;
        /* bunker (between the ship and the swarm) absorbs the shot first */
        if (erode_bunkers(bx1, pb_y, bx2, by2)) {
            pb_active = 0;
        } else {
            e = bullet_hit_enemy(bx1, bx2);
            if (e >= 0) {
                kill_enemy(e);
                pb_active = 0;
            } else if (pb_y < 12) {
                pb_active = 0;
            }
        }
    }

    /* enemy bullets */
    if (invuln > 0)
        invuln--;
    if (invuln == 0)
        spawn_enemy_bullet();
    for (k = 0; k < N_EB; k++) {
        int32_t bx1, bx2, by1;
        if (!eb_active[k]) continue;
        bx1 = eb_x[k] - EB_W / 2;
        bx2 = eb_x[k] + EB_W / 2;
        by1 = eb_y[k];                  /* old top before the move down */
        eb_y[k] += EB_SPEED;
        if (eb_y[k] > 470) {
            eb_active[k] = 0;
            continue;
        }
        /* bunker (above the ship) absorbs the enemy shot as well */
        if (erode_bunkers(bx1, by1, bx2, eb_y[k] + EB_H)) {
            eb_active[k] = 0;
            continue;
        }
        /* swept collision with the ship (anti-tunnel) */
        if (over(bx1, by1, bx2, eb_y[k] + EB_H,
                 ship_x, SHIP_Y, ship_x + SHIP_W, SHIP_Y + SHIP_H)) {
            eb_active[k] = 0;
            lose_life();
            break;
        }
    }
}

int main(void)
{
    uint32_t frame_cnt = 0;
    uint32_t ms_tick = 0;               /* 1 ms counter (debounce) */
    uint32_t last_fire_ms = 0;          /* time of last KEY3 shot */
    uint32_t last_reset_ms = 0;         /* time of last KEY4 reset */
    uint32_t prev_keys = 0xFFFFFFFFu;   /* previous key state (released = 1) */

    delay_init();
    delay_ms(10);                       /* let the PLL/clk_p come up before
                                           touching the framebuffer handshake */
    game_reset();

    while (1) {
        ms_tick++;

        uint32_t keys_now = apb_read(REG_KEY);
        uint32_t press_edge = (~keys_now) & prev_keys;   /* 1->0 = press */
        prev_keys = keys_now;

        /* KEY4 resets the game - EDGE triggered + 200 ms debounce */
        if ((press_edge & KEY_RESET) && (ms_tick - last_reset_ms > 200)) {
            game_reset();
            last_reset_ms = ms_tick;
        }

        if (!game_over) {
            ship_dir = 0;
            if (KEY_PRESSED(KEY_LEFT))  ship_dir -= 1;
            if (KEY_PRESSED(KEY_RIGHT)) ship_dir += 1;

            /* KEY3 fires - edge + debounce + one bullet at a time */
            if ((press_edge & KEY_FIRE) && (ms_tick - last_fire_ms > 200) && !pb_active) {
                pb_active = 1;
                pb_x = ship_x + SHIP_W / 2;
                pb_y = SHIP_Y - PB_H;
                last_fire_ms = ms_tick;
            }
        }

        /* ~30 Hz game tick (enemies, bullets, collisions) */
        if (++frame_cnt >= 33) {
            frame_cnt = 0;
            game_tick();
        }

        /* render changes into the framebuffer */
        render();

        delay_ms(1);
    }
}
