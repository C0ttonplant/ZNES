## ZNES
***
NES emulator in Zig, using raylib for the window.

    zig build run -Doptimize=ReleaseFast -- rom.nes   # defaults to AccuracyCoin.nes
    zig build headless -- rom.nes 600                 # no window, prints a hash per frame

Controls: arrows, `,` = A, `.` = B, Enter = Select, Right Shift = Start
(player 2: WASD, C, V, Q, E). F5 resets.

Mappers: 0 (NROM), 1 (MMC1), 2 (UxROM), 3 (CNROM), 7 (AxROM).

Known bugs and test ROM results are tracked in [BUGS.md](BUGS.md).

### Layout

```
src/
  main.zig            window, main loop
  headless.zig        windowless runner for regression checks
  nes.zig             the console: owns every part, runs a CPU cycle per bus access, DMA
  bus.zig             CPU address space, work RAM, open bus, OAM DMA state
  controller.zig      joypad
  cpu/
    cpu.zig           registers, instruction / interrupt sequencing, bus/stack helpers
    opcodes.zig       the 256 entry opcode table
    addressing.zig    addressing modes
    instructions.zig  instructions (official + illegal)
  ppu/
    ppu.zig           registers, PPU address space, dot timing, pixel mixing
    background.zig    background fetches and shifters
    sprites.zig       OAM, sprite evaluation, sprite fetches and shifters
    registers.zig     PPUCTRL / PPUMASK / PPUSTATUS / loopy layouts
    palette.zig       NES colours
  apu/
    apu.zig           frame counter, registers, mixing, sample ring buffer
    pulse.zig         pulse channels (+ sweep)
    triangle.zig
    noise.zig
    dmc.zig           delta modulation channel (samples fetched by DMA)
    units.zig         envelope, length counter
  cart/
    cartridge.zig     ROM + mapper, what the rest of the console talks to
    rom.zig           PRG / CHR memory and header info
    ines.zig          iNES / NES 2.0 parsing
    mapper.zig        mapper dispatch (tagged union), how to add a mapper
    mappers/
      nrom.zig        mapper 0
      mmc1.zig        mapper 1
      uxrom.zig       mapper 2
      cnrom.zig       mapper 3
      axrom.zig       mapper 7
      template.zig    starting point for a new mapper
  frontend/           raylib-only code: input, audio, debug drawing
```

Only `main.zig` and `frontend/` use raylib, the emulator core doesn't.
