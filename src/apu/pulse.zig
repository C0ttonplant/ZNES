//! Pulse (square wave) channel, $4000-$4003 and $4004-$4007.

const Pulse = @This();

const units = @import("units.zig");

const duty_table = [4][8]u1{
    .{ 0, 1, 0, 0, 0, 0, 0, 0 },
    .{ 0, 1, 1, 0, 0, 0, 0, 0 },
    .{ 0, 1, 1, 1, 1, 0, 0, 0 },
    .{ 1, 0, 0, 1, 1, 1, 1, 1 },
};

/// pulse 1 negates its sweep with one's complement, pulse 2 with two's
ones_complement: bool,

duty: u2 = 0,
step: u3 = 0,
period: u16 = 0,
timer: u16 = 0,
envelope: units.Envelope = .{},
length: units.LengthCounter = .{},

sweep_enabled: bool = false,
sweep_period: u8 = 0,
sweep_negate: bool = false,
sweep_shift: u4 = 0,
sweep_reload: bool = false,
sweep_divider: u8 = 0,

pub fn init(ones_complement: bool) Pulse {
    return .{ .ones_complement = ones_complement };
}

pub fn write(self: *Pulse, reg: u2, value: u8) void {
    switch (reg) {
        0 => {
            self.duty = @truncate(value >> 6);
            self.length.halt = value & 0x20 != 0;
            self.envelope.write(value);
        },
        1 => {
            self.sweep_enabled = value & 0x80 != 0;
            self.sweep_period = (value >> 4) & 0x07;
            self.sweep_negate = value & 0x08 != 0;
            self.sweep_shift = @truncate(value & 0x07);
            self.sweep_reload = true;
        },
        2 => self.period = (self.period & 0x0700) | value,
        3 => {
            self.period = (self.period & 0x00FF) | (@as(u16, value & 0x07) << 8);
            self.length.load(value);
            self.step = 0;
            self.envelope.start = true;
        },
    }
}

/// every APU cycle (every other CPU cycle)
pub fn clockTimer(self: *Pulse) void {
    if (self.timer == 0) {
        self.timer = self.period;
        self.step +%= 1;
    } else {
        self.timer -= 1;
    }
}

/// half frame
pub fn clockSweep(self: *Pulse) void {
    if (self.sweep_divider == 0 and self.sweep_enabled and self.sweep_shift > 0 and !self.muted()) {
        self.period = self.targetPeriod();
    }
    if (self.sweep_divider == 0 or self.sweep_reload) {
        self.sweep_divider = self.sweep_period;
        self.sweep_reload = false;
    } else {
        self.sweep_divider -= 1;
    }
}

fn targetPeriod(self: *const Pulse) u16 {
    const change = self.period >> self.sweep_shift;
    if (!self.sweep_negate) return self.period + change;
    return self.period -| (change + @intFromBool(self.ones_complement));
}

/// the sweep unit mutes the channel when the period is out of range, even if
/// the sweep is disabled
fn muted(self: *const Pulse) bool {
    return self.period < 8 or self.targetPeriod() > 0x7FF;
}

pub fn output(self: *const Pulse) u8 {
    if (!self.length.active() or self.muted() or duty_table[self.duty][self.step] == 0) return 0;
    return self.envelope.volume();
}
