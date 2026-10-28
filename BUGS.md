# Known bugs

Collected while restructuring the code base. Nothing in this list has been
fixed yet unless it is in the "Fixed by the restructure" section at the bottom.
The restructure kept emulation output identical (checked frame-by-frame with
`znes-headless` on 7 ROMs), apart from the NROM ROM-write fix listed at the
bottom, so every open bug below still behaves exactly as it did before. Some
are marked in the code with a `BUG:` comment.

Paths point at where the code lives after the restructure.

To check a fix only changes what you expect, record frame hashes before and
after and diff them:

    zig build -Doptimize=ReleaseSafe
    ./zig-out/bin/znes-headless smb.nes 1500 0 60:10,66:00,200:01 2> before.txt
    # ... change code, rebuild ...
    ./zig-out/bin/znes-headless smb.nes 1500 0 60:10,66:00,200:01 2> after.txt
    diff before.txt after.txt

## PPU (`src/ppu/`)

- [ ] **Reading $2002 does not clear the vblank flag.** `Ppu.cpuRead` only
      resets the write toggle. Games that poll $2002 for vblank see it stuck on.
- [ ] **Attribute address truncates for the bottom half of the screen.** In
      `Background.fetch`, `(v.coarse_y >> 2) << 3` is evaluated as a `u5`, so for
      coarse Y >= 16 bit 5 is lost and the wrong attribute row is read
      (e.g. row 20 reads $23C8 instead of $23E8). Cast to `u16` before shifting.
- [ ] **Sprite-0 hit left-clip check uses `or` instead of `and`.** In
      `Ppu.checkSpriteZeroHit`: hits in x 0..7 must be suppressed when *either*
      left-column bit is off, i.e. `!(show_bg_left and show_sprites_left)`.
      Also the hit range allows x = 255/256, real hardware stops at x = 254.
- [ ] **Left 8 pixel clipping is never applied** (`Mask.show_bg_left`,
      `Mask.show_sprites_left` are ignored when rendering).
- [ ] **$2007 read: palette check is `> 0x3F00`, should be `>= 0x3F00`.** Reading
      $3F00 itself returns the stale buffer. Palette reads should also refill the
      buffer with the nametable byte "underneath".
- [ ] **$2006 first write doesn't mask to 6 bits.** `t` gets the full byte in the
      high half, bit 14 is not cleared.
- [ ] **$2004 (OAMDATA) write doesn't increment the OAM address.**
- [ ] **OAM DMA ignores OAMADDR**, it always starts writing at OAM index 0
      (`Nes.stepDma`).
- [ ] **Enabling NMI in $2000 while vblank is already set doesn't fire an NMI.**
- [ ] **Single-screen / four-screen mirroring not supported.** `Mirroring.single_lo`,
      `single_hi` drop writes and read 0; the iNES four-screen bit is ignored.
- [ ] **Palette colours 0x00 and 0x01 are swapped** in `ppu/palette.zig`
      (0x00 should be 84,84,84 and 0x01 should be 0,30,116).
- [ ] **Pre-render vertical scroll copy uses dots 289-304, real range is 280-304.**
- [ ] **Odd-frame dot skip is emulated on scanline 0 dot 0** instead of skipping
      dot 340 of the pre-render line (close, but timing-sensitive tests notice).
- [ ] **Sprite overflow flag** is set as a simple "9th sprite found"; the real
      hardware evaluation bug isn't emulated. The `spriteCount < 9` / else branch
      in sprite evaluation was dead code.
- [ ] **$2002 low 5 bits** come from the read buffer instead of the real PPU open
      bus latch. No PPU open bus decay.
- [ ] **$2002 read / vblank race** (reading on the exact dot vblank is set
      should suppress the NMI) not emulated.
- [ ] **Mapper `scanline` hook** is called at dot 260 when rendering is on. MMC3
      actually clocks off PPU A12 rises; fine for now, revisit when adding MMC3.

## CPU (`src/cpu/`)

- [ ] **Reset state is wrong.** Should be SP = $FD and I = 1 (P = $24); currently
      SP = $FF and I = 0. `nestest.nes` logs will differ on line 1.
- [ ] **NMI/IRQ are taken immediately mid-instruction.** `Nes.clock` calls
      `cpu.nmi()` as soon as the PPU raises it, which pushes PC/P right away and
      overwrites the remaining cycle count of the current instruction. Interrupts
      should be polled at the end of an instruction (with the CLI/SEI/PLP one
      instruction delay, and BRK/NMI hijacking).
- [ ] **Nothing raises IRQ** (no APU frame IRQ, no DMC, no mapper IRQ).
- [ ] **RMW illegal opcodes read memory twice.** `DCP`, `RLA`, `RRA` call two
      operations, each of which does `fetch()`, so there's an extra bus read
      (side effects on $2002/$2007/$4016).
