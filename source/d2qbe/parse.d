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
  addr, // &...
  deref, // *...
  var_decl, // Type x; or Type x = init;
  gvar_decl, // Type x; at global scope
  cast_, // cast(Type) expr
  index, // x[y]
  str_literal, // "hello"
}

struct Type {
  const(char)* name;
  int ptr_depth;
  int array_size;
}

const(char)*[200] known_types;
int known_types_count = 0;

void register_type(const(char)* name) {
  known_types[known_types_count++] = name;
}

bool is_type_name(const(char)* str, int len) {
  if (len == 5 && strncmp(str, "const", 5) == 0) return true;
  if (len == 6 && strncmp(str, "extern", 6) == 0) return true;
  for (int i = 0; i < known_types_count; i++) {
    if (strlen(known_types[i]) == len && strncmp(known_types[i], str, len) == 0) {
      return true;
    }
  }
  return false;
}

void init_types() {
  known_types_count = 0;
  register_type("int");
  register_type("char");
  register_type("bool");
  register_type("void");
}

int get_type_size(Type t) {
  if (t.ptr_depth > 0) return 8;
  if (strcmp(t.name, "int") == 0) return 4;
  if (strcmp(t.name, "char") == 0 || strcmp(t.name, "bool") == 0) return 1;
  return 4; // default
}

