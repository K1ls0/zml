const std = @import("std");
const log = std.log.scoped(.zml);
const mem = std.mem;
const testing = std.testing;

pub const debug = @import("debug.zig");

const parse_state = @import("parse_state.zig");
pub const ParseState = parse_state.ParseState;
pub const ErrorValue = parse_state.ErrorValue;
pub const XmlProlog = parse_state.XmlProlog;
pub const parseContent = parse_state.parseContent;
pub const parseXmlProlog = parse_state.parseXmlProlog;

const element = @import("element.zig");
pub const Element = element.Element;
pub const Attr = element.Attr;
pub const ContentPart = element.ContentPart;

const document = @import("document.zig");
pub const Document = document.Document;
pub const parseDocument = document.parseDocument;

//pub const token = @import("token.zig");
//pub const Token = token.Token;

pub const errors = @import("error.zig");
pub const ZmlError = errors.ZmlError;
pub const ParseDocumentError = errors.ParseDocumentError;

test "zml.simple_parse" {
    const DATA =
        \\ <Testtag a="aa" a-b-c="ab&amp;c"  a_b_c="abc"/>
        \\ <outertag>
        \\  <innertag0 a="bb">
        \\      And this is the inner text of innertag0.
        \\  </innertag0>
        \\  <innertag1 a="cc">
        \\      This is some text in innertag1!
        \\  </innertag1>
        \\ </outertag>
    ;
    var bs = std.io.fixedBufferStream(DATA);
    const r = bs.reader();
    var ps = ParseState.init(testing.allocator);
    defer ps.deinit();
    var res = try parseContent(&ps, r);
    defer {
        for (res.items) |*item| {
            item.deinit(testing.allocator);
        }
        res.deinit(testing.allocator);
    }
    {
        try testing.expectEqual(2, res.items.len);
        {
            try testing.expect(res.items[0] == .elem);
            try testing.expectEqualStrings("Testtag", res.items[0].elem.tag);
            {
                try testing.expectEqual(3, res.items[0].elem.attrs.items.len);
                try testing.expectEqualDeep(Attr{ .name = "a", .value = "aa" }, res.items[0].elem.attrs.items[0]);
                try testing.expectEqualDeep(Attr{ .name = "a-b-c", .value = "ab&c" }, res.items[0].elem.attrs.items[1]);
                try testing.expectEqualDeep(Attr{ .name = "a_b_c", .value = "abc" }, res.items[0].elem.attrs.items[2]);
            }
            try testing.expectEqual(false, res.items[0].elem.special);
            try testing.expectEqual(0, res.items[0].elem.children.items.len);
        }

        {
            try testing.expect(res.items[1] == .elem);
            try testing.expectEqualStrings("outertag", res.items[1].elem.tag);
            try testing.expectEqual(0, res.items[1].elem.attrs.items.len);
            try testing.expectEqual(2, res.items[1].elem.children.items.len);
            {
                const item = res.items[1].elem.children.items[0];
                try testing.expect(item == .elem);
                try testing.expectEqualStrings("innertag0", item.elem.tag);
                try testing.expectEqual(false, item.elem.special);
                {
                    try testing.expectEqual(1, item.elem.attrs.items.len);
                    try testing.expectEqualDeep(Attr{ .name = "a", .value = "bb" }, item.elem.attrs.items[0]);
                }
                {
                    try testing.expectEqual(1, item.elem.children.items.len);
                    try testing.expect(item.elem.children.items[0] == .txt);
                    try testing.expectEqualStrings(
                        "And this is the inner text of innertag0.",
                        item.elem.children.items[0].txt,
                    );
                }
            }
            {
                const item = res.items[1].elem.children.items[1];
                try testing.expect(item == .elem);
                try testing.expectEqualStrings("innertag1", item.elem.tag);
                try testing.expectEqual(false, item.elem.special);
                {
                    try testing.expectEqual(1, item.elem.attrs.items.len);
                    try testing.expectEqualDeep(Attr{ .name = "a", .value = "cc" }, item.elem.attrs.items[0]);
                }
                {
                    try testing.expectEqual(1, item.elem.children.items.len);
                    try testing.expect(item.elem.children.items[0] == .txt);
                    try testing.expectEqualStrings(
                        "This is some text in innertag1!",
                        item.elem.children.items[0].txt,
                    );
                }
            }
        }
    }
}

test {
    _ = @import("element.zig");
    _ = @import("error.zig");
    _ = @import("ident.zig");
    _ = @import("parse_state.zig");
    _ = @import("root.zig");
    _ = @import("string.zig");
    _ = @import("token.zig");
    _ = @import("xmlspec.zig");
    _ = @import("debug.zig");
}
