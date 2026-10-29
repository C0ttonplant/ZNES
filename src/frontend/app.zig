//! The emulator window: menu bar, game screen and dialogs.
//!
//! `frame` is called once per displayed frame. It handles shortcuts and
//! dropped files, runs as many NES frames as real time asks for, then draws
//! everything. UI widgets handle their own input while drawing.

const App = @This();

const std = @import("std");
const rl = @import("raylib");

const Nes = @import("../nes.zig");
const Ppu = @import("../ppu/ppu.zig");
const Cartridge = @import("../cart/cartridge.zig");
const ines = @import("../cart/ines.zig");
const ui = @import("ui.zig");
const MenuBar = @import("menu_bar.zig");
const FileBrowser = @import("file_browser.zig");
const BindingsDialog = @import("bindings_dialog.zig");
const Settings = @import("settings.zig");
const input = @import("input.zig");
const audio = @import("audio.zig");
const savestate = @import("../savestate.zig");

/// save state slots, F1-F4 load and Shift+F1-F4 save
const state_slots = 4;
/// hide the mouse cursor in fullscreen after this long without movement
const cursor_hide_delay = 2.0;

/// NTSC frame rate, a bit over 60 Hz
const nes_frame_time = 1.0 / 60.0988;
/// don't try to catch up more than this many frames after a stall
const max_frames_per_update = 3;

gpa: std.mem.Allocator,
io: std.Io,
settings: Settings,

nes: ?*Nes = null,
/// absolute path of the loaded ROM, owned
rom_path: ?[]u8 = null,
/// identifies the loaded game, save state file names include it
rom_hash: u64 = 0,
screen: rl.Texture2D,
audio_ok: bool = false,

paused: bool = false,
speed: Speed = .normal,
frame_time_owed: f64 = 0,
fullscreen: bool = false,
quit: bool = false,
last_mouse_activity: f64 = 0,
last_mouse_position: rl.Vector2 = .{ .x = 0, .y = 0 },
cursor_hidden: bool = false,

menu: MenuBar.State = .{},
modal: Modal = .none,
browser: FileBrowser,
bindings_dialog: BindingsDialog = .{},
message_title: [:0]const u8 = "",
message_buf: [512]u8 = undefined,
message: [:0]const u8 = "",
toast_buf: [128]u8 = undefined,
toast: [:0]const u8 = "",
toast_until: f64 = 0,

const Modal = enum { none, open_rom, bindings, controls, about, message };

const Speed = enum {
    quarter,
    half,
    normal,
    double,
    quadruple,

    fn factor(self: Speed) f64 {
        return switch (self) {
            .quarter => 0.25,
            .half => 0.5,
            .normal => 1,
            .double => 2,
            .quadruple => 4,
        };
    }

    fn label(self: Speed) [:0]const u8 {
        return switch (self) {
            .quarter => "25%",
            .half => "50%",
            .normal => "100%",
            .double => "200%",
            .quadruple => "400%",
        };
    }
};

/// needs the window to exist
pub fn init(gpa: std.mem.Allocator, io: std.Io, environ: *const std.process.Environ.Map) !App {
    var self: App = .{
        .gpa = gpa,
        .io = io,
        .settings = .load(gpa, io, environ),
        .screen = try loadScreenTexture(),
        .browser = .init(gpa, io),
    };

    self.audio_ok = if (audio.init()) true else |_| false;
    self.applyVolume();
    return self;
}

pub fn deinit(self: *App) void {
    self.settings.save(self.gpa, self.io);
    self.closeRom();
    audio.deinit();
    rl.unloadTexture(self.screen);
    self.browser.deinit();
    self.settings.deinit(self.gpa);
}

/// texture the framebuffer gets copied into every frame
fn loadScreenTexture() !rl.Texture2D {
    const image = rl.genImageColor(Ppu.width, Ppu.height, .black);
    defer rl.unloadImage(image);
    return rl.loadTextureFromImage(image);
}

