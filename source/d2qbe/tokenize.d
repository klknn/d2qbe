module d2qbe.tokenize;

import d2qbe.c_declarations;

extern (C) void* get_stderr();

enum TokenKind {
  TK_reserved,
  TK_identifier,
  TK_num,
  TK_float_literal,
  TK_str_literal,
  TK_eof,
}

struct Token {
  TokenKind kind;
  Token* next;
  int val;
  char* str;
  int len;
}

Token* token;

/**
 * Reports an error to stderr and exits the program.
 * Params:
 *   fmt = format string
 */
extern (C) void error(const char* msg) {
  fprintf(get_stderr(), "%s\n", msg);
  exit(1);
}

char* user_input;

void print_error_line(const char* loc) {
  int pos = cast(int)(loc - user_input);
  fprintf(get_stderr(), "Error at offset: %d\n", pos);
  fprintf(get_stderr(), "%s\n", user_input);
  fprintf(get_stderr(), "%*s", pos, cast(const char*) " ");
  fprintf(get_stderr(), "^ ");
}

extern (C) void error_at(const char* loc, const char* msg) {
  print_error_line(loc);
  fprintf(get_stderr(), "%s\n", msg);
  exit(1);
}

/**
 * Checks if the current token matches the given reserved token string.
 * Params:
 *   op = operator or keyword string to match
 * Returns: true if the current token matches, false otherwise.
 */
bool is_token(const char* op) {
  return token.kind == TokenKind.TK_reserved &&
    strlen(op) == token.len &&
    memcmp(token.str, op, token.len) == 0;
}

/**
 * Consumes the current token if it matches the given reserved token string.
 * Params:
 *   op = operator or keyword string to match
 * Returns: true if the token was consumed, false otherwise.
 */
bool consume(const char* op) {
  if (is_token(op)) {
    token = token.next;
    return true;
  }
  return false;
}

/**
 * Consumes the current token if it is an identifier.
 * Returns: the consumed token if it was an identifier, null otherwise.
 */
Token* consume_ident() {
  if (token.kind != TokenKind.TK_identifier) {
    return null;
  }
  Token* ret = token;
  token = token.next;
  return ret;
}

/**
 * Expects the current token to match the given reserved token string and consumes it.
 * If it doesn't match, reports an error and exits.
 * Params:
 *   op = expected operator or keyword string
 */
void expect(const char* op) {
  if (!consume(op)) {
    print_error_line(token.str);
    fprintf(get_stderr(), "Expected token: %s\n", op);
    exit(1);
  }
}

/**
 * Expects the current token to be a number, consumes it, and returns its value.
 * If it is not a number, reports an error and exits.
 * Returns: the value of the expected number.
 */
int expect_number() {
  if (token.kind != TokenKind.TK_num) {
    error_at(token.str, "Expected a number");
  }
  int val = token.val;
  token = token.next;
  return val;
}

/**
 * Checks if we have reached the end of the input (EOF token).
 * Returns: true if at EOF, false otherwise.
 */
bool at_eof() {
  return token.kind == TokenKind.TK_eof;
}

/**
 * Creates a new token and appends it to the current token list.
 * Params:
 *   kind = kind of the new token
 *   cur = current token node (new token will be appended to cur.next)
 *   str = pointer to token string in source
 *   len = length of token string
 * Returns: the newly created token.
 */
Token* new_token(TokenKind kind, Token* cur, char* str, int len) {
  Token* tok = cast(Token*) calloc(1, Token.sizeof);
  tok.kind = kind;
  tok.str = str;
  tok.len = len;
  cur.next = tok;
  return tok;
}

/**
 * Helper function to check if string `a` starts with string `b`.
 */
bool startswith(const char* a, const char* b) {
  return strlen(a) >= strlen(b) && memcmp(a, b, strlen(b)) == 0;
}

/**
 * Computes the length of the identifier starting at `p`.
 * An identifier must start with a letter or underscore, followed by letters, digits, or underscores.
 * Returns: length of the identifier in bytes, or 0 if not a valid identifier start.
 */
int identifier_length(const(char)* p) {
  int i = 0;
  if (isalpha(p[i]) || p[i] == '_') {
    i++;
  }
  else {
    return 0;
  }
  while (isalnum(p[i]) || p[i] == '_') {
    i++;
  }
  return i;
}

