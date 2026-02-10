module d2qbe.parse;

import core.stdc.string;
import core.stdc.stdlib;

import d2qbe.tokenize;

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
  funcall, // f(...)
  defun, // f(...) { ... }
}

struct NodeList {
  NodeList* next;
  Node* value;
}

NodeList* push_back(NodeList* nl, Node* v) {
  nl.value = v;
  nl.next = cast(NodeList*) calloc(1, NodeList.sizeof);
  return nl.next;
}

const int MAX_PARAM_SIZE = 10;

struct Node {
  NodeKind kind;
  Node* lhs, rhs;
  int val; // for NodeKind.num.
  const(Token)* ident; // for NodeKind.lvar.

  Node* begin, advance; // for for statement.
  Node* cond, then, else_; // for if/while statement.
  NodeList statements; // for block/funcdef.
  NodeList args; // for funcall.
  const(Token)*[MAX_PARAM_SIZE] params; // for funcdef..
}

Node* new_node(NodeKind kind) {
  Node* node = cast(Node*) calloc(1, Node.sizeof);
  node.kind = kind;
  return node;
}

Node* new_node_binop(NodeKind kind, Node* lhs, Node* rhs) {
  Node* node = new_node(kind);
  node.lhs = lhs;
  node.rhs = rhs;
  return node;
}

Node* new_node_num(int val) {
  Node* node = new_node(NodeKind.num);
  node.val = val;
  return node;
}

// ENBF: primary = num | ident ("(" expr* ")")? | "(" expr ")"
Node* primary() {
  if (consume("(")) {
    Node* node = expr();
    expect(")");
    return node;
  }
  Token* tok = consume_ident();
  if (tok) {
    Node* node = cast(Node*) calloc(1, Node.sizeof);
    if (consume("(")) {
      node.kind = NodeKind.funcall;
      NodeList* args = &node.args;
      while (!consume(")")) {
        args = push_back(args, expr());
        bool _ = consume(","); // TODO: more strict syntax check.
      }
    }
    else {
      node.kind = NodeKind.lvar;
    }
    node.ident = tok;
    return node;
  }
  return new_node_num(expect_number());
}

// ENBF: unary = ("+" | "-")? unary | primary
Node* unary() {
  if (consume("-")) {
    return new_node_binop(NodeKind.sub, new_node_num(0), unary());
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
      node = new_node_binop(NodeKind.mul, node, unary());
    }
    else if (consume("/")) {
      node = new_node_binop(NodeKind.div, node, unary());
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
      node = new_node_binop(NodeKind.add, node, mul());
    }
    else if (consume("-")) {
      node = new_node_binop(NodeKind.sub, node, mul());
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
      node = new_node_binop(NodeKind.lt, node, add());
    }
    else if (consume("<=")) {
      node = new_node_binop(NodeKind.le, node, add());
    }
    else if (consume(">")) {
      node = new_node_binop(NodeKind.lt, add(), node);
    }
    else if (consume(">=")) {
      node = new_node_binop(NodeKind.le, add(), node);
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
      node = new_node_binop(NodeKind.eq, node, relational());
    }
    else if (consume("!=")) {
      node = new_node_binop(NodeKind.ne, node, relational());
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
    node = new_node_binop(NodeKind.assign, node, assign());
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
  if (consume("{")) {
    Node* block = cast(Node*) calloc(1, Node.sizeof);
    block.kind = NodeKind.block;
    NodeList* stmts = &block.statements;
    while (!consume("}")) {
      stmts = push_back(stmts, stmt());
    }
    return block;
  }
  if (consume("return")) {
    Node* node = new_node(NodeKind.return_);
    node.lhs = expr();
    expect(";");
    return node;
  }
  else if (consume("if")) {
    Node* node = new_node(NodeKind.if_);
    expect("(");
    node.cond = expr();
    expect(")");
    node.then = stmt();
    if (consume("else")) {
      node.else_ = stmt();
    }
    return node;
  }
  else if (consume("while")) {
    Node* node = new_node(NodeKind.while_);
    expect("(");
    node.cond = expr();
    expect(")");
    node.then = stmt();
    return node;
  }
  else if (consume("for")) {
    Node* node = new_node(NodeKind.for_);
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
    return node;
  }
  Node* node = expr();
  expect(";");
  return node;
}

// EBNF: defun = ident "(" ident* ")" stmt;
Node* defun() {
  Node* node = new_node(NodeKind.defun);
  Token* func_name = consume_ident();
  if (!func_name) {
    error_at(token.str, "function name expected.");
  }
  node.ident = func_name;
  expect("(");
  for (int i = 0; !consume(")"); ++i) {
    assert(i < MAX_PARAM_SIZE);
    node.params[i] = consume_ident();
  }
  node.then = stmt();
  return node;
}

Node*[100] code;

// EBNF: program = defun*
void program() {
  int i = 0;
  while (!at_eof()) {
    code[i++] = defun();
  }
  code[i] = null;
}
