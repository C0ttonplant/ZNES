# Known bugs

Open issues first, fixed ones at the bottom.

## Test ROM status

| ROM | Result |
|---|---|
| `AccuracyCoin.nes` | 110 / 125 (was 74 before the bug fixing pass) |
| `all_instrs.nes` (blargg) | All 16 tests passed |
| `official_only.nes` (blargg) | All 15 tests passed |
| `nestest.nes` | all official opcode groups OK |

How to check (results print to stderr):

    zig build -Doptimize=ReleaseSafe
    # blargg tests print their result text
    ./zig-out/bin/znes-headless all_instrs.nes 3600
    # AccuracyCoin: hold Start ~30 frames to run everything, the summary
    # page appears once every test is done (~3000 frames). The 5th argument
    # saves the last frame as a PPM image.
    ./zig-out/bin/znes-headless AccuracyCoin.nes 3000 0 60:10,90:00 shot.ppm

To check a change doesn't alter anything else, record frame hashes before
and after and diff them:

    ./zig-out/bin/znes-headless smb.nes 1500 0 60:10,66:00,200:01 2> before.txt
    # ... change code, rebuild ...
    ./zig-out/bin/znes-headless smb.nes 1500 0 60:10,66:00,200:01 2> after.txt
    diff before.txt after.txt

## Open

### AccuracyCoin failures (15)

- [ ] **SHA / SHS / SHY / SHX** (page 10, 5 tests, codes 6/7): the test
      identifies which of the known unstable SH* behaviours the chip has, and
      how a DMA (RDY low) right before the write changes the stored value.
      `storeHigh` in `cpu/instructions.zig` only does the "stable" behaviour.
- [ ] **DMA edge cases** (page 13, 5 tests): APU register activation (3),
      DMC DMA bus conflicts (2), DMC DMA + OAM DMA (2), explicit DMA abort
      (2), implicit DMA abort (2). `Nes.runDma` handles the basic get / put /
      halt / alignment cycles (the other DMA tests pass), but not DMC DMAs
      overlapping OAM DMA exactly, aborted DMAs, or the APU registers being
      visible on the bus during DMA.
- [ ] **Frame counter IRQ** (code C): with a $4017 write on one of the two
      cycle alignments the IRQ flag is set 1 cycle early. The other alignment,
      4-step and 5-step mode are exact.
- [ ] **Delta modulation channel** (code L): when $4015 enables the DMC 2
      cycles before its timer runs out, the DMA should be delayed by exactly
      1 cycle (codes M and N cover the 1 and 0 cycle cases). The enable delay
      is a fixed 3 cycles in `Apu.setChannelsEnabled`.
