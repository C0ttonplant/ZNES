//! User settings, saved as `key = value` lines in
//! `$XDG_CONFIG_HOME/znes/settings.ini` (or `~/.config/znes/settings.ini`).
//! Unknown keys and bad values are ignored, so an old or hand edited file
//! never stops the emulator from starting.

const Settings = @This();

const std = @import("std");
const input = @import("input.zig");

pub const ScaleMode = enum { integer, fit };
pub const max_recent = 8;

bindings: input.Bindings = .{},
scale_mode: ScaleMode = .integer,
volume: f32 = 1.0,
muted: bool = false,
show_fps: bool = false,
/// most recent first, owned
recent: [max_recent]?[]u8 = @splat(null),
/// directory the ROM browser opens in, owned
last_dir: ?[]u8 = null,
/// where the settings are saved, owned, null if no config dir was found
path: ?[]u8 = null,
/// folder for save states, owned, null if no data dir was found
states_dir: ?[]u8 = null,

pub fn deinit(self: *Settings, gpa: std.mem.Allocator) void {
    for (self.recent) |r| if (r) |p| gpa.free(p);
    if (self.last_dir) |d| gpa.free(d);
    if (self.path) |p| gpa.free(p);
    if (self.states_dir) |d| gpa.free(d);
}

pub fn load(gpa: std.mem.Allocator, io: std.Io, environ: *const std.process.Environ.Map) Settings {
    var self: Settings = .{ .path = configPath(gpa, environ), .states_dir = statesDir(gpa, environ) };
    const path = self.path orelse return self;

    const data = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(64 * 1024)) catch return self;
    defer gpa.free(data);

    var recent_count: usize = 0;
    var lines = std.mem.tokenizeAny(u8, data, "\r\n");
    while (lines.next()) |line| {
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..eq], " \t");
        const value = std.mem.trim(u8, line[eq + 1 ..], " \t");

        if (std.mem.eql(u8, key, "recent")) {
            if (recent_count < max_recent) {
                self.recent[recent_count] = gpa.dupe(u8, value) catch continue;
                recent_count += 1;
            }
        } else if (std.mem.eql(u8, key, "last_dir")) {
            self.last_dir = gpa.dupe(u8, value) catch null;
        } else if (std.mem.eql(u8, key, "scale")) {
            self.scale_mode = std.meta.stringToEnum(ScaleMode, value) orelse self.scale_mode;
        } else if (std.mem.eql(u8, key, "volume")) {
            const v = std.fmt.parseFloat(f32, value) catch continue;
            self.volume = std.math.clamp(v, 0, 1);
        } else if (std.mem.eql(u8, key, "muted")) {
            self.muted = parseBool(value) orelse self.muted;
        } else if (std.mem.eql(u8, key, "show_fps")) {
            self.show_fps = parseBool(value) orelse self.show_fps;
        } else if (std.mem.eql(u8, key, "gamepads")) {
            self.bindings.use_gamepads = parseBool(value) orelse self.bindings.use_gamepads;
        } else if (parseBindingKey(key)) |binding| {
            if (input.keyFromId(value)) |k| self.bindings.keys[binding.player][binding.button] = k;
        }
    }
    return self;
}

pub fn save(self: *const Settings, gpa: std.mem.Allocator, io: std.Io) void {
    const path = self.path orelse return;
    self.write(gpa, io, path) catch |err| std.log.warn("couldn't save settings to {s}: {t}", .{ path, err });
}

fn write(self: *const Settings, gpa: std.mem.Allocator, io: std.Io, path: []const u8) !void {
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    const w = &out.writer;

    try w.print("scale = {t}\nvolume = {d:.2}\nmuted = {}\nshow_fps = {}\ngamepads = {}\n", .{
        self.scale_mode, self.volume, self.muted, self.show_fps, self.bindings.use_gamepads,
    });
    for (self.bindings.keys, 0..) |keys, player| {
        for (keys, 0..) |key, i| {
            const button: input.Button = @fromBackingInt(@intCast(i));
            if (input.keyId(key)) |id| try w.print("p{d}.{t} = {s}\n", .{ player + 1, button, id });
        }
    }
    if (self.last_dir) |d| try w.print("last_dir = {s}\n", .{d});
    for (self.recent) |r| if (r) |p| try w.print("recent = {s}\n", .{p});

    if (std.fs.path.dirname(path)) |dir| try std.Io.Dir.cwd().createDirPath(io, dir);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = out.written() });
}

/// move `path` to the top of the recent list
pub fn addRecent(self: *Settings, gpa: std.mem.Allocator, path: []const u8) void {
    const copy = gpa.dupe(u8, path) catch return;

    // drop an existing entry for the same file, else the oldest one
    var remove: usize = max_recent - 1;
    for (self.recent, 0..) |r, i| {
        if (r) |p| if (std.mem.eql(u8, p, path)) {
            remove = i;
            break;
        };
    }
    if (self.recent[remove]) |old| gpa.free(old);

    var i = remove;
    while (i > 0) : (i -= 1) self.recent[i] = self.recent[i - 1];
    self.recent[0] = copy;
}

pub fn setLastDir(self: *Settings, gpa: std.mem.Allocator, dir: []const u8) void {
    const copy = gpa.dupe(u8, dir) catch return;
    if (self.last_dir) |d| gpa.free(d);
    self.last_dir = copy;
}

/// `$XDG_DATA_HOME/znes/states` or `~/.local/share/znes/states`
fn statesDir(gpa: std.mem.Allocator, environ: *const std.process.Environ.Map) ?[]u8 {
    if (environ.get("XDG_DATA_HOME")) |dir| {
        if (dir.len > 0) return std.fs.path.join(gpa, &.{ dir, "znes", "states" }) catch null;
    }
    if (environ.get("HOME")) |home| {
        return std.fs.path.join(gpa, &.{ home, ".local", "share", "znes", "states" }) catch null;
    }
    if (environ.get("APPDATA")) |appdata| {
        return std.fs.path.join(gpa, &.{ appdata, "znes", "states" }) catch null;
    }
    return null;
}

fn configPath(gpa: std.mem.Allocator, environ: *const std.process.Environ.Map) ?[]u8 {
    if (environ.get("XDG_CONFIG_HOME")) |dir| {
        if (dir.len > 0) return std.fs.path.join(gpa, &.{ dir, "znes", "settings.ini" }) catch null;
    }
    if (environ.get("HOME")) |home| {
        return std.fs.path.join(gpa, &.{ home, ".config", "znes", "settings.ini" }) catch null;
    }
    if (environ.get("APPDATA")) |appdata| {
        return std.fs.path.join(gpa, &.{ appdata, "znes", "settings.ini" }) catch null;
    }
    return null;
}

fn parseBool(value: []const u8) ?bool {
    if (std.mem.eql(u8, value, "true")) return true;
    if (std.mem.eql(u8, value, "false")) return false;
    return null;
}

/// "p1.start" -> player 0, button index of start
fn parseBindingKey(key: []const u8) ?struct { player: usize, button: usize } {
    if (key.len < 4 or key[0] != 'p' or key[2] != '.') return null;
    const player: usize = switch (key[1]) {
        '1' => 0,
        '2' => 1,
        else => return null,
    };
    const button = std.meta.stringToEnum(input.Button, key[3..]) orelse return null;
    return .{ .player = player, .button = @backingInt(button) };
}
