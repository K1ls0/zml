const std = @import("std");
const mem = std.mem;

const ZmlError = @import("error.zig").ZmlError;
const pstate = @import("parse_state.zig");
const ParseState = pstate.ParseState;
const element = @import("element.zig");
const parseIdent = @import("ident.zig").parseIdent;

pub fn parseString(
    parse_state: *ParseState,
    reader: anytype,
) (ZmlError || @TypeOf(reader).Error)!?[]const u8 {
    const State = enum {
        normal,
        escaped,
    };
    const esc_map = std.StaticStringMap(u8).initComptime(.{
        .{ "lt", '<' },
        .{ "gt", '>' },
        .{ "amp", '&' },
        .{ "quot", '"' },
        .{ "apos", '\'' },
    });

    var state: State = .normal;
    if (!try parse_state.consumeChar(reader, '"')) return null;

    var esc_buf: [4]u8 = undefined;
    var esc_buf_len: usize = 0;

    var s = std.ArrayListUnmanaged(u8){};
    errdefer s.deinit(parse_state.alloc);

    while (true) {
        const cc = try parse_state.next(reader) orelse {
            return ZmlError.UnexpectedEndOfInput;
        };

        switch (state) {
            .normal => switch (cc) {
                '&' => {
                    state = .escaped;
                    esc_buf_len = 0;
                },
                '"' => break,
                '<', '>', '\'' => return ZmlError.UnexpectedChar,
                else => try s.append(parse_state.alloc, cc),
            },
            .escaped => switch (cc) {
                ';' => {
                    const esc = esc_buf[0..esc_buf_len];
                    const c = esc_map.get(esc) orelse return ZmlError.InvalidEscapeSequence;
                    try s.append(parse_state.alloc, c);
                    state = .normal;
                },
                'a'...'z', 'A'...'Z' => {
                    if (esc_buf_len > esc_buf.len) return ZmlError.InvalidEscapeSequence;
                    esc_buf[esc_buf_len] = std.ascii.toLower(cc);
                    esc_buf_len += 1;
                },
                else => return ZmlError.UnexpectedChar,
            },
        }
    }

    s.shrinkAndFree(parse_state.alloc, s.items.len);
    return s.items;
}

test "Parse string" {
    const testing = std.testing;
    //const expect = std.testing.expect;
    const expectEqualDeep = testing.expectEqualDeep;

    const data =
        \\"sdlkfj&quot;""&lt;&gt;&apos;&amp;"
    ;
    var stream = std.io.fixedBufferStream(data);
    const r = stream.reader();

    var state = ParseState{ .alloc = testing.allocator };
    defer state.deinit();

    const res0 = try parseString(&state, r) orelse unreachable;
    defer testing.allocator.free(res0);
    try expectEqualDeep(res0, "sdlkfj\"");

    const res1 = try parseString(&state, r) orelse unreachable;
    defer testing.allocator.free(res1);
    try expectEqualDeep(res1, "<>'&");
}
