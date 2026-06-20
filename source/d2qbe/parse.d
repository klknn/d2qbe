module d2qbe.parse;

import core.stdc.string;
import core.stdc.stdlib;
import core.stdc.stdio;

import d2qbe.tokenize;

extern (C) FILE* get_stderr();

enum NodeKind {
  NK_add, // +
  NK_sub, // -
  NK_mul, // *
  NK_div, // /
  NK_lt_op, // <
  NK_le, // <=
  NK_eq, // ==
  NK_ne, // !=
  NK_num, // -?[0-9]+
  NK_assign, // int x = 1
  NK_lvar, // x
  NK_return_, // return x
  NK_if_, // if (...) ...
  NK_while_, // while (...) ...
  NK_for_, // for (...) ...
  NK_block, // { ... }
  NK_funcall, // f(...)
  NK_defun, // f(...) { ... }
  NK_addr, // &...
  NK_deref, // *...
  NK_var_decl, // Type x; or Type x = init;
  NK_gvar_decl, // Type x; at global scope
  NK_cast_, // cast(Type) expr
  NK_index, // x[y]
  NK_str_literal, // "hello"
  NK_assert_, // assert(x)
  NK_dot, // x.y
  NK_logical_and, // &&
  NK_logical_or, // ||
  NK_logical_not, // !
  NK_pre_inc, // ++x
  NK_pre_dec, // --x
  NK_post_inc, // x++
  NK_post_dec, // x--
  NK_continue_, // continue;
  NK_break_, // break;
}

struct Type {
  const(char)* name;
  int ptr_depth;
  int array_size;
}

struct Member {
  const(char)* name;
  Type type;
  int offset;
}

struct StructType {
  const(char)* name;
  Member[20] members;
  int members_count;
  int size;
  int alignment;
}

StructType[50] registered_structs;
int registered_structs_count = 0;

struct FunctionSymbol {
  const(char)* name;
  bool is_variadic;
  int num_params;
  Type return_type;
}
FunctionSymbol[200] registered_functions;
int registered_functions_count = 0;

/**
 * Registers a function signature.
 */
void register_function(const(char)* name, bool is_variadic, int num_params, Type* return_type) {
  for (int i = 0; i < registered_functions_count; i++) {
    if (strcmp(registered_functions[i].name, name) == 0) {
      return;
    }
  }
  assert(registered_functions_count < 200, "registered_functions overflow");
  registered_functions[registered_functions_count].name = name;
  registered_functions[registered_functions_count].is_variadic = is_variadic;
  registered_functions[registered_functions_count].num_params = num_params;
  registered_functions[registered_functions_count].return_type = *return_type;
  const(char)* ret_name = return_type.name;
  if (!ret_name) ret_name = "null";
  printf("# DEBUG: register_function '%s' ret='%s' ptr_depth=%d\n",
         name, ret_name, return_type.ptr_depth);
  registered_functions_count++;
}

/**
 * Finds a registered function signature by name.
 * Returns: pointer to FunctionSymbol if found, null otherwise.
 */
FunctionSymbol* find_function(const(char)* name) {
  for (int i = 0; i < registered_functions_count; i++) {
    if (strcmp(registered_functions[i].name, name) == 0) {
      return &registered_functions[i];
    }
  }
  return null;
}

/**
 * Finds a registered struct type by name.
 * Returns: pointer to StructType if found, null otherwise.
 */
StructType* find_struct(const(char)* name) {
  for (int i = 0; i < registered_structs_count; i++) {
    if (strcmp(registered_structs[i].name, name) == 0) {
      return &registered_structs[i];
    }
  }
  return null;
}

/**
 * Finds a member in a struct by name.
 * Returns: pointer to Member if found, null otherwise.
 */
Member* find_member(StructType* st, const(Token)* ident) {
  printf("# DEBUG: find_member in struct '%s' looking for '%.*s'\n", st.name, ident.len, ident.str);
  for (int i = 0; i < st.members_count; i++) {
    printf("# DEBUG:   checking member '%s'\n", st.members[i].name);
    if (strlen(st.members[i].name) == ident.len && strncmp(st.members[i].name, ident.str, ident.len) == 0) {
      printf("# DEBUG:     FOUND!\n");
      return &st.members[i];
    }
  }
  printf("# DEBUG:     NOT FOUND!\n");
  return null;
}

