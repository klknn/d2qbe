module dqbe.tokenize;

import core.stdc.ctype;
import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.string;

extern (C) FILE* get_stderr();

enum TokenKind {
  TK_reserved,
  TK_ident,
  TK_temp,
  TK_global,
  TK_label,
  TK_num,
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
char* user_input;

void error(const char* msg) {
  fprintf(get_stderr(), "%s\n", msg);
  exit(1);
}

void print_error_line(const char* loc) {
  int pos = cast(int)(loc - user_input);
  fprintf(get_stderr(), "Error at offset: %d\n", pos);
  fprintf(get_stderr(), "%s\n", user_input);
  fprintf(get_stderr(), "%*s", pos, cast(const char*) " ");
  fprintf(get_stderr(), "^ ");
}

void error_at(const char* loc, const char* msg) {
  print_error_line(loc);
  fprintf(get_stderr(), "%s\n", msg);
  exit(1);
}

bool is_token(const char* op) {
  return (token.kind == TokenKind.TK_reserved || token.kind == TokenKind.TK_ident) &&
    strlen(op) == token.len &&
    memcmp(token.str, op, token.len) == 0;
}

bool consume(const char* op) {
  if (is_token(op)) {
    token = token.next;
    return true;
  }
  return false;
}

Token* consume_kind(TokenKind kind) {
  if (token.kind != kind) {
    return null;
  }
  Token* ret = token;
  token = token.next;
  return ret;
}

void expect(const char* op) {
  if (!consume(op)) {
    print_error_line(token.str);
    fprintf(get_stderr(), "Expected token: %s\n", op);
    exit(1);
  }
}

int expect_number() {
  if (token.kind != TokenKind.TK_num) {
    error_at(token.str, "Expected a number");
  }
  int val = token.val;
  token = token.next;
  return val;
}

bool at_eof() {
  return token.kind == TokenKind.TK_eof;
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
  if (isalpha(p[i]) || p[i] == '_' || p[i] == '.') {
    i++;
  } else {
    return 0;
  }
  while (isalnum(p[i]) || p[i] == '_' || p[i] == '.') {
    i++;
  }
  return i;
}

Token* tokenize(char* p) {
  user_input = p;
  Token head;
  head.next = null;
  Token* cur = &head;
  while (*p) {
    if (isspace(*p)) {
      p++;
      continue;
    }
    // line comment (starts with # or //)
    if (*p == '#' || (p[0] == '/' && p[1] == '/')) {
      while (*p && *p != '\n') {
        p++;
      }
      continue;
    }
    // multi-punct reserved
    if (startswith(p, "...")) {
      cur = new_token(TokenKind.TK_reserved, cur, p, 3);
      p = p + 3;
      continue;
    }
    // single-punct reserved
    if (strchr("=,{}()", *p)) {
      cur = new_token(TokenKind.TK_reserved, cur, p++, 1);
      continue;
    }

    // temporaries %name
    if (*p == '%') {
      char* start = p;
      p++;
      int len = identifier_length(p);
      if (len == 0 && isdigit(*p)) {
        // support numbered temporaries like %1, %2
        while (isdigit(p[len])) {
          len++;
        }
      }
      if (len == 0) {
        error_at(start, "invalid temporary name");
      }
      p = p + len;
      cur = new_token(TokenKind.TK_temp, cur, start, cast(int)(p - start));
      continue;
    }

    // globals $name
    if (*p == '$') {
      char* start = p;
      p++;
      int len = identifier_length(p);
      if (len == 0) {
        error_at(start, "invalid global name");
      }
      p = p + len;
      cur = new_token(TokenKind.TK_global, cur, start, cast(int)(p - start));
      continue;
    }

    // labels @name
    if (*p == '@') {
      char* start = p;
      p++;
      int len = identifier_length(p);
      if (len == 0) {
        error_at(start, "invalid label name");
      }
      p = p + len;
      cur = new_token(TokenKind.TK_label, cur, start, cast(int)(p - start));
      continue;
    }

    // identifier (keywords, types, instruction ops)
    int ident_len = identifier_length(p);
    if (ident_len) {
      cur = new_token(TokenKind.TK_ident, cur, p, ident_len);
      p = p + ident_len;
      continue;
    }

    // string literal
    if (*p == '"') {
      char* start = p;
      p++;
      while (*p && *p != '"') {
        if (*p == '\\') p++;
        p++;
      }
      if (!*p) error_at(start, "unclosed string literal");
      p++;
      // Include the double quotes in the token string for easier emission
      cur = new_token(TokenKind.TK_str_literal, cur, start, cast(int)(p - start));
      continue;
    }

    // numbers (could be negative)
    if (isdigit(*p) || (*p == '-' && isdigit(p[1]))) {
      char* start = p;
      cur = new_token(TokenKind.TK_num, cur, p, 0);
      cur.val = cast(int) strtol(p, &p, 10);
      cur.len = cast(int)(p - start);
      continue;
    }

    fprintf(get_stderr(), "Failed at char code: %d\n", cast(int)*p);
    fflush(get_stderr());
    error_at(p, "Cannot tokenize QBE IR.");
  }

  Token* _ = new_token(TokenKind.TK_eof, cur, p, 1);
  return head.next;
}

unittest {
  char* input = cast(char*) "%t1 =w add 5, %t2 # comment\n @label $func \"hello\" -42";
  Token* tok = tokenize(input);
  
  assert(tok.kind == TokenKind.TK_temp);
  assert(tok.len == 3 && memcmp(tok.str, "%t1".ptr, 3) == 0);
  
  tok = tok.next;
  assert(tok.kind == TokenKind.TK_reserved);
  assert(tok.len == 1 && tok.str[0] == '=');
  
  tok = tok.next;
  assert(tok.kind == TokenKind.TK_ident); // 'w' type is TK_ident
  assert(tok.len == 1 && tok.str[0] == 'w');
  
  tok = tok.next;
  assert(tok.kind == TokenKind.TK_ident);
  assert(tok.len == 3 && memcmp(tok.str, "add".ptr, 3) == 0);
  
  tok = tok.next;
  assert(tok.kind == TokenKind.TK_num);
  assert(tok.val == 5);
  
  tok = tok.next;
  assert(tok.kind == TokenKind.TK_reserved);
  assert(tok.len == 1 && tok.str[0] == ',');
  
  tok = tok.next;
  assert(tok.kind == TokenKind.TK_temp);
  assert(tok.len == 3 && memcmp(tok.str, "%t2".ptr, 3) == 0);
  
  tok = tok.next;
  assert(tok.kind == TokenKind.TK_label);
  assert(tok.len == 6 && memcmp(tok.str, "@label".ptr, 6) == 0);
  
  tok = tok.next;
  assert(tok.kind == TokenKind.TK_global);
  assert(tok.len == 5 && memcmp(tok.str, "$func".ptr, 5) == 0);
  
  tok = tok.next;
  assert(tok.kind == TokenKind.TK_str_literal);
  assert(tok.len == 7 && memcmp(tok.str, "\"hello\"".ptr, 7) == 0);
  
  tok = tok.next;
  assert(tok.kind == TokenKind.TK_num);
  assert(tok.val == -42);
  
  tok = tok.next;
  assert(tok.kind == TokenKind.TK_eof);
}
