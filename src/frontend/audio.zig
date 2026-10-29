//! raylib audio output.
//!
//! The emulator runs on the main thread and the APU queues finished samples
//! in a ring buffer. `update` is called once per frame and hands raylib a
//! new chunk whenever one of its stream buffers is free, so nothing is
//! shared with raylib's audio thread.

const rl = @import("raylib");
const Apu = @import("../apu/apu.zig");

/// samples per raylib buffer, ~23 ms at 44.1 kHz (raylib double buffers)
const chunk_size = 1024;
/// if the APU gets this far ahead (the window was dragged, a debugger
/// paused us...), throw the backlog away instead of lagging behind forever
const max_queued = chunk_size * 4;

var stream: rl.AudioStream = undefined;
var chunk: [chunk_size]f32 = @splat(0);
/// false when there's no audio device, everything here is a no-op then
var ready = false;

pub fn init() !void {
    rl.initAudioDevice();
    if (!rl.isAudioDeviceReady()) return error.NoAudioDevice;
    rl.setAudioStreamBufferSizeDefault(chunk_size);
    stream = try rl.loadAudioStream(Apu.default_sample_rate, 32, 1);
    rl.playAudioStream(stream);
    ready = true;
}

pub fn deinit() void {
    if (ready) rl.unloadAudioStream(stream);
    rl.closeAudioDevice();
    ready = false;
}

/// 0.0 - 1.0
pub fn setVolume(volume: f32) void {
    if (ready) rl.setAudioStreamVolume(stream, volume);
}

/// feed raylib from the APU's queue, `apu` null plays silence
pub fn update(maybe_apu: ?*Apu) void {
    if (!ready) return;
    const apu = maybe_apu orelse {
        while (rl.isAudioStreamProcessed(stream)) {
            @memset(&chunk, 0);
            rl.updateAudioStream(stream, &chunk, chunk_size);
        }
        return;
    };

    while (apu.samplesQueued() > max_queued) {
        var discard: [chunk_size]f32 = undefined;
        _ = apu.takeSamples(&discard);
    }

    while (rl.isAudioStreamProcessed(stream)) {
        const n = apu.takeSamples(&chunk);
        // not enough yet, hold the last level instead of clicking to 0
        const fill = if (n > 0) chunk[n - 1] else 0;
        @memset(chunk[n..], fill);
        rl.updateAudioStream(stream, &chunk, chunk_size);
    }
}
