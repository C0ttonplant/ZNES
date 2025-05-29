const ppu_2c02 = @This();
const cpu_6502 = @import("cpu.zig");
const bus = @import("bus.zig");
const cartrige = @import("cartrige.zig");
const apu = @import("apu.zig");
const std = @import("std");
const rl = @import("raylib");

// internal variables
var cart: *cartrige = undefined;

var nameTable: [2][1024]u8 = undefined;
var patternTable: [2][0x1000]u8 = undefined;
var palletTable: [32]u8 = undefined;
var controlReg: control = .{};
var statusReg: status = .{};
var maskReg: mask = .{};
var vRam: loopy = .{};
var tRam: loopy = .{};

var spriteZeroHit: bool = false;
var spriteZeroRender: bool = false;

// helper variables
/// screen texture data
pub var screenImg: rl.Image = undefined;
// pub var screenTex: [256][240 * 4]u8 = undefined;
/// pallette color array
var palScreen: [0x40]rl.Color = 
.{
    rl.Color{ .r = 0  , .g = 30 , .b = 116, .a = 255},
    rl.Color{ .r = 84 , .g = 84 , .b = 84 , .a = 255},
    rl.Color{ .r = 8  , .g = 16 , .b = 144, .a = 255},
    rl.Color{ .r = 48 , .g = 0  , .b = 136, .a = 255},
    rl.Color{ .r = 68 , .g = 0  , .b = 100, .a = 255},
    rl.Color{ .r = 92 , .g = 0  , .b = 48 , .a = 255},
    rl.Color{ .r = 84 , .g = 4  , .b = 0  , .a = 255},
    rl.Color{ .r = 60 , .g = 24 , .b = 0  , .a = 255},
    rl.Color{ .r = 32 , .g = 42 , .b = 0  , .a = 255},
    rl.Color{ .r = 8  , .g = 58 , .b = 0  , .a = 255},
    rl.Color{ .r = 0  , .g = 64 , .b = 0  , .a = 255},
    rl.Color{ .r = 0  , .g = 60 , .b = 0  , .a = 255},
    rl.Color{ .r = 0  , .g = 50 , .b = 60 , .a = 255},
    rl.Color{ .r = 0  , .g = 0  , .b = 0  , .a = 255},
    rl.Color{ .r = 0  , .g = 0  , .b = 0  , .a = 255},
    rl.Color{ .r = 0  , .g = 0  , .b = 0  , .a = 255},
    rl.Color{ .r = 152, .g = 150, .b = 152, .a = 255},
    rl.Color{ .r = 8  , .g = 76 , .b = 196, .a = 255},
    rl.Color{ .r = 48 , .g = 50 , .b = 236, .a = 255},
    rl.Color{ .r = 92 , .g = 30 , .b = 228, .a = 255},
    rl.Color{ .r = 136, .g = 20 , .b = 176, .a = 255},
    rl.Color{ .r = 160, .g = 20 , .b = 100, .a = 255},
    rl.Color{ .r = 152, .g = 34 , .b = 32 , .a = 255},
    rl.Color{ .r = 120, .g = 60 , .b = 0  , .a = 255},
    rl.Color{ .r = 84 , .g = 90 , .b = 0  , .a = 255},
    rl.Color{ .r = 40 , .g = 114, .b = 0  , .a = 255},
    rl.Color{ .r = 8  , .g = 124, .b = 0  , .a = 255},
    rl.Color{ .r = 0  , .g = 118, .b = 40 , .a = 255},
    rl.Color{ .r = 0  , .g = 102, .b = 120, .a = 255},
    rl.Color{ .r = 0  , .g = 0  , .b = 0  , .a = 255},
    rl.Color{ .r = 0  , .g = 0  , .b = 0  , .a = 255},
    rl.Color{ .r = 0  , .g = 0  , .b = 0  , .a = 255},
    rl.Color{ .r = 236, .g = 238, .b = 236, .a = 255},
    rl.Color{ .r = 76 , .g = 154, .b = 236, .a = 255},
    rl.Color{ .r = 120, .g = 124, .b = 236, .a = 255},
    rl.Color{ .r = 176, .g = 98 , .b = 236, .a = 255},
    rl.Color{ .r = 228, .g = 84 , .b = 236, .a = 255},
    rl.Color{ .r = 236, .g = 88 , .b = 180, .a = 255},
    rl.Color{ .r = 236, .g = 106, .b = 100, .a = 255},
    rl.Color{ .r = 212, .g = 136, .b = 32 , .a = 255},
    rl.Color{ .r = 160, .g = 170, .b = 0  , .a = 255},
    rl.Color{ .r = 116, .g = 196, .b = 0  , .a = 255},
    rl.Color{ .r = 76 , .g = 208, .b = 32 , .a = 255},
    rl.Color{ .r = 56 , .g = 204, .b = 108, .a = 255},
    rl.Color{ .r = 56 , .g = 180, .b = 204, .a = 255},
    rl.Color{ .r = 60 , .g = 60 , .b = 60 , .a = 255},
    rl.Color{ .r = 0  , .g = 0  , .b = 0  , .a = 255},
    rl.Color{ .r = 0  , .g = 0  , .b = 0  , .a = 255},
    rl.Color{ .r = 236, .g = 238, .b = 236, .a = 255},
    rl.Color{ .r = 168, .g = 204, .b = 236, .a = 255},
    rl.Color{ .r = 188, .g = 188, .b = 236, .a = 255},
    rl.Color{ .r = 212, .g = 178, .b = 236, .a = 255},
    rl.Color{ .r = 236, .g = 174, .b = 236, .a = 255},
    rl.Color{ .r = 236, .g = 174, .b = 212, .a = 255},
    rl.Color{ .r = 236, .g = 180, .b = 176, .a = 255},
    rl.Color{ .r = 228, .g = 196, .b = 144, .a = 255},
    rl.Color{ .r = 204, .g = 210, .b = 120, .a = 255},
    rl.Color{ .r = 180, .g = 222, .b = 120, .a = 255},
    rl.Color{ .r = 168, .g = 226, .b = 144, .a = 255},
    rl.Color{ .r = 152, .g = 226, .b = 180, .a = 255},
    rl.Color{ .r = 160, .g = 214, .b = 228, .a = 255},
    rl.Color{ .r = 160, .g = 162, .b = 160, .a = 255},
    rl.Color{ .r = 0  , .g = 0  , .b = 0  , .a = 255},
    rl.Color{ .r = 0  , .g = 0  , .b = 0  , .a = 255},
};

