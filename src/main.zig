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
    const filename = blk: {
        var args = std.process.args();
        const exec_name = args.next() orelse unreachable;
        const filename = args.next() orelse {
            std.debug.print("Usage: {s} <filename>\n", .{exec_name});
            std.process.exit(1);
        };
        break :blk filename;
    };

    const xmlconf_file = try std.fs.cwd().openFile(filename, .{ .mode = .read_only });
    defer xmlconf_file.close();

    const file = try xmlconf_file.readToEndAlloc(alloc, std.math.maxInt(u64));
    defer alloc.free(file);

    std.debug.print("'{s}'", .{file});
    var state = zml.ParseState.init(alloc);
    defer state.deinit();

    const prolog, var elements = try parseDocument(alloc, filename);
    defer if (prolog) |p| p.deinit(alloc);
    defer {
        var it = elements.iterator(0);
        while (it.next()) |item| {
            item.deinit(alloc);
        }
        elements.deinit(alloc);
    }

    log.info("prolog: {?any}", .{prolog});
    if (prolog) |p| {
        std.debug.print("Prolog version='{s}' encoding='{s}'\n", .{ p.version, p.encoding });
    }
    {
        const stdout = std.io.getStdOut();
        defer stdout.close();
        var buffered_writer = std.io.bufferedWriter(stdout.writer());
        const w = buffered_writer.writer();

        var it = elements.iterator(0);
        while (it.next()) |item| {
            try zml.debug.printContent(item, w, .{});
        }
        try buffered_writer.flush();
    }

    //var state = zml.ParseState{};
    //zml.parseValue();
}

fn parseDocument(alloc: mem.Allocator, fname: []const u8) !struct {
    ?zml.XmlProlog,
    zml.Element.ContentList,
} {
    const file = try std.fs.cwd().openFile(
        fname,
        .{ .mode = .read_only },
    );
    var state = zml.ParseState.init(alloc);
    defer state.deinit();

    var reader = std.io.bufferedReader(file.reader());
    const r = reader.reader();

    try state.consumeWhiteSpaces(r, .any);

    const prolog = zml.parseXmlProlog(&state, r) catch |e| {
        log.err("Error occured at line {}, column {}", .{ state.line, state.col });
        return e;
    };
    errdefer if (prolog) |p| p.deinit(alloc);

    const content = zml.parseContent(&state, r) catch |e| {
        log.err("Error occured at line {}, column {}", .{ state.line, state.col });
        log.err("current char: {?c}", .{try state.peek(r)});
        return e;
    };

    //try state.consumeWhiteSpaces(r, .any);
    return .{
        prolog,
        content,
    };
}
