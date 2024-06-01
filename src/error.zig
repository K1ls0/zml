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
    XmlPrologUnexpectedIdent,
} || std.mem.Allocator.Error;