/// object attribute memory
pub var oam: [64]objAttribMem = undefined;
/// pointer to oam for writing bytes
pub var poam: *[256]u8 = @as(*[256]u8, @ptrCast(&oam));
var oamAddress: u8 = 0;

pub var nmi: bool = false;

var bgNextTileID: u8 = 0;
var bgNextTileAttrib: u8 = 0;
var bgNextTileLsb: u8 = 0;
var bgNextTileMsb: u8 = 0;

var sprShiftPatternLo: [8]u8 = undefined;
var sprShiftPatternHi: [8]u8 = undefined;

var bgShiftPatternLo: u16 = 0;
var bgShiftPatternHi: u16 = 0;
var bgShiftAttribLo: u16 = 0;
var bgShiftAttribHi: u16 = 0;

pub var sysClock: u128 = 0;
var scanLine: i16 = 0;
var scanRow: i16 = 0;
var oddFrame: bool = false;

// internal structs

/// status register struct
const status = packed struct 
{
    
    unused: u5 = 0,
    spriteOverflow: bool = false,
    spriteZeroHit: bool = false,
    verticalBlank: bool = false,

};

/// mask register struct
const mask = packed struct 
{
    grayscale: bool = false,
    renderBackgroundLeft: bool = false,
    renderSpritesLeft: bool = false,
    renderBackground: bool = false,
    renderSprites: bool = false,
    enhanceRed: bool = false,
    enhanceGreen: bool = false,
    enhanceBlue: bool = false,
};

/// control register struct
const control = packed struct 
{
    pub var addressLatch: u8 = 0;
    pub var dataBuffer: u8 = 0;
    //pub var address: u16 = 0;

    nametableX: bool = false,
    nametableY: bool = false,
    incrementMode: bool = false,
    patternSprite: bool = false,
    patternBackground: bool = false,
    spriteSize: bool = false,
    slaveMode: bool = false,
    enableNMI: bool = false,
};

/// loopy srtuct for sprite rendering
const loopy = packed struct 
{
    pub var fineX: u8 = 0;

    coarseX: u5 = 0,
    coarseY: u5 = 0,
    nametableX: bool = false,
    nametableY: bool = false,
    fineY: u3 = 0,
    unused: bool = false,
};

/// "sprite" memory struct
const objAttribMem = packed struct
{
    var scanline: [8]objAttribMem = undefined;
    var spriteCount: u8 = 0;

    y: u8 = 0,
    id: u8 = 0,
    attrib: u8 = 0,
    x: u8 = 0,
};

// functions