struct Constant {
  const(char)* name;
  int val;
}

Constant[500] constants;
int constants_count = 0;

/**
 * Adds a compile-time constant (enum member) to the registry.
 */
void add_constant(const(char)* name, int val) {
  assert(constants_count < 500, "constants overflow");
  constants[constants_count].name = name;
  constants[constants_count].val = val;
  constants_count++;
}

/**
 * Looks up a compile-time constant by name.
 * Returns: true if found (value written to val), false otherwise.
 */
bool lookup_constant(const(Token)* ident, int* val) {
  for (int i = 0; i < constants_count; i++) {
    if (strlen(constants[i].name) == ident.len && strncmp(constants[i].name, ident.str, ident.len) == 0) {
      *val = constants[i].val;
      return true;
    }
  }
  return false;
}

const(char)*[200] known_types;
int known_types_count = 0;

/**
 * Registers a new type name in the compiler.
 */
void register_type(const(char)* name) {
  assert(known_types_count < 200, "known_types overflow");
  known_types[known_types_count++] = name;
}

/**
 * Checks if the given string is a registered type name.
 */
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

/**
 * Initializes the built-in types.
 */
void init_types() {
  known_types_count = 0;
  register_type("int");
  register_type("char");
  register_type("bool");
  register_type("void");
}

/**
 * Computes the size in bytes of a D type.
 */
int get_type_size(Type* t) {
  int base_size;
  if (t.ptr_depth > 0) {
    base_size = 8;
  } else {
    base_size = 4;
    if (strcmp(t.name, "int") == 0) base_size = 4;
    else if (strcmp(t.name, "char") == 0 || strcmp(t.name, "bool") == 0) base_size = 1;
    else if (strcmp(t.name, "void") == 0) base_size = 1;
    else {
      StructType* st = find_struct(t.name);
      if (st) {
        base_size = st.size;
      }
    }
  }
  if (t.array_size > 0) {
    return t.array_size * base_size;
  }
  return base_size;
}

/**
 * Computes the alignment requirement in bytes of a D type.
 */
int get_type_alignment(Type* t) {
  if (t.ptr_depth > 0) return 8;
  if (strcmp(t.name, "int") == 0) return 4;
  if (strcmp(t.name, "char") == 0 || strcmp(t.name, "bool") == 0) return 1;
  StructType* st = find_struct(t.name);
  if (st) {
    return st.alignment;
  }
  return 4;
}

/**
 * Parses a type declaration (e.g. const(int)*[10]).
 */
void parse_type(Type* out_type) {
  Type t;
  bool is_const_paren = false;
  while (consume("const")) {
    if (consume("(")) {
      parse_type(&t);
      expect(")");
      is_const_paren = true;
      break;
    }
  }
  
  if (!is_const_paren) {
    while (consume("extern")) {
      if (consume("(")) {
        Token* tok = consume_ident();
        if (!tok || tok.len != 1 || tok.str[0] != 'C') {
          error_at(token.str, "Expected 'C'");
        }
        expect(")");
      }
    }
    Token* base_tok = consume_ident();
    if (!base_tok) {
      error_at(token.str, "type name expected");
    }
    char* name = cast(char*) calloc(1, base_tok.len + 1);
    memcpy(name, base_tok.str, base_tok.len);
    t.name = name;
    t.ptr_depth = 0;
    t.array_size = 0;
  }
  
  while (consume("*")) {
    t.ptr_depth++;
  }
  if (consume("[")) {
    int size;
    Token* tok = consume_ident();
    if (tok) {
      if (!lookup_constant(tok, &size)) {
        error_at(tok.str, "unknown constant for array size");
      }
    } else {
      size = expect_number();
    }
    t.array_size = size;
    expect("]");
  }
  *out_type = t;
}

struct NodeList {
  NodeList* next;
  Node* value;
}

