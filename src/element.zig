const std = @import("std");
const mem = std.mem;

const ZmlError = @import("error.zig").ZmlError;
const ParseState = @import("parse_state.zig").ParseState;
const parseIdent = @import("ident.zig").parseIdent;
const parseString = @import("string.zig").parseString;

pub const Attr = struct {
    name: []const u8,
    value: []const u8,

    pub fn deinit(self: Attr, allocator: mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.value);
    }
};

pub const ContentPart = union(enum) {
    txt: []const u8,
    comment: []const u8,
    elem: Element,

    pub fn deinit(self: *ContentPart, allocator: mem.Allocator) void {
        switch (self.*) {
            .txt => |txt| allocator.free(txt),
            .comment => |comment| allocator.free(comment),
            .elem => |*elem| elem.deinit(allocator),
        }
    }
};

pub const Element = struct {
    const Self = @This();
    pub const AttrList = std.ArrayListUnmanaged(Attr);
    pub const ContentList = std.ArrayListUnmanaged(ContentPart);

    tag: []const u8,
    attrs: AttrList = .{},
    children: ContentList = .{},
    special: bool = false,

    pub fn deinit(self: *Self, allocator: mem.Allocator) void {
        for (self.attrs.items) |*item| {
            item.deinit(allocator);
        }
        self.attrs.deinit(allocator);

        for (self.children.items) |*item| {
            item.deinit(allocator);
        }
        self.children.deinit(allocator);

        allocator.free(self.tag);
    }
};

//pub fn parseElement(parse_state: *ParseState, reader: anytype, alloc: mem.Allocator) !*Element {
//    if (!try parse_state.consumeChar(reader, '<')) return ZmlError.UnexpectedStartOfElement;
//    try parse_state.consumeWhiteSpaces(reader);
//    const tag = try parseIdent(parse_state, reader, alloc) orelse ZmlError.NoTagIdentifierGiven;
//    errdefer alloc.free(tag);
//
//    try parse_state.consumeWhiteSpaces(reader);
//
//    var attributes = Element.AttrList{};
//    errdefer attributes.deinit(alloc);
//
//    while (true) {
//        const ident = parseIdent(parse_state, reader, alloc) catch break;
//        errdefer alloc.free(ident);
//
//        try parse_state.consumeWhiteSpaces(reader, .any);
//        if (!try parse_state.consumeChar(reader, '=')) return ZmlError.ExpectedAttribValSep;
//        try parse_state.consumeWhiteSpaces(reader);
//        const val = try parseString(parse_state, reader, alloc);
//        errdefer alloc.free(val);
//
//        attributes.append(alloc, .{
//            .name = ident,
//            .value = val,
//        });
//    }
//
//    if (try parse_state.consumeChar(reader, '/')) {
//        if (!try parse_state.consumeChar(reader, '>')) return ZmlError.ExpectedEndOfTag;
//        const elem = try alloc.create(Element);
//        errdefer alloc.destroy(elem);
//        elem.* = .{
//            .tag = tag,
//            .attrs = attributes,
//            .children = .{},
//        };
//        return elem;
//    }
//
//    if (!try parse_state.consumeChar(reader, '>')) return ZmlError.ExpectedEndOfTag;
//
//    // TODO: Parse internals
//    return ZmlError.InvalidStr;
//}
