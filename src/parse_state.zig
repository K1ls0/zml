const std = @import("std");
const log = std.log.scoped(.parse_state);
const mem = std.mem;
const ZmlError = @import("error.zig").ZmlError;
const spec = @import("xmlspec.zig");
const element = @import("element.zig");
const ident = @import("ident.zig");
const string = @import("string.zig");

pub const Element = element.Element;

pub const ErrorValue = union(enum) {
    none,
};

pub const ParseState = struct {
    const Self = @This();

    alloc: std.mem.Allocator,

    _peeked: ?u8 = null,
    _peeked2: ?u8 = null,
    consumed_count: usize = 0,
    line: usize = 1,
    col: usize = 1,

    occured_error: ErrorValue = .none,
    buf: std.ArrayListUnmanaged(u8) = .{},

    // This structure stores the stack of tag names, that are currently on hold, the
    // string will not be copied, it is just a pointer to the slice that was allocated
    // at the beginning of the tag, therefor the slice is expected to still be alive
    // when popped.
    _tag_stack: std.SegmentedList(element.Element, 16) = .{},

    //state: State = .normal,

    pub fn init(alloc: std.mem.Allocator) Self {
        return Self{
            .buf = .{},
            .alloc = alloc,
        };
    }
    pub fn deinit(self: *Self) void {
        self.buf.deinit(self.alloc);
        self._tag_stack.deinit(self.alloc);
    }

    pub fn consumeChar(self: *Self, reader: anytype, to_match: u8) (ZmlError || @TypeOf(reader).Error)!bool {
        const c = try self.peek(reader) orelse return false;
        const matches = c == to_match;
        if (matches) _ = try self.next(reader);
        return matches;
    }

    pub fn consumeWhiteSpaces(
        self: *Self,
        reader: anytype,
        atleast_one: enum { any, atleastone },
    ) (ZmlError || @TypeOf(reader).Error)!void {
        var c = try self.peek(reader) orelse switch (atleast_one) {
            .any => return,
            .atleastone => return ZmlError.UnexpectedEndOfInput,
        };

        while (spec.isXmlWhitespace(c)) {
            _ = try self.next(reader) orelse return;
            c = try self.peek(reader) orelse return;
        }
    }

    pub fn peek(self: *Self, reader: anytype) (ZmlError || @TypeOf(reader).Error)!?u8 {
        if (self._peeked) |c| return c;
        if (self._peeked2) |c| {
            self._peeked = c;
            self._peeked2 = null;
        }

        self._peeked = reader.readByte() catch |e| switch (e) {
            error.EndOfStream => return null,
            else => |ee| return ee,
        };

        return self._peeked;
    }

    pub fn peek2(self: *Self, reader: anytype) (ZmlError || @TypeOf(reader).Error)!?u8 {
        if (self._peeked2) |c| return c;
        if (self._peeked == null) {
            self._peeked = reader.readByte() catch |e| switch (e) {
                error.EndOfStream => return null,
                else => |ee| return ee,
            };
        }
        std.debug.assert(self._peeked != null);
        self._peeked2 = reader.readByte() catch |e| switch (e) {
            error.EndOfStream => return null,
            else => |ee| return ee,
        };

        return self._peeked2;
    }

    pub fn next(self: *Self, reader: anytype) (ZmlError || @TypeOf(reader).Error)!?u8 {
        const c = if (self._peeked) |c|
            c
        else
            try self.peek(reader) orelse return null;

        switch (c) {
            '\n' => {
                self.line += 1;
                self.col = 1;
            },
            else => self.col += 1,
        }

        self._peeked = self._peeked2;
        self._peeked2 = null;
        self.consumed_count += 1;
        return c;
    }

    pub inline fn extractBuffer(self: *Self) mem.Allocator.Error![]const u8 {
        return try self.buf.toOwnedSlice();
    }

    pub inline fn pushTag(self: *Self, tagname: []const u8) ZmlError!void {
        try self._tag_stack.append(self.alloc, tagname);
    }

    pub fn peekTag(self: *Self) ?[]const u8 {
        const count = self._tag_stack.count();
        if (count == 0) return null;
        return self._tag_stack.at(count - 1).*;
    }

    pub fn popTag(self: *Self) ?[]const u8 {
        return self._tag_stack.pop();
    }

    /// Expect one byte, also returning an error if the end of input is reached
    pub inline fn expectOne(self: *Self, reader: anytype) ZmlError!u8 {
        return try self.next(reader) orelse return ZmlError.UnexpectedEndOfInput;
    }
};

//pub const State = enum {
//    normal,
//    document,
//
//    tag_start,
//    tag_name_open_or_close_or_special,
//    tag_name,
//    tag_close,
//    tag_special_question,
//    tag_special_exclamation_mark,
//    tag_comment_dash1,
//    tag_comment_dash2,
//
//    tag_attr_key_or_end,
//    tag_attr_eq,
//    tag_attr_value,
//
//    string,
//};