/**
 * Appends a node to the node list.
 * Returns: pointer to the next list node.
 */
NodeList* push_back(NodeList* nl, Node* v) {
  nl.value = v;
  nl.next = cast(NodeList*) calloc(1, NodeList.sizeof);
  return nl.next;
}

enum MAX_PARAM_SIZE = 10;

struct Node {
  NodeKind kind;
  Node* lhs; Node* rhs;
  int val; // for NodeKind.NK_num.
  const(Token)* ident; // for NodeKind.NK_lvar.

  Node* begin; Node* advance; // for for statement.
  Node* cond; Node* then; Node* else_; // for if/while statement.
  NodeList statements; // for block/funcdef.
  NodeList args; // for funcall.
  const(Token)*[MAX_PARAM_SIZE] params; // for funcdef.
  
  // New fields for D types
  Type type; // for NodeKind.NK_var_decl/gvar_decl
  Type return_type; // for NodeKind.NK_defun
  Type[MAX_PARAM_SIZE] params_types; // for NodeKind.NK_defun
  bool is_decl_only; // for NodeKind.NK_defun
  bool is_variadic; // for NodeKind.NK_defun
}

/**
 * Creates a new AST node of the given kind.
 */
Node* new_node(NodeKind kind) {
  Node* node = cast(Node*) calloc(1, Node.sizeof);
  node.kind = kind;
  return node;
}

/**
 * Creates a new binary operator AST node.
 */
Node* new_node_binop(NodeKind kind, Node* lhs, Node* rhs) {
  Node* node = new_node(kind);
  node.lhs = lhs;
  node.rhs = rhs;
  return node;
}

/**
 * Creates a new number literal AST node.
 */
Node* new_node_num(int val) {
  Node* node = new_node(NodeKind.NK_num);
  node.val = val;
  return node;
}

// ENBF: primary = num | "true" | "false" | "cast" "(" Type ")" unary | ident ("(" expr* ")")? | "(" expr ")"
/**
 * Parses a primary expression.
 * EBNF: primary = num | "true" | "false" | "cast" "(" Type ")" unary | ident ("(" expr* ")")? | "(" expr ")" | postfix_ops
 */
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
    Type cast_type;
    parse_type(&cast_type);
    expect(")");
    node = new_node(NodeKind.NK_cast_);
    node.type = cast_type;
    node.lhs = unary();
  } else if (token.kind == TokenKind.TK_str_literal) {
    node = new_node(NodeKind.NK_str_literal);
    node.ident = token;
    token = token.next;
  } else if (is_type_name(token.str, token.len)) {
    Token* next = token.next;
    while (next && next.kind == TokenKind.TK_reserved && next.len == 1 && next.str[0] == '*') {
      next = next.next;
    }
    bool is_sizeof = false;
    if (next && next.kind == TokenKind.TK_reserved && next.len == 1 && next.str[0] == '.') {
      Token* next2 = next.next;
      if (next2 && next2.kind == TokenKind.TK_reserved && next2.len == 6 && strncmp(next2.str, "sizeof", 6) == 0) {
        is_sizeof = true;
      }
    }
    
    if (is_sizeof) {
      Type t;
      parse_type(&t);
      expect(".");
      expect("sizeof");
      node = new_node_num(get_type_size(&t));
    } else {
      Type dummy;
      parse_type(&dummy);
      expect(".");
      node = primary();
    }
  } else {
    Token* tok = consume_ident();
    if (tok) {
      int const_val;
      if (lookup_constant(tok, &const_val)) {
        node = new_node_num(const_val);
      } else {
        node = cast(Node*) calloc(1, Node.sizeof);
        if (consume("(")) {
          node.kind = NodeKind.NK_funcall;
          NodeList* args = &node.args;
          while (!consume(")")) {
            args = push_back(args, expr());
            bool _ = consume(","); // TODO: more strict syntax check.
          }
        }
        else {
          node.kind = NodeKind.NK_lvar;
        }
        node.ident = tok;
      }
    }
    else {
      node = new_node_num(expect_number());
    }
  }

  // Parse postfix operators x[y] and x.y
  for (;;) {
    if (consume("[")) {
      Node* idx = new_node(NodeKind.NK_index);
      idx.lhs = node;
      idx.rhs = expr();
      expect("]");
      node = idx;
    } else if (consume(".")) {
      Token* mem_tok = consume_ident();
      if (!mem_tok) error_at(token.str, "member name expected");
      Node* dot_node = new_node(NodeKind.NK_dot);
      dot_node.lhs = node;
      dot_node.ident = mem_tok;
      node = dot_node;
    } else if (consume("++")) {
      Node* inc = new_node(NodeKind.NK_post_inc);
      inc.lhs = node;
      node = inc;
    } else if (consume("--")) {
      Node* dec = new_node(NodeKind.NK_post_dec);
      dec.lhs = node;
      node = dec;
    } else {
      break;
    }
  }
  return node;
}

