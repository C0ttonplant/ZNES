const std = @import("std");

PRGBanks: u8 = 0,
CHRBanks: u8 = 0,

pub fn init(prgBanks: u8, chrBanks: u8) @This()
{
    return .{ .PRGanks = prgBanks, .CHRBanks = chrBanks };
}

pub fn cpuMapRead (self: @This(), addr: u16, mappedAddr: *u32, dat: *u8) bool
{
    _ = self;
    _ = addr;
    _ = mappedAddr;
    _ = dat;
    return false;
}
pub fn cpuMapWrite(self: @This(), addr: u16, mappedAddr: *u32, dat: u8) bool
{
    _ = self;
    _ = addr;
    _ = mappedAddr;
    _ = dat;
    return false;
}
pub fn ppuMapRead (self: @This(), addr: u16, mappedAddr: *u32) bool
{
    _ = self;
    _ = addr;
    _ = mappedAddr;
    return false;
}
pub fn ppuMapWrite(self: @This(), addr: u16, mappedAddr: *u32) bool
{
    _ = self;
    _ = addr;
    _ = mappedAddr;
    return false;
}
pub fn scanLine() void
{
    
}