- [ ] **Whole instruction executes on its first cycle.** All bus accesses of an
      instruction happen at once, so mid-instruction timing (e.g. $2002 polling,
      DMA alignment) is off. Long-term: cycle-stepped CPU.
- [ ] `toBCD` is an unimplemented stub (the 2A03 has no decimal mode, so the
      `TODO: add decimal mode` notes on ADC/SBC can probably just be deleted).

## Bus / input (`src/bus.zig`, `src/controller.zig`)

- [ ] **$4017 writes go to controller 2 instead of the APU frame counter.**
- [ ] **Controller strobe is wrong.** Any write to $4016 latches only pad 1;
      pad 2 only latches on a $4017 write. The strobe bit (bit 0) is ignored, so
      the latch doesn't keep reloading while strobe is high.
- [ ] **Controller reads return 0 after 8 bits** (should return 1), and the
      upper bits should be open bus (usually $40).
- [ ] **No open bus.** Unmapped reads return 0.
- [ ] **No PRG-RAM at $6000-$7FFF.**
- [ ] `Nes.reset` doesn't reset PPU or APU state.

## Cartridge / mappers (`src/cart/`)

- [ ] **Trainer skip seeks to $200 instead of $210** (16 byte header + 512 byte
      trainer) in `ines.zig`.
- [ ] **NES 2.0 ROM sizes read the wrong header byte.** Uses byte 8 instead of
      byte 9, the wrong bit masks, and stores the result in a `u8`. Should be
      `prg = (byte9 & 0x0F) << 8 | byte4`, `chr = (byte9 & 0xF0) << 4 | byte5`.
      The NES 2.0 mapper high bits / submapper (byte 8) are ignored too.
- [ ] **CHR-RAM carts fail to load.** With 0 CHR banks the loader still tries to
      read 8 KB of CHR from the file (`EndOfStream`). For NES 2.0 files it
      allocates 0 bytes of CHR-RAM instead.
- [ ] **Old iNES headers with garbage in bytes 7-15** (e.g. "DiskDude!",
      `Golf.nes`) give a wrong mapper number. Ignore byte 7 when bytes 12-15
      aren't zero.
- [ ] **PAL / TV system flags ignored.**
- [ ] **Only mapper 0 is implemented.** `tetris.nes` and `nes86.nes` fail with
      `UnsupportedMapper`. `all_instrs.nes` and `official_only.nes` (mapper 1,
      CHR-RAM) fail earlier with `EndOfStream` because of the CHR-RAM bug above.

## APU (`src/apu/`)

- [ ] **$4003 write clobbers the low timer byte**: uses `reload & 0xFF00`
      instead of `reload & 0x00FF`.
- [ ] Only the pulse 1 duty/timer exists: no envelope, sweep, length counter,
      pulse 2, triangle, noise, DMC, $4015 status read, or frame IRQ.
- [ ] The frame counter's quarter/half frame signals are computed but unused.
- [ ] The sample ring buffer drops a sample every time it wraps (index 511
      resets without writing).
- [ ] **Audio output is disabled.** `frontend/audio.zig` runs the emulator from
      the raylib audio thread (data race with the main loop) and never fills
      the output buffer. Needs a design: e.g. run emulation on the main thread
      and push samples into a lock-free ring buffer that the callback drains,
      or use `updateAudioStream` from the main loop.

## Frontend (`src/main.zig`, `src/frontend/`)

- [ ] Emulation is paced by `setTargetFPS(60)`; the NES runs at ~60.0988 Hz.

## Fixed by the restructure

These fell out of rewriting the code around them:

- [x] **NROM let the CPU write into PRG ROM**, and for 16 KB carts the write
      mask was inverted (`0x7FFF` into a 16 KB buffer), an out-of-bounds write.
      ROM writes are now ignored. This is the one visible output change:
      AccuracyCoin's "ROM is not writable" test (`STA $8003 / LDA $8003`) now
      reads back the ROM byte.
- [x] **Unknown mapper numbers crashed** in `@enumFromInt` before the
      "invalid mapper" error could be returned. Now `error.UnsupportedMapper`.
- [x] **Vertically flipped 8x16 sprites panicked** (integer overflow in
      `7 - row`) in Debug / ReleaseSafe builds.
- [x] **The APU's `u32` clock counter overflowed** after ~13 minutes (panic in
      safe builds).
- [x] **First frame unloaded an uninitialised texture**, and a new texture was
      created every frame. The screen texture is now created once and updated.
- [x] **JAM called `std.process.exit` from inside the CPU.** The CPU now halts
      and the frontend reports it and exits.
- [x] **The mapper scanline hook only ran on the (unused) audio path**, it now
      runs every frame.
- [x] **`dumpVirtualMemory` / `drawCurrentInstruction` didn't compile**
      (private fields, 2D indexing of the opcode table, removed `std.fs` API).
      Rewritten in `frontend/debug.zig`.
- [x] PPU had two copies of the per-dot logic (`clock` and an unused `clocks`).