/**
 * Parses a unary expression.
 * EBNF: unary = "+"? primary | "-"? unary | ("*" | "&") unary
 */
Node* unary() {
  if (consume("++")) {
    Node* node = new_node(NodeKind.NK_pre_inc);
    node.lhs = unary();
    return node;
  }
  if (consume("--")) {
    Node* node = new_node(NodeKind.NK_pre_dec);
    node.lhs = unary();
    return node;
  }
  if (consume("*")) {
    Node* node = new_node(NodeKind.NK_deref);
    node.lhs = unary();
    return node;
  }
  if (consume("&")) {
    Node* node = new_node(NodeKind.NK_addr);
    node.lhs = unary();
    return node;
  }
  if (consume("-")) {
    return new_node_binop(NodeKind.NK_sub, new_node_num(0), unary());
  }
  if (consume("+")) {
    return primary();
  }
  if (consume("!")) {
    Node* node = new_node(NodeKind.NK_logical_not);
    node.lhs = unary();
    return node;
  }
  return primary();
}

/**
 * Parses a multiplicative expression (*, /).
 * EBNF: mul = unary ("*" unary | "/" unary)*
 */
Node* parse_mul() {
  Node* node = unary();
  for (;;) {
    if (consume("*")) {
      printf("# DEBUG: parse_mul matched '*'\n");
      node = new_node_binop(NodeKind.NK_mul, node, unary());
      printf("# DEBUG: parse_mul created NodeKind.NK_mul=%d node.kind=%d\n", NodeKind.NK_mul, node.kind);
    }
    else if (consume("/")) {
      node = new_node_binop(NodeKind.NK_div, node, unary());
    }
    else {
      return node;
    }
  }
}

/**
 * Parses an additive expression (+, -).
 * EBNF: add = mul ("+" mul | "-" mul)*
 */
Node* parse_add() {
  Node* node = parse_mul();
  for (;;) {
    if (consume("+")) {
      node = new_node_binop(NodeKind.NK_add, node, parse_mul());
    }
    else if (consume("-")) {
      node = new_node_binop(NodeKind.NK_sub, node, parse_mul());
    }
    else {
      return node;
    }
  }
}

/**
 * Parses a relational expression (<, <=, >, >=).
 * EBNF: relational = add ("<" add | "<=" add | ">" add | ">=" add)*
 */
Node* relational() {
  Node* node = parse_add();
  for (;;) {
    if (consume("<")) {
      node = new_node_binop(NodeKind.NK_lt_op, node, parse_add());
    }
    else if (consume("<=")) {
      node = new_node_binop(NodeKind.NK_le, node, parse_add());
    }
    else if (consume(">")) {
      node = new_node_binop(NodeKind.NK_lt_op, parse_add(), node);
    }
    else if (consume(">=")) {
      node = new_node_binop(NodeKind.NK_le, parse_add(), node);
    }
    else {
      return node;
    }
  }
}

/**
 * Parses an equality expression (==, !=).
 * EBNF: equality = relational ("==" relational | "!=" relational)*
 */
Node* equality() {
  Node* node = relational();
  for (;;) {
    if (consume("==")) {
      node = new_node_binop(NodeKind.NK_eq, node, relational());
    }
    else if (consume("!=")) {
      node = new_node_binop(NodeKind.NK_ne, node, relational());
    }
    else {
      return node;
    }
  }
}