// actions

pub fn loadRom(self: *App, path: []const u8) void {
    const abs_path = std.fs.path.resolveAlloc(self.gpa, &.{ rl.getWorkingDirectory(), path }) catch return;

    const data = std.Io.Dir.cwd().readFileAlloc(self.io, abs_path, self.gpa, .limited(16 * 1024 * 1024)) catch |err| {
        self.showMessage("Couldn't open ROM", "{s}\n\n{t}", .{ abs_path, err });
        self.gpa.free(abs_path);
        return;
    };
    defer self.gpa.free(data);

    const cart = Cartridge.fromBytes(self.gpa, data) catch |err| {
        switch (err) {
            error.UnsupportedMapper => self.showMessage(
                "Unsupported game",
                "{s}\n\nuses mapper {d}, which isn't supported yet.\nSupported: 0 (NROM), 1 (MMC1), 2 (UxROM), 3 (CNROM), 7 (AxROM).",
                .{ std.fs.path.basename(abs_path), ines.mapperIdFromHeader(data) orelse 0 },
            ),
            error.InvalidRom => self.showMessage("Not a ROM", "{s}\n\nisn't an iNES (.nes) file.", .{abs_path}),
            else => self.showMessage("Couldn't load ROM", "{s}\n\n{t}", .{ abs_path, err }),
        }
        self.gpa.free(abs_path);
        return;
    };

    const nes = self.gpa.create(Nes) catch {
        var c = cart;
        c.deinit(self.gpa);
        self.gpa.free(abs_path);
        return;
    };
    nes.init(cart);

    self.closeRom();
    self.nes = nes;
    self.rom_path = abs_path;
    self.rom_hash = savestate.romHash(&nes.cart.rom);
    self.paused = false;
    self.frame_time_owed = 0;

    self.settings.addRecent(self.gpa, abs_path);
    if (std.fs.path.dirname(abs_path)) |dir| self.settings.setLastDir(self.gpa, dir);
    self.settings.save(self.gpa, self.io);

    const name = std.fs.path.basename(abs_path);
    rl.setWindowTitle(ui.fmt("ZNES - {s}", .{name}));
    self.showToast("Loaded {s}", .{name});
}

pub fn closeRom(self: *App) void {
    if (self.nes) |nes| {
        nes.deinit(self.gpa);
        self.gpa.destroy(nes);
        self.nes = null;
    }
    if (self.rom_path) |p| self.gpa.free(p);
    self.rom_path = null;
    rl.setWindowTitle("ZNES");
}

fn reset(self: *App) void {
    const nes = self.nes orelse return;
    nes.reset();
    self.paused = false;
    self.showToast("Reset", .{});
}

/// reload the ROM from disk, everything back to power on state
fn powerCycle(self: *App) void {
    const path = self.rom_path orelse return;
    const copy = self.gpa.dupe(u8, path) catch return;
    defer self.gpa.free(copy);
    self.loadRom(copy);
    self.showToast("Power cycle", .{});
}

fn togglePause(self: *App) void {
    if (self.nes == null) return;
    self.paused = !self.paused;
    self.showToast("{s}", .{if (self.paused) "Paused" else "Resumed"});
}

fn frameAdvance(self: *App) void {
    const nes = self.nes orelse return;
    if (!self.paused) return;
    nes.runFrame();
}

fn setSpeed(self: *App, speed: Speed) void {
    self.speed = speed;
    self.showToast("Speed {s}", .{speed.label()});
}

fn toggleMute(self: *App) void {
    self.settings.muted = !self.settings.muted;
    self.applyVolume();
    self.showToast("{s}", .{if (self.settings.muted) "Muted" else "Sound on"});
}

fn setVolume(self: *App, volume: f32) void {
    self.settings.volume = volume;
    self.settings.muted = false;
    self.applyVolume();
}

