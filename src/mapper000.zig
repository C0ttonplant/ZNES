const std = @import("std");

PRGBanks: u8 = 0,
CHRBanks: u8 = 0,

pub fn init(prgBanks: u8, chrBanks: u8) @This()
{
    return .{ .PRGanks = prgBanks, .CHRBanks = chrBanks };
}

pub fn cpuMapRead(self: @This(), addr: u16, mappedAddr: *u32, _: *u8) bool
{
    if (addr >= 0x8000 and addr <= 0xFFFF)
	{
        mappedAddr.* = addr & (if((self.PRGBanks > 1)) @as(u16, 0x7FFF) else 0x3FFF);
        // mappedAddr.* = addr & 0x7FFF;
        return true;
    }
    return false;
}
pub fn cpuMapWrite(self: @This(), addr: u16, mappedAddr: *u32, _: u8) bool
{
    if (addr >= 0x8000 and addr <= 0xFFFF)
	{
        mappedAddr.* = addr & (if(!(self.PRGBanks > 1)) @as(u16, 0x7FFF) else 0x3FFF);
        // mappedAddr.* = addr & 0x7FFF;
        return true;
    }
    return false;
}
pub fn ppuMapRead(_: @This(), addr: u16, mappedAddr: *u32) bool
{
    if(addr > 0x1FFF) return false;

    mappedAddr.* = addr;
    return true;
}
pub fn ppuMapWrite(self: @This(), addr: u16, mappedAddr: *u32) bool
{
    if(addr > 0x1FFF or self.CHRBanks != 0) return false;

    mappedAddr.* = addr;

    return true;
}
