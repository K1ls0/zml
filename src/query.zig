const std = @import("std");
const log = std.log.scoped(.zml_query);
const mem = std.mem;
const parse_state = @import("parse_state.zig");
const element = @import("element.zig");
const Element = element.Element;
const ContentPart = element.ContentPart;

pub const Query = struct {
    target: Target = .element,
    tag: Tag = null,
    attrs: []Attr = &.{},
    max_depth: ?usize = null,
    sub: ?*const Query = null,

    pub const Target = enum { text, element };

    pub const Tag = union(enum) {
        tag: []const u8,
        @"or": struct {*const Tag, *const Tag},
        @"and": struct {*const Tag, *const Tag},
        not: *const Tag,
    };

    pub fn iterator(self: Query, allocator: mem.Allocator) QueryIt {
        return QueryIt{
            .query = self,
            .stack = std.ArrayList(usize).init(allocator),
            .attr = null,
        };
    }
};

pub const QueryIt = struct {
    query: Query,
    stack: std.ArrayList(usize),
    data: *const ContentPart,

    pub const MatchesElementOptions = struct {
        ignore_case: bool = false,
    };

    pub fn next(self: *const Query) mem.Allocator.Error!*const Element {
        const clist = self.getElement(self.stack.items.len-1);
        _ = clist; // autofix
    }

    fn getElement(self: *const Query, depth: usize) ?*const Element {
        var celement: *const ContentPart = self.data;
        for (self.stack.items[0..depth]) |cidx| {
            std.debug.assert(celement.* == .elem);
            celement = &celement.elem;
            _ = cidx; // autofix

        }
    }

    pub fn elementMatchesQuery(
        self: *const Query,
        elem: *const Element,
        depth: usize,
        comptime options: MatchesElementOptions,
    ) bool {
        const str_eql = if (options.ignore_case) std.ascii.eqlIgnoreCase else blk: {
            const Closure = struct {
                pub fn str_eql(a: []const u8, b: []const u8) bool {
                    return std.mem.eql(u8, a, b);
                }
            };
            break :blk Closure.str_eql;
        };

        if (self.max_depth) |max_depth| if (depth > max_depth) return false;
        if (self.tag) |tag| if (!str_eql(elem.tag, tag)) return false;
        // TODO: Better way to search attributes
        for (self.attrs) |attr_query| {
            for (elem.attrs.items) |cattr| {
                if (attr_query.name) |query_name| {
                    if (!str_eql(query_name, cattr.name)) return false;
                }
                if (attr_query.value) |query_value| {
                    if (!str_eql(query_value, cattr.value)) return false;
                }
            }
        }
        return true;
    }
};

pub const Attr = struct {
    name: ?[]const u8 = null,
    value: ?[]const u8 = null,
};


//pub fn query(e: *ContentPart, allocator: mem.Allocator, q: Query) mem.Allocator.Error!QueryIterator {
//    var pos = std.ArrayList(usize).init(allocator);
//    errdefer pos.deinit();
//    try pos.append(0);
//
//    return QueryIterator{
//        .query = q,
//        .base = e,
//        .pos = try std.ArrayList(usize).initCapacity(allocator, 10),
//    };
//}

//const QueryIterator = struct {
//    stack: std.ArrayList(usize),
//    base: *ContentPart,
//    query: Query,
//
//    pub fn next(self: *QueryIterator) mem.Allocator.Error!?*Element {
//        while (true) {
//            if (self.stack.items.len == 0) return null;
//            const depth = self.stack.items.len - 1;
//            const cnode: *ContentPart, const cnode_idx = blk: {
//                var cnode = self.base;
//                var node_idx: usize = 0;
//                for (self.stack.items, 0..) |cidx, i| {
//                    if (cnode.elem.children.items.len >= cidx) {
//                        _ = self.stack.pop();
//                        break :blk .{ cnode, node_idx };
//                    }
//                    node_idx = cidx;
//                    cnode = &cnode.elem.children.items[cidx];
//                    log.info("[stack {}] -> {} -> {any}", .{ i, cidx, cnode });
//                }
//                break :blk .{ cnode, node_idx };
//            };
//
//            log.info("[{}] cnode: {any}", .{ cnode_idx, cnode });
//
//            switch (cnode.*) {
//                .elem => |*elem| {
//                    if (self.query.matchesElement(
//                        elem,
//                        depth,
//                        .{},
//                    )) {
//                        return elem;
//                    }
//                },
//                else => {},
//            }
//            _ = self.stack.pop();
//            try self.stack.append(cnode_idx + 1);
//        }
//    }
//    pub inline fn deinit(self: *QueryIterator) void {
//        self.stack.deinit();
//    }
//};

/// klsdkfjsldfkjslkfjdsldkfj

//pub fn query(doc: *const Document, q: Query) ElementIterator {
//    return ElementIterator{
//        .query = q,
//        .doc = doc,
//        .current = .{ .root = doc.content.items },
//        .idx = 0,
//    };
//}

//pub const ElementIterator = struct {
//    allocator: mem.Allocator,
//    query: Query,
//    query_pos: std.ArrayListUnmanaged(usize),
//    doc: *Document,
//    current: Elem,
//    idx: usize,
//
//    pub const Elem = union(enum) {
//        root: []const ContentPart,
//        elem: *const Element,
//    };
//
//    pub fn next(self: *ElementIterator) ?*Element {
//        switch (self.current) {
//            .root => {},
//            .elem => {},
//        }
//    }
//};

fn list(
    comptime T: type,
    allocator: mem.Allocator,
    items: []const T,
) std.ArrayListUnmanaged(T) {
    var l = std.ArrayListUnmanaged(T).initCapacity(allocator, items.len) catch @panic("OOM");
    l.appendSlice(items) catch @panic("OOM");
    return l;
}

const testing = std.testing;
test "zml.query.simple_single" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.allocator();
    const doc = Document{ .content = list(ContentPart, arena.allocator(), &.{
        ContentPart{ .elem = .{ .tag = "test1" } },
        ContentPart{ .elem = .{ .tag = "test2" } },
        ContentPart{ .elem = .{ .tag = "test3" } },
    }) };
    var it = query(&doc, .{ .elemname = "test*" });
    while (it.next()) |item| {
        std.debug.print("item: {any}", .{item});
    }
}
