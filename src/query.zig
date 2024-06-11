const std = @import("std");
const log = std.log.scoped(.zml_query);
const mem = std.mem;
const parse_state = @import("parse_state.zig");
const element = @import("element.zig");
const Element = element.Element;
const ContentPart = element.ContentPart;

pub const Query = struct {
    tag: ?[]const u8 = null,
    attrs: []Attr = &.{},
    max_depth: ?usize = null,

    pub const MatchesElementOptions = struct {
        ignore_case: bool = false,
    };
    pub fn matchesElement(
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

pub fn query(e: *ContentPart, allocator: mem.Allocator, q: Query) mem.Allocator.Error!QueryIterator {
    var pos = std.ArrayList(usize).init(allocator);
    errdefer pos.deinit();
    try pos.append(0);

    return QueryIterator{
        .query = q,
        .base = e,
        .pos = try std.ArrayList(usize).initCapacity(allocator, 10),
    };
}

const QueryIterator = struct {
    pos: std.ArrayList(usize),

    base: *ContentPart,
    query: Query,

    pub fn next(self: *QueryIterator) mem.Allocator.Error!?*Element {
        while (true) {
            if (self.pos.items.len == 0) return null;
            const depth = self.pos.items.len - 1;
            const cnode: *ContentPart, const cnode_idx = blk: {
                var cnode = self.base;
                var node_idx: usize = 0;
                for (self.pos.items, 0..) |cidx, i| {
                    if (cnode.elem.children.items.len >= cidx) {
                        _ = self.pos.pop();
                        break :blk .{ cnode, node_idx };
                    }
                    node_idx = cidx;
                    cnode = &cnode.elem.children.items[cidx];
                    log.info("[stack {}] -> {} -> {any}", .{ i, cidx, cnode });
                }
                break :blk .{ cnode, node_idx };
            };

            log.info("[{}] cnode: {any}", .{ cnode_idx, cnode });

            switch (cnode.*) {
                .elem => |*elem| {
                    if (self.query.matchesElement(
                        elem,
                        depth,
                        .{},
                    )) {
                        return elem;
                    }
                },
                else => {},
            }
            _ = self.pos.pop();
            try self.pos.append(cnode_idx + 1);
        }
    }
    pub inline fn deinit(self: QueryIterator) void {
        self.pos.deinit();
    }
};
