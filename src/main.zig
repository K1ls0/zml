const std = @import("std");
const mem = std.mem;
const log = std.log;
const zml = @import("zml");

const xmlconf_fname = "./xml.xml";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
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

    var doc = try parseDocument(alloc, filename);
    defer doc.deinit();

    log.info("prolog: {?any}", .{doc.prolog});
    if (doc.prolog) |p| {
        std.debug.print("Prolog version='{s}' encoding='{s}'\n", .{ p.version, p.encoding });
    }
    {
        const stdout = std.io.getStdOut();
        defer stdout.close();
        var buffered_writer = std.io.bufferedWriter(stdout.writer());
        const w = buffered_writer.writer();
        _ = w; // autofix

        for (doc.content.items[0].elem.children.items) |*item| {
            switch (item.*) {
                .elem => |*e| {
                    std.debug.print("tag: {s}\n", .{e.tag});
                },
                .txt => |txt| {
                    std.debug.print("text: {s}\n", .{if (txt.len > 10) txt[0..] else txt});
                },
                .comment => |cmt| {
                    std.debug.print("comment: {s}\n", .{if (cmt.len > 10) cmt[0..] else cmt});
                },
            }
            //try zml.debug.printContent(item, w, .{});
        }
        try buffered_writer.flush();
    }

    //var state = zml.ParseState{};
    //zml.parseValue();
}

fn parseDocument(alloc: mem.Allocator, fname: []const u8) !zml.Document {
    const file = try std.fs.cwd().openFile(
        fname,
        .{ .mode = .read_only },
    );
    var state = zml.ParseState.init(alloc);
    defer state.deinit();

    var reader = std.io.bufferedReader(file.reader());
    const r = reader.reader();

    const doc = try zml.parseDocument(&state, r);
    //try state.consumeWhiteSpaces(r, .any);
    return doc;
}
