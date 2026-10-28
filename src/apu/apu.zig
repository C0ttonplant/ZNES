//! Ricoh 2A03 APU: two pulse channels, triangle, noise, DMC and the frame
//! counter that clocks their envelopes, sweeps and length counters.
//! https://www.nesdev.org/wiki/APU
//!
//! `clock` runs once per CPU cycle. The mixed output is averaged down to the
//! output sample rate and queued in `samples` for the frontend to play.

const Apu = @This();

const std = @import("std");
const Pulse = @import("pulse.zig");
const Triangle = @import("triangle.zig");
const Noise = @import("noise.zig");
const Dmc = @import("dmc.zig");

pub const default_sample_rate = 44100;
/// NTSC CPU clock
const cpu_rate = 1789773.0;

pulse1: Pulse = .init(true),
pulse2: Pulse = .init(false),
triangle: Triangle = .{},
noise: Noise = .{},
dmc: Dmc = .{},

/// the CPU cycle currently running (starts at -1, before the first one),
/// see `isGetCycle`. The pulse timers run on put cycles.
cycle: u64 = std.math.maxInt(u64),
frame: FrameCounter = .{},
/// a $4015 write enabling the DMC takes effect after a short delay
dmc_enable_delay: u8 = 0,

// audio output
time_per_sample: f64 = cpu_rate / @as(f64, default_sample_rate),
sample_time: f64 = 0,
sample_sum: f32 = 0,
sample_count: u32 = 0,
/// DC blocking filter state
filter_in: f32 = 0,
filter_out: f32 = 0,
/// ring buffer of finished samples, drained by `takeSamples`
samples: [8192]f32 = @splat(0),
samples_read: usize = 0,
samples_written: usize = 0,

const FrameCounter = struct {
    five_step: bool = false,
    irq_inhibit: bool = false,
    irq_flag: bool = false,
    /// a $4015 read clears `irq_flag`, but only at the next get cycle
    clear_irq_pending: bool = false,
    /// CPU cycles into the sequence
    cycle: u32 = 0,
    /// a $4017 write takes effect 3 or 4 cycles later
    write_delay: u8 = 0,
    pending_five_step: bool = false,
};

pub fn setSampleRate(self: *Apu, sample_rate: u32) void {
    self.time_per_sample = cpu_rate / @as(f64, @floatFromInt(sample_rate));
}

/// the reset button silences everything and restarts the frame counter
pub fn reset(self: *Apu) void {
    self.setChannelsEnabled(0);
    self.dmc.irq_flag = false;
    self.frame.irq_flag = false;
    self.frame.cycle = 0;
    self.frame.write_delay = 0;
    self.triangle.step = 0;
}

pub fn irq(self: *const Apu) bool {
    return self.frame.irq_flag or self.dmc.irq_flag;
}

/// even cycles are "get" cycles, odd ones "put" cycles (counting from 0,
/// same as the DMA get / put cycles in `Nes`)
pub fn isGetCycle(self: *const Apu) bool {
    return self.cycle % 2 == 0;
}

/// called at the start of every CPU cycle
pub fn clock(self: *Apu) void {
    self.cycle +%= 1;

    if (self.frame.clear_irq_pending and self.isGetCycle()) {
        self.frame.clear_irq_pending = false;
        self.frame.irq_flag = false;
    }
    if (self.dmc_enable_delay > 0) {
        self.dmc_enable_delay -= 1;
        if (self.dmc_enable_delay == 0) self.dmc.setEnabled(true);
    }

    self.clockFrameCounter();

    self.triangle.clockTimer();
    self.noise.clockTimer();
    self.dmc.clockTimer();
    if (!self.isGetCycle()) {
        self.pulse1.clockTimer();
        self.pulse2.clockTimer();
    }

    self.mixSample();
}

// frame counter

fn clockFrameCounter(self: *Apu) void {
    const fc = &self.frame;

    if (fc.write_delay > 0) {
        fc.write_delay -= 1;
        if (fc.write_delay == 0) {
            fc.five_step = fc.pending_five_step;
            fc.cycle = 0;
            // switching to 5 step mode clocks everything right away
            if (fc.five_step) {
                self.quarterFrame();
                self.halfFrame();
            }
        }
    }

    fc.cycle += 1;
    if (!fc.five_step) {
        switch (fc.cycle) {
            7457 => self.quarterFrame(),
            14913 => {
                self.quarterFrame();
                self.halfFrame();
            },
            22371 => self.quarterFrame(),
            29828 => self.frameIrq(),
            29829 => {
                self.frameIrq();
                self.quarterFrame();
                self.halfFrame();
            },
            29830 => {
                self.frameIrq();
                fc.cycle = 0;
            },
            else => {},
        }
    } else {
        switch (fc.cycle) {
            7457 => self.quarterFrame(),
            14913 => {
                self.quarterFrame();
                self.halfFrame();
            },
            22371 => self.quarterFrame(),
            37281 => {
                self.quarterFrame();
                self.halfFrame();
            },
            37282 => fc.cycle = 0,
            else => {},
        }
    }
}

fn frameIrq(self: *Apu) void {
    if (!self.frame.irq_inhibit) self.frame.irq_flag = true;
}

/// envelopes and the triangle's linear counter
fn quarterFrame(self: *Apu) void {
    self.pulse1.envelope.clock();
    self.pulse2.envelope.clock();
    self.noise.envelope.clock();
    self.triangle.clockLinear();
}

