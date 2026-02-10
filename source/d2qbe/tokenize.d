module d2qbe.tokenize;

import core.stdc.ctype;
import core.stdc.stdarg;
import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.string;

enum TokenKind {
  reserved,
  ident,
  num,
  eof,
}

struct Token {
  TokenKind kind;
  Token* next;
  int val;
  char* str;
  int len;
}

Token* token;

// Reports an error like printf.
extern (C) void error(const char* fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  vfprintf(stderr, fmt, ap);
  fprintf(stderr, "\n");
  exit(1);
}

char* user_input;

extern (C) void error_at(const char* loc, const char* fmt, ...) {
  // Display the error position in the line.
  int pos = cast(int)(loc - user_input);
  fprintf(stderr, "%s\n", user_input);
  fprintf(stderr, "%*s", pos, cast(const char*) " ");
  fprintf(stderr, "^ ");

  va_list ap;
  va_start(ap, fmt);
  vfprintf(stderr, fmt, ap);
  fprintf(stderr, "\n");
  exit(1);
}

bool is_token(const char* op) {
  return token.kind == TokenKind.reserved &&
    strlen(op) == token.len &&
    memcmp(token.str, op, token.len) == 0;
}

// Consumes one token and returns true if the token is op.
bool consume(const char* op) {
  if (is_token(op)) {
    token = token.next;
    return true;
  }
  return false;
}

Token* consume_ident() {
  if (token.kind != TokenKind.ident) {
    return null;
  }
  Token* ret = token;
  token = token.next;
  return ret;
}

void expect(const char* op) {
  if (!consume(op)) {
    error_at(token.str, "Expected token %s", op);
  }
}

int expect_number() {
  if (token.kind != TokenKind.num) {
    error_at(token.str, "Expected a number");
  }
  int val = token.val;
  token = token.next;
  return val;
}

bool at_eof() {
  return token.kind == TokenKind.eof;
}

Token* new_token(TokenKind kind, Token* cur, char* str, int len) {
  Token* tok = cast(Token*) calloc(1, Token.sizeof);
  tok.kind = kind;
  tok.str = str;
  tok.len = len;
  cur.next = tok;
  return tok;
}

bool startswith(const char* a, const char* b) {
  return strlen(a) >= strlen(b) && memcmp(a, b, strlen(b)) == 0;
}

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

const(char)** keywords = ["return", "if", "else", "while", "for", ""];

bool is_keyword(const char* p) {
  if (strlen(p) == 0) {
    return false;
  }
  int ident_len = identifier_length(p);
  for (int i = 0; keywords[i] != ""; i++) {
    const(char)* k = keywords[i];
    if (strlen(k) == ident_len && strncmp(p, k, ident_len) == 0) {
      return true;
    }
  }
  return false;
}

unittest {
  assert(is_keyword("return a;"));
  assert(!is_keyword("returna;"));
  assert(is_keyword("for (;;)"));
  assert(!is_keyword(""));
  assert(!is_keyword("a"));
  assert(!is_keyword("f"));
  // assert(!is_keyword("f(){}"));
}

Token* tokenize(char* p) {
  Token head;
  head.next = null;
  Token* cur = &head;
  while (*p) {
    if (isspace(*p)) {
      p++;
      continue;
    }
    // multi-punct reserved.
    if (startswith(p, "==") || startswith(p, "!=") ||
      startswith(p, "<=") || startswith(p, ">=")) {
      cur = new_token(TokenKind.reserved, cur, p, 2);
      p += 2;
      continue;
    }
    // single-punct reserved.
    if (strchr("+-*/()<>=;{},", *p)) {
      cur = new_token(TokenKind.reserved, cur, p++, 1);
      continue;
    }

    // identifier or ident-like reserved.
    int ident_len = identifier_length(p);
    if (ident_len) {
      TokenKind kind = TokenKind.ident;
      if (is_keyword(p)) {
        kind = TokenKind.reserved;
      }
      cur = new_token(kind, cur, p, ident_len);
      p += ident_len;
      continue;
    }

    if (isdigit(*p)) {
      cur = new_token(TokenKind.num, cur, p, 0);
      cur.val = cast(int) strtol(p, &p, 10);
      cur.len = cast(int)(p - cur.str);
      continue;
    }

    error_at(p, "Cannot tokenize.");
  }

  Token* _ = new_token(TokenKind.eof, cur, p, 1);
  return head.next;
}
