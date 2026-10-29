//! Small immediate mode UI toolkit on top of raylib: theme, text helpers,
//! buttons and dialog panels. Widgets draw and handle input in the same call.
//!
//! Mouse clicks are consumed by the first widget that takes them each frame
//! (`beginFrame` resets this), so overlapping widgets don't both react.

const std = @import("std");
const rl = @import("raylib");

pub const font_size = 20;
pub const line_height = 28;
pub const padding = 10;

pub const theme = struct {
    pub const background = rl.Color.init(24, 24, 28, 255);
    pub const bar = rl.Color.init(38, 38, 44, 255);
    pub const panel = rl.Color.init(46, 46, 54, 255);
    pub const border = rl.Color.init(80, 80, 92, 255);
    pub const hover = rl.Color.init(62, 92, 160, 255);
    pub const pressed = rl.Color.init(48, 72, 128, 255);
    pub const button = rl.Color.init(64, 64, 74, 255);
    pub const text = rl.Color.init(230, 230, 235, 255);
    pub const text_dim = rl.Color.init(140, 140, 150, 255);
    pub const accent = rl.Color.init(110, 160, 255, 255);
    pub const danger = rl.Color.init(230, 90, 90, 255);
    pub const shade = rl.Color.init(0, 0, 0, 150);
};

var click_consumed = false;

pub fn beginFrame() void {
    click_consumed = false;
}

pub fn mousePosition() rl.Vector2 {
    return rl.getMousePosition();
}

pub fn hovered(rect: rl.Rectangle) bool {
    return rl.checkCollisionPointRec(mousePosition(), rect);
}

/// true if the left button was pressed inside `rect` this frame and nothing
/// else has taken the click yet
pub fn clicked(rect: rl.Rectangle) bool {
    if (click_consumed or !rl.isMouseButtonPressed(.left) or !hovered(rect)) return false;
    click_consumed = true;
    return true;
}

/// true if the left button was pressed anywhere and nothing has taken it,
/// takes it
pub fn clickedAnywhere() bool {
    if (click_consumed or !rl.isMouseButtonPressed(.left)) return false;
    click_consumed = true;
    return true;
}

pub fn consumeClick() void {
    click_consumed = true;
}

// text

var fmt_buffers: [8][512]u8 = undefined;
var fmt_index: usize = 0;

/// format into one of a few rotating buffers, good until a few calls later
/// (long enough to draw it)
pub fn fmt(comptime format: []const u8, args: anytype) [:0]const u8 {
    fmt_index = (fmt_index + 1) % fmt_buffers.len;
    return std.fmt.bufPrintSentinel(&fmt_buffers[fmt_index], format, args, 0) catch "...";
}

pub fn textWidth(text: [:0]const u8) f32 {
    return @floatFromInt(rl.measureText(text, font_size));
}

pub fn drawText(text: [:0]const u8, x: f32, y: f32, color: rl.Color) void {
    rl.drawText(text, @intFromFloat(x), @intFromFloat(y), font_size, color);
}

/// text vertically centred in a row of height `h` starting at `y`
pub fn drawTextRow(text: [:0]const u8, x: f32, y: f32, h: f32, color: rl.Color) void {
    drawText(text, x, y + (h - font_size) / 2, color);
}

pub fn drawTextCentered(text: [:0]const u8, rect: rl.Rectangle, color: rl.Color) void {
    drawText(text, rect.x + (rect.width - textWidth(text)) / 2, rect.y + (rect.height - font_size) / 2, color);
}

/// draw `text` word wrapped to `width`, '\n' starts a new line. Returns
/// the height used.
pub fn drawWrapped(text: []const u8, x: f32, y: f32, width: f32, color: rl.Color) f32 {
    var line_y = y;
    var paragraphs = std.mem.splitScalar(u8, text, '\n');
    while (paragraphs.next()) |paragraph| {
        var line: [256]u8 = undefined;
        var len: usize = 0;
        var words = std.mem.tokenizeScalar(u8, paragraph, ' ');
        while (words.next()) |word| {
            // try adding the word, start a new line if it doesn't fit
            const sep: usize = @intFromBool(len > 0);
            if (len + sep + word.len + 1 > line.len) break;
            var candidate = line;
            if (sep == 1) candidate[len] = ' ';
            @memcpy(candidate[len + sep ..][0..word.len], word);
            candidate[len + sep + word.len] = 0;

            if (len > 0 and textWidth(candidate[0 .. len + sep + word.len :0]) > width) {
                line[len] = 0;
                drawText(line[0..len :0], x, line_y, color);
                line_y += font_size + 4;
                @memcpy(line[0..word.len], word);
                len = word.len;
            } else {
                line = candidate;
                len += sep + word.len;
            }
        }
        line[len] = 0;
        drawText(line[0..len :0], x, line_y, color);
        line_y += font_size + 4;
    }
    return line_y - y;
}

/// `text` shortened from the left with "..." until it fits `width`
pub fn fitLeft(text: []const u8, width: f32) [:0]const u8 {
    var start: usize = 0;
    while (start < text.len) : (start += 1) {
        const candidate = if (start == 0) fmt("{s}", .{text}) else fmt("...{s}", .{text[start..]});
        if (textWidth(candidate) <= width) return candidate;
    }
    return "...";
}

// widgets

pub const ButtonOptions = struct {
    enabled: bool = true,
    /// drawn highlighted, e.g. the selected option
    active: bool = false,
};

pub fn button(rect: rl.Rectangle, text: [:0]const u8, options: ButtonOptions) bool {
    const hot = options.enabled and hovered(rect);
    const color = if (options.active) theme.pressed else if (hot) theme.hover else theme.button;
    rl.drawRectangleRec(rect, color);
    rl.drawRectangleLinesEx(rect, 1, theme.border);
    drawTextCentered(text, rect, if (options.enabled) theme.text else theme.text_dim);
    return options.enabled and clicked(rect);
}

/// darken everything drawn so far, for modal dialogs
pub fn shadeScreen() void {
    rl.drawRectangle(0, 0, rl.getScreenWidth(), rl.getScreenHeight(), theme.shade);
}

/// a dialog box of `width` x `height` centred on the screen, returns the
/// area inside it below the title bar
pub fn dialog(title: [:0]const u8, width: f32, height: f32) rl.Rectangle {
    const screen_w: f32 = @floatFromInt(rl.getScreenWidth());
    const screen_h: f32 = @floatFromInt(rl.getScreenHeight());
    const w = @min(width, screen_w - 2 * padding);
    const h = @min(height, screen_h - 2 * padding);
    const rect = rl.Rectangle.init(@round((screen_w - w) / 2), @round((screen_h - h) / 2), w, h);

    rl.drawRectangleRec(rect, theme.panel);
    rl.drawRectangleLinesEx(rect, 1, theme.border);
    const title_bar = rl.Rectangle.init(rect.x, rect.y, rect.width, line_height + 4);
    rl.drawRectangleRec(title_bar, theme.bar);
    drawTextRow(title, rect.x + padding, rect.y, title_bar.height, theme.text);

    return rl.Rectangle.init(
        rect.x + padding,
        rect.y + title_bar.height + padding,
        rect.width - 2 * padding,
        rect.height - title_bar.height - 2 * padding,
    );
}
