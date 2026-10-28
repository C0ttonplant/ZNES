//! Triangle channel, $4008-$400B.

const Triangle = @This();

const units = @import("units.zig");

const sequence = [32]u8{
    15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5,  4,  3,  2,  1,  0,
    0,  1,  2,  3,  4,  5,  6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
};

period: u16 = 0,
timer: u16 = 0,
step: u5 = 0,
length: units.LengthCounter = .{},

linear_counter: u8 = 0,
linear_reload_value: u8 = 0,
linear_reload: bool = false,
/// also the length counter halt flag
control: bool = false,

pub fn write(self: *Triangle, reg: u2, value: u8) void {
    switch (reg) {
        0 => {
            self.control = value & 0x80 != 0;
            self.length.halt = self.control;
            self.linear_reload_value = value & 0x7F;
        },
        1 => {},
        2 => self.period = (self.period & 0x0700) | value,
        3 => {
            self.period = (self.period & 0x00FF) | (@as(u16, value & 0x07) << 8);
            self.length.load(value);
            self.linear_reload = true;
        },
    }
}

/// every CPU cycle
pub fn clockTimer(self: *Triangle) void {
    if (self.timer == 0) {
        self.timer = self.period;
        if (self.length.active() and self.linear_counter > 0) self.step +%= 1;
    } else {
        self.timer -= 1;
    }
}

/// quarter frame
pub fn clockLinear(self: *Triangle) void {
    if (self.linear_reload) {
        self.linear_counter = self.linear_reload_value;
    } else if (self.linear_counter > 0) {
        self.linear_counter -= 1;
    }
    if (!self.control) self.linear_reload = false;
}

pub fn output(self: *const Triangle) u8 {
    // very short periods are ultrasonic, the real chip outputs them but they
    // only pop on speakers, hold the midpoint instead
    if (self.period < 2) return 7;
    return sequence[self.step];
}
