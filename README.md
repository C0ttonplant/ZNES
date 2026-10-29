## ZNES
***
NES emulator in Zig, using raylib for the window.

    zig build run -Doptimize=ReleaseFast              # open ROMs from the File menu
    zig build run -Doptimize=ReleaseFast -- rom.nes   # or start with one
    zig build headless -- rom.nes 600                 # no window, prints a hash per frame

ROMs can also be dragged onto the window. The menu bar has File (open,
recent, close), Emulation (pause, frame advance, reset, power cycle, speed),
Video (scaling, window size, fullscreen, FPS), Audio (mute, volume), Input
(rebind keys for both players, gamepads) and Help.

Default controls: arrows, `,` = A, `.` = B, Enter = Select, Right Shift =
Start (player 2: WASD, C, V, Q, E). Gamepads work too. Shortcuts: Ctrl+O
open, P pause, F frame advance, F5 reset, Shift+F5 power cycle, F1-F4 load
state (Shift+F1-F4 save), M mute, F11 fullscreen. In fullscreen the menu bar
and mouse cursor hide, move the mouse to the top edge to get the menus back.
Esc leaves fullscreen.

Settings are saved in `~/.config/znes/settings.ini`, save states in
`~/.local/share/znes/states/`.

Mappers: 0 (NROM), 1 (MMC1), 2 (UxROM), 3 (CNROM), 7 (AxROM).

Known bugs and test ROM results are tracked in [BUGS.md](BUGS.md).

### Layout

```
src/
  main.zig            creates the window, runs the app
  headless.zig        windowless runner for regression checks
  nes.zig             the console: owns every part, runs a CPU cycle per bus access, DMA
  bus.zig             CPU address space, work RAM, open bus, OAM DMA state
  savestate.zig       save / load the whole console state
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
  frontend/           raylib-only code
    app.zig           the window: owns the console, menus, dialogs, pacing
    menu_bar.zig      immediate mode menu bar
    ui.zig            theme, text helpers, buttons, dialog boxes
    file_browser.zig  "Open ROM" dialog
    bindings_dialog.zig  key rebinding dialog
    settings.zig      settings file (bindings, recent ROMs, video/audio options)
    input.zig         keyboard / gamepad -> controllers
    audio.zig         feeds the APU's samples to raylib
    debug.zig         memory dump, CPU state overlay
```

Only `main.zig` and `frontend/` use raylib, the emulator core doesn't.
