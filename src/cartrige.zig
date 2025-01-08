const cartrige = @This();
const mapper000 = @import("mapper000.zig");
const std = @import("std");
const fs = std.fs;

PRGMemory: []u8,
CHRMemory: []u8,
mapperID: mappers = .none,
PRGBanks: u8 = 0,
CHRBanks: u8 = 0,
mirror: Mirror = .Horizontal,

mapper: *anyopaque,

pub fn init(fileName: []const u8) anyerror!@This()
{
    var cart: @This() = undefined;

    var cwd = fs.cwd();
    var f = try cwd.openFile(fileName, .{});
    defer f.close();

    var b: [16]u8 = undefined;
    _ = try f.read(&b);

    const h: Header = @bitCast(b);

    if (h.mapper1 & 0x04 != 0)
        try f.seekTo(0x200);

    std.debug.print("mapperID: {d}\n", .{((h.mapper2 >> 4) << 4) | (h.mapper1 >> 4)});
    cart.mapperID = @enumFromInt(((h.mapper2 >> 4) << 4) | (h.mapper1 >> 4));
    cart.mirror = if(h.mapper1 & 1 != 0) Mirror.Vertical else Mirror.Horizontal;
    std.debug.print("mapperID: {any}\n", .{cart.mapperID});
    var fileType: u8 = 1;
    if(h.mapper2 & 0xC == 8) fileType = 2;

    std.debug.print("fileType: {d}\n", .{fileType});
    switch (fileType) 
    {
        0 => 
        {
            
        },
        1 => 
        {
            cart.PRGBanks = h.prg_rom_chunks;
            cart.PRGMemory = (try std.heap.page_allocator.alloc(u8, @as(u32, cart.PRGBanks) * 0x4000));
            _ = try f.read(cart.PRGMemory);

            cart.CHRBanks = h.chr_rom_chunks;
            cart.CHRMemory = try std.heap.page_allocator.alloc(u8, @as(u32, @max(1, cart.CHRBanks)) * 0x2000);
            _ = try f.read(cart.CHRMemory);
        },
        2 => 
        {
            // TODO: figure out why a u8 is getting left shift by 8
            cart.PRGBanks = ((h.prg_ram_size & 0x07) << 4) | h.prg_rom_chunks;
            cart.PRGMemory = (try std.heap.page_allocator.alloc(u8, @as(u32, cart.PRGBanks) * 0x4000));
            _ = try f.read(cart.PRGMemory);

            cart.CHRBanks = ((h.prg_ram_size & 0x38) << 4) | h.chr_rom_chunks;
            cart.CHRMemory = try std.heap.page_allocator.alloc(u8, @as(u32, cart.CHRBanks) * 0x2000);
            _ = try f.read(cart.CHRMemory);
        },
        else => {},
    }

    std.debug.print("CHRBanks: {d}, PRGBanks: {d}\n", .{cart.CHRBanks, cart.CHRBanks});

    try mappers.createMapper(&cart);

    return cart;
}

pub fn deInit(self: @This()) void
{
    std.heap.page_allocator.free(self.CHRMemory);
    std.heap.page_allocator.free(self.PRGMemory);
    mappers.destroyMapper(self);
}

pub fn cpuWrite(self: @This(), addr: u16, dat: u8) bool
{
    var mappedAddr: u32 = addr;

    if(self.mapperID.cpuMapWrite(self.mapper, addr, &mappedAddr, dat))
    {
        if (mappedAddr == 0xFFFFFFFF)
		{
			// Mapper has actually set the data value, for example cartridge based RAM
			return true;
		}
		else
		{
			// Mapper has produced an offset into cartridge bank memory
			self.PRGMemory[mappedAddr] = dat;
		}
        return true;
    }

    return false;
}