fn applyVolume(self: *App) void {
    audio.setVolume(if (self.settings.muted) 0 else self.settings.volume);
}

fn toggleFullscreen(self: *App) void {
    rl.toggleBorderlessWindowed();
    self.fullscreen = !self.fullscreen;
}

fn setWindowScale(self: *App, scale: i32) void {
    if (self.fullscreen) self.toggleFullscreen();
    rl.setWindowSize(Ppu.width * scale, Ppu.height * scale + MenuBar.height);
}

fn openRomDialog(self: *App) void {
    const start = self.settings.last_dir orelse rl.getWorkingDirectory();
    self.browser.open(start);
    self.modal = .open_rom;
}

fn showMessage(self: *App, title: [:0]const u8, comptime format: []const u8, args: anytype) void {
    self.message_title = title;
    self.message = std.fmt.bufPrintSentinel(&self.message_buf, format, args, 0) catch "(message too long)";
    self.modal = .message;
}

// save states

/// `<states dir>/<rom name>-<rom hash>.s<slot>`, the hash keeps games with
/// the same file name apart
fn statePath(self: *App, slot: usize) ?[]u8 {
    if (self.nes == null) return null;
    const dir = self.settings.states_dir orelse return null;
    const rom_name = std.fs.path.stem(self.rom_path orelse return null);
    const hash: u32 = @truncate(self.rom_hash);
    const file = std.fmt.allocPrint(self.gpa, "{s}-{x:0>8}.s{d}", .{ rom_name, hash, slot + 1 }) catch return null;
    defer self.gpa.free(file);
    return std.fs.path.join(self.gpa, &.{ dir, file }) catch null;
}

fn stateExists(self: *App, slot: usize) bool {
    const path = self.statePath(slot) orelse return false;
    defer self.gpa.free(path);
    std.Io.Dir.cwd().access(self.io, path, .{}) catch return false;
    return true;
}

fn saveState(self: *App, slot: usize) void {
    const nes = self.nes orelse return;
    const path = self.statePath(slot) orelse {
        self.showToast("No folder to save states in", .{});
        return;
    };
    defer self.gpa.free(path);

    const data = savestate.save(nes, self.gpa) catch {
        self.showToast("Out of memory", .{});
        return;
    };
    defer self.gpa.free(data);

    const cwd = std.Io.Dir.cwd();
    if (std.fs.path.dirname(path)) |dir| cwd.createDirPath(self.io, dir) catch {};
    cwd.writeFile(self.io, .{ .sub_path = path, .data = data }) catch |err| {
        self.showMessage("Couldn't save state", "{s}\n\n{t}", .{ path, err });
        return;
    };
    self.showToast("Saved state {d}", .{slot + 1});
}

fn loadState(self: *App, slot: usize) void {
    const nes = self.nes orelse return;
    const path = self.statePath(slot) orelse return;
    defer self.gpa.free(path);

    const data = std.Io.Dir.cwd().readFileAlloc(self.io, path, self.gpa, .limited(16 * 1024 * 1024)) catch {
        self.showToast("State {d} is empty", .{slot + 1});
        return;
    };
    defer self.gpa.free(data);

    savestate.load(nes, data) catch |err| {
        switch (err) {
            error.WrongVersion => self.showMessage("Can't load state", "State {d} was made by a different version of ZNES and can't be loaded.", .{slot + 1}),
            error.WrongGame => self.showMessage("Can't load state", "State {d} belongs to a different game.", .{slot + 1}),
            else => self.showMessage("Can't load state", "State {d} is damaged.", .{slot + 1}),
        }
        return;
    };
    self.frame_time_owed = 0;
    self.showToast("Loaded state {d}", .{slot + 1});
}

// mouse cursor

