const std = @import("std");

pub const ZmlError = error{
    UnexpectedEndOfInput,
    UnexpectedChar,
    InvalidEscapeSequence,
    InvalidStr,
    UnexpectedStartOfElement,
    ExpectedAttribValSep,
    ExpectedEndOfTag,
    Syntax,
    UnexpectedEndOfString,
    ExpectedIdentifier,
    UnmatchedTagName,
    XmlPrologUnexpectedAttr,
    XmlPrologEncodingVersionNotGiven,
} || std.mem.Allocator.Error;
