const str = @import("str");

pub const Token = union(enum) {
    l_paren: void,
    r_paren: void,
    string: []const u8,
    integer: []const u8,
    float: []const u8,
    quoted_symbol: []const u8,
    identifier: []const u8,
    eof: void,
};

pub const LexerError = error{
    UnexpectedToken,
    UnterminatedString,
    UnexpectedStringTerminator,
    IncorrectNumberFormat,
};

pub const Span = struct {
    row: usize,
    col: usize,
};

pub const Lexer = struct {
    source: []const u8,

    cursor: usize = 0,
    row: usize = 1,
    col: usize = 1,

    token_delimiters: []const u8 = " \t\n",
    atom_terminators: []const u8 = " \t\n)",

    pub fn init(source: []const u8) Lexer {
        return .{ .source = source };
    }

    pub fn nextToken(self: *Lexer) !Token {
        self.skipWhitespaces();

        const char = self.peekChar() orelse return .eof;

        switch (char) {
            '"' => return try self.readString(),
            '0'...'9' => return try self.readNumber(),
            '@' => return try self.readQuotedSymbol(),
            '(' => {
                self.advance();
                return .l_paren;
            },
            ')' => {
                self.advance();
                return .r_paren;
            },
            else => return try self.readIdentifier(),
        }
    }

    pub fn peekToken(self: *Lexer) !Token {
        const current_cursor = self.cursor;
        defer self.cursor = current_cursor;

        const current_row = self.row;
        defer self.row = current_row;

        const current_col = self.col;
        defer self.col = current_col;

        return try self.nextToken();
    }

    pub fn getSpan(self: Lexer) Span {
        return .{ .row = self.row, .col = self.col };
    }

    fn advance(self: *Lexer) void {
        self.cursor += 1;
        self.col += 1;
    }

    fn skipWhitespaces(self: *Lexer) void {
        while (self.peekChar()) |char| {
            if (char == '\n') {
                self.row += 1;
                self.col = 1;
            }
            if (!str.inludesChar(self.token_delimiters, char)) break;
            self.advance();
        }
    }

    fn skipEscapeChar(self: *Lexer) !void {
        self.advance();
        _ = self.peekChar() orelse return LexerError.UnterminatedString;
        self.advance();
    }

    fn isTerminatorCorrect(self: Lexer, terminator: ?u8) bool {
        if (terminator) |char| {
            return str.inludesChar(self.atom_terminators, char);
        }
        return true;
    }

    fn peekChar(self: Lexer) ?u8 {
        if (self.cursor >= self.source.len) return null;
        return self.source[self.cursor];
    }

    fn readString(self: *Lexer) !Token {
        self.advance();
        const start_pos = self.cursor;

        while (self.peekChar()) |char| {
            switch (char) {
                '"' => {
                    self.advance();
                    if (!self.isTerminatorCorrect(self.peekChar())) return LexerError.UnexpectedStringTerminator;
                    return .{ .string = self.source[start_pos .. self.cursor - 1] };
                },
                '\\' => {
                    try self.skipEscapeChar();
                },
                else => self.advance(),
            }
        }

        return LexerError.UnterminatedString;
    }

    fn readNumber(self: *Lexer) !Token {
        var is_float = false;
        const start_pos = self.cursor;

        while (self.peekChar()) |char| {
            switch (char) {
                '0'...'9' => self.advance(),
                '.' => {
                    switch (is_float) {
                        true => return LexerError.IncorrectNumberFormat,
                        false => {
                            self.advance();
                            is_float = true;
                        },
                    }
                },
                else => {
                    if (self.isTerminatorCorrect(char)) break;
                    return LexerError.IncorrectNumberFormat;
                },
            }
        }

        return switch (is_float) {
            true => .{ .float = self.source[start_pos..self.cursor] },
            false => .{ .integer = self.source[start_pos..self.cursor] },
        };
    }

    pub fn readQuotedSymbol(self: *Lexer) !Token {
        self.advance();
        const string_token = try self.readString();
        return .{ .quoted_symbol = string_token.string };
    }

    pub fn readIdentifier(self: *Lexer) !Token {
        const start_pos = self.cursor;

        while (self.peekChar()) |char| {
            if (self.isTerminatorCorrect(char)) {
                break;
            }
            self.advance();
        }

        const identifier = self.source[start_pos..self.cursor];
        if (identifier.len == 0) return LexerError.UnexpectedToken;

        return .{ .identifier = identifier };
    }
};