unittest {
  assert(identifier_length("a") == 1);
  assert(identifier_length("f") == 1);
  assert(identifier_length("_") == 1);
  assert(identifier_length("") == 0);
  assert(identifier_length("0") == 0);
  assert(identifier_length("a ") == 1);
  assert(identifier_length("a0 ") == 2);
  assert(identifier_length("a0=1") == 2);
}

bool is_keyword(const char* p) {
  int len = identifier_length(p);
  if (len == 7 && strncmp(p, "foreach", 7) == 0) return true;
  if (len == 15 && strncmp(p, "foreach_reverse", 15) == 0) return true;
  if (len == 6 && strncmp(p, "return", 6) == 0) return true;
  if (len == 2 && strncmp(p, "if", 2) == 0) return true;
  if (len == 4 && strncmp(p, "else", 4) == 0) return true;
  if (len == 5 && strncmp(p, "while", 5) == 0) return true;
  if (len == 3 && strncmp(p, "for", 3) == 0) return true;
  if (len == 6 && strncmp(p, "struct", 6) == 0) return true;
  if (len == 4 && strncmp(p, "enum", 4) == 0) return true;
  if (len == 4 && strncmp(p, "cast", 4) == 0) return true;
  if (len == 6 && strncmp(p, "sizeof", 6) == 0) return true;
  if (len == 5 && strncmp(p, "const", 5) == 0) return true;
  if (len == 6 && strncmp(p, "extern", 6) == 0) return true;
  if (len == 8 && strncmp(p, "unittest", 8) == 0) return true;
  if (len == 8 && strncmp(p, "continue", 8) == 0) return true;
  if (len == 5 && strncmp(p, "break", 5) == 0) return true;
  if (len == 4 && strncmp(p, "true", 4) == 0) return true;
  if (len == 5 && strncmp(p, "false", 5) == 0) return true;
  if (len == 6 && strncmp(p, "assert", 6) == 0) return true;
  if (len == 6 && strncmp(p, "switch", 6) == 0) return true;
  if (len == 4 && strncmp(p, "case", 4) == 0) return true;
  if (len == 7 && strncmp(p, "default", 7) == 0) return true;
  if (len == 8 && strncmp(p, "template", 8) == 0) return true;
  if (len == 5 && strncmp(p, "alias", 5) == 0) return true;
  if (len == 6 && strncmp(p, "static", 6) == 0) return true;
  if (len == 4 && strncmp(p, "init", 4) == 0) return true;
  if (len == 7 && strncmp(p, "alignof", 7) == 0) return true;
  if (len == 7 && strncmp(p, "version", 7) == 0) return true;
  if (len == 5 && strncmp(p, "debug", 5) == 0) return true;
  if (len == 4 && strncmp(p, "auto", 4) == 0) return true;
  if (len == 4 && strncmp(p, "this", 4) == 0) return true;
  if (len == 4 && strncmp(p, "null", 4) == 0) return true;
  if (len == 6 && strncmp(p, "module", 6) == 0) return true;
  if (len == 6 && strncmp(p, "import", 6) == 0) return true;
  if (len == 9 && strncmp(p, "__gshared", 9) == 0) return true;
  return false;
}

unittest {
  assert(is_keyword("foreach (x; arr)"));
  assert(is_keyword("foreach_reverse (x; arr)"));
  assert(is_keyword("return a;"));
  assert(!is_keyword("returna;"));
  assert(is_keyword("for (;;)"));
  assert(!is_keyword(""));
  assert(!is_keyword("a"));
  assert(!is_keyword("f"));
  // assert(!is_keyword("f(){}"));
}

/**
 * Tokenizes the input source string `p` and returns the head of the token list.
 * Params:
 *   p = null-terminated source code string
 * Returns: pointer to the first token in the tokenized list.
 */
