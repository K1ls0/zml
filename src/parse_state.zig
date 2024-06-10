const std = @import("std");
const log = std.log.scoped(.parse_state);
const mem = std.mem;
const ZmlError = @import("error.zig").ZmlError;
const spec = @import("xmlspec.zig");
const element = @import("element.zig");
const ident = @import("ident.zig");
const string = @import("string.zig");

const Element = element.Element;

pub const ErrorValue = union(enum) {
    none,
    simple: struct { line: usize, col: usize },
};

pub const ParseState = struct {
    const Self = @This();

    alloc: std.mem.Allocator,

    _peeked: ?u8 = null,
    _peeked2: ?u8 = null,
    consumed_count: usize = 0,
    line: usize = 1,
    col: usize = 1,

    error_value: ErrorValue = .none,
    buf: std.ArrayListUnmanaged(u8) = .{},

    pub fn init(alloc: std.mem.Allocator) Self {
        return Self{
            .buf = .{},
            .alloc = alloc,
        };
    }
    pub fn deinit(self: *Self) void {
        self.buf.deinit(self.alloc);
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

    pub inline fn setError(self: *Self, e: ErrorValue) void {
        self.error_value = e;
    }

    /// Expect one byte, also returning an error if the end of input is reached
    pub inline fn expectOne(self: *Self, reader: anytype) ZmlError!u8 {
        return try self.next(reader) orelse return ZmlError.UnexpectedEndOfInput;
    }
};

pub const XmlProlog = struct {
    version: []const u8,
    encoding: []const u8,

    pub fn deinit(self: @This(), allocator: mem.Allocator) void {
        allocator.free(self.version);
        allocator.free(self.encoding);
    }
};

pub fn parseComment(s: *ParseState, r: anytype) (ZmlError || @TypeOf(r).Error)!?[]const u8 {
    if ((try s.peek(r) orelse return null) != '<') return null;
    if ((try s.peek2(r) orelse return null) != '!') return null;
    if (!try s.consumeChar(r, '<')) return null;
    if (!try s.consumeChar(r, '!')) return null;
    if (!try s.consumeChar(r, '-')) return ZmlError.UnexpectedChar;
    if (!try s.consumeChar(r, '-')) return ZmlError.UnexpectedChar;

    var state: enum { normal, dash0, dash1 } = .normal;

    try s.consumeWhiteSpaces(r, .any);

    var str = std.ArrayListUnmanaged(u8){};
    defer str.deinit(s.alloc);

    while_blk: while (true) {
        const c = try s.next(r) orelse return ZmlError.UnexpectedEndOfInput;
        switch (state) {
            .normal => switch (c) {
                '-' => {
                    state = .dash0;
                },
                else => try str.append(s.alloc, c),
            },
            .dash0 => switch (c) {
                '-' => state = .dash1,
                else => {
                    state = .normal;
                    try str.appendSlice(s.alloc, &.{ '-', c });
                },
            },
            .dash1 => switch (c) {
                '>' => break :while_blk,
                else => {
                    state = .normal;
                    try str.appendSlice(s.alloc, &.{ '-', '-', c });
                },
            },
        }
    }

    while (str.items.len > 0 and spec.isXmlWhitespace(str.getLast())) {
        _ = str.pop();
    }

    return try str.toOwnedSlice(s.alloc);
}

pub fn parseTag(s: *ParseState, r: anytype) (ZmlError || @TypeOf(r).Error)!?element.Element {
    if ((try s.peek(r) orelse return null) != '<') return null;
    switch (try s.peek2(r) orelse return null) {
        '/', '?', '!' => return null,
        else => {},
    }
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
    var content = try parseContent(s, r);
    errdefer content.deinit(s.alloc);

    try s.consumeWhiteSpaces(r, .any);

    if (!try s.consumeChar(r, '<')) return ZmlError.UnexpectedChar;
    if (!try s.consumeChar(r, '/')) return ZmlError.UnexpectedChar;

    try s.consumeWhiteSpaces(r, .any);

    const close_tagname = try ident.parseIdent(s, r) orelse return ZmlError.ExpectedIdentifier;
    defer s.alloc.free(close_tagname);
    if (!std.mem.eql(u8, tagname, close_tagname)) return ZmlError.UnmatchedTagName;

    try s.consumeWhiteSpaces(r, .any);

    if (!try s.consumeChar(r, '>')) return ZmlError.UnexpectedChar;

    return Element{
        .tag = tagname,
        .attrs = attributes,
        .children = content,
    };
}

pub fn parseContent(s: *ParseState, r: anytype) (ZmlError || @TypeOf(r).Error)!Element.ContentList {
    var content = Element.ContentList{};
    errdefer content.deinit(s.alloc);
    while_blk: while (true) {
        try s.consumeWhiteSpaces(r, .any);

        if (try parseComment(s, r)) |comment| {
            try content.append(s.alloc, element.ContentPart{ .comment = comment });
            continue;
        }

        if (try parseTag(s, r)) |tag| {
            try content.append(s.alloc, element.ContentPart{ .elem = tag });
            continue;
        }

        if (try parseText(s, r)) |txt| {
            try content.append(s.alloc, element.ContentPart{ .txt = txt });
            continue;
        }

        break :while_blk;
    }

    return content;
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

pub fn parseXmlProlog(s: *ParseState, r: anytype) (ZmlError || @TypeOf(r).Error)!?XmlProlog {
    if ((try s.peek(r) orelse return null) != '<') return null;
    if ((try s.peek2(r) orelse return null) != '?') return null;
    if (!try s.consumeChar(r, '<')) return null;
    if (!try s.consumeChar(r, '?')) return null;

    try s.consumeWhiteSpaces(r, .any);

    {
        const id = try ident.parseIdent(s, r) orelse return null;
        defer s.alloc.free(id);
        if (!std.ascii.eqlIgnoreCase(id, "xml")) return ZmlError.XmlPrologUnexpectedIdent;
    }

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
            encoding = attrvalue;
        } else return ZmlError.XmlPrologUnexpectedAttr;
    }

    try s.consumeWhiteSpaces(r, .any);
    if (!try s.consumeChar(r, '?')) return ZmlError.UnexpectedChar;
    if (!try s.consumeChar(r, '>')) return ZmlError.UnexpectedChar;

    return XmlProlog{
        .version = version orelse return ZmlError.XmlPrologEncodingVersionNotGiven,
        .encoding = encoding orelse return ZmlError.XmlPrologEncodingVersionNotGiven,
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
