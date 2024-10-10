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
    DuplicateAttributes,
    UnexpectedEndOfString,
    ExpectedIdentifier,
    UnmatchedTagName,
    XmlPrologUnexpectedAttr,
    XmlPrologEncodingVersionNotGiven,
    XmlPrologUnexpectedIdent,
} || std.mem.Allocator.Error;

pub const ParseDocumentError = error{UnexpectedTokensAfterEnd};
