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
    pub const AttrList = std.StringHashMapUnmanaged([]const u8);
    pub const ContentList = std.ArrayListUnmanaged(ContentPart);

    tag: []const u8,
    attrs: AttrList = .{},
    children: ContentList = .{},
    special: bool = false,

    pub fn deinit(self: *Self, allocator: mem.Allocator) void {
        {
            var it = self.attrs.iterator();
            while (it.next()) |entry| {
                allocator.free(entry.value_ptr.*);
                allocator.free(entry.key_ptr.*);
            }
        }
        self.attrs.deinit(allocator);

        for (self.children.items) |*item| {
            item.deinit(allocator);
        }
        self.children.deinit(allocator);

        allocator.free(self.tag);
    }

    pub fn getChildren(self: *const Element) []const ContentPart {
        return self.children.items;
    }
    pub fn getChildrenMut(self: *Element) []ContentPart {
        return self.children.items;
    }

    pub inline fn getAttr(self: *const Element, attr: []const u8) ![]const u8 {
        const cattr: []const u8 = self.attrs.get(attr) orelse return error.AttrNotPresent;
        return cattr;
    }

    pub fn getDirectChildByTag(self: *const Element, child_tag: []const u8) DirectChildIterator {
        return DirectChildIterator{
            .element = self,
            .idx = 0,
            .tag_to_match = child_tag,
        };
    }

    pub fn getOneChild(self: *const Element, child_tag: []const u8) !*const Element {
        var it = self.getDirectChildByTag(child_tag);
        const res = it.next();
        std.debug.assert(it.next() == null);
        return res orelse return error.NoChildPresent;
    }

    pub fn getTextChild(self: *const Element) ![]const u8 {
        if (self.children.items.len != 1) return error.ExpectedOneChild;
        switch (self.children.items[0]) {
            .txt => |s| return s,
            else => return error.ExpectedText,
        }
    }
};

pub const DirectChildIterator = struct {
    element: *const Element,
    idx: usize,
    tag_to_match: []const u8,

    pub fn next(self: *DirectChildIterator) ?*const Element {
        for (self.element.children.items[self.idx..]) |*item| {
            self.idx += 1;

            switch (item.*) {
                .elem => |*el| if (std.ascii.eqlIgnoreCase(el.tag, self.tag_to_match)) {
                    return el;
                },
                else => {},
            }
        }
        return null;
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