Type parse_type() {
  while (consume("const")) {
    if (consume("(")) {
      Type t = parse_type();
      expect(")");
      return t;
    }
  }
  while (consume("extern")) {
    if (consume("(")) {
      consume("C");
      expect(")");
    }
  }
  Token* base_tok = consume_ident();
  if (!base_tok) {
    error_at(token.str, "type name expected");
  }
  char* name = cast(char*) calloc(1, base_tok.len + 1);
  memcpy(name, base_tok.str, base_tok.len);
  Type t;
  t.name = name;
  t.ptr_depth = 0;
  t.array_size = 0;
  while (consume("*")) {
    t.ptr_depth++;
  }
  if (consume("[")) {
    t.array_size = expect_number();
    expect("]");
  }
  return t;
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
  const(Token)*[MAX_PARAM_SIZE] params; // for funcdef.
  
  // New fields for D types
  Type type; // for NodeKind.var_decl/gvar_decl
  Type return_type; // for NodeKind.defun
  Type[MAX_PARAM_SIZE] params_types; // for NodeKind.defun
  bool is_decl_only; // for NodeKind.defun
  bool is_variadic; // for NodeKind.defun
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

// ENBF: primary = num | "true" | "false" | "cast" "(" Type ")" unary | ident ("(" expr* ")")? | "(" expr ")"
Node* primary() {
  Node* node;
  if (consume("(")) {
    node = expr();
    expect(")");
  } else if (consume("true")) {
    node = new_node_num(1);
  } else if (consume("false")) {
    node = new_node_num(0);
  } else if (consume("cast")) {
    expect("(");
    Type cast_type = parse_type();
    expect(")");
    node = new_node(NodeKind.cast_);
    node.type = cast_type;
    node.lhs = unary();
  } else if (token.kind == TokenKind.str_literal) {
    node = new_node(NodeKind.str_literal);
    node.ident = token;
    token = token.next;
  } else if (is_type_name(token.str, token.len)) {
    Type t = parse_type();
    expect(".");
    expect("sizeof");
    node = new_node_num(get_type_size(t));
  } else {
    Token* tok = consume_ident();
    if (tok) {
      node = cast(Node*) calloc(1, Node.sizeof);
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
    }
    else {
      node = new_node_num(expect_number());
    }
  }

  // Parse postfix index operator x[y]
  while (is_token("[")) {
    if (consume("[")) {
      Node* idx = new_node(NodeKind.index);
      idx.lhs = node;
      idx.rhs = expr();
      expect("]");
      node = idx;
    }
  }
  return node;
}

// ENBF: unary ="+"? primary | "-"? unary | ("*" | "&") unary
Node* unary() {
  if (consume("*")) {
    Node* node = new_node(NodeKind.deref);
    node.lhs = unary();
    return node;
  }
  if (consume("&")) {
    Node* node = new_node(NodeKind.addr);
    node.lhs = unary();
    return node;
  }
  if (consume("-")) {
    return new_node_binop(NodeKind.sub, new_node_num(0), unary());
  }
  if (consume("+")) {
    return primary();
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
//            | Type ident ( "=" expr )? ";"
bool is_decl_statement() {
  Token* tok = token;
  while (tok && (tok.len == 5 && strncmp(tok.str, "const", 5) == 0 ||
                 tok.len == 6 && strncmp(tok.str, "extern", 6) == 0)) {
    if (tok.next && tok.next.len == 1 && tok.next.str[0] == '(') {
      tok = tok.next.next;
      while (tok && !(tok.len == 1 && tok.str[0] == ')')) {
        tok = tok.next;
      }
      if (tok) tok = tok.next;
    } else {
      tok = tok.next;
    }
  }
  if (!tok || !is_type_name(tok.str, tok.len)) {
    return false;
  }
  tok = tok.next;
  while (tok && tok.len == 1 && tok.str[0] == '*') {
    tok = tok.next;
  }
  if (tok && tok.len == 1 && tok.str[0] == '[') {
    tok = tok.next;
    if (tok && tok.kind == TokenKind.num) tok = tok.next;
    if (tok && tok.len == 1 && tok.str[0] == ']') tok = tok.next;
  }
  return tok && tok.kind == TokenKind.ident;
}

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
  if (is_decl_statement()) {
    Type t = parse_type();
    Token* ident = consume_ident();
    if (!ident) {
      error_at(token.str, "variable name expected");
    }
    Node* node = new_node(NodeKind.var_decl);
    node.type = t;
    node.ident = ident;
    if (consume("=")) {
      node.lhs = expr();
    }
    expect(";");
    return node;
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
      if (is_decl_statement()) {
        Type t = parse_type();
        Token* ident = consume_ident();
        Node* decl = new_node(NodeKind.var_decl);
        decl.type = t;
        decl.ident = ident;
        if (consume("=")) {
          decl.lhs = expr();
        }
        node.begin = decl;
      } else {
        node.begin = expr();
      }
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

void parse_struct() {
  expect("struct");
  Token* name_tok = consume_ident();
  if (!name_tok) error_at(token.str, "struct name expected");
  char* name = cast(char*) calloc(1, name_tok.len + 1);
  memcpy(name, name_tok.str, name_tok.len);
  register_type(name);
  expect("{");
  while (!consume("}")) {
    parse_type();
    consume_ident();
    expect(";");
  }
}

void parse_enum() {
  expect("enum");
  Token* name_tok = consume_ident();
  if (!name_tok) error_at(token.str, "enum name expected");
  char* name = cast(char*) calloc(1, name_tok.len + 1);
  memcpy(name, name_tok.str, name_tok.len);
  register_type(name);
  expect("{");
  while (!consume("}")) {
    consume_ident();
    if (consume("=")) {
      expect_number();
    }
    consume(",");
  }
}

Node* parse_function(Type ret_type, Token* func_name) {
  Node* node = new_node(NodeKind.defun);
  node.ident = func_name;
  node.return_type = ret_type;
  
  expect("(");
  int i = 0;
  while (!consume(")")) {
    if (consume("...")) {
      node.is_variadic = true;
      expect(")");
      break;
    }
    assert(i < MAX_PARAM_SIZE);
    node.params_types[i] = parse_type();
    node.params[i] = consume_ident();
    i++;
    consume(",");
  }
  
  if (consume(";")) {
    node.is_decl_only = true;
  } else {
    node.then = stmt();
    node.is_decl_only = false;
  }
  return node;
}

Node*[500] code;

// EBNF: program = (struct_decl | enum_decl | global_decl | defun | untyped_defun)*
void program() {
  init_types();
  int i = 0;
  while (!at_eof()) {
    if (consume(";")) {
      continue;
    }
    if (consume("unittest")) {
      stmt();
      continue;
    }
    if (is_token("struct")) {
      parse_struct();
      continue;
    }
    if (is_token("enum")) {
      parse_enum();
      continue;
    }
    
    if (is_type_name(token.str, token.len)) {
      Type t = parse_type();
      Token* ident = consume_ident();
      if (!ident) {
        error_at(token.str, "identifier expected at top level");
      }
      if (is_token("(")) {
        code[i++] = parse_function(t, ident);
      } else {
        Node* gvar = new_node(NodeKind.gvar_decl);
        gvar.type = t;
        gvar.ident = ident;
        if (consume("=")) {
          gvar.lhs = expr();
        }
        expect(";");
        code[i++] = gvar;
      }
    } else {
      // Untyped function definition for legacy test support
      Token* ident = consume_ident();
      if (!ident) {
        error_at(token.str, "identifier expected at top level");
      }
      Type t;
      t.name = "int";
      t.ptr_depth = 0;
      t.array_size = 0;
      
      Node* node = new_node(NodeKind.defun);
      node.ident = ident;
      node.return_type = t;
      expect("(");
      int p_idx = 0;
      while (!consume(")")) {
        assert(p_idx < MAX_PARAM_SIZE);
        Type pt;
        pt.name = "int";
        pt.ptr_depth = 0;
        pt.array_size = 0;
        node.params_types[p_idx] = pt;
        node.params[p_idx] = consume_ident();
        p_idx++;
        consume(",");
      }
      node.then = stmt();
      node.is_decl_only = false;
      code[i++] = node;
    }
  }
  code[i] = null;
}

unittest {
  init_types();
  
  // Test 1: variable declaration parsing
  user_input = cast(char*) "int x = 42;";
  token = tokenize(user_input);
  Node* node = stmt();
  assert(node != null);
  assert(node.kind == NodeKind.var_decl);
  assert(strncmp(node.ident.str, "x", node.ident.len) == 0);
  assert(strcmp(node.type.name, "int") == 0);
  assert(node.lhs.kind == NodeKind.num);
  assert(node.lhs.val == 42);
  
  // Test 2: typed function parsing
  user_input = cast(char*) "int main() { return 0; }";
  token = tokenize(user_input);
  program();
  assert(code[0] != null);
  assert(code[0].kind == NodeKind.defun);
  assert(strncmp(code[0].ident.str, "main", code[0].ident.len) == 0);
  assert(strcmp(code[0].return_type.name, "int") == 0);

  // Test 3: cast parsing
  user_input = cast(char*) "cast(char*) x;";
  token = tokenize(user_input);
  Node* cast_node = stmt();
  assert(cast_node != null);
  assert(cast_node.kind == NodeKind.cast_);
  assert(strcmp(cast_node.type.name, "char") == 0);
  assert(cast_node.type.ptr_depth == 1);
  assert(cast_node.lhs.kind == NodeKind.lvar);

  // Test 4: index parsing
  user_input = cast(char*) "y[0];";
  token = tokenize(user_input);
  Node* idx_node = stmt();
  assert(idx_node != null);
  assert(idx_node.kind == NodeKind.index);
  assert(idx_node.lhs.kind == NodeKind.lvar);
  assert(idx_node.rhs.kind == NodeKind.num);
  assert(idx_node.rhs.val == 0);

  // Test 5: sizeof parsing
  user_input = cast(char*) "int.sizeof;";
  token = tokenize(user_input);
  Node* sz_node = stmt();
  assert(sz_node != null);
  assert(sz_node.kind == NodeKind.num);
  assert(sz_node.val == 4);

  // Test 6: string literal tokenization and parsing
  user_input = cast(char*) "\"hello\";";
  token = tokenize(user_input);
  assert(token.kind == TokenKind.str_literal);
  Node* str_node = stmt();
  assert(str_node != null);
  assert(str_node.kind == NodeKind.str_literal);
  assert(strncmp(str_node.ident.str, "hello", str_node.ident.len) == 0);
}