pub fn parseTag(s: *ParseState, r: anytype) (ZmlError || @TypeOf(r).Error)!?element.Element {
    if ((try s.peek(r) orelse return null) != '<') return null;
    if ((try s.peek2(r) orelse return null) == '/') return null;
    if (!try s.consumeChar(r, '<')) return null;

    try s.consumeWhiteSpaces(r, .any);

    const tagname = try ident.parseIdent(s, r) orelse {
        return ZmlError.ExpectedIdentifier;
    };
    errdefer s.alloc.free(tagname);

    try s.consumeWhiteSpaces(r, .any);

    var attributes = Element.AttrList{};
    errdefer attributes.deinit(s.alloc);

    while_blk: while (true) {
        try s.consumeWhiteSpaces(r, .any);

        const attrname = try ident.parseIdent(s, r) orelse break :while_blk;
        errdefer s.alloc.free(attrname);

        try s.consumeWhiteSpaces(r, .any);
        const attrvalue = if (!try s.consumeChar(r, '=')) blk: {
            break :blk try s.alloc.dupe(u8, "true");
        } else blk: {
            try s.consumeWhiteSpaces(r, .any);
            break :blk try string.parseString(s, r) orelse return ZmlError.UnexpectedChar;
        };
        errdefer s.alloc.free(attrvalue);

        try attributes.append(s.alloc, .{
            .name = attrname,
            .value = attrvalue,
        });
    }

    if (try s.consumeChar(r, '/')) {
        if (!try s.consumeChar(r, '>')) return ZmlError.ExpectedEndOfTag;
        return Element{
            .tag = tagname,
            .attrs = attributes,
            .children = .{},
        };
    }

    if (!try s.consumeChar(r, '>')) return ZmlError.ExpectedEndOfTag;

    // parse children
    var content = Element.ContentList{};
    errdefer content.deinit(s.alloc);
    while_blk: while (true) {
        try s.consumeWhiteSpaces(r, .any);

        if (try parseText(s, r)) |txt| {
            try content.append(s.alloc, element.ContentPart{ .txt = txt });
            continue;
        }

        if (try parseTag(s, r)) |tag| {
            try content.append(s.alloc, element.ContentPart{ .elem = tag });
            continue;
        }

        break :while_blk;
    }

    try s.consumeWhiteSpaces(r, .any);

    if (!try s.consumeChar(r, '<')) return ZmlError.UnexpectedChar;
    if (!try s.consumeChar(r, '/')) return ZmlError.UnexpectedChar;

    try s.consumeWhiteSpaces(r, .any);

    const close_tagname = try ident.parseIdent(s, r) orelse return ZmlError.ExpectedIdentifier;
    if (!std.mem.eql(u8, tagname, close_tagname)) return ZmlError.UnmatchedTagName;

    try s.consumeWhiteSpaces(r, .any);

    if (!try s.consumeChar(r, '>')) return ZmlError.UnexpectedChar;

    return Element{
        .tag = tagname,
        .attrs = attributes,
        .children = content,
    };
}