/// length counters and sweeps
fn halfFrame(self: *Apu) void {
    self.pulse1.length.clock();
    self.pulse2.length.clock();
    self.triangle.length.clock();
    self.noise.length.clock();
    self.pulse1.clockSweep();
    self.pulse2.clockSweep();
}

// registers

pub fn cpuWrite(self: *Apu, addr: u16, value: u8) void {
    const reg: u2 = @truncate(addr);
    switch (addr) {
        0x4000...0x4003 => self.pulse1.write(reg, value),
        0x4004...0x4007 => self.pulse2.write(reg, value),
        0x4008...0x400B => self.triangle.write(reg, value),
        0x400C...0x400F => self.noise.write(reg, value),
        0x4010...0x4013 => self.dmc.write(reg, value),
        0x4015 => self.setChannelsEnabled(value),
        0x4017 => {
            self.frame.pending_five_step = value & 0x80 != 0;
            self.frame.irq_inhibit = value & 0x40 != 0;
            if (self.frame.irq_inhibit) self.frame.irq_flag = false;
            // the sequencer restarts 3 cycles after a write on a put cycle, 4
            // after a get cycle. Counted from the start of the next cycle
            // here, which flips which of the two needs the extra cycle.
            self.frame.write_delay = if (self.isGetCycle()) 3 else 4;
        },
        else => {},
    }
}

fn setChannelsEnabled(self: *Apu, value: u8) void {
    self.pulse1.length.setEnabled(value & 0x01 != 0);
    self.pulse2.length.setEnabled(value & 0x02 != 0);
    self.triangle.length.setEnabled(value & 0x04 != 0);
    self.noise.length.setEnabled(value & 0x08 != 0);

    self.dmc.irq_flag = false;
    if (value & 0x10 == 0) {
        self.dmc.setEnabled(false);
        self.dmc_enable_delay = 0;
    } else {
        // enabling only happens 2 or 3 cycles later, a DMA the channel
        // wants before then waits for it
        self.dmc_enable_delay = if (self.isGetCycle()) dmc_enable_delay_get else dmc_enable_delay_put;
    }
}

const dmc_enable_delay_get = 3;
const dmc_enable_delay_put = 3;

/// $4015 read, bit 5 is open bus (filled in by the bus). Clears the frame IRQ.
pub fn readStatus(self: *Apu) u8 {
    var status: u8 = 0;
    if (self.pulse1.length.active()) status |= 0x01;
    if (self.pulse2.length.active()) status |= 0x02;
    if (self.triangle.length.active()) status |= 0x04;
    if (self.noise.length.active()) status |= 0x08;
    if (self.dmc.bytes_remaining > 0) status |= 0x10;
    if (self.frame.irq_flag) status |= 0x40;
    if (self.dmc.irq_flag) status |= 0x80;

    self.frame.clear_irq_pending = true;
    return status;
}

// DMC DMA, run by `Nes`

pub fn dmcDmaPending(self: *const Apu) bool {
    return self.dmc.dmaPending();
}

pub fn dmcAddress(self: *const Apu) u16 {
    return self.dmc.current_address;
}

pub fn dmcFill(self: *Apu, value: u8) void {
    self.dmc.fill(value);
}

// audio output

/// the nonlinear DAC mix of every channel, 0.0 to ~1.0
fn mix(self: *const Apu) f32 {
    const pulse: f32 = @floatFromInt(@as(u16, self.pulse1.output()) + self.pulse2.output());
    const pulse_out: f32 = if (pulse == 0) 0 else 95.88 / (8128.0 / pulse + 100.0);

    const tnd: f32 = @as(f32, @floatFromInt(self.triangle.output())) / 8227.0 +
        @as(f32, @floatFromInt(self.noise.output())) / 12241.0 +
        @as(f32, @floatFromInt(self.dmc.output())) / 22638.0;
    const tnd_out: f32 = if (tnd == 0) 0 else 159.79 / (1.0 / tnd + 100.0);

    return pulse_out + tnd_out;
}

/// average the mix over each output sample period, then remove the DC offset
fn mixSample(self: *Apu) void {
    self.sample_sum += self.mix();
    self.sample_count += 1;

    self.sample_time += 1;
    if (self.sample_time < self.time_per_sample) return;
    self.sample_time -= self.time_per_sample;

    const sample = self.sample_sum / @as(f32, @floatFromInt(self.sample_count));
    self.sample_sum = 0;
    self.sample_count = 0;

    // one pole high pass at ~20 Hz
    self.filter_out = sample - self.filter_in + 0.997 * self.filter_out;
    self.filter_in = sample;

    self.pushSample(self.filter_out);
}

fn pushSample(self: *Apu, sample: f32) void {
    // full, drop the oldest
    if (self.samples_written - self.samples_read == self.samples.len) self.samples_read += 1;
    self.samples[self.samples_written % self.samples.len] = sample;
    self.samples_written += 1;
}

/// number of samples waiting in the ring buffer
pub fn samplesQueued(self: *const Apu) usize {
    return self.samples_written - self.samples_read;
}

/// move queued samples into `out`, returns how many were copied
pub fn takeSamples(self: *Apu, out: []f32) usize {
    const n = @min(out.len, self.samplesQueued());
    for (out[0..n]) |*sample| {
        sample.* = self.samples[self.samples_read % self.samples.len];
        self.samples_read += 1;
    }
    return n;
}