/**
 * Parses a logical AND expression (&&).
 * EBNF: logical_and = equality ("&&" equality)*
 */
Node* parse_logical_and() {
  Node* node = equality();
  for (;;) {
    if (consume("&&")) {
      node = new_node_binop(NodeKind.NK_logical_and, node, equality());
    } else {
      return node;
    }
  }
}

/**
 * Parses a logical OR expression (||).
 * EBNF: logical_or = logical_and ("||" logical_and)*
 */
Node* parse_logical_or() {
  Node* node = parse_logical_and();
  for (;;) {
    if (consume("||")) {
      node = new_node_binop(NodeKind.NK_logical_or, node, parse_logical_and());
    } else {
      return node;
    }
  }
}

/**
 * Parses an assignment expression (=).
 * EBNF: assign = logical_or ("=" assign)?
 */
Node* parse_assign() {
  Node* node = parse_logical_or();
  if (consume("=")) {
    node = new_node_binop(NodeKind.NK_assign, node, parse_assign());
  }
  return node;
}

/**
 * Parses an expression.
 * EBNF: expr = assign
 */
Node* expr() {
  return parse_assign();
}

// EBNF: stmt = expr ";"
//            | "{" stmt* "}"
//            | "if" "(" expr ")" stmt ("else" stmt)?
//            | "while" "(" expr ")" stmt
//            | "for" "(" expr? ";" expr? ";" expr? ")" stmt
//            | "return" expr ";"
//            | Type ident ( "=" expr )? ";"
/**
 * Checks if the upcoming tokens look like a variable declaration statement.
 * Returns: true if it is a declaration, false otherwise.
 */
bool is_decl_statement() {
  Token* tok = token;
  bool has_type_name = false;
  while (tok && (tok.len == 5 && strncmp(tok.str, "const", 5) == 0 ||
                 tok.len == 6 && strncmp(tok.str, "extern", 6) == 0)) {
    if (tok.next && tok.next.len == 1 && tok.next.str[0] == '(') {
      Token* type_tok = tok.next.next;
      if (type_tok && is_type_name(type_tok.str, type_tok.len)) {
        has_type_name = true;
      }
      tok = type_tok.next;
      while (tok && !(tok.len == 1 && tok.str[0] == ')')) {
        tok = tok.next;
      }
      if (tok) tok = tok.next;
    } else {
      tok = tok.next;
    }
  }
  if (!has_type_name) {
    if (!tok || !is_type_name(tok.str, tok.len)) {
      return false;
    }
    tok = tok.next;
  }
  while (tok && tok.len == 1 && tok.str[0] == '*') {
    tok = tok.next;
  }
  if (tok && tok.len == 1 && tok.str[0] == '[') {
    tok = tok.next;
    if (tok && (tok.kind == TokenKind.TK_num || tok.kind == TokenKind.TK_identifier)) tok = tok.next;
    if (tok && tok.len == 1 && tok.str[0] == ']') tok = tok.next;
  }
  return tok && tok.kind == TokenKind.TK_identifier;
}

/**
 * Parses a statement.
 * EBNF: stmt = expr ";" | "{" stmt* "}" | "if" "(" expr ")" stmt ("else" stmt)? | "while" "(" expr ")" stmt | "for" "(" expr? ";" expr? ";" expr? ")" stmt | "return" expr ";" | Type ident ( "=" expr )? ";"
 */
