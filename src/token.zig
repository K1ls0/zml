const std = @import("std");
const parse_state = @import("parse_state.zig");
const State = parse_state.State;
const ParseState = parse_state.ParseState;
const ZmlError = @import("error.zig").ZmlError;

pub const TokenData = union {
    glyph: u21,
    s: []const u8,
};

pub const Token = struct {
    pos: usize,
    ty: TokenTy,
    data: TokenData,
    line: usize = 0,
    col: usize = 0,
};

pub const TokenTy = enum {
    string,
    bigger_than,
    less_than,
    utf8glyph,
};

//pub const LexAnyTextUntilOptions = struct {
//    endchars: []const u8,
//};
//
//fn lexAnyTextUntil(s: *ParseState, comptime options: LexAnyTextUntilOptions, reader: anytype) ZmlError!?[]const u8 {
//    const TState = enum {
//        string,
//
//        // &
//
//        // From http://unicode.org/mail-arch/unicode-ml/y2003-m02/att-0467/01-The_Algorithm_to_Valide_an_UTF-8_String
//        string_utf8_last_byte, // State A
//        string_utf8_second_to_last_byte, // State B
//        string_utf8_second_to_last_byte_guard_against_overlong, // State C
//        string_utf8_second_to_last_byte_guard_against_surrogate_half, // State D
//        string_utf8_third_to_last_byte, // State E
//        string_utf8_third_to_last_byte_guard_against_overlong, // State F
//        string_utf8_third_to_last_byte_guard_against_too_large, // State G
//    };
//
//    var state: TState = .string;
//
//    while (try s.peek() != null) {
//        const cchar = try s.peek() orelse ZmlError.UnexpectedEndOfString;
//
//        inline for (options.endchars) |endchar| {
//            if (cchar == endchar) {
//                const b = try s.extractBuffer();
//                errdefer s.alloc.free(b);
//                _ = try s.next(reader);
//                return b;
//            }
//        }
//
//        switch (cchar) {
//            0...0x1f => return ZmlError.SyntaxError, // Bare ASCII control code in string.
//
//            // Special characters.
//            //'"' => {
//            //    const result = s.extractBuffer();
//            //    _ = try s.next(reader);
//            //    state = .tag_attr_key_or_end;
//            //    return result;
//            //},
//            //'\\' => {
//            //    _ = try s.next(reader);
//            //    state = .string_backslash;
//            //},
//
//            // ASCII plain text.
//            0x20...('"' - 1), ('"' + 1)...('\\' - 1), ('\\' + 1)...0x7F => |c| {
//                try s.buf.append(c);
//                _ = try s.next(reader);
//            },
//
//            // UTF-8 validation.
//            // See http://unicode.org/mail-arch/unicode-ml/y2003-m02/att-0467/01-The_Algorithm_to_Valide_an_UTF-8_String
//            0xC2...0xDF => |c| {
//                _ = try s.next(reader);
//                try s.buf.append(c);
//                state = .string_utf8_last_byte;
//                continue;
//            },
//            0xE0 => |c| {
//                _ = try s.next(reader);
//                try s.buf.append(c);
//                state = .string_utf8_second_to_last_byte_guard_against_overlong;
//                continue;
//            },
//            0xE1...0xEC, 0xEE...0xEF => |c| {
//                _ = try s.next(reader);
//                try s.buf.append(c);
//                state = .string_utf8_second_to_last_byte;
//                continue;
//            },
//            0xED => |c| {
//                _ = try s.next(reader);
//                try s.buf.append(c);
//                state = .string_utf8_second_to_last_byte_guard_against_surrogate_half;
//                continue;
//            },
//            0xF0 => |c| {
//                _ = try s.next(reader);
//                try s.buf.append(c);
//                state = .string_utf8_third_to_last_byte_guard_against_overlong;
//                continue;
//            },
//            0xF1...0xF3 => |c| {
//                _ = try s.next(reader);
//                state = .string_utf8_third_to_last_byte;
//                try s.buf.append(c);
//                continue;
//            },
//            0xF4 => |c| {
//                _ = try s.next(reader);
//                try s.buf.append(c);
//                state = .string_utf8_third_to_last_byte_guard_against_too_large;
//                continue;
//            },
//            0x80...0xC1, 0xF5...0xFF => return error.SyntaxError, // Invalid UTF-8.
//        }
//    }
//    return ZmlError.UnexpectedEndOfString;
//}
//
//pub fn nextToken(s: *ParseState, reader: anytype) ZmlError!?Token {
//    state_loop: while (true) {
//        switch (s.state) {
//            .document => switch (try s.peek(reader) orelse return null) {
//                '<' => {
//                    s.state = .tag_start;
//                    try s.next(reader);
//                },
//                else => {},
//            },
//
//            .tag_start => {},
//
//            .string => {
//                while (try s.peek() != null) {
//                    switch (try s.peek(reader) orelse return ZmlError.UnexpectedEndOfString) {
//                        0...0x1f => return ZmlError.SyntaxError, // Bare ASCII control code in string.
//
//                        // ASCII plain text.
//                        0x20...('"' - 1), ('"' + 1)...('\\' - 1), ('\\' + 1)...0x7F => |c| {
//                            try s.buf.append(c);
//                            _ = try s.next(reader);
//                        },
//
//                        // Special characters.
//                        '"' => {
//                            const result = try s.extractBuffer();
//                            _ = try s.next(reader);
//                            s.state = .tag_attr_key_or_end;
//                            return result;
//                        },
//                        '\\' => {
//                            _ = try s.next(reader);
//                            s.state = .string_backslash;
//                        },
//
//                        // UTF-8 validation.
//                        // See http://unicode.org/mail-arch/unicode-ml/y2003-m02/att-0467/01-The_Algorithm_to_Valide_an_UTF-8_String
//                        0xC2...0xDF => |c| {
//                            _ = try s.next(reader);
//                            try s.buf.append(c);
//                            s.state = .string_utf8_last_byte;
//                            continue :state_loop;
//                        },
//                        0xE0 => |c| {
//                            _ = try s.next(reader);
//                            try s.buf.append(c);
//                            s.state = .string_utf8_second_to_last_byte_guard_against_overlong;
//                            continue :state_loop;
//                        },
//                        0xE1...0xEC, 0xEE...0xEF => |c| {
//                            _ = try s.next(reader);
//                            try s.buf.append(c);
//                            s.state = .string_utf8_second_to_last_byte;
//                            continue :state_loop;
//                        },
//                        0xED => |c| {
//                            _ = try s.next(reader);
//                            try s.buf.append(c);
//                            s.state = .string_utf8_second_to_last_byte_guard_against_surrogate_half;
//                            continue :state_loop;
//                        },
//                        0xF0 => |c| {
//                            _ = try s.next(reader);
//                            try s.buf.append(c);
//                            s.state = .string_utf8_third_to_last_byte_guard_against_overlong;
//                            continue :state_loop;
//                        },
//                        0xF1...0xF3 => |c| {
//                            _ = try s.next(reader);
//                            s.state = .string_utf8_third_to_last_byte;
//                            try s.buf.append(c);
//                            continue :state_loop;
//                        },
//                        0xF4 => |c| {
//                            _ = try s.next(reader);
//                            try s.buf.append(c);
//                            s.state = .string_utf8_third_to_last_byte_guard_against_too_large;
//                            continue :state_loop;
//                        },
//                        0x80...0xC1, 0xF5...0xFF => return error.SyntaxError, // Invalid UTF-8.
//                    }
//                }
//                if (try s.peek() == null) return ZmlError.UnexpectedEndOfInput;
//                const slice = try s.extractBuffer();
//
//                return Token{
//                    .pos = s.consumed_count,
//                    .ty = .string,
//                    .data = .{ .s = slice },
//                };
//            },
//            //.string_backslash => {
//            //    switch (try s.expectOne()) {
//            //        '"', '\\', '/' => |c| {
//            //            try s.buf.append(c);
//            //            // Since these characters now represent themselves literally,
//            //            // we can simply begin the next plaintext slice here.
//            //            continue :state_loop;
//            //        },
//            //        else => return error.SyntaxError,
//            //    }
//            //},
//            .string_utf8_last_byte => {
//                switch (try s.expectOne()) {
//                    0x80...0xBF => {
//                        s.cursor_pos += 1;
//                        s.state = .string;
//                    },
//                    else => return ZmlError.Syntax, // Invalid UTF-8.
//                }
//            },
//            .string_utf8_second_to_last_byte => {
//                switch (try s.expectByte()) {
//                    0x80...0xBF => {
//                        s.cursor += 1;
//                        s.state = .string_utf8_last_byte;
//                    },
//                    else => return ZmlError.Syntax, // Invalid UTF-8.
//                }
//            },
//            .string_utf8_second_to_last_byte_guard_against_overlong => {
//                switch (try s.expectByte()) {
//                    0xA0...0xBF => {
//                        s.cursor += 1;
//                        s.state = .string_utf8_last_byte;
//                    },
//                    else => return ZmlError.Syntax, // Invalid UTF-8.
//                }
//            },
//            .string_utf8_second_to_last_byte_guard_against_surrogate_half => {
//                switch (try s.expectByte()) {
//                    0x80...0x9F => {
//                        s.cursor += 1;
//                        s.state = .string_utf8_last_byte;
//                    },
//                    else => return ZmlError.Syntax, // Invalid UTF-8.
//                }
//            },
//            .string_utf8_third_to_last_byte => {
//                switch (try s.expectByte()) {
//                    0x80...0xBF => {
//                        s.cursor += 1;
//                        s.state = .string_utf8_second_to_last_byte;
//                    },
//                    else => return ZmlError.Syntax, // Invalid UTF-8.
//                }
//            },
//            .string_utf8_third_to_last_byte_guard_against_overlong => {
//                switch (try s.expectByte()) {
//                    0x90...0xBF => {
//                        s.cursor += 1;
//                        s.state = .string_utf8_second_to_last_byte;
//                    },
//                    else => return ZmlError.Syntax, // Invalid UTF-8.
//                }
//            },
//            .string_utf8_third_to_last_byte_guard_against_too_large => {
//                switch (try s.expectByte()) {
//                    0x80...0x8F => {
//                        s.cursor += 1;
//                        s.state = .string_utf8_second_to_last_byte;
//                    },
//                    else => return ZmlError.Syntax, // Invalid UTF-8.
//                }
//            },
//        }
//    }
//}
