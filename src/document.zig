const std = @import("std");
const mem = std.mem;
const log = std.log.scoped(.zml_document);

const parse_state = @import("parse_state.zig");
pub const ParseState = parse_state.ParseState;
pub const ErrorValue = parse_state.ErrorValue;
pub const XmlProlog = parse_state.XmlProlog;
pub const parseContent = parse_state.parseContent;
pub const parseXmlProlog = parse_state.parseXmlProlog;

const element = @import("element.zig");
pub const Element = element.Element;
pub const ContentPart = element.ContentPart;

pub const errors = @import("error.zig");
pub const ZmlError = errors.ZmlError;
pub const ParseDocumentError = errors.ParseDocumentError;

pub const Document = struct {
    allocator: mem.Allocator,
    prolog: ?XmlProlog = null,
    content: Element.ContentList = .{},

    pub fn deinit(self: *Document) void {
        if (self.prolog) |*prolog| {
            prolog.deinit(self.allocator);
        }
        for (self.content.items) |*item| {
            item.deinit(self.allocator);
        }
        self.content.deinit(self.allocator);
    }

    pub inline fn getContent(self: *const Document) []const ContentPart {
        return self.content.items;
    }

    pub inline fn getContentMut(self: *Document) []ContentPart {
        return self.content.items;
    }
};

pub fn parseDocument(
    state: *ParseState,
    r: anytype,
) (ZmlError || ParseDocumentError || @TypeOf(r).Error)!Document {
    var document = Document{ .allocator = state.alloc };
    errdefer document.deinit();

    try state.consumeWhiteSpaces(r, .any);

    document.prolog = parseXmlProlog(state, r) catch |e| {
        log.err("Error occured at line {}, column {}", .{ state.line, state.col });
        return e;
    };

    document.content = parseContent(state, r) catch |e| {
        log.err("Error occured at line {}, column {}", .{ state.line, state.col });
        log.err("current char: {?c}", .{try state.peek(r)});
        return e;
    };
    try state.consumeWhiteSpaces(r, .any);
    if (try state.peek(r) != null) return error.UnexpectedTokensAfterEnd;

    return document;
}
