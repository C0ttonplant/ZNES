//! Standard NES joypad, read one bit at a time through $4016 / $4017.

const Controller = @This();

/// buttons currently held, set by the frontend
buttons: Buttons = .{},
/// latched buttons being shifted out to the cpu
shift: u8 = 0,

/// bit order is the reverse of the order the console reads them (A first)
pub const Buttons = packed struct(u8) {
    right: bool = false,
    left: bool = false,
    down: bool = false,
    up: bool = false,
    select: bool = false,
    start: bool = false,
    b: bool = false,
    a: bool = false,
};

pub fn read(self: *Controller) u8 {
    const bit: u8 = self.shift >> 7;
    self.shift <<= 1;
    return bit;
}

pub fn latch(self: *Controller) void {
    self.shift = @bitCast(self.buttons);
}
