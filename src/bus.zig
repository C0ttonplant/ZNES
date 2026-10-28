//! The CPU address space: work RAM, PPU and APU registers, controllers,
//! OAM DMA and the cartridge.

const Bus = @This();

const Ppu = @import("ppu/ppu.zig");
const Apu = @import("apu/apu.zig");
const Cartridge = @import("cart/cartridge.zig");
const Controller = @import("controller.zig");

ram: [2048]u8 = @splat(0),
controllers: [2]Controller = .{ .{}, .{} },
dma: Dma = .{},

ppu: *Ppu,
apu: *Apu,
cart: *Cartridge,

/// OAM DMA ($4014) state, `Nes.clock` steps it while it's active
pub const Dma = struct {
    page: u8 = 0,
    addr: u8 = 0,
    data: u8 = 0,
    active: bool = false,
    /// waiting for an odd cycle to start
    waiting: bool = true,
};

pub fn write(self: *Bus, addr: u16, value: u8) void {
    // the cartridge can take any write
    if (self.cart.cpuWrite(addr, value)) return;

    switch (addr) {
        0x0000...0x1FFF => self.ram[addr & 0x07FF] = value,
        0x2000...0x3FFF => self.ppu.cpuWrite(addr, value),
        0x4000...0x4013, 0x4015 => self.apu.cpuWrite(addr, value),
        0x4014 => {
            self.dma.page = value;
            self.dma.addr = 0;
            self.dma.active = true;
        },
        // TODO: $4017 is the APU frame counter, see BUGS.md
        0x4016...0x4017 => self.controllers[addr & 1].latch(),
        else => {},
    }
}

pub fn read(self: *Bus, addr: u16) u8 {
    if (self.cart.cpuRead(addr)) |value| return value;

    return switch (addr) {
        0x0000...0x1FFF => self.ram[addr & 0x07FF],
        0x2000...0x3FFF => self.ppu.cpuRead(addr),
        0x4000...0x4013, 0x4015 => self.apu.cpuRead(addr),
        0x4016...0x4017 => self.controllers[addr & 1].read(),
        else => 0,
    };
}
