//! raylib audio output. Not hooked up yet, see the audio entry in BUGS.md:
//! the callback runs on raylib's audio thread, so driving the emulator from
//! here races with the main loop.

const std = @import("std");
const rl = @import("raylib");
const Nes = @import("../nes.zig");
const Apu = @import("../apu/apu.zig");

const max_samples_per_update = 4096;

var stream: rl.AudioStream = undefined;
/// raylib's callback has no user data pointer
var nes: *Nes = undefined;

pub fn init(console: *Nes) !void {
    nes = console;
    nes.apu.setSampleRate(Apu.default_sample_rate);

    rl.initAudioDevice();
    rl.setAudioStreamBufferSizeDefault(max_samples_per_update);
    stream = try rl.loadAudioStream(Apu.default_sample_rate, 32, 1);

    rl.setAudioStreamCallback(stream, audioCallback);
    rl.playAudioStream(stream);
}

pub fn deinit() void {
    rl.unloadAudioStream(stream);
    rl.closeAudioDevice();
}

fn audioCallback(buffer: ?*anyopaque, frames: c_uint) callconv(.c) void {
    const out: [*]f32 = @ptrCast(@alignCast(buffer orelse return));

    for (0..frames) |i| {
        while (!nes.clock()) {}
        out[i] = @floatCast(nes.apu.sample);
    }
}
