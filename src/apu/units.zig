//! Building blocks shared by the APU channels.

pub const length_table = [32]u8{
    10, 254, 20, 2,  40, 4,  80, 6,  160, 8,  60, 10, 14, 12, 26, 14,
    12, 16,  24, 18, 48, 20, 96, 22, 192, 24, 72, 26, 16, 28, 32, 30,
};

/// silences the channel after a set time, clocked every half frame
pub const LengthCounter = struct {
    value: u8 = 0,
    halt: bool = false,
    enabled: bool = false,

    pub fn load(self: *LengthCounter, index: u8) void {
        if (self.enabled) self.value = length_table[index >> 3];
    }

    pub fn clock(self: *LengthCounter) void {
        if (!self.halt and self.value > 0) self.value -= 1;
    }

    /// $4015 enable bit, disabling clears the counter
    pub fn setEnabled(self: *LengthCounter, enabled: bool) void {
        self.enabled = enabled;
        if (!enabled) self.value = 0;
    }

    pub fn active(self: *const LengthCounter) bool {
        return self.value > 0;
    }
};

/// volume that decays from 15 to 0 (or a constant volume), clocked every quarter frame
pub const Envelope = struct {
    start: bool = false,
    divider: u8 = 0,
    decay: u8 = 0,
    /// divider period, also the constant volume
    period: u8 = 0,
    loop: bool = false,
    constant: bool = false,

    /// the low 6 bits of $4000 / $4004 / $400C
    pub fn write(self: *Envelope, value: u8) void {
        self.loop = value & 0x20 != 0;
        self.constant = value & 0x10 != 0;
        self.period = value & 0x0F;
    }

    pub fn clock(self: *Envelope) void {
        if (self.start) {
            self.start = false;
            self.decay = 15;
            self.divider = self.period;
            return;
        }

        if (self.divider > 0) {
            self.divider -= 1;
            return;
        }
        self.divider = self.period;
        if (self.decay > 0) {
            self.decay -= 1;
        } else if (self.loop) {
            self.decay = 15;
        }
    }

    pub fn volume(self: *const Envelope) u8 {
        return if (self.constant) self.period else self.decay;
    }
};