pub fn parseText(
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

    var esc_buf: [4]u8 = undefined;
    var esc_buf_len: usize = 0;

    var s = std.ArrayListUnmanaged(u8){};
    defer s.deinit(parse_state.alloc);

    while_blk: while (true) {
        const cc = try parse_state.peek(reader) orelse break :while_blk;

        switch (state) {
            .normal => switch (cc) {
                '&' => {
                    state = .escaped;
                    esc_buf_len = 0;
                },
                '<' => break :while_blk,
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
        _ = try parse_state.next(reader);
    }

    const trimmed = std.mem.trim(u8, s.items, &.{ ' ', '\t', '\n', '\r' });
    if (trimmed.len == 0) return null;
    return try parse_state.alloc.dupe(u8, trimmed);
}

pub const XmlProlog = struct {
    version: []const u8,
    encoding: []const u8,

    pub fn deinit(self: @This(), allocator: mem.Allocator) void {
        allocator.free(self.version);
        allocator.free(self.encoding);
    }
};

pub fn parseXmlProlog(s: *ParseState, r: anytype) (ZmlError || @TypeOf(r).Error)!?XmlProlog {
    if ((try s.peek(r) orelse return null) != '<') return null;
    if ((try s.peek2(r) orelse return null) == '?') return null;
    if (!try s.consumeChar(r, '<')) return null;
    if (!try s.consumeChar(r, '?')) return null;

    try s.consumeWhiteSpaces(r, .any);

    var encoding: ?[]const u8 = null;
    var version: ?[]const u8 = null;

    while_blk: while (true) {
        try s.consumeWhiteSpaces(r, .any);

        const attrname = try ident.parseIdent(s, r) orelse break :while_blk;
        defer s.alloc.free(attrname);

        try s.consumeWhiteSpaces(r, .any);
        const attrvalue = if (!try s.consumeChar(r, '=')) blk: {
            break :blk try s.alloc.dupe(u8, "true");
        } else blk: {
            try s.consumeWhiteSpaces(r, .any);
            break :blk try string.parseString(s, r) orelse return ZmlError.UnexpectedChar;
        };
        errdefer s.alloc.free(attrvalue);

        if (std.ascii.eqlIgnoreCase(attrname, "version")) {
            version = attrvalue;
        } else if (std.ascii.eqlIgnoreCase(attrname, "encoding")) {
            encoding = encoding;
        } else return ZmlError.XmlPrologUnexpectedAttr;
    }

    if (encoding == null or version == null) {
        if (encoding) |str| s.alloc.free(str);
        if (version) |str| s.alloc.free(str);
        return ZmlError.XmlPrologEncodingVersionNotGiven;
    }

    try s.consumeWhiteSpaces(r, .any);
    if (!try s.consumeChar(r, '?')) return ZmlError.UnexpectedChar;
    if (!try s.consumeChar(r, '>')) return ZmlError.UnexpectedChar;

    return XmlProlog{
        .version = version orelse unreachable,
        .encoding = encoding orelse unreachable,
    };
}

test "parse_state.peek" {
    const expect = std.testing.expect;
    //{
    //    var file = try std.fs.cwd().openFile("./tst.xml");
    //    defer file.close();

    //    const creader = file.reader();
    //    creader.read();
    //}
    const data =
        \\<testtag> ll
        \\</testtag>
    ;
    var stream = std.io.fixedBufferStream(data);
    const r = stream.reader();

    var pstate = ParseState.init(std.testing.allocator);
    defer pstate.deinit();

    try expect((try pstate.peek(r)).? == '<');
    try expect((try pstate.peek(r)).? == '<');
    try expect((try pstate.next(r)).? == '<');
    try expect((try pstate.next(r)).? == 't');
    try expect((try pstate.peek(r)).? == 'e');
    try expect((try pstate.peek(r)).? == 'e');
    try expect((try pstate.next(r)).? == 'e');
    try expect((try pstate.next(r)).? == 's');

    try expect((try pstate.next(r)).? == 't');
    try expect((try pstate.next(r)).? == 't');
    try expect((try pstate.next(r)).? == 'a');
    try expect((try pstate.next(r)).? == 'g');
    try expect((try pstate.next(r)).? == '>');
    try expect((try pstate.next(r)).? == ' ');
    try expect((try pstate.next(r)).? == 'l');
    try expect((try pstate.next(r)).? == 'l');
    try expect((try pstate.next(r)).? == '\n');
    try expect((try pstate.next(r)).? == '<');
    try expect((try pstate.next(r)).? == '/');
    try expect((try pstate.next(r)).? == 't');
    try expect((try pstate.next(r)).? == 'e');
    try expect((try pstate.next(r)).? == 's');
    try expect((try pstate.next(r)).? == 't');
    try expect((try pstate.next(r)).? == 't');
    try expect((try pstate.next(r)).? == 'a');
    try expect((try pstate.next(r)).? == 'g');
    try expect((try pstate.next(r)).? == '>');
    try expect((try pstate.peek(r)) == null);
    try expect((try pstate.next(r)) == null);
    try expect((try pstate.next(r)) == null);
}

test "parse_state.peek2" {
    const expect = std.testing.expect;
    //{
    //    var file = try std.fs.cwd().openFile("./tst.xml");
    //    defer file.close();

    //    const creader = file.reader();
    //    creader.read();
    //}
    const data =
        \\<testtag> ll
        \\</testtag>
    ;

    var stream = std.io.fixedBufferStream(data);
    const r = stream.reader();

    var pstate = ParseState.init(std.testing.allocator);
    defer pstate.deinit();

    try expect((try pstate.peek(r)).? == '<');
    try expect((try pstate.peek2(r)).? == 't');
    try expect((try pstate.peek(r)).? == '<');

    try expect((try pstate.next(r)).? == '<');
    try expect((try pstate.next(r)).? == 't');
    try expect((try pstate.peek2(r)).? == 's');
    try expect((try pstate.peek(r)).? == 'e');
    try expect((try pstate.next(r)).? == 'e');
    try expect((try pstate.next(r)).? == 's');
    try expect((try pstate.next(r)).? == 't');
    try expect((try pstate.next(r)).? == 't');
    try expect((try pstate.next(r)).? == 'a');
    try expect((try pstate.next(r)).? == 'g');
    try expect((try pstate.next(r)).? == '>');
    try expect((try pstate.next(r)).? == ' ');
    try expect((try pstate.next(r)).? == 'l');
    try expect((try pstate.next(r)).? == 'l');
    try expect((try pstate.next(r)).? == '\n');
    try expect((try pstate.next(r)).? == '<');
    try expect((try pstate.next(r)).? == '/');
    try expect((try pstate.next(r)).? == 't');
    try expect((try pstate.next(r)).? == 'e');
    try expect((try pstate.next(r)).? == 's');
    try expect((try pstate.next(r)).? == 't');
    try expect((try pstate.next(r)).? == 't');
    try expect((try pstate.next(r)).? == 'a');
    try expect((try pstate.next(r)).? == 'g');
    try expect((try pstate.peek2(r)) == null);
    try expect((try pstate.next(r)).? == '>');
    try expect((try pstate.peek2(r)) == null);
    try expect((try pstate.peek(r)) == null);
    try expect((try pstate.next(r)) == null);
    try expect((try pstate.next(r)) == null);
    try expect((try pstate.peek(r)) == null);
    try expect((try pstate.peek2(r)) == null);
}
