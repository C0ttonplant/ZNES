//! Keyboard to controller mapping.

const rl = @import("raylib");
const Controller = @import("../controller.zig");

pub fn poll(controllers: *[2]Controller) void {
    controllers[0].buttons = .{
        .up = rl.isKeyDown(.up),
        .down = rl.isKeyDown(.down),
        .left = rl.isKeyDown(.left),
        .right = rl.isKeyDown(.right),
        .a = rl.isKeyDown(.comma),
        .b = rl.isKeyDown(.period),
        .select = rl.isKeyDown(.enter),
        .start = rl.isKeyDown(.right_shift),
    };

    controllers[1].buttons = .{
        .up = rl.isKeyDown(.w),
        .down = rl.isKeyDown(.s),
        .left = rl.isKeyDown(.a),
        .right = rl.isKeyDown(.d),
        .a = rl.isKeyDown(.c),
        .b = rl.isKeyDown(.v),
        .select = rl.isKeyDown(.q),
        .start = rl.isKeyDown(.e),
    };
}
