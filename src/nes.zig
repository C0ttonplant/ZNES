//! The console. Owns every component and keeps them in step.
//!
//! The CPU drives time: each of its bus accesses is one CPU cycle, and
//! `cpuRead` / `cpuWrite` run the PPU for 3 dots and the APU for one cycle
//! before doing the access. DMA also happens here, it stalls the CPU on its
//! next read.
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
/// NMI line level at the end of the last CPU cycle, for edge detection
nmi_line: bool = false,

/// takes ownership of `cart`
pub fn init(self: *Nes, cart: Cartridge) void {
    self.* = .{
        .cpu = .init(self),
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

/// the reset button
pub fn reset(self: *Nes) void {
    self.ppu.reset();
    self.apu.reset();
    self.bus.dma = .{};
    self.cpu.reset();
}

/// run until the PPU finishes a frame
pub fn runFrame(self: *Nes) void {
    while (!self.ppu.frame_complete) self.cpu.step();
    self.ppu.frame_complete = false;
}

// CPU cycles

pub fn cpuRead(self: *Nes, addr: u16) u8 {
    if (self.bus.dma.active or self.apu.dmcDmaPending()) self.runDma(addr);

    self.startCycle();
    const value = self.bus.read(addr);
    self.endCycle();
    return value;
}

pub fn cpuWrite(self: *Nes, addr: u16, value: u8) void {
    self.startCycle();
    self.bus.write(addr, value);
    self.endCycle();
}

/// of the 3 PPU dots in a CPU cycle, how many happen before the CPU's bus
/// access (the rest happen after it). This decides exactly which dot a
/// $2002 read lands on relative to vblank.
const dots_before_access = 2;

/// everything that happens in a CPU cycle before the bus access
fn startCycle(self: *Nes) void {
    for (0..dots_before_access) |_| self.ppu.step();
    self.apu.clock();
}

/// everything after the bus access: the CPU samples its interrupt lines
fn endCycle(self: *Nes) void {
    for (dots_before_access..3) |_| self.ppu.step();

    // the CPU reacts to the NMI line going active, not to its level
    const nmi_line = self.ppu.nmiLine();
    const nmi_edge = nmi_line and !self.nmi_line;
    self.nmi_line = nmi_line;

    self.cpu.irq_line = self.apu.irq() or self.cart.irq();
    self.cpu.pollInterrupts(nmi_edge);

    if (self.isGetCycle()) self.bus.updateStrobe();
    self.cpu.clock_count += 1;
}

/// a cycle where DMA holds the CPU, the CPU's read gets repeated
fn haltedCycle(self: *Nes, cpu_addr: u16) void {
    self.startCycle();
    _ = self.bus.read(cpu_addr);
    self.endCycle();
}

/// DMA reads alternate with the CPU-side "put" cycles
fn isGetCycle(self: *const Nes) bool {
    return self.cpu.clock_count % 2 == 0;
}

/// OAM DMA ($4014) and DMC sample DMA. Both halt the CPU on a read cycle,
/// then read on "get" cycles; OAM DMA writes to $2004 on "put" cycles. When
/// both want the bus, DMC takes the get cycle and OAM DMA waits.
fn runDma(self: *Nes, cpu_addr: u16) void {
    const oam = &self.bus.dma;
    var oam_data: ?u8 = null;
    // DMC DMA needs one cycle after the halt before it can read
    var dmc_ready = false;

    self.haltedCycle(cpu_addr);

    while (oam.active or self.apu.dmcDmaPending()) {
        const dmc_pending = self.apu.dmcDmaPending();

        if (self.isGetCycle()) {
            if (dmc_pending and dmc_ready) {
                self.startCycle();
                self.apu.dmcFill(self.bus.read(self.apu.dmcAddress()));
                self.endCycle();
                dmc_ready = false;
            } else if (oam.active and oam_data == null) {
                self.startCycle();
                oam_data = self.bus.read((@as(u16, oam.page) << 8) | oam.addr);
                self.endCycle();
            } else {
                self.haltedCycle(cpu_addr);
            }
        } else if (oam.active and oam_data != null) {
            self.startCycle();
            self.ppu.cpuWrite(0x2004, oam_data.?);
            self.endCycle();
            oam_data = null;

            oam.addr +%= 1;
            if (oam.addr == 0) oam.active = false;
        } else {
            self.haltedCycle(cpu_addr);
        }

        if (dmc_pending) dmc_ready = true;
    }
}