pub fn cpuWrite(addr: u16, dat: u8) void
{
    const address: u16 = addr & 7;

    switch (address) 
    {
        0 =>
        {
            // Control
            controlReg = @bitCast(dat);
            tRam.nametableX = controlReg.nametableX;
            tRam.nametableY = controlReg.nametableY;
        },
        1 =>
        {
            // Mask
            maskReg = @bitCast(dat);
        },
        2 =>
        {
            // Status
        },
        3 =>
        {
            // OAM Address
            oamAddress = dat;
        },
        4 =>
        {
            // OAM Data
            poam[oamAddress] = dat;
        },
        5 =>
        {
            // Scroll
            if(control.addressLatch == 0)
            {
                loopy.fineX = dat & 0x07;
                tRam.coarseX = @truncate(dat >> 3);
                control.addressLatch = 1;
            }
            else
            {
                tRam.fineY = @truncate(dat & 0x07);
                tRam.coarseY = @truncate(dat >> 3);
                control.addressLatch = 0;
            }
        },
        6 =>
        {
            // PPU Adress
            if(control.addressLatch == 0)
            {
                tRam = @bitCast((@as(u16, @bitCast(tRam)) & 0x00ff) | (@as(u16, dat) << 8)); 
                control.addressLatch = 1;
            }
            else
            {
                tRam = @bitCast((@as(u16, @bitCast(tRam)) & 0xff00) | dat);
                vRam = tRam;
                control.addressLatch = 0;
            }

        },
        7 =>
        {
            // PPU Data
            ppuWrite(@bitCast(vRam), dat);
            vRam = @bitCast(@addWithOverflow(@as(u16, @bitCast(vRam)), if(controlReg.incrementMode) @as(u16, 32) else 1)[0]);

        },
        else => {},
    }
}

pub fn cpuRead(addr: u16, readOnly: bool) u8
{
    _ = readOnly;
    const address: u16 = addr & 7;

    return switch (address) 
    {
        0 => blk:
        {
            // Control
            break :blk 0;
        },
        1 => blk:
        {
            // Mask
            break :blk 0;
        },
        2 => blk:
        {
            // Status
            control.addressLatch = 0;
            break :blk (@as(u8, @bitCast(statusReg)) & 0xE0) | (control.dataBuffer & 0x1F);
            
        },
        3 => blk:
        {
            // OAM Address
            break :blk 0;
        },
        4 => blk:
        {
            // OAM Data
            break :blk poam[oamAddress];
        },
        5 => blk:
        {
            // Scroll
            break :blk 0;
        },
        6 => blk:
        {
            // PPU Adress
            break :blk 0;
        },
        7 => blk:
        {
            // PPU Data
            var data = control.dataBuffer;
            control.dataBuffer = ppuRead(@bitCast(vRam), false);
            if(@as(u16, @bitCast(vRam)) > 0x3f00) data = control.dataBuffer;

            vRam = @bitCast(@addWithOverflow(@as(u16, @bitCast(vRam)), if(controlReg.incrementMode) @as(u16, 32) else 1)[0]);

            break :blk data;
        },
        else => 0,
    };
}

pub fn ppuWrite(addr: u16, dat: u8) void
{
    var address: u16 = addr & 0x3fff;

    if(cart.ppuWrite(addr, dat)) return;

    switch (address) 
    {
        // pattern memory (patternTable)
        0x0000...0x1FFF => 
        { 
            patternTable[(addr & 0x1000) >> 0xC][addr & 0x0FFF] = dat;
        },
        // name table memory (nameTable)
        0x2000...0x3EFF => 
        { 
            address &= 0xfff;
            switch (cart.mirror) 
            {

                .Vertical =>
                {
                    switch (address) 
                    {
                        0x0000...0x03FF => nameTable[0][address & 0x03FF] = dat,
                        0x0400...0x07FF => nameTable[1][address & 0x03FF] = dat,
                        0x0800...0x0BFF => nameTable[0][address & 0x03FF] = dat,
                        0x0C00...0x0FFF => nameTable[1][address & 0x03FF] = dat,
                        else => {},
                    }
                },
                .Horizontal =>
                {
                    switch (address) 
                    {
                        0x0000...0x03FF => nameTable[0][address & 0x03FF] = dat,
                        0x0400...0x07FF => nameTable[0][address & 0x03FF] = dat,
                        0x0800...0x0BFF => nameTable[1][address & 0x03FF] = dat,
                        0x0C00...0x0FFF => nameTable[1][address & 0x03FF] = dat,
                        else => {},
                    }
                },
                else => {},
            }
        },
        // pallet memory (palletTable)
        0x3F00...0x3FFF => 
        {
            address &= 0x001F;
            if (address == 0x0010) address = 0x0000;
		    if (address == 0x0014) address = 0x0004;
		    if (address == 0x0018) address = 0x0008;
		    if (address == 0x001C) address = 0x000C;
            palletTable[address] = dat;
        },

        else => {  },
    }
}