/// in fullscreen, hide the cursor while the mouse isn't being used
fn updateCursor(self: *App) void {
    const now = rl.getTime();
    const position = rl.getMousePosition();
    const moved = position.x != self.last_mouse_position.x or position.y != self.last_mouse_position.y;
    self.last_mouse_position = position;
    if (moved or rl.isMouseButtonDown(.left) or rl.isMouseButtonDown(.right)) {
        self.last_mouse_activity = now;
    }

    const idle = now - self.last_mouse_activity > cursor_hide_delay;
    const hide = self.fullscreen and idle and self.modal == .none and !MenuBar.isOpen(&self.menu);
    if (hide and !self.cursor_hidden) {
        rl.hideCursor();
        self.cursor_hidden = true;
    } else if (!hide and self.cursor_hidden) {
        rl.showCursor();
        self.cursor_hidden = false;
    }
}

fn showToast(self: *App, comptime format: []const u8, args: anytype) void {
    self.toast = std.fmt.bufPrintSentinel(&self.toast_buf, format, args, 0) catch "";
    self.toast_until = rl.getTime() + 2.0;
}

// per frame

pub fn frame(self: *App) void {
    ui.beginFrame();
    self.updateCursor();
    self.handleDroppedFiles();
    if (self.modal == .none) self.handleShortcuts();
    self.runEmulation();
    self.draw();
}

fn handleDroppedFiles(self: *App) void {
    if (!rl.isFileDropped()) return;
    const files = rl.loadDroppedFiles();
    defer rl.unloadDroppedFiles(files);
    if (files.count == 0) return;

    const path = std.mem.span(files.paths[0]);
    self.modal = .none;
    self.loadRom(path);
}

/// a shortcut key, unless it's also bound to a controller button
fn shortcut(self: *const App, key: rl.KeyboardKey) bool {
    if (!rl.isKeyPressed(key)) return false;
    for (self.settings.bindings.keys) |keys| {
        for (keys) |k| if (k == key) return false;
    }
    return true;
}

fn handleShortcuts(self: *App) void {
    const ctrl = rl.isKeyDown(.left_control) or rl.isKeyDown(.right_control);
    const shift = rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift);

    if (ctrl and rl.isKeyPressed(.o)) self.openRomDialog();
    if (self.shortcut(.p) or self.shortcut(.pause)) self.togglePause();
    if (self.shortcut(.f5)) {
        if (shift) self.powerCycle() else self.reset();
    }
    if (self.shortcut(.f)) self.frameAdvance();
    if (self.shortcut(.m)) self.toggleMute();
    if (self.shortcut(.f11)) self.toggleFullscreen();

    const slot_keys = [state_slots]rl.KeyboardKey{ .f1, .f2, .f3, .f4 };
    for (slot_keys, 0..) |key, slot| {
        if (self.shortcut(key)) {
            if (shift) self.saveState(slot) else self.loadState(slot);
        }
    }
    // Escape leaves fullscreen, unless it's closing a menu
    if (self.fullscreen and !MenuBar.isOpen(&self.menu) and rl.isKeyPressed(.escape)) self.toggleFullscreen();
}

/// in fullscreen the menu bar hides until the mouse goes to the top edge
fn menuBarVisible(self: *const App) bool {
    if (!self.fullscreen or MenuBar.isOpen(&self.menu)) return true;
    // dialogs block the bar anyway
    if (self.modal != .none) return false;
    return rl.getMousePosition().y < MenuBar.height;
}

fn runEmulation(self: *App) void {
    const nes = self.nes orelse {
        audio.update(null);
        return;
    };

    const running = !self.paused and self.modal == .none;
    if (running) {
        input.poll(&self.settings.bindings, &nes.bus.controllers);

        const dt: f64 = rl.getFrameTime();
        self.frame_time_owed = @min(self.frame_time_owed + dt * self.speed.factor(), nes_frame_time * max_frames_per_update);
        while (self.frame_time_owed >= nes_frame_time) : (self.frame_time_owed -= nes_frame_time) {
            nes.runFrame();
            if (nes.cpu.jammed) break;
        }
    } else {
        self.frame_time_owed = 0;
    }

    if (nes.cpu.jammed and !self.paused) {
        self.paused = true;
        self.showMessage("CPU stopped", "The game ran into an illegal JAM opcode (${x:0>2}) and the CPU halted.\n\nUse Emulation > Reset to try again.", .{nes.cpu.opcode});
    }

    audio.update(&nes.apu);
    rl.updateTexture(self.screen, &nes.ppu.framebuffer);
}

