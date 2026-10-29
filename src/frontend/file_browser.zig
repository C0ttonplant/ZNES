//! "Open ROM" dialog: lists folders and .nes files, double click (or Enter)
//! opens, Backspace goes up a folder, Escape cancels.

const FileBrowser = @This();

const std = @import("std");
const rl = @import("raylib");
const ui = @import("ui.zig");

gpa: std.mem.Allocator,
io: std.Io,
/// absolute path of the folder being shown, owned
dir: []u8 = &.{},
entries: std.ArrayList(Entry) = .empty,
selected: ?usize = null,
/// first visible row
scroll: usize = 0,
last_click_time: f64 = 0,
last_click_index: ?usize = null,
error_text: ?[:0]const u8 = null,

const Entry = struct {
    name: [:0]u8,
    is_dir: bool,
};

pub const Result = union(enum) {
    none,
    cancel,
    /// absolute path, owned by the caller
    open: []u8,
};

pub fn init(gpa: std.mem.Allocator, io: std.Io) FileBrowser {
    return .{ .gpa = gpa, .io = io };
}

pub fn deinit(self: *FileBrowser) void {
    self.clearEntries();
    self.entries.deinit(self.gpa);
    self.gpa.free(self.dir);
}

/// show `dir` (absolute)
pub fn open(self: *FileBrowser, dir: []const u8) void {
    const copy = self.gpa.dupe(u8, dir) catch return;
    self.gpa.free(self.dir);
    self.dir = copy;
    self.refresh();
}

fn clearEntries(self: *FileBrowser) void {
    for (self.entries.items) |e| self.gpa.free(e.name);
    self.entries.clearRetainingCapacity();
}

fn refresh(self: *FileBrowser) void {
    self.clearEntries();
    self.selected = null;
    self.scroll = 0;
    self.error_text = null;

    var dir = std.Io.Dir.cwd().openDir(self.io, self.dir, .{ .iterate = true }) catch {
        self.error_text = "Can't open this folder";
        return;
    };
    defer dir.close(self.io);

    var it = dir.iterate();
    while (it.next(self.io) catch null) |entry| {
        if (entry.name.len == 0 or entry.name[0] == '.') continue;
        const is_dir = entry.kind == .directory;
        if (!is_dir and !std.ascii.eqlIgnoreCase(std.fs.path.extension(entry.name), ".nes")) continue;

        const name = self.gpa.dupeSentinel(u8, entry.name, 0) catch continue;
        self.entries.append(self.gpa, .{ .name = name, .is_dir = is_dir }) catch self.gpa.free(name);
    }

    std.mem.sort(Entry, self.entries.items, {}, struct {
        fn lessThan(_: void, a: Entry, b: Entry) bool {
            if (a.is_dir != b.is_dir) return a.is_dir;
            return std.ascii.lessThanIgnoreCase(a.name, b.name);
        }
    }.lessThan);
}

fn goUp(self: *FileBrowser) void {
    const parent = std.fs.path.dirname(self.dir) orelse return;
    const copy = self.gpa.dupe(u8, parent) catch return;
    self.gpa.free(self.dir);
    self.dir = copy;
    self.refresh();
}

/// open the folder or return the file at `index`
fn activate(self: *FileBrowser, index: usize) Result {
    const entry = self.entries.items[index];
    const path = std.fs.path.join(self.gpa, &.{ self.dir, entry.name }) catch return .none;
    if (!entry.is_dir) return .{ .open = path };

    self.gpa.free(self.dir);
    self.dir = path;
    self.refresh();
    return .none;
}

pub fn draw(self: *FileBrowser) Result {
    ui.shadeScreen();
    const area = ui.dialog("Open ROM", 640, 520);

    // current folder
    ui.drawTextRow(ui.fitLeft(self.dir, area.width), area.x, area.y, ui.line_height, ui.theme.text_dim);

    const button_h = ui.line_height + 4;
    const list = rl.Rectangle.init(area.x, area.y + ui.line_height + 4, area.width, area.height - ui.line_height - button_h - 16);
    rl.drawRectangleRec(list, ui.theme.background);
    rl.drawRectangleLinesEx(list, 1, ui.theme.border);

    const row_h: f32 = ui.line_height;
    const visible: usize = @intFromFloat(@max(1, @floor((list.height - 4) / row_h)));

    // keyboard
    const count = self.entries.items.len;
    if (rl.isKeyPressedRepeat(.down) or rl.isKeyPressed(.down)) {
        self.selected = if (self.selected) |s| @min(s + 1, count -| 1) else 0;
    }
    if (rl.isKeyPressedRepeat(.up) or rl.isKeyPressed(.up)) {
        self.selected = if (self.selected) |s| s -| 1 else 0;
    }
    if (rl.isKeyPressed(.backspace)) self.goUp();
    if (rl.isKeyPressed(.escape)) return .cancel;
    if ((rl.isKeyPressed(.enter) or rl.isKeyPressed(.kp_enter)) and self.selected != null and count > 0) {
        return self.activate(self.selected.?);
    }

    // keep the selection visible, mouse wheel scrolls
    if (self.selected) |s| {
        if (s < self.scroll) self.scroll = s;
        if (s >= self.scroll + visible) self.scroll = s + 1 - visible;
    }
    if (ui.hovered(list)) {
        const wheel = rl.getMouseWheelMove();
        if (wheel > 0) self.scroll -|= 3;
        if (wheel < 0) self.scroll += 3;
    }
    self.scroll = @min(self.scroll, count -| visible);

    if (self.error_text) |e| ui.drawTextRow(e, list.x + ui.padding, list.y + 2, row_h, ui.theme.danger);
    if (count == 0 and self.error_text == null) {
        ui.drawTextRow("No .nes files here", list.x + ui.padding, list.y + 2, row_h, ui.theme.text_dim);
    }

    var result: Result = .none;
    for (self.scroll..@min(count, self.scroll + visible)) |i| {
        const entry = self.entries.items[i];
        const row = rl.Rectangle.init(list.x + 2, list.y + 2 + @as(f32, @floatFromInt(i - self.scroll)) * row_h, list.width - 4, row_h);

        if (self.selected == i) {
            rl.drawRectangleRec(row, ui.theme.pressed);
        } else if (ui.hovered(row)) {
            rl.drawRectangleRec(row, ui.theme.button);
        }
        const label = if (entry.is_dir) ui.fmt("{s}/", .{entry.name}) else entry.name;
        ui.drawTextRow(label, row.x + ui.padding, row.y, row_h, if (entry.is_dir) ui.theme.accent else ui.theme.text);

        if (ui.clicked(row)) {
            // second click on the same row soon after = double click
            const now = rl.getTime();
            if (self.last_click_index == i and now - self.last_click_time < 0.4) {
                result = self.activate(i);
                self.last_click_index = null;
                // `entries` may have been replaced by opening a folder
                break;
            }
            self.selected = i;
            self.last_click_index = i;
            self.last_click_time = now;
        }
    }
    if (result != .none) return result;

    // buttons
    const by = area.y + area.height - button_h;
    if (ui.button(.init(area.x, by, 90, button_h), "Up", .{ .enabled = std.fs.path.dirname(self.dir) != null })) {
        self.goUp();
    }
    if (ui.button(.init(area.x + area.width - 220, by, 105, button_h), "Cancel", .{})) return .cancel;
    const can_open = self.selected != null and count > 0;
    if (ui.button(.init(area.x + area.width - 105, by, 105, button_h), "Open", .{ .enabled = can_open })) {
        return self.activate(self.selected.?);
    }
    return .none;
}