pub fn ppuRead(addr: u16, readOnly: bool) u8
{
    _ = readOnly;
    
    var data: u8 = 0;
    var address: u16 = addr & 0x3fff;

    if(cart.ppuRead(addr, &data)) return data;

    return switch (address) 
    {
        // pattern memory (patternTable)
        0x0000...0x1FFF => blk: 
        { 
            break :blk patternTable[(address & 0x1000) >> 0xC][address & 0x0FFF];
        },
        // name table memory (nameTable)
        0x2000...0x3EFF => blk:
        { 
            address &= 0xfff;
            break :blk switch (cart.mirror) 
            {
                .Vertical =>
                {
                    switch (address) 
                    {
                        0x0000...0x03FF => break :blk nameTable[0][address & 0x03FF],
                        0x0400...0x07FF => break :blk nameTable[1][address & 0x03FF],
                        0x0800...0x0BFF => break :blk nameTable[0][address & 0x03FF],
                        0x0C00...0x0FFF => break :blk nameTable[1][address & 0x03FF],
                        else => break :blk 0,
                    }
                },
                .Horizontal =>
                {
                    switch (address) 
                    {
                        0x0000...0x03FF => break :blk nameTable[0][address & 0x03FF],
                        0x0400...0x07FF => break :blk nameTable[0][address & 0x03FF],
                        0x0800...0x0BFF => break :blk nameTable[1][address & 0x03FF],
                        0x0C00...0x0FFF => break :blk nameTable[1][address & 0x03FF],
                        else => break :blk 0,
                    }
                },
                else => 0,
            };
        },
        // pallet memory (palletTable)
        0x3F00...0x3FFF => blk:
        {
            address &= 0x001F;
            if (address == 0x0010) address = 0x0000;
		    if (address == 0x0014) address = 0x0004;
		    if (address == 0x0018) address = 0x0008;
		    if (address == 0x001C) address = 0x000C;
            break :blk palletTable[address] & (if(maskReg.grayscale) @as(u8, 0x30) else 0x3F);
        },

        else => 0,
    };
}

fn tryIncScrollX() void
{
    if(maskReg.renderBackground or maskReg.renderSprites)
    {
        if(vRam.coarseX == 31)
        {
            vRam.coarseX = 0;
            vRam.nametableX = !vRam.nametableX;
        }
        else vRam.coarseX += 1;
    }
}

fn tryIncScrollY() void
{
    if(maskReg.renderBackground or maskReg.renderSprites)
    {
        if(vRam.fineY < 7)
        {
            vRam.fineY += 1;
        }
        else
        {
            vRam.fineY = 0;

            if(vRam.coarseY == 29)
            {
                vRam.coarseY = 0;
                vRam.nametableY = !vRam.nametableY;
            }
            else if(vRam.coarseY == 31)
            {
                vRam.coarseY = 0;
            }
            else vRam.coarseY += 1;
        }
    }
}

fn trytransferAddrX() void
{
    if(maskReg.renderBackground or maskReg.renderSprites)
    {
        vRam.nametableX = tRam.nametableX;
        vRam.coarseX = tRam.coarseX;
    }
}

fn trytransferAddrY() void
{
    if(maskReg.renderBackground or maskReg.renderSprites)
    {
        vRam.fineY = tRam.fineY;
        vRam.nametableY = tRam.nametableY;
        vRam.coarseY = tRam.coarseY;
    }}

fn loadBgShifters() void
{
    bgShiftPatternLo = (bgShiftPatternLo & 0xFF00) | bgNextTileLsb;
    bgShiftPatternHi = (bgShiftPatternHi & 0xFF00) | bgNextTileMsb;

    bgShiftAttribLo = (bgShiftAttribLo & 0xFF00) | (if((bgNextTileAttrib & 0b01) != 0) @as(u16, 0xFF) else 0);
    bgShiftAttribHi = (bgShiftAttribHi & 0xFF00) | (if((bgNextTileAttrib & 0b10) != 0) @as(u16, 0xFF) else 0);
}

fn updateShifters() void
{
    if(maskReg.renderBackground)
    {
        bgShiftPatternLo <<= 1;
        bgShiftPatternHi <<= 1;
        bgShiftAttribLo <<= 1;
        bgShiftAttribHi <<= 1;
    }

    if(maskReg.renderSprites and scanRow >= 1 and scanRow < 258)
    {
        for (0..objAttribMem.spriteCount) |i| 
        {
            

            if(objAttribMem.scanline[i].x > 0)
            {
                objAttribMem.scanline[i].x -= 1;
            }
            else 
            {
                sprShiftPatternLo[i] <<= 1;
                sprShiftPatternHi[i] <<= 1;
            }
        }
    }
}