// drawing

fn draw(self: *App) void {
    rl.beginDrawing();
    defer rl.endDrawing();
    rl.clearBackground(ui.theme.background);

    const w: f32 = @floatFromInt(rl.getScreenWidth());
    const h: f32 = @floatFromInt(rl.getScreenHeight());
    // fullscreen uses the whole screen, the bar draws over the game when it shows
    const bar_space: f32 = if (self.fullscreen) 0 else MenuBar.height;
    const area = rl.Rectangle.init(0, bar_space, w, h - bar_space);

    if (self.nes != null) {
        self.drawGame(area);
    } else {
        drawSplash(area);
    }

    if (self.settings.show_fps) rl.drawFPS(@intFromFloat(area.x + 8), @intFromFloat(area.y + 8));
    if (rl.getTime() < self.toast_until) {
        const tw = ui.textWidth(self.toast);
        const box = rl.Rectangle.init(area.x + 8, area.y + area.height - ui.line_height - 8, tw + 2 * ui.padding, ui.line_height);
        rl.drawRectangleRec(box, ui.theme.shade);
        ui.drawTextRow(self.toast, box.x + ui.padding, box.y, box.height, ui.theme.text);
    }

    if (self.menuBarVisible()) self.drawMenuBar();
    self.drawModal();
}

fn drawGame(self: *App, area: rl.Rectangle) void {
    var scale = @min(area.width / Ppu.width, area.height / Ppu.height);
    if (self.settings.scale_mode == .integer) scale = @max(1, @floor(scale));

    const dest = rl.Rectangle.init(
        @round(area.x + (area.width - Ppu.width * scale) / 2),
        @round(area.y + (area.height - Ppu.height * scale) / 2),
        Ppu.width * scale,
        Ppu.height * scale,
    );
    rl.drawTexturePro(self.screen, .init(0, 0, Ppu.width, Ppu.height), dest, .init(0, 0), 0, .white);

    if (self.paused) {
        rl.drawRectangleRec(dest, ui.theme.shade);
        ui.drawTextCentered("PAUSED", dest, ui.theme.text);
    }
}

fn drawSplash(area: rl.Rectangle) void {
    const title = rl.Rectangle.init(area.x, area.y + area.height / 2 - 50, area.width, 40);
    rl.drawText("ZNES", @intFromFloat(title.x + (title.width - @as(f32, @floatFromInt(rl.measureText("ZNES", 40)))) / 2), @intFromFloat(title.y), 40, ui.theme.accent);
    ui.drawTextCentered("File > Open ROM (Ctrl+O), or drop a .nes file here", .init(area.x, title.y + 50, area.width, ui.line_height), ui.theme.text_dim);
}

