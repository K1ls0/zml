const std = @import("std");
const fmt = std.fmt;
const element = @import("element.zig");

const PrintOptions = struct {
    depth: usize = 0,
};
pub fn printContent(p: *const element.ContentPart, w: anytype, options: PrintOptions) @TypeOf(w).Error!void {
    switch (p.*) {
        .comment => |s| try fmt.format(w, "<!-- \"{s}\" -->\n", .{s}),
        .txt => |s| try fmt.format(w, "{s}\n", .{s}),
        .elem => |*t| try printTag(t, w, options),
    }
}

pub fn printTag(tag: *const element.Element, w: anytype, options: PrintOptions) @TypeOf(w).Error!void {
    try fmt.format(w, "<{s}", .{tag.tag});
    {
        var it = tag.attrs.constIterator(0);
        while (it.next()) |item| {
            try fmt.format(w, " {s}=\"{s}\"", .{ item.name, item.value });
        }
    }
    try w.writeAll(">");
    if (tag.children.len > 0) {
        try w.writeAll("\n");
        var it = tag.children.constIterator(0);
        while (it.next()) |content| {
            for (0..options.depth + 1) |_| try w.writeAll("\t");
            try printContent(content, w, .{ .depth = options.depth + 1 });
        }
        for (0..options.depth) |_| try w.writeAll("\t");
    }
    try fmt.format(w, "</{s}>\n", .{tag.tag});
}