Token* tokenize(char* p) {
  Token head;
  head.next = null;
  Token* cur = &head;
  while (*p) {
    if (isspace(*p)) {
      p++;
      continue;
    }
    // line comment.
    if (p[0] == '/' && p[1] == '/') {
      p = p + 2;
      while (*p && *p != '\n') {
        p++;
      }
      continue;
    }
    // block comment.
    if (p[0] == '/' && p[1] == '*') {
      p = p + 2;
      while (*p && !(p[0] == '*' && p[1] == '/')) {
        p++;
      }
      if (*p) {
        p = p + 2;
      }
      continue;
    }
    // multi-punct reserved.
    if (startswith(p, "...") ||
      startswith(p, "..") ||
      startswith(p, "<<=") || startswith(p, ">>=") ||
      startswith(p, "==") || startswith(p, "!=") ||
      startswith(p, "<=") || startswith(p, ">=") ||
      startswith(p, "&&") || startswith(p, "||") ||
      startswith(p, "++") || startswith(p, "--") ||
      startswith(p, "<<") || startswith(p, ">>") ||
      startswith(p, "+=") || startswith(p, "-=") ||
      startswith(p, "*=") || startswith(p, "/=") ||
      startswith(p, "%=") || startswith(p, "&=") ||
      startswith(p, "|=") || startswith(p, "^=")) {
      int len = 2;
      if (startswith(p, "...")) {
        len = 3;
      } else if (startswith(p, "<<=") || startswith(p, ">>=")) {
        len = 3;
      } else if (startswith(p, "..")) {
        len = 2;
      }
      cur = new_token(TokenKind.TK_reserved, cur, p, len);
      p = p + len;
      continue;
    }
    // single-punct reserved.
    if (strchr("+-*/()<>=;{},&.|[]!^~%:?", *p)) {
      cur = new_token(TokenKind.TK_reserved, cur, p++, 1);
      continue;
    }

    // identifier or ident-like reserved.
    int ident_len = identifier_length(p);
    if (ident_len) {
      TokenKind kind = TokenKind.TK_identifier;
      if (is_keyword(p)) {
        kind = TokenKind.TK_reserved;
      }
      cur = new_token(kind, cur, p, ident_len);
      p = p + ident_len;
      continue;
    }

    if (*p == '\'') {
      char* start = p;
      p++;
      int val = 0;
      if (*p == '\\') {
        p++;
        if (*p == 'n') val = 10;
        else if (*p == 'r') val = 13;
        else if (*p == 't') val = 9;
        else if (*p == '0') val = 0;
        else if (*p == '\'') val = 39;
        else if (*p == '\\') val = 92;
        else error_at(p, "unknown escape sequence");
        p++;
      } else {
        val = *p;
        p++;
      }
      if (*p != '\'') {
        error_at(p, "unclosed character literal");
      }
      p++;
      cur = new_token(TokenKind.TK_num, cur, start, cast(int)(p - start));
      cur.val = val;
      continue;
    }

    if (*p == '"') {
      char* start = ++p;
      while (*p && *p != '"') {
        if (*p == '\\') p++;
        p++;
      }
      if (!*p) error_at(start, "unclosed string literal");
      cur = new_token(TokenKind.TK_str_literal, cur, start, cast(int)(p - start));
      p++;
      continue;
    }

    if (isdigit(*p)) {
      int fl_len = parse_float_literal_length(p);
      if (fl_len > 0) {
        cur = new_token(TokenKind.TK_float_literal, cur, p, fl_len);
        p = p + fl_len;
        continue;
      }
      cur = new_token(TokenKind.TK_num, cur, p, 0);
      cur.val = cast(int) strtol(p, &p, 10);
      cur.len = cast(int)(p - cur.str);
      continue;
    }

    fprintf(get_stderr(), "Failed at char code: %d\n", cast(int)*p);
    fflush(get_stderr());
    error_at(p, "Cannot tokenize.");
  }

  Token* _ = new_token(TokenKind.TK_eof, cur, p, 1);
  return head.next;
}

int parse_float_literal_length(const(char)* p) {
  const(char)* s = p;
  if (!isdigit(*s)) return 0;
  
  while (isdigit(*s)) {
    s++;
  }
  
  bool is_float = false;
  
  if (*s == '.') {
    if (*(s + 1) == '.') {
      return 0;
    }
    is_float = true;
    s++;
    while (isdigit(*s)) {
      s++;
    }
  }
  
  if (*s == 'e' || *s == 'E') {
    is_float = true;
    s++;
    if (*s == '+' || *s == '-') {
      s++;
    }
    if (!isdigit(*s)) {
      return 0;
    }
    while (isdigit(*s)) {
      s++;
    }
  }
  
  if (*s == 'f' || *s == 'F') {
    is_float = true;
    s++;
  }
  
  if (is_float) {
    return cast(int)(s - p);
  }
  return 0;
}

unittest {
  Token* tok = tokenize(cast(char*) "+= <<=");
  assert(tok != null && tok.kind == TokenKind.TK_reserved && tok.len == 2 && strncmp(tok.str, "+=", 2) == 0);
  tok = tok.next;
  assert(tok != null && tok.kind == TokenKind.TK_reserved && tok.len == 3 && strncmp(tok.str, "<<=", 3) == 0);
  tok = tok.next;
  assert(tok != null && tok.kind == TokenKind.TK_eof);
}