- [ ] **Misaligned OAM behaviour** (code 5): misaligned OAMADDR rules 3 and 4
      happening on the same scanline. Rule 4 ("realign when a sprite's X is
      out of range") isn't modelled in `Sprites.evalStep`.
- [ ] **OAM corruption** (code 2): turning rendering off mid-scanline should
      copy OAM row 0 over another row. Not emulated.
- [ ] **RMW $2007 extra write**: an RMW instruction on $2007 should do an
      extra write. AccuracyCoin has since removed this test ("more research
      required"), so maybe leave it.

### PPU (`src/ppu/`)

- [ ] **Mapper `scanline` hook** is called at dot 260 when rendering is on.
      MMC3 actually counts PPU A12 rises; switch to that when adding MMC3.

### CPU (`src/cpu/`)

- [ ] The cycle-accurate rewrite models every bus access, but RDY (DMA)
      halting in the middle of the unstable SH* stores isn't modelled (see
      above).

### Cartridge / mappers (`src/cart/`)

- [ ] **Supported mappers: 0 (NROM), 1 (MMC1), 2 (UxROM), 3 (CNROM),
      7 (AxROM).** `nes86.nes` needs mapper 5 (MMC5). MMC3 (mapper 4) is the
      most common one still missing, it needs the A12 scanline counter above
      and uses the cartridge IRQ hook that's already wired up.
- [ ] MMC1 ignores the "consecutive write" rule (writes on back to back
      cycles, e.g. from RMW instructions, should be ignored).
- [ ] **PAL**: the region is read from the header (`Rom.region`) but the
      console always runs NTSC timing.
- [ ] Battery backed PRG RAM (`Rom.battery`) isn't saved to disk.
- [ ] NES 2.0 exponent-multiplier ROM sizes are rejected
      (`UnsupportedRomSize`).

### APU (`src/apu/`)

- [ ] Audio has only been checked by numbers (sample rate, levels, the APU
      timing tests), not by ear. Listen to a few games.

### Frontend (`src/main.zig`, `src/frontend/`)

- [ ] `tetris.nes` stays on its title screen even with Start held. It's
      polling $2002 normally, so it's not a hang; unverified whether it wants
      different input or something is wrong.

## Fixed

### Bug fixing pass (2026-10-28)

CPU
- [x] **Cycle accurate CPU.** Every bus access is a CPU cycle, and the PPU
      and APU run for that cycle before the access (`Nes.cpuRead` /
      `cpuWrite`). Instructions do their real access sequence, dummy reads
      included (implied, zero page indexed, (ind,x), stack ops, JSR order,
      RTS/RTI). Fixes instruction timing, dummy reads and JSR edge cases.
- [x] **Interrupts are polled per cycle** and taken based on the poll from
      the second to last cycle, so the CLI/SEI/PLP delay, RTI, branch
      polling quirks, NMI suppression and BRK / IRQ hijacking by NMI work.
- [x] **Reset state** (SP drops by 3 with reads, I set).
- [x] **RMW illegal opcodes no longer read memory twice** (DCP, RLA, RRA,
      ISC share helpers with ADC / CMP / ROL / ROR).
- [x] **LXA magic constant** is $FF (blargg), ANE stays $EE.
- [x] Dropped the decimal mode TODOs (the 2A03 has no decimal mode).

PPU
- [x] **Reading $2002 clears vblank**, and the vblank / NMI race is handled.
- [x] **Attribute address truncation** for the bottom half of the screen.
- [x] **Palette colours 0x00 / 0x01** swapped back.
- [x] **Left 8 pixel clipping**, and sprite 0 hit respects it and stops at x = 254.
- [x] **$2007 palette reads** are immediate and refill the buffer from the
      nametable underneath.
- [x] **$2006** masks the first write to 6 bits.
- [x] **$2004**: writes increment OAMADDR (by 4 and realign while
      rendering, without writing), reads return what sprite evaluation sees,
      attribute bytes drop bits 2-4.
- [x] **OAM DMA starts at OAMADDR** (it writes through $2004).
- [x] **NMI is an edge** on `vblank and enable_nmi`, so enabling NMI during
      vblank fires one.
- [x] **Single screen and four screen mirroring.**
- [x] **Sprite evaluation runs dot by dot** from OAMADDR, with misaligned
      OAMADDR handling, "first entry evaluated is sprite 0", the sprite
      overflow hardware bug, and OAMADDR held at 0 during dots 257-320.
- [x] **Pre-render vertical scroll copy** uses dots 280-304.
- [x] **Odd frame skip** happens on the pre-render line's last dot.
- [x] **PPU open bus latch with decay** (write-only registers and the low
      bits of $2002 read it).
- [x] **PPU reset flag**: writes to $2000/$2001/$2005/$2006 are ignored until
      the first pre-render line.
- [x] **CPU / PPU alignment**: 2 of the 3 dots in a CPU cycle happen before
      the CPU's access (`dots_before_access` in `nes.zig`), which makes every
      vblank / NMI timing test pass.

APU
- [x] **Full APU**: both pulses (envelope, sweep, length), triangle (linear
      counter), noise, DMC (with DMA and IRQ), frame counter (4 / 5 step,
      IRQ, $4017 write delay), $4015 status. The $4003 low byte bug is gone.
- [x] **Get / put cycles**: DMA, the $4015 frame IRQ clear and the
      controller strobe all follow the APU's get / put cycles.
- [x] **Audio output works.** Emulation stays on the main thread, the APU
      averages its output down to 44.1 kHz into a ring buffer, and
      `frontend/audio.zig` feeds raylib with `updateAudioStream`. No more
      emulator running on the audio thread.

Bus / input
- [x] **$4017 goes to the APU frame counter.**
- [x] **Controller strobe** goes to both pads, follows bit 0, reloads while
      high, and only updates on the get -> put transition.
- [x] **Controllers return 1 after 8 reads**, the upper bits are open bus.
- [x] **CPU open bus.**
- [x] **PRG RAM at $6000-$7FFF.**
- [x] **`Nes.reset` resets the PPU and APU too** (F5 in the frontend).

Cartridge / mappers
- [x] **Trainer** skips $210 bytes.
- [x] **NES 2.0** ROM sizes, mapper bits 8-11, submapper, RAM sizes, region.
- [x] **CHR RAM** carts load.
- [x] **"DiskDude!" headers** don't corrupt the mapper number.
- [x] **Mappers 1, 2, 3 and 7** added, plus an IRQ hook for mappers.

Frontend
- [x] **Frames are paced to 60.0988 Hz** by real time instead of `setTargetFPS(60)`.

### Fixed by the restructure

- [x] NROM let the CPU write into PRG ROM, and for 16 KB carts the write
      mask was inverted (out of bounds write).
- [x] Unknown mapper numbers crashed in `@enumFromInt`.
- [x] Vertically flipped 8x16 sprites panicked in Debug / ReleaseSafe builds.
- [x] The APU's `u32` clock counter overflowed after ~13 minutes.
- [x] The first frame unloaded an uninitialised texture, and a new texture
      was created every frame.
- [x] JAM called `std.process.exit` from inside the CPU.
- [x] The mapper scanline hook only ran on the (unused) audio path.
- [x] `dumpVirtualMemory` / `drawCurrentInstruction` didn't compile.
- [x] The PPU had two copies of the per-dot logic.
