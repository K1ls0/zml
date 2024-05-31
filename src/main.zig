const std = @import("std");
const mem = std.mem;
const log = std.log;
const zml = @import("zml");

const xmlconf_fname = "./xml.xml";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = false }){};
    defer std.debug.assert(gpa.deinit() == .ok);

    const alloc = gpa.allocator();
    //const expect = std.testing.expect;
    const xmlconf_file = try std.fs.cwd().openFile(xmlconf_fname, .{ .mode = .read_only });
    defer xmlconf_file.close();

    const file = try xmlconf_file.readToEndAlloc(alloc, std.math.maxInt(u64));
    defer alloc.free(file);

    std.debug.print("'{s}'", .{file});
    var state = zml.ParseState.init(alloc);
    defer state.deinit();

    const prolog, var elements = try parseDocument(alloc, xmlconf_fname);
    defer if (prolog) |p| p.deinit(alloc);
    defer {
        for (elements.items) |*item| {
            item.deinit(alloc);
        }
        elements.deinit(alloc);
    }
    if (prolog) |p| {
        std.debug.print("Prolog version='{s}' encoding='{s}'\n", .{ p.version, p.encoding });
    }
    for (elements.items) |elem| {
        printTag(&elem, .{});
    }

    //var state = zml.ParseState{};
    //zml.parseValue();
}

fn parseDocument(alloc: mem.Allocator, fname: []const u8) !struct {
    ?zml.XmlProlog,
    std.ArrayListUnmanaged(zml.Element),
} {
    const file = try std.fs.cwd().openFile(
        fname,
        .{ .mode = .read_only },
    );
    var state = zml.ParseState.init(alloc);
    defer state.deinit();

    var reader = std.io.bufferedReader(file.reader());
    const r = reader.reader();

    const prolog = try zml.parse_state.parseXmlProlog(&state, r);
    errdefer if (prolog) |p| p.deinit(alloc);

    var elements = std.ArrayListUnmanaged(zml.Element){};
    errdefer {
        for (elements.items) |*item| {
            item.deinit(alloc);
        }
        elements.deinit(alloc);
    }

    while (try zml.parse_state.parseTag(&state, r)) |tag| {
        try elements.append(alloc, tag);
    }
    //try state.consumeWhiteSpaces(r, .any);
    return .{
        prolog,
        elements,
    };
}

const PrintTagOptions = struct {
    depth: usize = 0,
};
fn printTag(tag: *const zml.Element, options: PrintTagOptions) void {
    std.debug.print("<{s}", .{tag.tag});
    {
        var it = tag.attrs.constIterator(0);
        while (it.next()) |item| {
            std.debug.print(" '{s}'='{s}'", .{ item.name, item.value });
        }
    }
    std.debug.print(">", .{});
    if (tag.children.len > 0) {
        std.debug.print("\n", .{});
        var it = tag.children.constIterator(0);
        while (it.next()) |content| {
            for (0..options.depth + 1) |_| std.debug.print("\t", .{});
            switch (content.*) {
                .elem => |*elem| printTag(elem, .{ .depth = options.depth + 1 }),
                .txt => |txt| std.debug.print("text: [{s}]", .{txt}),
                .comment => unreachable,
            }
        }
        for (0..options.depth) |_| std.debug.print("\t", .{});
    }
    std.debug.print("</{s}>\n", .{tag.tag});
}
