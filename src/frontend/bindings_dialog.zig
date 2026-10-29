//! "Configure Player N" dialog: click a button, then press the key for it.

const BindingsDialog = @This();

const rl = @import("raylib");
const ui = @import("ui.zig");
const input = @import("input.zig");

player: u1 = 0,
/// waiting for a key press for this button
listening: ?usize = null,

pub const Result = enum { none, done, changed };

pub fn open(self: *BindingsDialog, player: u1) void {
    self.* = .{ .player = player };
}

pub fn draw(self: *BindingsDialog, bindings: *input.Bindings) Result {
    ui.shadeScreen();
    const title = if (self.player == 0) "Player 1 Controls" else "Player 2 Controls";
    const button_h = ui.line_height + 4;
    const area = ui.dialog(title, 420, @as(f32, input.button_count) * (button_h + 4) + 3 * button_h + 40);
    const keys = &bindings.keys[self.player];

    var result: Result = .none;

    if (self.listening) |index| {
        // Escape cancels, any other key is taken
        const key = rl.getKeyPressed();
        if (key == .escape) {
            self.listening = null;
        } else if (key != .null) {
            keys[index] = key;
            self.listening = null;
            result = .changed;
        }
    } else if (rl.isKeyPressed(.escape) or rl.isKeyPressed(.enter)) {
        return .done;
    }

    var y = area.y;
    for (keys, 0..) |key, i| {
        const button: input.Button = @fromBackingInt(@intCast(i));
        ui.drawTextRow(button.label(), area.x, y, button_h, ui.theme.text);

        var name_buf: [32]u8 = undefined;
        const listening = self.listening == i;
        const text = if (listening) "press a key..." else input.keyName(key, &name_buf);
        const key_rect = rl.Rectangle.init(area.x + 120, y, area.width - 120, button_h);
        if (ui.button(key_rect, text, .{ .active = listening })) self.listening = @intCast(i);
        y += button_h + 4;
    }

    ui.drawTextRow("Esc cancels a key change", area.x, y, button_h, ui.theme.text_dim);
    y += button_h + 4;

    if (ui.button(.init(area.x, y, 140, button_h), "Defaults", .{})) {
        keys.* = input.Bindings.default_keys[self.player];
        self.listening = null;
        result = .changed;
    }
    if (ui.button(.init(area.x + area.width - 100, y, 100, button_h), "Done", .{})) return .done;
    return result;
}
