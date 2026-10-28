//! Noise channel, $400C-$400F.

const Noise = @This();

const units = @import("units.zig");

/// timer periods in CPU cycles (NTSC)
const period_table = [16]u16{ 4, 8, 16, 32, 64, 96, 128, 160, 202, 254, 380, 508, 762, 1016, 2034, 4068 };

/// 15 bit linear feedback shift register
shift: u15 = 1,
/// short mode, feedback from bit 6 instead of bit 1
short_mode: bool = false,
period: u16 = period_table[0],
timer: u16 = 0,
envelope: units.Envelope = .{},
length: units.LengthCounter = .{},

pub fn write(self: *Noise, reg: u2, value: u8) void {
    switch (reg) {
        0 => {
            self.length.halt = value & 0x20 != 0;
            self.envelope.write(value);
        },
        1 => {},
        2 => {
            self.short_mode = value & 0x80 != 0;
            self.period = period_table[value & 0x0F];
        },
        3 => {
            self.length.load(value);
            self.envelope.start = true;
        },
    }
}

/// every CPU cycle
pub fn clockTimer(self: *Noise) void {
    if (self.timer > 0) {
        self.timer -= 1;
        return;
    }
    self.timer = self.period - 1;

    const tap: u4 = if (self.short_mode) 6 else 1;
    const feedback = (self.shift ^ (self.shift >> tap)) & 1;
    self.shift = (self.shift >> 1) | (feedback << 14);
}

pub fn output(self: *const Noise) u8 {
    if (!self.length.active() or self.shift & 1 != 0) return 0;
    return self.envelope.volume();
}
