const std = @import("std");
const mem = std.mem;
const testing = std.testing;

pub const token = @import("token.zig");
pub const parse_state = @import("parse_state.zig");
pub const string = @import("string.zig");
pub const element = @import("element.zig");

pub const ZmlError = @import("error.zig").ZmlError;

pub const ParseState = parse_state.ParseState;
pub const XmlProlog = parse_state.XmlProlog;
pub const Token = token.Token;

pub const Element = element.Element;
pub const Attr = element.Attr;

test {
    _ = @import("element.zig");
    _ = @import("error.zig");
    _ = @import("ident.zig");
    _ = @import("parse_state.zig");
    _ = @import("root.zig");
    _ = @import("string.zig");
    _ = @import("token.zig");
    _ = @import("xmlspec.zig");
}
