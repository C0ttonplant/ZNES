const apu_2A03 = @This();
const rl = @import("raylib");
const std = @import("std");
const bus = @import("bus.zig");
const ppu = @import("ppu.zig");
var rand = std.Random.Isaac64.init(82907389);
const MAX_SAMPLES: i32            =  512;
const MAX_SAMPLES_PER_UPDATE: i32 = 4096;
const SAMPLE_RATE: usize          = 44100;

pub var audioBuffer: [512]f64 = undefined;
pub var bufferInd: u32 = 0;

pub var pulse1Enable: bool = false;
pub var pulse1Sample: f64 = 0;
pub var pulse1Seq: sequencer = .{};

pub var audioSample: f64 = 0;
pub var timePerSystemSample: f64 = 0;
pub var timePerNesClock: f64 = 0;   
pub var audioTime: f64 = 0;

var stream: rl.AudioStream = undefined;

var frameClockCounter: u32 = 0;
var clockCounter: u32 = 0;

const sequencer = packed struct 
{
    sequence: u32 = 0,
    timer: u16 = 0,
    reload: u16 = 0,
    output: u8 = 0,

    pub fn clock(self: *sequencer, enable: bool, func: *const fn (s: *u32) void) u8
    {
        if(!enable) return 0;

        self.timer = @subWithOverflow(self.timer, 1)[0];
        if(self.timer == 0xFFFF)
        {
            self.timer = self.reload + 1;
            func(&self.sequence);
            self.output = @truncate(self.sequence & 1);
        }

        return self.output;
    }
};

pub fn audioCallback(buffer: ?*anyopaque, frames: c_uint) callconv(.C) void
{
    var bfr: *[MAX_SAMPLES_PER_UPDATE]f32 = @alignCast(@ptrCast(buffer orelse return));   

    for (0..frames) |i| 
    {
        // while (!ppu.drawSynced()) {}
        clock();
        bfr[i] = @floatCast(getOutputSample());
    }
    ppu.drawFrame();
}

pub fn setSampleFrequency(sampleRate: u32) void
{
    timePerSystemSample = 1.0 / @as(f64, @floatFromInt(sampleRate));
    timePerNesClock = 1.0 / 5369318.0; 
}

pub fn getOutputSample() f64
{
    return pulse1Sample * 0.1;
}

pub fn init() !void
{
    setSampleFrequency(SAMPLE_RATE);

    rl.initAudioDevice();
    rl.setAudioStreamBufferSizeDefault(MAX_SAMPLES_PER_UPDATE);
    stream = try rl.loadAudioStream(SAMPLE_RATE, 32, 1);

    rl.setAudioStreamCallback(stream, audioCallback);   

    rl.playAudioStream(stream);
}

pub fn destroy() void
{
    // wait for drawSync to finish
    // while(!complete) { std.time.sleep(100_000_000); }
    rl.unloadAudioStream(stream);
    rl.closeAudioDevice();
}

pub fn clock() void
{
    var quarterFrame: bool = false;
    var halfFrame: bool = false;

    if(clockCounter % 6 == 0)
    {
        frameClockCounter += 1;

        halfFrame = frameClockCounter == 7457 or frameClockCounter == 14916;
        quarterFrame = halfFrame or frameClockCounter == 3729 or frameClockCounter == 11186;

        frameClockCounter = frameClockCounter % 14916;

        _ = pulse1Seq.clock(pulse1Enable, &ror);

        pulse1Sample = @floatFromInt(pulse1Seq.output);
    }

    clockCounter += 1;
}

pub fn ror(s: *u32) void
{
    s.* = ((s.* & 1) << 7) | ((s.* & 0xFE) >> 1); 
}

pub fn cpuWrite(addr: u16, dat: u8) void
{
    switch (addr) 
    {
        0x4000 => 
        {
            switch ((dat & 0xC0) >> 6) 
            {
                0 => pulse1Seq.sequence = 0b00000001,
                1 => pulse1Seq.sequence = 0b00000011,
                2 => pulse1Seq.sequence = 0b00001111,
                3 => pulse1Seq.sequence = 0b11111100,
                else => {},
            }
        },
        0x4001 => 
        {
            
        },
        0x4002 => 
        {
            pulse1Seq.reload = (pulse1Seq.reload & 0xFF00) | dat;
        },
        0x4003 => 
        {
            pulse1Seq.reload = (@as(u16, dat & 0x07) << 8) | (pulse1Seq.reload & 0xFF00);
            pulse1Seq.timer = pulse1Seq.reload;
        },
        0x4004 => 
        {
            
        },
        0x4005 => 
        {
            
        },
        0x4006 => 
        {
            
        },
        0x4007 => 
        {
            
        },
        0x4008 => 
        {
            
        },
        0x400C => 
        {
            
        },
        0x400E => 
        {
            
        },
        0x4015 => 
        {
            pulse1Enable = dat & 1 != 0;
        },
        0x400F => 
        {
            
        },
        else => {}
    }
}

pub fn cpuRead(addr: u16) u8
{
    return switch (addr) 
    {
        else => 0,
    };
}