pub fn clock() void
{

    if(scanLine == 241 and scanRow == 1)
    {
        statusReg.verticalBlank = true;

        if(controlReg.enableNMI)
            cpu_6502.nmi();
    }
    if(!(scanLine >= -1 and scanLine < 240)) return;

    switch (scanRow) 
    {
        0 =>
        {
            if(scanLine == 0 and oddFrame and (maskReg.renderBackground or maskReg.renderSprites))
            {
                scanRow = 1;
            }
        },
        1 =>
        {
            if(scanLine == -1)
            {
                statusReg.verticalBlank = false;
                statusReg.spriteZeroHit = false;
                statusReg.spriteOverflow = false;

                sprShiftPatternLo = .{0, 0, 0, 0, 0, 0, 0, 0};
                sprShiftPatternHi = .{0, 0, 0, 0, 0, 0, 0, 0};
            }
        },
        2...255,321...337 =>
        {
            rowEnum();
        },
        256 =>
        {
            rowEnum();
            tryIncScrollY();
        },
        257 =>
        {
            rowEnum();
            loadBgShifters();
            trytransferAddrX();

            if(scanLine >= 0)
            {
                objAttribMem.scanline = undefined;

                objAttribMem.spriteCount = 0;

                sprShiftPatternLo = .{0, 0, 0, 0, 0, 0, 0, 0};
                sprShiftPatternHi = .{0, 0, 0, 0, 0, 0, 0, 0};

                const sprHeight: u8 = if(!controlReg.spriteSize) 8 else 16;

                spriteZeroHit = false;
                for (oam, 0..) |spr, i| 
                {
                    const dif: i16 = @as(i16, @intCast(scanLine)) - @as(i16, spr.y);

                    if(dif >= 0 and dif < sprHeight)
                    {
                        if(objAttribMem.spriteCount < 8)
                        {
                            if(i == 0)
                            {
                                spriteZeroHit = true;
                            }
                            objAttribMem.scanline[objAttribMem.spriteCount] = spr;
                            objAttribMem.spriteCount += 1;
                        }
                        else if(objAttribMem.spriteCount < 9)
                        {
                            statusReg.spriteOverflow = true;
                            // objAttribMem.spriteCount = 8;
                            break;
                        }
                        else break;
                    }
                }
            }
        },
        289...304 =>
        {
            if(scanLine == -1)
            {
                trytransferAddrY();
            }
        },
        338 =>
        {
            bgNextTileID = ppuRead(0x2000 | (@as(u16, @bitCast(vRam)) & 0xFFF), false);
        },
        340 =>
        {
            bgNextTileID = ppuRead(0x2000 | (@as(u16, @bitCast(vRam)) & 0xFFF), false);
            
            for (0..objAttribMem.spriteCount) |i| 
            {
                var sprPatternBitLo: u8 = 0;
                var sprPatternBitHi: u8 = 0;
                var sprPatternAddrLo: u16 = 0;
                var sprPatternAddrHi: u16 = 0;
                const spr: *objAttribMem = &objAttribMem.scanline[i];   
                if(scanLine < 0) continue;
                const sl: u16 = @intCast(scanLine);

                if(!controlReg.spriteSize)
                {
                    // 8x8
                    if(objAttribMem.scanline[i].attrib & 0x80 == 0) // sprite vertical flip
                    {
                        sprPatternAddrLo = 
                          (@as(u16, @intFromBool(controlReg.patternSprite)) << 12)
                        | (@as(u16, spr.id) << 4)
                        | (sl - spr.y);
                    }
                    else
                    {
                        sprPatternAddrLo = 
                          (@as(u16, @intFromBool(controlReg.patternSprite)) << 12)
                        | (@as(u16, spr.id) << 4)
                        | (7 - (sl - spr.y));
                    }
                }
                else
                {
                    // 8x16
                    if(spr.attrib & 0x80 == 0) // sprite vertical flip
                    {
                        if(scanLine - spr.y < 8)
                        {
                            // top half
                            sprPatternAddrLo = 
                              (@as(u16, spr.id & 1) << 12)
                            | (@as(u16, spr.id & 0xFE) << 4)
                            | ((sl - spr.y) & 7);
                        }
                        else
                        {
                            // bottom half
                            sprPatternAddrLo = 
                              (@as(u16, spr.id & 1) << 12)
                            | (((@as(u16, spr.id & 0xFE)) + 1) << 4)
                            | ((sl - spr.y) & 7);
                        }
                    }
                    else
                    {
                        if(scanLine - spr.y < 8)
                        {
                            // top half
                            sprPatternAddrLo = 
                              (@as(u16, spr.id & 1) << 12)
                            | (((@as(u16, spr.id & 0xFE)) + 1) << 4)
                            | (7 - (sl - spr.y) & 7);
                        }
                        else
                        {
                            // bottom half
                            sprPatternAddrLo = 
                              (@as(u16, spr.id & 1) << 12)
                            | ((@as(u16, spr.id) & 0xFE) << 4)
                            | (7 - (sl - spr.y) & 7);
                        }
                    }
                }

                sprPatternAddrHi = sprPatternAddrLo + 8;

                sprPatternBitLo = ppuRead(sprPatternAddrLo, false);
                sprPatternBitHi = ppuRead(sprPatternAddrHi, false);

                if(spr.attrib & 0x40 != 0)
                {
                    sprPatternBitLo = @bitReverse(sprPatternBitLo);
                    sprPatternBitHi = @bitReverse(sprPatternBitHi);
                }

                sprShiftPatternLo[i] = sprPatternBitLo;
                sprShiftPatternHi[i] = sprPatternBitHi;
            }

        },
        else => {},
    }


    drawPixel();
    
}