fn drawMenuBar(self: *App) void {
    var bar = MenuBar.begin(&self.menu, self.modal == .none);
    const has_rom = self.nes != null;

    if (bar.menu("File")) {
        if (bar.item("Open ROM...", "Ctrl+O", .{})) self.openRomDialog();

        var any_recent = false;
        for (self.settings.recent) |r| {
            const path = r orelse continue;
            if (!any_recent) {
                bar.separator();
                bar.heading("Recent");
                any_recent = true;
            }
            if (bar.item(ui.fmt("{s}", .{std.fs.path.basename(path)}), null, .{})) {
                const copy = self.gpa.dupe(u8, path) catch continue;
                defer self.gpa.free(copy);
                self.loadRom(copy);
                break;
            }
        }

        bar.separator();
        if (bar.item("Close ROM", null, .{ .enabled = has_rom })) self.closeRom();
        if (bar.item("Exit", null, .{})) self.quit = true;
    }

    if (bar.menu("Emulation")) {
        if (bar.item("Pause", "P", .{ .enabled = has_rom, .checked = self.paused })) self.togglePause();
        if (bar.item("Frame Advance", "F", .{ .enabled = has_rom and self.paused })) self.frameAdvance();
        bar.separator();
        if (bar.item("Reset", "F5", .{ .enabled = has_rom })) self.reset();
        if (bar.item("Power Cycle", "Shift+F5", .{ .enabled = has_rom })) self.powerCycle();
        bar.separator();
        bar.heading("Speed");
        for (std.enums.values(Speed)) |speed| {
            if (bar.item(speed.label(), null, .{ .checked = self.speed == speed })) self.setSpeed(speed);
        }
    }

    if (bar.menu("State")) {
        bar.heading("Save");
        for (0..state_slots) |slot| {
            if (bar.item(ui.fmt("Slot {d}", .{slot + 1}), ui.fmt("Shift+F{d}", .{slot + 1}), .{ .enabled = has_rom })) {
                self.saveState(slot);
            }
        }
        bar.separator();
        bar.heading("Load");
        for (0..state_slots) |slot| {
            const exists = has_rom and self.stateExists(slot);
            const label = if (has_rom and !exists) ui.fmt("Slot {d} (empty)", .{slot + 1}) else ui.fmt("Slot {d}", .{slot + 1});
            if (bar.item(label, ui.fmt("F{d}", .{slot + 1}), .{ .enabled = exists })) self.loadState(slot);
        }
    }

    if (bar.menu("Video")) {
        bar.heading("Scaling");
        if (bar.item("Whole pixels", null, .{ .checked = self.settings.scale_mode == .integer })) self.settings.scale_mode = .integer;
        if (bar.item("Fill window", null, .{ .checked = self.settings.scale_mode == .fit })) self.settings.scale_mode = .fit;
        bar.separator();
        bar.heading("Window size");
        for (1..5) |n| {
            if (bar.item(ui.fmt("{d}x", .{n}), null, .{})) self.setWindowScale(@intCast(n));
        }
        bar.separator();
        if (bar.item("Fullscreen", "F11", .{ .checked = self.fullscreen })) self.toggleFullscreen();
        if (bar.item("Show FPS", null, .{ .checked = self.settings.show_fps })) self.settings.show_fps = !self.settings.show_fps;
    }

    if (bar.menu("Audio")) {
        if (bar.item("Mute", "M", .{ .checked = self.settings.muted, .enabled = self.audio_ok })) self.toggleMute();
        bar.separator();
        bar.heading("Volume");
        for ([_]f32{ 0.25, 0.5, 0.75, 1.0 }) |volume| {
            const checked = !self.settings.muted and @abs(self.settings.volume - volume) < 0.01;
            const label = ui.fmt("{d}%", .{@as(u32, @intFromFloat(volume * 100))});
            if (bar.item(label, null, .{ .checked = checked, .enabled = self.audio_ok })) self.setVolume(volume);
        }
        if (!self.audio_ok) bar.heading("(no audio device)");
    }

    if (bar.menu("Input")) {
        if (bar.item("Player 1 Controls...", null, .{})) self.openBindings(0);
        if (bar.item("Player 2 Controls...", null, .{})) self.openBindings(1);
        bar.separator();
        if (bar.item("Use Gamepads", null, .{ .checked = self.settings.bindings.use_gamepads })) {
            self.settings.bindings.use_gamepads = !self.settings.bindings.use_gamepads;
        }
    }

    if (bar.menu("Help")) {
        if (bar.item("Controls...", null, .{})) self.modal = .controls;
        if (bar.item("About ZNES...", null, .{})) self.modal = .about;
    }

    bar.end();
}

