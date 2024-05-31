const std = @import("std");
const log = std.log.scoped(.parse_state_ident);
const mem = std.mem;

const ParseState = @import("parse_state.zig").ParseState;

// TODO
pub fn parseIdent(parse_state: *ParseState, reader: anytype) !?[]const u8 {
    var s = std.ArrayListUnmanaged(u8){};
    defer s.deinit(parse_state.alloc);

    while_blk: while (true) {
        const cc = try parse_state.peek(reader) orelse break;
        switch (cc) {
            'a'...'z', 'A'...'Z', '0'...'9', '-', '.', '_' => {
                //_ = try parse_state.pop(reader);
                _ = try parse_state.next(reader);
                try s.append(parse_state.alloc, cc);
            },
            else => break :while_blk,
        }
    }

    if (s.items.len == 0) {
        return null;
    } else {
        return try s.toOwnedSlice(parse_state.alloc);
    }
}

test "ident.simple.1" {
    const testing = std.testing;
    const expectEqualDeep = testing.expectEqualDeep;
    const expect = testing.expect;

    const data = "0923-aseweb.abeJ_>";
    var stream = std.io.fixedBufferStream(data);
    const r = stream.reader();

    var pstate = ParseState{ .alloc = std.testing.allocator };
    defer pstate.deinit();
    const res0 = try parseIdent(&pstate, r) orelse unreachable;
    defer std.testing.allocator.free(res0);
    try expectEqualDeep(res0, "0923-aseweb.abeJ_");
    try expect((try pstate.next(r)).? == '>');
}

test "ident.simple.2" {
    const testing = std.testing;
    const expectEqualDeep = testing.expectEqualDeep;
    const expect = testing.expect;

    const data = "0923-aseweb.abeJ_ ";
    var stream = std.io.fixedBufferStream(data);
    const r = stream.reader();

    var pstate = ParseState{ .alloc = std.testing.allocator };
    defer pstate.deinit();
    const res0 = try parseIdent(&pstate, r) orelse unreachable;
    defer std.testing.allocator.free(res0);
    try expectEqualDeep(res0, "0923-aseweb.abeJ_");
    try expect((try pstate.next(r)).? == ' ');
}
