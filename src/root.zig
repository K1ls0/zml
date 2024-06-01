const std = @import("std");
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

//pub const token = @import("token.zig");
//pub const Token = token.Token;

pub const ZmlError = @import("error.zig").ZmlError;

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