pub fn clocks() void
{
    if (scanLine >= -1 and scanLine < 240)
    {
        if(scanLine == 0 and scanRow == 0 and oddFrame and (maskReg.renderBackground or maskReg.renderSprites))
        {
            scanRow = 1;
        }

        if(scanLine == -1 and scanRow == 1)
        {
            statusReg.verticalBlank = false;
            statusReg.spriteZeroHit = false;
            statusReg.spriteOverflow = false;

            sprShiftPatternLo = .{0, 0, 0, 0, 0, 0, 0, 0};
            sprShiftPatternHi = .{0, 0, 0, 0, 0, 0, 0, 0};
        }

        if((scanRow >= 2 and scanRow < 258) or (scanRow >= 321 and scanRow < 338))
        {
            rowEnum();
        }

        if(scanRow == 256)
        {
            tryIncScrollY();
        }

        if(scanRow == 257)
        {
            loadBgShifters();
            trytransferAddrX();
        }

        if(scanRow == 338 or scanRow == 340)
        {
            bgNextTileID = ppuRead(0x2000 | (@as(u16, @bitCast(vRam)) & 0xFFF), false);
        }

        if(scanLine == -1 and scanRow >= 280 and scanRow < 305)
        {
            trytransferAddrY();
        }

        if(scanRow == 257 and scanLine >= 0)
        {
            objAttribMem.scanline = undefined;

            objAttribMem.spriteCount = 0;

            sprShiftPatternLo = .{0, 0, 0, 0, 0, 0, 0, 0};
            sprShiftPatternHi = .{0, 0, 0, 0, 0, 0, 0, 0};

            const sprHeight: u8 = if(!controlReg.spriteSize) 8 else 16;

            spriteZeroHit = false;
            for (oam, 0..) |spr, i| 
            {
                const dif: i16 = @as(i16, @intCast(scanLine)) - @as(i16, spr.y);

                if(dif >= 0 and dif < sprHeight)
                {
                    if(objAttribMem.spriteCount < 8)
                    {
                        if(i == 0)
                        {
                            spriteZeroHit = true;
                        }
                        objAttribMem.scanline[objAttribMem.spriteCount] = spr;
                        objAttribMem.spriteCount += 1;
                    }
                    else if(objAttribMem.spriteCount < 9)
                    {
                        statusReg.spriteOverflow = true;
                        // objAttribMem.spriteCount = 8;
                        break;
                    }
                    else break;
                }
            }
        }
        
        if(scanRow == 340)
        {
            for (0..objAttribMem.spriteCount) |i| 
            {
                var sprPatternBitLo: u8 = 0;
                var sprPatternBitHi: u8 = 0;
                var sprPatternAddrLo: u16 = 0;
                var sprPatternAddrHi: u16 = 0;
                const spr: *objAttribMem = &objAttribMem.scanline[i];   
                if(scanLine < 0) continue;
                const sl: u16 = @intCast(scanLine);

                if(!controlReg.spriteSize)
                {
                    // 8x8
                    if(objAttribMem.scanline[i].attrib & 0x80 == 0) // sprite vertical flip
                    {
                        sprPatternAddrLo = 
                          (@as(u16, @intFromBool(controlReg.patternSprite)) << 12)
                        | (@as(u16, spr.id) << 4)
                        | (sl - spr.y);
                    }
                    else
                    {
                        sprPatternAddrLo = 
                          (@as(u16, @intFromBool(controlReg.patternSprite)) << 12)
                        | (@as(u16, spr.id) << 4)
                        | (7 - (sl - spr.y));
                    }
                }
                else
                {
                    // 8x16
                    if(spr.attrib & 0x80 == 0) // sprite vertical flip
                    {
                        if(scanLine - spr.y < 8)
                        {
                            // top half
                            sprPatternAddrLo = 
                              (@as(u16, spr.id & 1) << 12)
                            | (@as(u16, spr.id & 0xFE) << 4)
                            | ((sl - spr.y) & 7);
                        }
                        else
                        {
                            // bottom half
                            sprPatternAddrLo = 
                              (@as(u16, spr.id & 1) << 12)
                            | (((@as(u16, spr.id & 0xFE)) + 1) << 4)
                            | ((sl - spr.y) & 7);
                        }
                    }
                    else
                    {
                        if(scanLine - spr.y < 8)
                        {
                            // top half
                            sprPatternAddrLo = 
                              (@as(u16, spr.id & 1) << 12)
                            | (((@as(u16, spr.id & 0xFE)) + 1) << 4)
                            | (7 - (sl - spr.y) & 7);
                        }
                        else
                        {
                            // bottom half
                            sprPatternAddrLo = 
                              (@as(u16, spr.id & 1) << 12)
                            | ((@as(u16, spr.id) & 0xFE) << 4)
                            | (7 - (sl - spr.y) & 7);
                        }
                    }
                }

                sprPatternAddrHi = sprPatternAddrLo + 8;

                sprPatternBitLo = ppuRead(sprPatternAddrLo, false);
                sprPatternBitHi = ppuRead(sprPatternAddrHi, false);

                if(spr.attrib & 0x40 != 0)
                {
                    sprPatternBitLo = @bitReverse(sprPatternBitLo);
                    sprPatternBitHi = @bitReverse(sprPatternBitHi);
                }

                sprShiftPatternLo[i] = sprPatternBitLo;
                sprShiftPatternHi[i] = sprPatternBitHi;
            }
        }
    }


    if(scanLine == 241 and scanRow == 1)
    {
        statusReg.verticalBlank = true;

        if(controlReg.enableNMI)
            cpu_6502.nmi();
    }

    drawPixel();
}

