//! Delta modulation channel, $4010-$4013. Plays 1 bit delta samples that it
//! fetches from CPU memory with DMA (see `Nes.runDma`).

const Dmc = @This();

/// timer periods in CPU cycles (NTSC)
const rate_table = [16]u16{ 428, 380, 340, 320, 286, 254, 226, 214, 190, 160, 142, 128, 106, 84, 72, 54 };

irq_enabled: bool = false,
loop: bool = false,
rate: u16 = rate_table[0],
timer: u16 = 0,
/// 7 bit output level
level: u8 = 0,

sample_address: u16 = 0xC000,
sample_length: u16 = 1,
current_address: u16 = 0xC000,
bytes_remaining: u16 = 0,

/// the next byte, fetched by DMA, null when it needs a new one
sample_buffer: ?u8 = null,
shift: u8 = 0,
bits_remaining: u8 = 8,
silence: bool = true,

irq_flag: bool = false,

pub fn write(self: *Dmc, reg: u2, value: u8) void {
    switch (reg) {
        0 => {
            self.irq_enabled = value & 0x80 != 0;
            if (!self.irq_enabled) self.irq_flag = false;
            self.loop = value & 0x40 != 0;
            self.rate = rate_table[value & 0x0F];
        },
        1 => self.level = value & 0x7F,
        2 => self.sample_address = 0xC000 + @as(u16, value) * 64,
        3 => self.sample_length = @as(u16, value) * 16 + 1,
    }
}

/// $4015 bit 4
pub fn setEnabled(self: *Dmc, enabled: bool) void {
    self.irq_flag = false;
    if (!enabled) {
        self.bytes_remaining = 0;
    } else if (self.bytes_remaining == 0) {
        self.restart();
    }
}

fn restart(self: *Dmc) void {
    self.current_address = self.sample_address;
    self.bytes_remaining = self.sample_length;
}

/// the sample buffer is empty and there are bytes left to fetch
pub fn dmaPending(self: *const Dmc) bool {
    return self.sample_buffer == null and self.bytes_remaining > 0;
}

/// a byte fetched by DMA
pub fn fill(self: *Dmc, value: u8) void {
    self.sample_buffer = value;
    self.current_address = if (self.current_address == 0xFFFF) 0x8000 else self.current_address + 1;
    self.bytes_remaining -= 1;

    if (self.bytes_remaining == 0) {
        if (self.loop) {
            self.restart();
        } else if (self.irq_enabled) {
            self.irq_flag = true;
        }
    }
}

/// every CPU cycle
pub fn clockTimer(self: *Dmc) void {
    if (self.timer > 0) {
        self.timer -= 1;
        return;
    }
    self.timer = self.rate - 1;

    if (!self.silence) {
        if (self.shift & 1 != 0) {
            if (self.level <= 125) self.level += 2;
        } else {
            if (self.level >= 2) self.level -= 2;
        }
    }
    self.shift >>= 1;

    self.bits_remaining -= 1;
    if (self.bits_remaining == 0) {
        self.bits_remaining = 8;
        if (self.sample_buffer) |byte| {
            self.silence = false;
            self.shift = byte;
            self.sample_buffer = null;
        } else {
            self.silence = true;
        }
    }
}

pub fn output(self: *const Dmc) u8 {
    return self.level;
}
