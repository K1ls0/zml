const std = @import("std");
const builtin = @import("builtin");
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
pub const ContentPartTag = enum {
    txt,
    comment,
    elem,
};

pub const ContentPart = union(ContentPartTag) {
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

    pub fn getTextChild(self: ContentPart) ?[]const u8 {
        return switch (self) {
            .txt => |txt| txt,
            else => null,
        };
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

    pub fn getAttr(self: Self, name: []const u8) ?[]const u8 {
        for (self.attrs.items) |attr| {
            if (std.mem.eql(u8, attr.name, name)) return attr.value;
        }
        return null;
    }

    pub fn getDirectChildByTag(self: *const Self, tag: []const u8) ElementChildIterator {
        return self.childIterator(Filter{
            .type = .elem,
            .tag = tag,
        });
    }

    pub fn getOneChild(self: *const Self, tag: []const u8) ?*const Element {
        var it = self.childIterator(Filter{
            .type = .elem,
            .tag = tag,
        });
        const item = if (it.next()) |item| &item.elem else return null;
        if (comptime builtin.mode == .Debug) {
            if (it.next() != null) {
                std.log.warn("[getOneChild] Multiple children with given tag", .{});
            }
        }
        return item;
    }

    pub fn getTextChild(self: *const Self) ?[]const u8 {
        var it = self.childIterator(null);
        const child = it.next() orelse return null;
        std.debug.assert(it.next() == null);
        return switch (child.*) {
            .txt => |txt| txt,
            else => null,
        };
    }

    pub fn childIterator(self: *const Self, filter: ?Filter) ElementChildIterator {
        return .{
            .children = self.children.items,
            .idx = 0,
            .filter = filter,
        };
    }
};

pub const ElementChildIterator = struct {
    filter: ?Filter,
    children: []const ContentPart,
    idx: usize,

    pub fn next(self: *ElementChildIterator) ?*const ContentPart {
        return if (self.filter) |f|
            self.nextFiltered(f)
        else
            self.nextUnfiltered();
    }

    fn nextUnfiltered(self: *ElementChildIterator) ?*const ContentPart {
        if (self.idx >= self.children.len) {
            @branchHint(.unlikely);
            return null;
        }
        const child = &self.children[self.idx];
        self.idx += 1;
        return child;
    }

    fn nextFiltered(self: *ElementChildIterator, filter: Filter) ?*const ContentPart {
        var cnext = self.nextUnfiltered() orelse return null;
        while (!filter.matches(cnext)) {
            cnext = self.nextUnfiltered() orelse return null;
        }
        return cnext;
    }
};

pub const Filter = struct {
    type: ?ContentPartTag = null,
    tag: ?[]const u8 = null,
    attribute_name: ?[]const u8 = null,
    attribute_value: ?[]const u8 = null,
    match_case: bool = true,

    pub fn matches(self: Filter, to_match: *const ContentPart) bool {
        if (self.type) |ty| if (to_match.* != ty) return false;
        switch (to_match.*) {
            .txt => return true,
            .elem => |elem| {
                if (self.tag) |tag_name| {
                    if (!self.strMatches(tag_name, elem.tag)) return false;
                }
                if (self.attribute_name) |attribute_name| {
                    var any_attr_matches = false;
                    for (elem.attrs.items) |attr| {
                        any_attr_matches = false;
                        if (self.strMatches(attribute_name, attr.name)) any_attr_matches = true;
                        if (self.attribute_value) |attribute_value| if (any_attr_matches) {
                            any_attr_matches = self.strMatches(attribute_value, attr.value);
                        };
                        if (any_attr_matches) break;
                    }
                    if (!any_attr_matches) return false;
                }
                return true;
            },
            .comment => return true,
        }
    }

    fn strMatches(self: Filter, a: []const u8, b: []const u8) bool {
        if (self.match_case) {
            return std.mem.eql(u8, a, b);
        } else {
            return std.ascii.eqlIgnoreCase(a, b);
        }
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
