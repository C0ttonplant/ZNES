//! PPU register layouts.

/// $2000 PPUCTRL
pub const Ctrl = packed struct(u8) {
    nametable_x: bool = false,
    nametable_y: bool = false,
    /// add 32 to the vram address after $2007 access instead of 1
    increment_32: bool = false,
    /// 8x8 sprite pattern table at $1000 instead of $0000
    sprite_table: bool = false,
    /// background pattern table at $1000 instead of $0000
    bg_table: bool = false,
    /// 8x16 sprites
    tall_sprites: bool = false,
    slave_mode: bool = false,
    enable_nmi: bool = false,
};

/// $2001 PPUMASK
pub const Mask = packed struct(u8) {
    grayscale: bool = false,
    show_bg_left: bool = false,
    show_sprites_left: bool = false,
    show_bg: bool = false,
    show_sprites: bool = false,
    emphasize_red: bool = false,
    emphasize_green: bool = false,
    emphasize_blue: bool = false,
};

/// $2002 PPUSTATUS
pub const Status = packed struct(u8) {
    unused: u5 = 0,
    sprite_overflow: bool = false,
    sprite_zero_hit: bool = false,
    vblank: bool = false,
};

/// "loopy" vram address register layout, used for both `v` and `t`
pub const Loopy = packed struct(u16) {
    coarse_x: u5 = 0,
    coarse_y: u5 = 0,
    nametable_x: bool = false,
    nametable_y: bool = false,
    fine_y: u3 = 0,
    unused: bool = false,
};