pub fn cpuRead(self: @This(), addr: u16, dat: *u8) bool
{
    var mappedAddr: u32 = addr;

    if(self.mapperID.cpuMapRead(self.mapper, addr,  &mappedAddr, dat))
    {
        if (mappedAddr == 0xFFFFFFFF)
		{
			// Mapper has actually set the data value, for example cartridge based RAM
			return true;
		}
		else
		{
			// Mapper has produced an offset into cartridge bank memory
			dat.* = self.PRGMemory[mappedAddr];
		}
        return true;
    }

    return false;
}

pub fn ppuWrite(self: @This(), addr: u16, dat: u8) bool
{
    var mappedAddr: u32 = addr;
    
    if(self.mapperID.ppuMapWrite(self.mapper, addr, &mappedAddr))
    {
        self.CHRMemory[mappedAddr] = dat;
        return true;
    }

    return false;
}

pub fn ppuRead(self: @This(), addr: u16, dat: *u8) bool
{
    var mappedAddr: u32 = addr;

    if(self.mapperID.ppuMapRead(self.mapper, addr, &mappedAddr))
    {
        dat.* = self.CHRMemory[mappedAddr];
        return true;
    }

    return false;
}

const Mirror = enum 
{
    Horizontal,
    Vertical,
    ScreenLo,
    ScreenHi,
};

const Header = packed struct(u128) 
{
    name: u32,
    prg_rom_chunks: u8,
    chr_rom_chunks: u8,
    mapper1: u8,
    mapper2: u8,
    prg_ram_size: u8,
    tv_system1: u8,
    tv_system2: u8,
    unused: u40,
};

const mapperError = error
{
    InvalidMapperID,
    OutOfMemory,
};

const mappers = enum(u32)
{
    none = 0xFFFFFFFF,
    m000 = 0,
    m001 = 1,
    m002 = 2,
    m003 = 3,
    m004 = 4,
    m066 = 66,

    pub fn createMapper(self: *cartrige) mapperError!void
    {

        switch (self.mapperID) 
        {
            .m000   => 
            {

                const m = std.heap.page_allocator.create(mapper000) catch return mapperError.OutOfMemory;
                m.CHRBanks = self.CHRBanks;
                m.PRGBanks = self.PRGBanks;
                self.mapper = m;
            },
            else    => return mapperError.InvalidMapperID,
        }
    }

    pub fn destroyMapper(self: cartrige) void
    {
        switch (self.mapperID) 
        {
            .m000   => std.heap.page_allocator.destroy(@as(*mapper000, @ptrCast(self.mapper))),
            else    => unreachable,
        }
    }

    pub fn cpuMapRead (self: mappers, mapper: *anyopaque, addr: u16, mappedAddr: *u32, dat: *u8) bool
    {
        return switch (self) 
        {
            .m000   => @as(*mapper000, @ptrCast(mapper)).cpuMapRead(addr, mappedAddr, dat),
            else    => false,
        };
    }

    pub fn cpuMapWrite(self: mappers, mapper: *anyopaque, addr: u16, mappedAddr: *u32, dat: u8) bool
    {
        return switch (self) 
        {
            .m000   => @as(*mapper000, @ptrCast(mapper)).cpuMapWrite(addr, mappedAddr, dat),
            else    => false,
        };
    }

    pub fn ppuMapRead (self: mappers, mapper: *anyopaque, addr: u16, mappedAddr: *u32) bool
    {
        return switch (self) 
        {
            .m000   => @as(*mapper000, @ptrCast(mapper)).ppuMapRead(addr, mappedAddr),
            else    => false,
        };
    }

    pub fn ppuMapWrite(self: mappers, mapper: *anyopaque, addr: u16, mappedAddr: *u32) bool
    {
        return switch (self) 
        {
            .m000   => @as(*mapper000, @ptrCast(mapper)).ppuMapWrite(addr, mappedAddr),
            else    => false,
        };
    }

    pub fn scanLine(self: mappers) void
    {
        switch (self) 
        {
            else => {},
        }
    }
};
