//! Ricoh 2A03 APU. Only the duty sequencer of pulse 1 exists so far, see
//! BUGS.md for what's missing.

const Apu = @This();

const std = @import("std");

pub const default_sample_rate = 44100;
/// PPU dots per second, `sampleClock` is called once per dot
const dot_rate = 5369318.0;

pulse1_enable: bool = false,
pulse1_sample: f64 = 0,
pulse1: Sequencer = .{},

/// PPU dots, 0-5, the APU runs every 6th dot (every other CPU cycle)
clock_divider: u8 = 0,
/// APU cycles into the frame counter sequence
frame_clock_counter: u32 = 0,

// audio output
sample: f64 = 0,
time_per_sample: f64 = 1.0 / @as(f64, default_sample_rate),
time_per_dot: f64 = 1.0 / dot_rate,
audio_time: f64 = 0,
buffer: [512]f64 = @splat(0),
buffer_index: u32 = 0,

const Sequencer = struct {
    sequence: u8 = 0,
    timer: u16 = 0,
    reload: u16 = 0,
    output: u8 = 0,

    fn clock(self: *Sequencer, enable: bool) u8 {
        if (!enable) return 0;

        self.timer -%= 1;
        if (self.timer == 0xFFFF) {
            self.timer = self.reload + 1;
            self.sequence = std.math.rotr(u8, self.sequence, 1);
            self.output = self.sequence & 1;
        }

        return self.output;
    }
};

pub fn setSampleRate(self: *Apu, sample_rate: u32) void {
    self.time_per_sample = 1.0 / @as(f64, @floatFromInt(sample_rate));
}

/// called once per PPU dot
pub fn clock(self: *Apu) void {
    if (self.clock_divider == 0) {
        self.frame_clock_counter += 1;
        // TODO: quarter frames at 3729, 7457, 11186, 14916 and half frames at
        // 7457, 14916 should clock the envelopes, sweeps and length counters
        self.frame_clock_counter %= 14916;

        _ = self.pulse1.clock(self.pulse1_enable);
        self.pulse1_sample = @floatFromInt(self.pulse1.output);
    }

    self.clock_divider = (self.clock_divider + 1) % 6;
}

/// advance the output sample clock by one PPU dot, returns true when a new
/// sample was produced
pub fn sampleClock(self: *Apu) bool {
    self.audio_time += self.time_per_dot;
    if (self.audio_time < self.time_per_sample) return false;

    self.audio_time -= self.time_per_sample;
    self.sample = self.outputSample();
    if (self.buffer_index < 511) {
        self.buffer[self.buffer_index] = self.sample;
        self.buffer_index += 1;
    } else self.buffer_index = 0;

    return true;
}

pub fn outputSample(self: *const Apu) f64 {
    return self.pulse1_sample * 0.1;
}

pub fn cpuWrite(self: *Apu, addr: u16, value: u8) void {
    switch (addr) {
        0x4000 => self.pulse1.sequence = switch (value >> 6) {
            0 => 0b00000001,
            1 => 0b00000011,
            2 => 0b00001111,
            3 => 0b11111100,
            else => unreachable,
        },
        0x4002 => self.pulse1.reload = (self.pulse1.reload & 0xFF00) | value,
        0x4003 => {
            // BUG: should keep the low byte (& 0x00FF), see BUGS.md
            self.pulse1.reload = (@as(u16, value & 0x07) << 8) | (self.pulse1.reload & 0xFF00);
            self.pulse1.timer = self.pulse1.reload;
        },
        0x4015 => self.pulse1_enable = value & 1 != 0,
        else => {},
    }
}

pub fn cpuRead(self: *Apu, addr: u16) u8 {
    _ = self;
    _ = addr;
    return 0;
}
