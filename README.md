## ZNES
***
NES emulator in Zig, using raylib for the window.

    zig build run -- rom.nes          # defaults to AccuracyCoin.nes
    zig build headless -- rom.nes 600 # no window, prints a hash per frame

Known bugs are tracked in [BUGS.md](BUGS.md).

### Layout

```
src/
  main.zig            window, main loop
  headless.zig        windowless runner for regression checks
  nes.zig             the console: owns every part, steps them off the PPU dot clock
  bus.zig             CPU address space, work RAM, OAM DMA state
  controller.zig      joypad
  cpu/
    cpu.zig           registers, clock, interrupts, bus/stack helpers
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
    apu.zig
  cart/
    cartridge.zig     ROM + mapper, what the rest of the console talks to
    rom.zig           PRG / CHR memory and header info
    ines.zig          iNES / NES 2.0 parsing
    mapper.zig        mapper dispatch (tagged union), how to add a mapper
    mappers/
      nrom.zig        mapper 0
      template.zig    starting point for a new mapper
  frontend/           raylib-only code: input, audio, debug drawing
```

Only `main.zig` and `frontend/` use raylib, the emulator core doesn't.
