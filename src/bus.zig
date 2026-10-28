//! The CPU address space: work RAM, PPU and APU registers, controllers,
//! OAM DMA and the cartridge.

const Bus = @This();

const Ppu = @import("ppu/ppu.zig");
const Apu = @import("apu/apu.zig");
const Cartridge = @import("cart/cartridge.zig");
const Controller = @import("controller.zig");

ram: [2048]u8 = @splat(0),
/// last value on the data bus, unmapped reads return it
open_bus: u8 = 0,
/// bit 0 of the last $4016 write
strobe_latch: bool = false,
controllers: [2]Controller = .{ .{}, .{} },
dma: Dma = .{},

ppu: *Ppu,
apu: *Apu,
cart: *Cartridge,

/// OAM DMA ($4014) state, `Nes` runs it on the CPU's next read
pub const Dma = struct {
    page: u8 = 0,
    addr: u8 = 0,
    active: bool = false,
};

pub fn write(self: *Bus, addr: u16, value: u8) void {
    self.open_bus = value;

    switch (addr) {
        0x0000...0x1FFF => self.ram[addr & 0x07FF] = value,
        0x2000...0x3FFF => self.ppu.cpuWrite(addr, value),
        0x4000...0x4013, 0x4015, 0x4017 => self.apu.cpuWrite(addr, value),
        0x4014 => {
            self.dma.page = value;
            self.dma.addr = 0;
            self.dma.active = true;
        },
        // the strobe pin only updates between cycles, see `updateStrobe`
        0x4016 => self.strobe_latch = value & 1 != 0,
        0x4018...0x401F => {},
        // the cartridge sees everything from $4020 up
        else => _ = self.cart.cpuWrite(addr, value),
    }
}

/// the $4016 output pin (the controllers' strobe) takes the written value
/// on the get -> put transition, so a 1 cycle strobe written on a put cycle
/// is overwritten before it reaches the controllers
pub fn updateStrobe(self: *Bus) void {
    for (&self.controllers) |*pad| pad.setStrobe(self.strobe_latch);
}

pub fn read(self: *Bus, addr: u16) u8 {
    switch (addr) {
        // reading $4015 doesn't drive the external bus, bit 5 is whatever was left on it
        0x4015 => return self.apu.readStatus() | (self.open_bus & 0x20),
        else => {},
    }

    self.open_bus = switch (addr) {
        0x0000...0x1FFF => self.ram[addr & 0x07FF],
        0x2000...0x3FFF => self.ppu.cpuRead(addr),
        // controllers only drive bit 0 (bits 1-4 are other input devices)
        0x4016...0x4017 => (self.open_bus & 0xE0) | self.controllers[addr & 1].read(),
        // write only APU / IO registers
        0x4000...0x4014, 0x4018...0x401F => self.open_bus,
        else => self.cart.cpuRead(addr) orelse self.open_bus,
    };
    return self.open_bus;
}
