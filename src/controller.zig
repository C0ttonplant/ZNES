//! Standard NES joypad, read one bit at a time through $4016 / $4017.

const Controller = @This();

/// buttons currently held, set by the frontend
buttons: Buttons = .{},
/// latched buttons being shifted out to the cpu, A first
shift: u8 = 0,
/// while the strobe is high the buttons are reloaded continuously
strobe: bool = false,

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
    if (self.strobe) self.latch();

    const bit: u8 = self.shift >> 7;
    // after all 8 buttons official pads return 1s
    self.shift = (self.shift << 1) | 1;
    return bit;
}

pub fn setStrobe(self: *Controller, high: bool) void {
    // the latch follows the buttons while high and holds them once it goes low
    if (self.strobe or high) self.latch();
    self.strobe = high;
}

fn latch(self: *Controller) void {
    self.shift = @bitCast(self.buttons);
}
