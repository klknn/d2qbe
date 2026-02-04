module d2qbe.parse;

import core.stdc.ctype;
import core.stdc.stdarg;
import core.stdc.stdio;
import core.stdc.string;
import core.stdc.stdlib;

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
    if (strncmp(p, keywords[i], ident_len) == 0) {
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
    if (strchr("+-*/()<>=;{}", *p)) {
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

enum NodeKind {
  add, // +
  sub, // -
  mul, // *
  div, // /
  lt, // <
  le, // <=
  eq, // ==
  ne, // !=
  num, // -?[0-9]+
  assign, // int x = 1
  lvar, // x
  return_, // return x
  if_, // if (...) ...
  while_, // while (...) ...
  for_, // for (...) ...
  block, // { ... }
}

struct Node {
  NodeKind kind;
  Node* lhs, rhs;
  int val; // for NodeKind.num.
  char* ident; // for NodeKind.lvar.

  Node* begin, advance; // for for statement.
  Node* cond, then, else_; // for if/while statement.
  Node* block_list; // for block.
}

Node* new_node(NodeKind kind, Node* lhs, Node* rhs) {
  Node* node = cast(Node*) calloc(1, Node.sizeof);
  node.kind = kind;
  node.lhs = lhs;
  node.rhs = rhs;
  return node;
}

Node* new_node_num(int val) {
  Node* node = cast(Node*) calloc(1, Node.sizeof);
  node.kind = NodeKind.num;
  node.val = val;
  return node;
}

// ENBF: primary = num | ident | "(" expr ")"
Node* primary() {
  if (consume("(")) {
    Node* node = expr();
    expect(")");
    return node;
  }
  Token* tok = consume_ident();
  if (tok) {
    Node* node = cast(Node*) calloc(1, Node.sizeof);
    node.kind = NodeKind.lvar;
    node.ident = cast(char*) calloc(tok.len + 1, 1);
    strncpy(node.ident, tok.str, tok.len);
    // printf("👺 ident %s", node.ident);
    return node;
  }
  return new_node_num(expect_number());
}

// ENBF: unary = ("+" | "-")? unary | primary
Node* unary() {
  if (consume("-")) {
    return new_node(NodeKind.sub, new_node_num(0), unary());
  }
  if (consume("+")) {
    return unary();
  }
  return primary();
}

// ENBF: mul = unary ("*" unary | "/" unary)*
Node* mul() {
  Node* node = unary();
  for (;;) {
    if (consume("*")) {
      node = new_node(NodeKind.mul, node, unary());
    }
    else if (consume("/")) {
      node = new_node(NodeKind.div, node, unary());
    }
    else {
      return node;
    }
  }
}

// ENBF: add = mul ("+" mul | "-" mul)*
Node* add() {
  Node* node = mul();
  for (;;) {
    if (consume("+")) {
      node = new_node(NodeKind.add, node, mul());
    }
    else if (consume("-")) {
      node = new_node(NodeKind.sub, node, mul());
    }
    else {
      return node;
    }
  }
}

// EBNF: relational = add ("<" add | "<=" add | ">" add | ">=" add)*
// e.g. x < y
Node* relational() {
  Node* node = add();
  for (;;) {
    if (consume("<")) {
      node = new_node(NodeKind.lt, node, add());
    }
    else if (consume("<=")) {
      node = new_node(NodeKind.le, node, add());
    }
    else if (consume(">")) {
      node = new_node(NodeKind.lt, add(), node);
    }
    else if (consume(">=")) {
      node = new_node(NodeKind.le, add(), node);
    }
    else {
      return node;
    }
  }
}

// EBNF: equality = relational ("==" relational | "!=" relational)*
// e.g. x == y
Node* equality() {
  Node* node = relational();
  for (;;) {
    if (consume("==")) {
      node = new_node(NodeKind.eq, node, relational());
    }
    else if (consume("!=")) {
      node = new_node(NodeKind.ne, node, relational());
    }
    else {
      return node;
    }
  }
}

// EBNF: assign = equality ("=" assign)?
Node* assign() {
  Node* node = equality();
  if (consume("=")) {
    node = new_node(NodeKind.assign, node, assign());
  }
  return node;
}

// EBNF: expr = assign
Node* expr() {
  return assign();
}

// EBNF: stmt = expr ";"
//            | "{" stmt* "}"
//            | "if" "(" expr ")" stmt ("else" stmt)?
//            | "while" "(" expr ")" stmt
//            | "for" "(" expr? ";" expr? ";" expr? ")" stmt
//            | "return" expr ";"
Node* stmt() {
  Node* node;
  if (consume("{")) {
    Node* block = cast(Node*) calloc(1, Node.sizeof);
    block.kind = NodeKind.block;
    node = block;
    while (!consume("}")) {
      node.block_list = stmt();
      node = node.block_list;
    }
    return block;
  }
  if (consume("return")) {
    node = cast(Node*) calloc(1, Node.sizeof);
    node.kind = NodeKind.return_;
    node.lhs = expr();
  }
  else if (consume("if")) {
    node = cast(Node*) calloc(1, Node.sizeof);
    node.kind = NodeKind.if_;
    expect("(");
    node.cond = expr();
    expect(")");
    node.then = stmt();
    if (consume("else")) {
      node.else_ = stmt();
    }
  }
  else if (consume("while")) {
    node = cast(Node*) calloc(1, Node.sizeof);
    node.kind = NodeKind.while_;
    expect("(");
    node.cond = expr();
    expect(")");
    node.then = stmt();
  }
  else if (consume("for")) {
    node = cast(Node*) calloc(1, Node.sizeof);
    node.kind = NodeKind.for_;
    expect("(");
    if (!consume(";")) {
      node.begin = expr();
      expect(";");
    }
    if (!consume(";")) {
      node.cond = expr();
      expect(";");
    }
    if (!consume(")")) {
      node.advance = expr();
      expect(")");
    }
    node.then = stmt();
  }
  else {
    node = expr();
  }
  // expect(";");
  bool _ = consume(";");
  return node;
}

Node*[100] code;

// EBNF: program = stmt*
void program() {
  int i = 0;
  while (!at_eof()) {
    code[i++] = stmt();
  }
  code[i] = null;
}
