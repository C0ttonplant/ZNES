const bus = @This();

const std = @import("std");
const rl = @import("raylib");
const cpu_6502 = @import("cpu.zig");
const ppu_2c02 = @import("ppu.zig");
const apu_2A02 = @import("apu.zig");
const cartrige = @import("cartrige.zig");

pub var systemClockCounter: u128 = 0;

pub var ram: ram16k = .{};
pub var cart: *cartrige = undefined;

var dmaPage: u8 = 0;
var dmaAddr: u8 = 0;
var dmaData: u8 = 0;
var dmaTransfer: bool = false;
var dmaDummy: bool = true;  

/// write data onto bus
pub fn write(addr: u16, dat: u8) void
{
    // the cartrige can take any write
    if(cart.cpuWrite(addr, dat))
    {
        return;
    }

    switch (addr) 
    {
        0...0x1FFF => ram.write(addr, dat),

        0x2000...0x3FFF => ppu_2c02.cpuWrite(addr, dat),

        0x4000...0x4013,
        0x4015 => apu_2A02.cpuWrite(addr, dat),
        // TODO: fix address conflict on 0x4017
        0x4016...0x4017 => controller.write(addr),

        0x4014 => 
        {
            dmaPage = dat;
            dmaAddr = 0;
            dmaTransfer = true;
        },
        else => {},
    }
}

/// read data from bus
pub fn read(addr: u16, readOnly: bool) u8
{
    var data: u8 = 0;
    _ = readOnly;

    if(cart.cpuRead(addr, &data))
    {
        return data;
    }
    return switch (addr) 
    {
        0...0x1FFF => ram.read(addr),

        0x2000...0x3FFF => ppu_2c02.cpuRead(addr, false),

        0x4000...0x4013,
        0x4015 => apu_2A02.cpuRead(addr),

        0x4016...0x4017 => controller.read(addr),

        else => 0,
    };
}

pub fn instertCartrage(crt: *cartrige) void
{
    cart = crt;
    ppu_2c02.insertCartrige(crt);
}

pub fn removeCartrige() void
{
    ppu_2c02.removeCartrige();
    cart.deInit();
    cart = undefined;
}

pub fn reset() void
{
    cpu_6502.reset();
    systemClockCounter = 0;
}

pub fn clock() bool
{

    ppu_2c02.clock();

    apu_2A02.clock();

    if(systemClockCounter % 3 == 0)
    {
        const state: u3 = (@as(u3, @intFromBool(dmaTransfer)) << 2) | (@as(u3, @intFromBool(dmaDummy)) << 1) | @as(u3, @intCast(systemClockCounter % 2));
        
        switch (state) 
        {
            // no dma transfer, clock like normal
            0b000...0b011 => cpu_6502.clock(),
            // dma initiated, but not started
            0b111 => dmaDummy = false,
            // alternate between reading data ..
            0b100 => dmaData = read((@as(u16, dmaPage) << 8) | dmaAddr, false),
            // .. to writing data
            0b101 => 
            {
                ppu_2c02.poam[dmaAddr] = dmaData;
                dmaAddr = @addWithOverflow(dmaAddr, 1)[0];

                if(dmaAddr == 0)
                {
                    dmaTransfer = false;
                    dmaDummy = true;
                }
            },
            else => {},
        }
    }

    // var audioSampleReady: bool = false;
    // apu_2A02.audioTime += apu_2A02.timePerNesClock;

    // if(apu_2A02.audioTime >= apu_2A02.timePerSystemSample)
    // {
    //     apu_2A02.audioTime -= apu_2A02.timePerSystemSample;
    //     apu_2A02.audioSample = apu_2A02.getOutputSample();
    //     if(apu_2A02.bufferInd < 511)
    //     {
    //         apu_2A02.audioBuffer[apu_2A02.bufferInd] = apu_2A02.audioSample;
    //         apu_2A02.bufferInd += 1;
    //     }
    //     else apu_2A02.bufferInd = 0;

    //     audioSampleReady = true;
    // }

    systemClockCounter += 1;

    return true;
}


pub const ram16k = struct 
{
    startOffset: u16 = 0,
    data: [2048]u8 = [_]u8{0} ** 2048,

    /// read from memory onto bus
    pub fn read(self: *ram16k, addr: u16) u8
    {
        if(addr < self.startOffset or addr > 0x1FFF) return 0;
        return self.data[addr & 0x07ff];
    }

    /// write from bus onto memory
    pub fn write(self: *ram16k, addr: u16, dat: u8) void
    {

        if(addr < self.startOffset or addr > 0x1FFF) return;
        self.data[addr & 0x07ff] = dat;
    }
};

pub const controller = struct 
{
    pub const a: u8 =      7;
    pub const b: u8 =      6;
    pub const start: u8 =  5;
    pub const select: u8 = 4;
    pub const up: u8 =     3;
    pub const down: u8 =   2;
    pub const left: u8 =   1;
    pub const right: u8 =  0;

    pub var data: [2]u8 = .{0,0};
    pub var state: [2]u8 = .{0,0};

    pub fn read(addr: u16) u8
    {
        const dat: u8 =  @intFromBool(data[addr & 1] & 0x80 > 0);
        data[addr & 1]  <<= 1;
        return dat;

    }

    pub fn write(addr: u16) void
    {
        data[addr & 1] = state[addr & 1];
    }

    pub fn update() void
    {
        state[0] = 0;
        state[0] |= @as(u8, @intFromBool(rl.isKeyDown(rl.KeyboardKey.up          ))) << up;
        state[0] |= @as(u8, @intFromBool(rl.isKeyDown(rl.KeyboardKey.down        ))) << down;
        state[0] |= @as(u8, @intFromBool(rl.isKeyDown(rl.KeyboardKey.left        ))) << left;
        state[0] |= @as(u8, @intFromBool(rl.isKeyDown(rl.KeyboardKey.right       ))) << right;
        state[0] |= @as(u8, @intFromBool(rl.isKeyDown(rl.KeyboardKey.comma       ))) << a;
        state[0] |= @as(u8, @intFromBool(rl.isKeyDown(rl.KeyboardKey.period      ))) << b;
        state[0] |= @as(u8, @intFromBool(rl.isKeyDown(rl.KeyboardKey.enter       ))) << select;
        state[0] |= @as(u8, @intFromBool(rl.isKeyDown(rl.KeyboardKey.right_shift ))) << start;

        state[1] = 0;
        state[1] |= @as(u8, @intFromBool(rl.isKeyDown(rl.KeyboardKey.w ))) << up;
        state[1] |= @as(u8, @intFromBool(rl.isKeyDown(rl.KeyboardKey.s ))) << down;
        state[1] |= @as(u8, @intFromBool(rl.isKeyDown(rl.KeyboardKey.a ))) << left;
        state[1] |= @as(u8, @intFromBool(rl.isKeyDown(rl.KeyboardKey.d ))) << right;
        state[1] |= @as(u8, @intFromBool(rl.isKeyDown(rl.KeyboardKey.c ))) << a;
        state[1] |= @as(u8, @intFromBool(rl.isKeyDown(rl.KeyboardKey.v ))) << b;
        state[1] |= @as(u8, @intFromBool(rl.isKeyDown(rl.KeyboardKey.q ))) << select;
        state[1] |= @as(u8, @intFromBool(rl.isKeyDown(rl.KeyboardKey.e ))) << start;
    }
};