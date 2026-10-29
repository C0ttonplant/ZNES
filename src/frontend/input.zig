//! Keyboard and gamepad to controller mapping.

const std = @import("std");
const rl = @import("raylib");
const Controller = @import("../controller.zig");

/// the 8 NES buttons, in the order the binding dialog lists them
pub const Button = enum {
    up,
    down,
    left,
    right,
    a,
    b,
    select,
    start,

    pub fn label(self: Button) [:0]const u8 {
        return switch (self) {
            .up => "Up",
            .down => "Down",
            .left => "Left",
            .right => "Right",
            .a => "A",
            .b => "B",
            .select => "Select",
            .start => "Start",
        };
    }
};

pub const button_count = std.enums.values(Button).len;
pub const KeyMap = [button_count]rl.KeyboardKey;

pub const Bindings = struct {
    keys: [2]KeyMap = default_keys,
    /// gamepad N drives controller N
    use_gamepads: bool = true,

    pub const default_keys = [2]KeyMap{
        .{ .up, .down, .left, .right, .comma, .period, .enter, .right_shift },
        .{ .w, .s, .a, .d, .c, .v, .q, .e },
    };
};

pub fn poll(bindings: *const Bindings, controllers: *[2]Controller) void {
    for (controllers, 0..) |*pad, player| {
        var buttons: Controller.Buttons = .{};
        inline for (comptime std.enums.values(Button), 0..) |button, i| {
            const down = rl.isKeyDown(bindings.keys[player][i]) or
                (bindings.use_gamepads and gamepadDown(@intCast(player), button));
            @field(buttons, @tagName(button)) = down;
        }

        // a real d-pad can't press opposite directions, some games break if it does
        if (buttons.left and buttons.right) {
            buttons.left = false;
            buttons.right = false;
        }
        if (buttons.up and buttons.down) {
            buttons.up = false;
            buttons.down = false;
        }
        pad.buttons = buttons;
    }
}

fn gamepadDown(gamepad: i32, button: Button) bool {
    if (!rl.isGamepadAvailable(gamepad)) return false;

    const dead_zone = 0.5;
    const x = rl.getGamepadAxisMovement(gamepad, .left_x);
    const y = rl.getGamepadAxisMovement(gamepad, .left_y);
    return switch (button) {
        .up => rl.isGamepadButtonDown(gamepad, .left_face_up) or y < -dead_zone,
        .down => rl.isGamepadButtonDown(gamepad, .left_face_down) or y > dead_zone,
        .left => rl.isGamepadButtonDown(gamepad, .left_face_left) or x < -dead_zone,
        .right => rl.isGamepadButtonDown(gamepad, .left_face_right) or x > dead_zone,
        // same physical layout as an NES pad: A on the right, B below / left
        .a => rl.isGamepadButtonDown(gamepad, .right_face_right),
        .b => rl.isGamepadButtonDown(gamepad, .right_face_down) or rl.isGamepadButtonDown(gamepad, .right_face_left),
        .select => rl.isGamepadButtonDown(gamepad, .middle_left),
        .start => rl.isGamepadButtonDown(gamepad, .middle_right),
    };
}

/// display name of a key ("Right Shift", "Comma", "A")
pub fn keyName(key: rl.KeyboardKey, buffer: []u8) [:0]const u8 {
    const tag = std.enums.tagName(rl.KeyboardKey, key) orelse
        return std.fmt.bufPrintSentinel(buffer, "Key {d}", .{@backingInt(key)}, 0) catch "?";

    var len: usize = 0;
    var word_start = true;
    for (tag) |c| {
        if (len + 1 >= buffer.len) break;
        if (c == '_') {
            buffer[len] = ' ';
            word_start = true;
        } else {
            buffer[len] = if (word_start) std.ascii.toUpper(c) else c;
            word_start = false;
        }
        len += 1;
    }
    buffer[len] = 0;
    return buffer[0..len :0];
}

/// key name as stored in the settings file (the raylib enum name)
pub fn keyId(key: rl.KeyboardKey) ?[]const u8 {
    return std.enums.tagName(rl.KeyboardKey, key);
}

pub fn keyFromId(id: []const u8) ?rl.KeyboardKey {
    return std.meta.stringToEnum(rl.KeyboardKey, id);
}
