//! The console. Owns every component and steps them together off the PPU
//! dot clock (CPU and OAM DMA every 3rd dot).
//!
//! Components point at each other, so a `Nes` must not move after `init`
//! (allocate it, or `init` it in place).

const Nes = @This();

const std = @import("std");
const Cpu = @import("cpu/cpu.zig");
const Ppu = @import("ppu/ppu.zig");
const Apu = @import("apu/apu.zig");
const Bus = @import("bus.zig");
const Cartridge = @import("cart/cartridge.zig");

cpu: Cpu,
ppu: Ppu,
apu: Apu,
bus: Bus,
cart: Cartridge,
/// PPU dots since power on
clock_count: u64 = 0,

/// takes ownership of `cart`
pub fn init(self: *Nes, cart: Cartridge) void {
    self.* = .{
        .cpu = .init(&self.bus),
        .ppu = .init(&self.cart),
        .apu = .{},
        .bus = .{ .ppu = &self.ppu, .apu = &self.apu, .cart = &self.cart },
        .cart = cart,
    };
    self.cpu.reset();
}

pub fn deinit(self: *Nes, gpa: std.mem.Allocator) void {
    self.cart.deinit(gpa);
}

pub fn reset(self: *Nes) void {
    self.cpu.reset();
    self.clock_count = 0;
}

/// run until the PPU finishes a frame
pub fn runFrame(self: *Nes) void {
    while (!self.ppu.frame_complete) _ = self.clock();
    self.ppu.frame_complete = false;
}

/// advance one PPU dot, returns true when the APU produced an audio sample
pub fn clock(self: *Nes) bool {
    self.ppu.clock();
    if (self.ppu.nmi_requested) {
        self.ppu.nmi_requested = false;
        self.cpu.nmi();
    }

    self.apu.clock();

    if (self.clock_count % 3 == 0) {
        if (self.bus.dma.active) {
            self.stepDma();
        } else {
            _ = self.cpu.clock();
        }
    }

    const sample_ready = self.apu.sampleClock();

    self.clock_count += 1;
    self.ppu.advanceDot();
    return sample_ready;
}

/// one CPU cycle of OAM DMA, the CPU is stalled while it runs
fn stepDma(self: *Nes) void {
    const dma = &self.bus.dma;
    const odd_cycle = self.clock_count % 2 == 1;

    if (dma.waiting) {
        // wait for an odd cycle before starting
        if (odd_cycle) dma.waiting = false;
        return;
    }

    if (!odd_cycle) {
        // read on even cycles ..
        dma.data = self.bus.read((@as(u16, dma.page) << 8) | dma.addr);
    } else {
        // .. write on odd cycles
        self.ppu.sprites.oamBytes()[dma.addr] = dma.data;
        dma.addr +%= 1;

        if (dma.addr == 0) {
            dma.active = false;
            dma.waiting = true;
        }
    }
}