Node* stmt() {
  if (consume("{")) {
    Node* block_node = cast(Node*) calloc(1, Node.sizeof);
    block_node.kind = NodeKind.NK_block;
    NodeList* stmts = &block_node.statements;
    while (!consume("}")) {
      stmts = push_back(stmts, stmt());
    }
    return block_node;
  }
  if (is_decl_statement()) {
    Type t;
    parse_type(&t);
    Token* ident = consume_ident();
    if (!ident) {
      error_at(token.str, "variable name expected");
    }
    Node* node = new_node(NodeKind.NK_var_decl);
    node.type = t;
    node.ident = ident;
    if (consume("=")) {
      node.lhs = expr();
    }
    expect(";");
    return node;
  }
  if (consume("assert")) {
    Node* node = new_node(NodeKind.NK_assert_);
    expect("(");
    node.cond = expr();
    if (consume(",")) {
      expr();
    }
    expect(")");
    expect(";");
    return node;
  }
  if (consume("continue")) {
    Node* node = new_node(NodeKind.NK_continue_);
    expect(";");
    return node;
  }
  if (consume("break")) {
    Node* node = new_node(NodeKind.NK_break_);
    expect(";");
    return node;
  }
  if (consume("return")) {
    Node* node = new_node(NodeKind.NK_return_);
    if (!consume(";")) {
      node.lhs = expr();
      expect(";");
    }
    return node;
  }
  else if (consume("if")) {
    Node* node = new_node(NodeKind.NK_if_);
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
    Node* node = new_node(NodeKind.NK_while_);
    expect("(");
    node.cond = expr();
    expect(")");
    node.then = stmt();
    return node;
  }
  else if (consume("for")) {
    Node* node = new_node(NodeKind.NK_for_);
    expect("(");
    if (!consume(";")) {
      if (is_decl_statement()) {
        Type t;
        parse_type(&t);
        Token* ident = consume_ident();
        Node* decl = new_node(NodeKind.NK_var_decl);
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

/**
 * Parses a struct declaration and registers its type and layout.
 * EBNF: struct_decl = "struct" ident "{" (Type ident ";")* "}"
 */
void parse_struct() {
  expect("struct");
  Token* name_tok = consume_ident();
  if (!name_tok) error_at(token.str, "struct name expected");
  char* name = cast(char*) calloc(1, name_tok.len + 1);
  memcpy(name, name_tok.str, name_tok.len);
  
  register_type(name);
  
  StructType st;
  st.name = name;
  st.members_count = 0;
  st.size = 0;
  st.alignment = 1;
  
  expect("{");
  while (!consume("}")) {
    Type t;
    parse_type(&t);
    Token* mem_ident = consume_ident();
    if (!mem_ident) error_at(token.str, "member name expected");
    expect(";");
    
    char* mem_name = cast(char*) calloc(1, mem_ident.len + 1);
    memcpy(mem_name, mem_ident.str, mem_ident.len);
    
    int mem_size = get_type_size(&t);
    int mem_align = get_type_alignment(&t);
    
    st.size = ((st.size + mem_align - 1) / mem_align) * mem_align;
    
    Member m;
    m.name = mem_name;
    m.type = t;
    m.offset = st.size;
    
    assert(st.members_count < 20, "struct members overflow");
    st.members[st.members_count++] = m;
    st.size = st.size + mem_size;
    if (mem_align > st.alignment) {
      st.alignment = mem_align;
    }
  }
  
  st.size = ((st.size + st.alignment - 1) / st.alignment) * st.alignment;
  
  assert(registered_structs_count < 50, "registered_structs overflow");
  registered_structs[registered_structs_count++] = st;
}

/**
 * Parses an enum declaration (manifest constants, anonymous, or named).
 * EBNF: enum_decl = "enum" "{" (ident ("=" num)? ",")* "}"
 *                 | "enum" ident "=" num ";"
 *                 | "enum" ident "{" (ident ("=" num)? ",")* "}"
 */
void parse_enum() {
  expect("enum");
  if (consume("{")) {
    int next_val = 0;
    while (!consume("}")) {
      Token* mem_tok = consume_ident();
      if (!mem_tok) error_at(token.str, "member name expected");
      if (consume("=")) {
        next_val = expect_number();
      }
      char* mem_name = cast(char*) calloc(1, mem_tok.len + 1);
      memcpy(mem_name, mem_tok.str, mem_tok.len);
      add_constant(mem_name, next_val);
      next_val++;
      consume(",");
    }
    return;
  }
  
  Token* name_tok = consume_ident();
  if (!name_tok) error_at(token.str, "enum name or '{' expected");
  
  if (consume("=")) {
    int val = expect_number();
    expect(";");
    char* name = cast(char*) calloc(1, name_tok.len + 1);
    memcpy(name, name_tok.str, name_tok.len);
    add_constant(name, val);
    return;
  }
  
  char* name = cast(char*) calloc(1, name_tok.len + 1);
  memcpy(name, name_tok.str, name_tok.len);
  register_type(name);
  
  expect("{");
  int next_val = 0;
  while (!consume("}")) {
    Token* mem_tok = consume_ident();
    if (!mem_tok) error_at(token.str, "member name expected");
    if (consume("=")) {
      next_val = expect_number();
    }
    char* mem_name = cast(char*) calloc(1, mem_tok.len + 1);
    memcpy(mem_name, mem_tok.str, mem_tok.len);
    add_constant(mem_name, next_val);
    next_val++;
    consume(",");
  }
}

/**
 * Parses a function declaration or definition.
 * EBNF: defun = Type ident "(" parameters? ")" (stmt | ";")
 */
Node* parse_function(Type* ret_type, Token* func_name) {
  Node* node = new_node(NodeKind.NK_defun);
  node.ident = func_name;
  node.return_type = *ret_type;
  
  expect("(");
  int i = 0;
  while (!consume(")")) {
    if (consume("...")) {
      node.is_variadic = true;
      expect(")");
      break;
    }
    assert(i < MAX_PARAM_SIZE);
    parse_type(&node.params_types[i]);
    node.params[i] = consume_ident();
    i++;
    consume(",");
  }
  
  char* name = cast(char*) calloc(1, func_name.len + 1);
  memcpy(name, func_name.str, func_name.len);
  register_function(name, node.is_variadic, i, ret_type);

  if (consume(";")) {
    node.is_decl_only = true;
  } else {
    node.then = stmt();
    node.is_decl_only = false;
  }
  return node;
}

Node*[500] code;
int code_count = 0;

void add_to_code(Node* n) {
  assert(code_count < 500 - 1, "code array overflow");
  code[code_count++] = n;
}

/**
 * Parses the entire program.
 * EBNF: program = (struct_decl | enum_decl | global_decl | defun | untyped_defun)*
 */
void program() {
  init_types();
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
      Type t;
      parse_type(&t);
      Token* ident = consume_ident();
      if (!ident) {
        error_at(token.str, "identifier expected at top level");
      }
      if (is_token("(")) {
        add_to_code(parse_function(&t, ident));
      } else {
        Node* gvar = new_node(NodeKind.NK_gvar_decl);
        gvar.type = t;
        gvar.ident = ident;
        if (consume("=")) {
          gvar.lhs = expr();
        }
        expect(";");
        add_to_code(gvar);
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
      
      Node* node = new_node(NodeKind.NK_defun);
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
      
      char* name = cast(char*) calloc(1, ident.len + 1);
      memcpy(name, ident.str, ident.len);
      register_function(name, false, p_idx, &t);

      node.then = stmt();
      node.is_decl_only = false;
      add_to_code(node);
    }
  }
  code[code_count] = null;
}

unittest {
  init_types();
  
  // Test 1: variable declaration parsing
  user_input = cast(char*) "int x = 42;";
  token = tokenize(user_input);
  Node* node = stmt();
  assert(node != null);
  assert(node.kind == NodeKind.NK_var_decl);
  assert(strncmp(node.ident.str, "x", node.ident.len) == 0);
  assert(strcmp(node.type.name, "int") == 0);
  assert(node.lhs.kind == NodeKind.NK_num);
  assert(node.lhs.val == 42);
  
  // Test 2: typed function parsing
  user_input = cast(char*) "int main() { return 0; }";
  token = tokenize(user_input);
  program();
  assert(code[0] != null);
  assert(code[0].kind == NodeKind.NK_defun);
  assert(strncmp(code[0].ident.str, "main", code[0].ident.len) == 0);
  assert(strcmp(code[0].return_type.name, "int") == 0);

  // Test 3: cast parsing
  user_input = cast(char*) "cast(char*) x;";
  token = tokenize(user_input);
  Node* cast_node = stmt();
  assert(cast_node != null);
  assert(cast_node.kind == NodeKind.NK_cast_);
  assert(strcmp(cast_node.type.name, "char") == 0);
  assert(cast_node.type.ptr_depth == 1);
  assert(cast_node.lhs.kind == NodeKind.NK_lvar);

  // Test 4: index parsing
  user_input = cast(char*) "y[0];";
  token = tokenize(user_input);
  Node* idx_node = stmt();
  assert(idx_node != null);
  assert(idx_node.kind == NodeKind.NK_index);
  assert(idx_node.lhs.kind == NodeKind.NK_lvar);
  assert(idx_node.rhs.kind == NodeKind.NK_num);
  assert(idx_node.rhs.val == 0);

  // Test 5: sizeof parsing
  user_input = cast(char*) "int.sizeof;";
  token = tokenize(user_input);
  Node* sz_node = stmt();
  assert(sz_node != null);
  assert(sz_node.kind == NodeKind.NK_num);
  assert(sz_node.val == 4);

  // Test 6: string literal tokenization and parsing
  user_input = cast(char*) "\"hello\";";
  token = tokenize(user_input);
  assert(token.kind == TokenKind.TK_str_literal);
  Node* str_node = stmt();
  assert(str_node != null);
  assert(str_node.kind == NodeKind.NK_str_literal);
  assert(strncmp(str_node.ident.str, "hello", str_node.ident.len) == 0);
}

unittest {
  init_types();
  registered_structs_count = 0;
  constants_count = 0;

  // Test Stage 4: Struct parsing and layout
  user_input = cast(char*) "struct S { char a; int b; char c; }";
  token = tokenize(user_input);
  program();

  StructType* st = find_struct("S");
  assert(st != null);
  assert(strcmp(st.name, "S") == 0);
  assert(st.members_count == 3);
  
  assert(strcmp(st.members[0].name, "a") == 0);
  assert(strcmp(st.members[0].type.name, "char") == 0);
  assert(st.members[0].offset == 0);
  
  assert(strcmp(st.members[1].name, "b") == 0);
  assert(strcmp(st.members[1].type.name, "int") == 0);
  assert(st.members[1].offset == 4);
  
  assert(strcmp(st.members[2].name, "c") == 0);
  assert(strcmp(st.members[2].type.name, "char") == 0);
  assert(st.members[2].offset == 8);
  
  assert(st.size == 12);
  assert(st.alignment == 4);

  // Test Stage 4: Member access parsing
  user_input = cast(char*) "s.b;";
  token = tokenize(user_input);
  Node* dot_node = stmt();
  assert(dot_node != null);
  assert(dot_node.kind == NodeKind.NK_dot);
  assert(dot_node.lhs.kind == NodeKind.NK_lvar);
  assert(strncmp(dot_node.lhs.ident.str, "s", dot_node.lhs.ident.len) == 0);
  assert(strncmp(dot_node.ident.str, "b", dot_node.ident.len) == 0);

  // Test Stage 4: Enum parsing (manifest constant)
  user_input = cast(char*) "enum X = 42;";
  token = tokenize(user_input);
  program();
  int val;
  Token tX; tX.str = cast(char*)"X"; tX.len = 1;
  assert(lookup_constant(&tX, &val));
  assert(val == 42);

  // Test Stage 4: Enum parsing (anonymous enum)
  user_input = cast(char*) "enum { A, B = 10, C }";
  token = tokenize(user_input);
  program();
  Token tA; tA.str = cast(char*)"A"; tA.len = 1;
  Token tB; tB.str = cast(char*)"B"; tB.len = 1;
  Token tC; tC.str = cast(char*)"C"; tC.len = 1;
  assert(lookup_constant(&tA, &val)); assert(val == 0);
  assert(lookup_constant(&tB, &val)); assert(val == 10);
  assert(lookup_constant(&tC, &val)); assert(val == 11);

  // Test Stage 4: Constant resolution in parser
  user_input = cast(char*) "A;";
  token = tokenize(user_input);
  Node* num_node = stmt();
  assert(num_node != null);
  assert(num_node.kind == NodeKind.NK_num);
  assert(num_node.val == 0);
}


