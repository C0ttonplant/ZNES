//! Immediate mode menu bar.
//!
//!     var bar = MenuBar.begin(&state, enabled);
//!     if (bar.menu("File")) {
//!         if (bar.item("Open ROM...", "Ctrl+O", .{})) openRom();
//!         bar.separator();
//!         if (bar.item("Exit", null, .{})) quit();
//!     }
//!     bar.end();
//!
//! A dropdown's size is only known after its items ran, so the panel behind
//! them uses the size measured on the previous frame.

const MenuBar = @This();

const std = @import("std");
const rl = @import("raylib");
const ui = @import("ui.zig");

pub const height = ui.line_height + 4;
const max_menus = 16;
const item_height = ui.line_height;
const check_width = 22;
const shortcut_gap = 40;

/// kept between frames
pub const State = struct {
    open: ?usize = null,
    size: [max_menus]rl.Vector2 = @splat(.{ .x = 160, .y = 0 }),
};

state: *State,
enabled: bool,
/// x of the next menu title
x: f32 = 0,
index: usize = 0,
/// the dropdown being filled in, if the current menu is open
dropdown: ?Dropdown = null,

const Dropdown = struct {
    index: usize,
    x: f32,
    y: f32,
    /// widest item so far, becomes next frame's width
    width: f32,
};

pub const ItemOptions = struct {
    enabled: bool = true,
    /// draw a check mark (true) or an empty box (false), null for neither
    checked: ?bool = null,
};

pub fn begin(state: *State, enabled: bool) MenuBar {
    const w: f32 = @floatFromInt(rl.getScreenWidth());
    rl.drawRectangleRec(.init(0, 0, w, height), ui.theme.bar);
    rl.drawLine(0, height - 1, @intFromFloat(w), height - 1, ui.theme.border);

    if (!enabled) state.open = null;
    return .{ .state = state, .enabled = enabled, .x = ui.padding / 2 };
}

/// a top level menu, true if it's open and its items should be added
pub fn menu(self: *MenuBar, title: [:0]const u8) bool {
    self.finishDropdown();
    defer self.index += 1;

    const rect = rl.Rectangle.init(self.x, 0, ui.textWidth(title) + 2 * ui.padding, height);
    self.x += rect.width;

    const is_open = self.state.open == self.index;
    if (self.enabled and ui.hovered(rect)) {
        // while a menu is open, hovering another title switches to it
        if (self.state.open != null and !is_open) self.state.open = self.index;
        if (ui.clicked(rect)) self.state.open = if (is_open) null else self.index;
    }

    const now_open = self.state.open == self.index;
    if (now_open or (self.enabled and ui.hovered(rect))) {
        rl.drawRectangleRec(rect, if (now_open) ui.theme.hover else ui.theme.button);
    }
    ui.drawTextCentered(title, rect, ui.theme.text);

    if (!now_open) return false;

    // panel behind the items, sized from last frame
    const size = self.state.size[self.index];
    const panel = rl.Rectangle.init(rect.x, height, size.x, size.y + 4);
    rl.drawRectangleRec(.init(panel.x + 3, panel.y + 3, panel.width, panel.height), ui.theme.shade);
    rl.drawRectangleRec(panel, ui.theme.panel);
    rl.drawRectangleLinesEx(panel, 1, ui.theme.border);

    self.dropdown = .{ .index = self.index, .x = rect.x, .y = height + 2, .width = 120 };
    return true;
}

/// an entry in the open menu, true when clicked (the menu closes)
pub fn item(self: *MenuBar, label: [:0]const u8, shortcut: ?[:0]const u8, options: ItemOptions) bool {
    const dd = &(self.dropdown orelse return false);
    const width = self.state.size[dd.index].x;
    const rect = rl.Rectangle.init(dd.x + 2, dd.y, width - 4, item_height);
    dd.y += item_height;

    // measure for next frame
    var needed = check_width + ui.textWidth(label) + 2 * ui.padding;
    if (shortcut) |s| needed += shortcut_gap + ui.textWidth(s);
    dd.width = @max(dd.width, needed);

    const hot = options.enabled and ui.hovered(rect);
    if (hot) rl.drawRectangleRec(rect, ui.theme.hover);

    const text_color = if (options.enabled) ui.theme.text else ui.theme.text_dim;
    if (options.checked) |checked| {
        const box = rl.Rectangle.init(rect.x + ui.padding / 2, rect.y + (item_height - 12) / 2, 12, 12);
        rl.drawRectangleLinesEx(box, 1, text_color);
        if (checked) rl.drawRectangleRec(.init(box.x + 3, box.y + 3, 6, 6), text_color);
    }
    ui.drawTextRow(label, rect.x + check_width, rect.y, item_height, text_color);
    if (shortcut) |s| {
        ui.drawTextRow(s, rect.x + rect.width - ui.padding - ui.textWidth(s), rect.y, item_height, ui.theme.text_dim);
    }

    if (options.enabled and ui.clicked(rect)) {
        self.state.open = null;
        return true;
    }
    return false;
}

/// a dim, unclickable heading inside a menu
pub fn heading(self: *MenuBar, label: [:0]const u8) void {
    const dd = &(self.dropdown orelse return);
    dd.width = @max(dd.width, check_width + ui.textWidth(label) + 2 * ui.padding);
    ui.drawTextRow(label, dd.x + 2 + check_width, dd.y, item_height, ui.theme.text_dim);
    dd.y += item_height;
}

pub fn separator(self: *MenuBar) void {
    const dd = &(self.dropdown orelse return);
    const width = self.state.size[dd.index].x;
    const y: i32 = @intFromFloat(dd.y + 4);
    rl.drawLine(@intFromFloat(dd.x + 6), y, @intFromFloat(dd.x + width - 6), y, ui.theme.border);
    dd.y += 9;
}

pub fn end(self: *MenuBar) void {
    self.finishDropdown();

    if (self.state.open != null) {
        // clicking anywhere else, or Escape, closes the menu
        if (rl.isKeyPressed(.escape)) {
            self.state.open = null;
        } else if (ui.clickedAnywhere()) {
            self.state.open = null;
        }
    }
}

/// true while a menu is open (the app shouldn't react to clicks then)
pub fn isOpen(state: *const State) bool {
    return state.open != null;
}

fn finishDropdown(self: *MenuBar) void {
    const dd = self.dropdown orelse return;
    self.state.size[dd.index] = .{ .x = dd.width, .y = dd.y - (height + 2) };
    self.dropdown = null;
}