pub fn rowEnum() void
{
    updateShifters();

    switch (@as(u16, @intCast(scanRow - 1)) & 0b111) 
    {
        0 => 
        {
            loadBgShifters();
            bgNextTileID = ppuRead(0x2000 | (@as(u16, @bitCast(vRam)) & 0x0FFF), false);
        },
        2 => 
        {
            bgNextTileAttrib = ppuRead(0x23C0 
            | (@as(u16, @intFromBool(vRam.nametableY)) << 11)
            | (@as(u16, @intFromBool(vRam.nametableX)) << 10)
            | ((vRam.coarseY >> 2) << 3)
            | (vRam.coarseX >> 2), false);

            if(vRam.coarseY & 2 != 0) bgNextTileAttrib >>= 4;
            if(vRam.coarseX & 2 != 0) bgNextTileAttrib >>= 2;

            bgNextTileAttrib &= 3;
        },
        4 => 
        {
            bgNextTileLsb = ppuRead(
                (@as(u16, @intFromBool(controlReg.patternBackground)) << 12)
                + (@as(u16, bgNextTileID) << 4)
                + (vRam.fineY)
                + 0, false);
                
        },
        6 => 
        {
            bgNextTileMsb = ppuRead(
                (@as(u16, @intFromBool(controlReg.patternBackground)) << 12)
                + (@as(u16, bgNextTileID) << 4)
                + (vRam.fineY)
                + 8, false);
        },
        7 => tryIncScrollX(),
        else => {},
    }
}

pub fn drawFrame() void
{
    while (true) 
    {
        _ = bus.clock();

        scanRow += 1;
        if(scanRow >= 341)
        {
            scanRow = 0;
            scanLine += 1;

            if(scanLine >= 261)
            {
                scanLine = -1;
                oddFrame = !oddFrame;
                break;
            }
        }

        sysClock += 1;
    }
}

pub fn drawSynced() bool
{
    const tmp: bool = bus.clock();

    scanRow += 1;
    if(maskReg.renderBackground or maskReg.renderSprites)
    {
        if(scanRow == 260 and scanLine < 240)
        {
            cart.mapperID.scanLine();
        }
    }

    if(scanRow >= 341)
    {
        scanRow = 0;
        scanLine += 1;

        if(scanLine >= 261)
        {
            scanLine = -1;
            oddFrame = !oddFrame;
        }
    }

    sysClock += 1;
    
    return tmp;
}

