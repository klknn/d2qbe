import core.stdc.ctype;
import core.stdc.stdarg;
import core.stdc.stdio;
import core.stdc.string;
import core.stdc.stdlib;

enum TokenKind {
  reserved,
  num,
  eof,
}

struct Token {
  TokenKind kind;
  Token* next;
  int val;
  char* str;
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

// Consumes one token and returns true if the token is op.
bool consume(char op) {
  if (token.kind != TokenKind.reserved || token.str[0] != op) {
    return false;
  }
  token = token.next;
  return true;
}

void expect(char op) {
  if (!consume(op)) {
    error_at(token.str, "Expected token %c", op);
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

Token* new_token(TokenKind kind, Token* cur, char* str) {
  Token* tok = cast(Token*) calloc(1, Token.sizeof);
  tok.kind = kind;
  tok.str = str;
  cur.next = tok;
  return tok;
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
    if (strchr("+-*/()", *p)) {
      cur = new_token(TokenKind.reserved, cur, p++);
      continue;
    }
    if (isdigit(*p)) {
      cur = new_token(TokenKind.num, cur, p);
      cur.val = cast(int) strtol(p, &p, 10);
      continue;
    }

    error_at(p, "Cannot tokenize.");
  }

  Token* _ = new_token(TokenKind.eof, cur, p);
  return head.next;
}

// Syntax EBNF:
// expr    = mul ("+" mul | "-" mul)*
// mul     = primary ("*" primary | "/" primary)*
// primary = num | "(" expr ")"
enum NodeKind {
  add,
  sub,
  mul,
  div,
  num
}

struct Node {
  NodeKind kind;
  Node* lhs, rhs;
  int val;
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

Node* num();

Node* primary() {
  if (consume('(')) {
    Node* node = expr();
    expect(')');
    return node;
  }
  return new_node_num(expect_number());
}

Node* mul() {
  Node* node = primary();
  for (;;) {
    if (consume('*')) {
      node = new_node(NodeKind.mul, node, primary());
    }
    else if (consume('/')) {
      node = new_node(NodeKind.div, node, primary());
    }
    else {
      return node;
    }
  }
}

Node* expr() {
  Node* node = mul();
  for (;;) {
    if (consume('+')) {
      node = new_node(NodeKind.add, node, mul());
    }
    else if (consume('-')) {
      node = new_node(NodeKind.sub, node, mul());
    }
    else {
      return node;
    }
  }
}

const(char)* node_kind_to_str(NodeKind kind) {
  final switch (kind) {
  case NodeKind.add:
    return "add";
  case NodeKind.sub:
    return "sub";
  case NodeKind.mul:
    return "mul";
  case NodeKind.div:
    return "div";
  case NodeKind.num:
    return "num";
  }
}

int gen(Node* node, int ret_var) {
  if (node.kind == NodeKind.num) {
    printf("  %%t%d =w copy %d\n", ret_var + 1, node.val);
    return ret_var + 1;
  }
  int l = gen(node.lhs, ret_var);
  int r = gen(node.rhs, l);
  printf("  %%t%d =w %s %%t%d, %%t%d\n", r + 1, node_kind_to_str(node.kind), l, r);
  return r + 1;
}

extern (C)
int main(int argc, char** argv) {
  if (argc != 2) {
    fprintf(stderr, "wrong number of args\n");
    return 1;
  }

  user_input = argv[1];
  token = tokenize(argv[1]);
  Node* node = expr();

  printf("export function w $main() {\n");
  printf("@main\n");
  int ret = gen(node, 0);
  printf("  ret %%t%d\n", ret);
  printf("}\n");

  return 0;
}