fn openBindings(self: *App, player: u1) void {
    self.bindings_dialog.open(player);
    self.modal = .bindings;
}

fn drawModal(self: *App) void {
    switch (self.modal) {
        .none => {},
        .open_rom => switch (self.browser.draw()) {
            .none => {},
            .cancel => self.modal = .none,
            .open => |path| {
                defer self.gpa.free(path);
                self.modal = .none;
                self.loadRom(path);
            },
        },
        .bindings => switch (self.bindings_dialog.draw(&self.settings.bindings)) {
            .none => {},
            .changed => self.settings.save(self.gpa, self.io),
            .done => {
                self.settings.save(self.gpa, self.io);
                self.modal = .none;
            },
        },
        .controls => self.drawControls(),
        .about => drawTextDialog(self, "About ZNES", "ZNES, a NES emulator written in Zig.\n\nMappers: 0, 1, 2, 3, 7\nAudio, cycle accurate CPU, PPU and APU.\n\nSettings: ~/.config/znes/settings.ini", 520, 280),
        .message => drawTextDialog(self, self.message_title, self.message, 560, 260),
    }
}

/// a dialog with some text and an OK button
fn drawTextDialog(self: *App, title: [:0]const u8, text: [:0]const u8, width: f32, height: f32) void {
    ui.shadeScreen();
    const area = ui.dialog(title, width, height);

    _ = ui.drawWrapped(text, area.x, area.y, area.width, ui.theme.text);

    const button_h = ui.line_height + 4;
    const ok = rl.Rectangle.init(area.x + area.width - 100, area.y + area.height - button_h, 100, button_h);
    if (ui.button(ok, "OK", .{}) or rl.isKeyPressed(.enter) or rl.isKeyPressed(.escape)) self.modal = .none;
}

fn drawControls(self: *App) void {
    ui.shadeScreen();
    const row_h: f32 = ui.line_height;
    const area = ui.dialog("Controls", 560, (input.button_count + 8) * row_h + 60);
    const col = [_]f32{ area.x, area.x + 140, area.x + 320 };

    var y = area.y;
    ui.drawTextRow("Button", col[0], y, row_h, ui.theme.text_dim);
    ui.drawTextRow("Player 1", col[1], y, row_h, ui.theme.text_dim);
    ui.drawTextRow("Player 2", col[2], y, row_h, ui.theme.text_dim);
    y += row_h;

    for (0..input.button_count) |i| {
        const button: input.Button = @fromBackingInt(@intCast(i));
        ui.drawTextRow(button.label(), col[0], y, row_h, ui.theme.text);
        for (0..2) |p| {
            var buf: [32]u8 = undefined;
            ui.drawTextRow(input.keyName(self.settings.bindings.keys[p][i], &buf), col[p + 1], y, row_h, ui.theme.text);
        }
        y += row_h;
    }

    y += row_h / 2;
    const shortcuts = [_][2][:0]const u8{
        .{ "Ctrl+O", "Open ROM" },
        .{ "P", "Pause" },
        .{ "F", "Frame advance (while paused)" },
        .{ "F5 / Shift+F5", "Reset / power cycle" },
        .{ "F1-F4", "Load state (Shift: save)" },
        .{ "M / F11", "Mute / fullscreen" },
    };
    for (shortcuts) |s| {
        ui.drawTextRow(s[0], col[0], y, row_h, ui.theme.accent);
        ui.drawTextRow(s[1], col[1] + 40, y, row_h, ui.theme.text);
        y += row_h;
    }

    const button_h = ui.line_height + 4;
    const ok = rl.Rectangle.init(area.x + area.width - 100, area.y + area.height - button_h, 100, button_h);
    if (ui.button(ok, "OK", .{}) or rl.isKeyPressed(.enter) or rl.isKeyPressed(.escape)) self.modal = .none;
}