pub fn drawPixel() void
{
    
    var bgPix: u8 = 0;
    var bgPallet: u8 = 0;

    if(maskReg.renderBackground)
    {
        const mux: u16 = if(loopy.fineX < 0x10) @as(u16, 0x8000) >> @truncate(loopy.fineX) else 0;

        const pi0: u8 = @intFromBool(bgShiftPatternLo & mux != 0);
        const pi1: u8 = @intFromBool(bgShiftPatternHi & mux != 0);
        bgPix = (pi1 << 1) | (pi0); 

        const pa0: u8 = @intFromBool(bgShiftAttribLo & mux != 0);
        const pa1: u8 = @intFromBool(bgShiftAttribHi & mux != 0);
        bgPallet = (pa1 << 1) | (pa0); 
    }


    var fgPix: u8 = 0;
    var fgPallet: u8 = 0;
    var fgPriority: bool = false;

    if(maskReg.renderSprites)
    {
        spriteZeroRender = false;
        for (0..objAttribMem.spriteCount) |i| 
        {
            const spr: *objAttribMem = &objAttribMem.scanline[i];
            if(spr.x == 0)
            {
                const pixLo: u8 = sprShiftPatternLo[i] >> 7;
                const pixHi: u8 = sprShiftPatternHi[i] >> 7;
                fgPix = (pixHi << 1) | pixLo;

                fgPallet = (spr.attrib & 0x03) + 0x04;
                fgPriority = (spr.attrib & 0x20) == 0;

                if(fgPix != 0)
                {
                    if(i == 0)
                    {
                        spriteZeroRender = true;
                    }
                    break;
                }
            }
        }
    }

    var pixel: u8 = 0;
    var pallet: u8 = 0;

    if(bgPix == 0 and fgPix > 0)
    {
        pixel = fgPix;
        pallet = fgPallet;
    }
    if(bgPix > 0 and fgPix == 0)
    {
        pixel = bgPix;
        pallet = bgPallet;
    }
    if(bgPix > 0 and fgPix > 0)
    {
        if(fgPriority)
        {
            pixel = fgPix;
            pallet = fgPallet;
        }
        else 
        {
            pixel = bgPix;
            pallet = bgPallet;
        }

        if(spriteZeroHit and spriteZeroRender)
        {
            if(maskReg.renderBackground and maskReg.renderSprites)
            {
                if(!(maskReg.renderBackgroundLeft or maskReg.renderSpritesLeft))
                {
                    statusReg.spriteZeroHit = if(scanRow >= 9 and scanRow < 258) true else statusReg.spriteZeroHit;
                }
                else
                {
                    statusReg.spriteZeroHit = if(scanRow >= 1 and scanRow < 258) true else statusReg.spriteZeroHit;
                }
            }
        }
    }


    // rl.drawPixel(scanRow - 1, scanLine, getColorFromPixel(pallet, pixel));

    drawTexPixel(getColorFromPixel(pallet, pixel));
}

pub fn insertCartrige(crt: *cartrige) void
{
    cart = crt;
}

pub fn removeCartrige() void
{
    cart = undefined;
}

pub fn drawPatternTable(index: usize, pallet: u8, x: i32, y: i32) void
{
    var offset: u16 = 0;

    var lsb: u8 = 0;
    var msb: u8 = 0;
    var pix: u2 = 0;
    var ox: i32 = 0;
    var oy: i32 = 0;

    for (0..16) |tileX| 
    {
        for (0..16) |tileY| 
        {
            offset = @intCast(tileY * 256 + tileX * 16);

            for (0..8) |row| 
            {

                lsb = ppuRead(@intCast(index * 0x1000 + offset + row + 0), false);
                msb = ppuRead(@intCast(index * 0x1000 + offset + row + 8), false);

                for (0..8) |col| 
                {
                    pix = @truncate(((lsb & 1) << 1) | (msb & 1));

                    lsb >>= 1;
                    msb >>= 1;

                    ox = @intCast(tileX * 8 + (7-col));
                    oy = @intCast(tileY * 8 + row);

                    rl.drawPixel(x + ox, y + oy, getColorFromPixel(pallet, pix)); 
                }
            }
        }
    }
}

pub fn getColorFromPixel(pallet: u8, pixel: u8) rl.Color
{
    return palScreen[ppuRead((0x3F00 + (@as(u16, @intCast(pallet)) << 2) + pixel), false) & 0x3F];
}


pub fn drawTexPixel(col: rl.Color) void
{
    screenImg.drawPixel(scanRow - 1, scanLine, col);
}