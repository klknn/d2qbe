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
  NK_mod, // %
  NK_bitwise_and, // &
  NK_bitwise_or, // |
  NK_bitwise_xor, // ^
  NK_bitwise_not, // ~
  NK_lshift, // <<
  NK_rshift, // >>
  NK_switch_, // switch (x) { ... }
  NK_case_, // case val:
  NK_default_, // default:
  NK_slice, // x[start .. end]
  NK_ternary, // cond ? then : else
  NK_float_num, // float or double literal
}

struct Type {
  const(char)* name;
  int ptr_depth;
  int[5] array_sizes;
  int array_dims;
  bool is_slice;
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

struct TemplateSymbol {
  const(char)* name;
  const(char)* param_name;
  Token* body_start;
  Token* body_end;
}
TemplateSymbol[50] registered_templates;
int registered_templates_count = 0;

struct TypeAlias {
  const(char)* alias_name;
  Type target_type;
}
TypeAlias[100] registered_aliases;
int registered_aliases_count = 0;

enum MAX_PARAM_SIZE = 10;

struct FunctionSymbol {
  const(char)* name;
  const(char)* unmangled_name;
  bool is_extern_c;
  bool is_variadic;
  int num_params;
  Type return_type;
  Type[MAX_PARAM_SIZE] params_types;
}
FunctionSymbol[200] registered_functions;
int registered_functions_count = 0;

/**
 * Registers a function signature.
 */
void register_function(const(char)* name, const(char)* unmangled_name, bool is_extern_c, bool is_variadic, int num_params, Type* return_type, Type* params_types) {
  for (int i = 0; i < registered_functions_count; i++) {
    if (strcmp(registered_functions[i].name, name) == 0) {
      return;
    }
  }
  assert(registered_functions_count < 200, "registered_functions overflow");
  registered_functions[registered_functions_count].name = name;
  registered_functions[registered_functions_count].unmangled_name = unmangled_name;
  registered_functions[registered_functions_count].is_extern_c = is_extern_c;
  registered_functions[registered_functions_count].is_variadic = is_variadic;
  registered_functions[registered_functions_count].num_params = num_params;
  registered_functions[registered_functions_count].return_type = *return_type;
  for (int j = 0; j < num_params; j++) {
    registered_functions[registered_functions_count].params_types[j] = params_types[j];
  }
  const(char)* ret_name = return_type.name;
  if (!ret_name) ret_name = "null";
  printf("# DEBUG: register_function '%s' (unmangled='%s') ret='%s' ptr_depth=%d is_extern_c=%d\n",
         name, unmangled_name, ret_name, return_type.ptr_depth, is_extern_c);
  registered_functions_count++;
}

char* mangle_function_name(const(char)* base_name, Type* params_types, int num_params, bool is_extern_c) {
  if (is_extern_c) {
    char* name = cast(char*) calloc(1, strlen(base_name) + 1);
    strcpy(name, base_name);
    return name;
  }
  
  int len = 4 + cast(int) strlen(base_name);
  for (int i = 0; i < num_params; i++) {
    len = len + 50;
  }
  
  char* buf = cast(char*) calloc(1, len);
  strcpy(buf, "_D_");
  strcat(buf, base_name);
  
  for (int i = 0; i < num_params; i++) {
    strcat(buf, "_");
    Type* t = &params_types[i];
    for (int p = 0; p < t.ptr_depth; p++) {
      strcat(buf, "p");
    }
    if (t.is_slice) {
      strcat(buf, "s");
    }
    
    if (strcmp(t.name, "int") == 0) strcat(buf, "i");
    else if (strcmp(t.name, "char") == 0) strcat(buf, "c");
    else if (strcmp(t.name, "bool") == 0) strcat(buf, "b");
    else if (strcmp(t.name, "void") == 0) strcat(buf, "v");
    else if (strcmp(t.name, "float") == 0) strcat(buf, "f");
    else if (strcmp(t.name, "double") == 0) strcat(buf, "d");
    else {
      strcat(buf, t.name);
    }
  }
  return buf;
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
  for (int i = 0; i < registered_aliases_count; i++) {
    if (strlen(registered_aliases[i].alias_name) == len && strncmp(registered_aliases[i].alias_name, str, len) == 0) {
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
  register_type("float");
  register_type("double");
  register_type("FILE");
}

/**
 * Computes the size in bytes of a D type.
 */
int get_type_size(Type* t) {
  if (t.is_slice) {
    return 16;
  }
  int base_size;
  if (t.ptr_depth > 0) {
    base_size = 8;
  } else {
    base_size = 4;
    if (strcmp(t.name, "int") == 0) base_size = 4;
    else if (strcmp(t.name, "float") == 0) base_size = 4;
    else if (strcmp(t.name, "double") == 0) base_size = 8;
    else if (strcmp(t.name, "char") == 0 || strcmp(t.name, "bool") == 0) base_size = 1;
    else if (strcmp(t.name, "void") == 0) base_size = 1;
    else {
      StructType* st = find_struct(t.name);
      if (st) {
        base_size = st.size;
      }
    }
  }
  if (t.array_dims > 0) {
    int total_size = base_size;
    for (int i = 0; i < t.array_dims; i++) {
      total_size = total_size * t.array_sizes[i];
    }
    return total_size;
  }
  return base_size;
}

/**
 * Computes the alignment requirement in bytes of a D type.
 */
int get_type_alignment(Type* t) {
  if (t.is_slice) return 8;
  if (t.ptr_depth > 0) return 8;
  if (strcmp(t.name, "int") == 0) return 4;
  if (strcmp(t.name, "float") == 0) return 4;
  if (strcmp(t.name, "double") == 0) return 8;
  if (strcmp(t.name, "char") == 0 || strcmp(t.name, "bool") == 0) return 1;
  StructType* st = find_struct(t.name);
  if (st) {
    return st.alignment;
  }
  return 4;
}

TypeAlias* find_alias(const(char)* name) {
  for (int i = 0; i < registered_aliases_count; i++) {
    if (strcmp(registered_aliases[i].alias_name, name) == 0) {
      return &registered_aliases[i];
    }
  }
  return null;
}

void register_alias(const(char)* name, Type* target) {
  for (int i = 0; i < registered_aliases_count; i++) {
    if (strcmp(registered_aliases[i].alias_name, name) == 0) {
      error("duplicate alias definition");
    }
  }
  assert(registered_aliases_count < 100, "registered_aliases overflow");
  registered_aliases[registered_aliases_count].alias_name = name;
  registered_aliases[registered_aliases_count].target_type = *target;
  registered_aliases_count++;
}

void parse_alias() {
  expect("alias");
  Token* alias_tok = consume_ident();
  if (!alias_tok) {
    error_at(token.str, "alias name expected");
  }
  expect("=");
  Type target_type;
  parse_type(&target_type);
  expect(";");
  
  char* alias_name = cast(char*) calloc(1, alias_tok.len + 1);
  memcpy(alias_name, alias_tok.str, alias_tok.len);
  
  register_alias(alias_name, &target_type);
}

/**
 * Parses a type declaration (e.g. const(int)*[10]).
 */
void parse_type(Type* out_type) {
  Type t;
  t.name = null;
  t.ptr_depth = 0;
  t.array_dims = 0;
  t.is_slice = false;
  for (int i = 0; i < 5; i++) {
    t.array_sizes[i] = 0;
  }
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
    char* base_name = cast(char*) calloc(1, base_tok.len + 1);
    memcpy(base_name, base_tok.str, base_tok.len);
    
    char* name;
    if (is_token("!")) {
      name = resolve_template_instantiation(base_name);
    } else {
      name = base_name;
    }
    
    TypeAlias* al = find_alias(name);
    if (al) {
      t.name = al.target_type.name;
      t.ptr_depth = al.target_type.ptr_depth;
      t.array_dims = al.target_type.array_dims;
      for (int i = 0; i < t.array_dims; i++) {
        t.array_sizes[i] = al.target_type.array_sizes[i];
      }
    } else {
      t.name = name;
      t.ptr_depth = 0;
      t.array_dims = 0;
    }
  }
  
  while (consume("*")) {
    t.ptr_depth++;
  }
  while (consume("[")) {
    if (consume("]")) {
      t.is_slice = true;
    } else {
      int size;
      Token* tok = consume_ident();
      if (tok) {
        if (!lookup_constant(tok, &size)) {
          error_at(tok.str, "unknown constant for array size");
        }
      } else {
        size = expect_number();
      }
      for (int i = t.array_dims; i > 0; i--) {
        t.array_sizes[i] = t.array_sizes[i - 1];
      }
      t.array_sizes[0] = size;
      t.array_dims++;
      expect("]");
    }
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
  bool is_extern_c; // for NodeKind.NK_defun
  char* mangled_name; // for NodeKind.NK_defun
}

Node* expr();

int eval_const_expr(Node* node) {
  if (!node) {
    error("null node in constant evaluation");
  }
  if (node.kind == NodeKind.NK_num) {
    return node.val;
  }
  if (node.kind == NodeKind.NK_add) {
    return eval_const_expr(node.lhs) + eval_const_expr(node.rhs);
  }
  if (node.kind == NodeKind.NK_sub) {
    return eval_const_expr(node.lhs) - eval_const_expr(node.rhs);
  }
  if (node.kind == NodeKind.NK_mul) {
    return eval_const_expr(node.lhs) * eval_const_expr(node.rhs);
  }
  if (node.kind == NodeKind.NK_div) {
    int r = eval_const_expr(node.rhs);
    if (r == 0) error("division by zero in compile-time constant expression");
    return eval_const_expr(node.lhs) / r;
  }
  if (node.kind == NodeKind.NK_mod) {
    int r = eval_const_expr(node.rhs);
    if (r == 0) error("modulo by zero in compile-time constant expression");
    return eval_const_expr(node.lhs) % r;
  }
  if (node.kind == NodeKind.NK_eq) {
    return eval_const_expr(node.lhs) == eval_const_expr(node.rhs);
  }
  if (node.kind == NodeKind.NK_ne) {
    return eval_const_expr(node.lhs) != eval_const_expr(node.rhs);
  }
  if (node.kind == NodeKind.NK_lt_op) {
    return eval_const_expr(node.lhs) < eval_const_expr(node.rhs);
  }
  if (node.kind == NodeKind.NK_le) {
    return eval_const_expr(node.lhs) <= eval_const_expr(node.rhs);
  }
  if (node.kind == NodeKind.NK_bitwise_and) {
    return eval_const_expr(node.lhs) & eval_const_expr(node.rhs);
  }
  if (node.kind == NodeKind.NK_bitwise_or) {
    return eval_const_expr(node.lhs) | eval_const_expr(node.rhs);
  }
  if (node.kind == NodeKind.NK_bitwise_xor) {
    return eval_const_expr(node.lhs) ^ eval_const_expr(node.rhs);
  }
  if (node.kind == NodeKind.NK_lshift) {
    return eval_const_expr(node.lhs) << eval_const_expr(node.rhs);
  }
  if (node.kind == NodeKind.NK_rshift) {
    return eval_const_expr(node.lhs) >> eval_const_expr(node.rhs);
  }
  if (node.kind == NodeKind.NK_bitwise_not) {
    return ~eval_const_expr(node.lhs);
  }
  if (node.kind == NodeKind.NK_logical_not) {
    return !eval_const_expr(node.lhs);
  }
  error("expression is not a compile-time constant");
  return 0;
}

void parse_static_assert() {
  expect("static");
  expect("assert");
  expect("(");
  Node* cond = expr();
  if (consume(",")) {
    if (token.kind != TokenKind.TK_str_literal) {
      error_at(token.str, "string literal expected for static assert message");
    }
    token = token.next;
  }
  expect(")");
  expect(";");
  
  int val = eval_const_expr(cond);
  if (!val) {
    error("static assert failure");
  }
}

Node* stmt();
void parse_top_level();

bool is_version_active(Token* ident) {
  if (ident.len == 5 && strncmp(ident.str, "Posix", 5) == 0) return true;
  if (ident.len == 5 && strncmp(ident.str, "Linux", 5) == 0) return true;
  return false;
}

bool is_debug_active() {
  return false;
}

void skip_statement() {
  if (consume("{")) {
    int nest = 1;
    while (nest > 0 && token.kind != TokenKind.TK_eof) {
      if (is_token("{")) nest++;
      else if (is_token("}")) nest--;
      token = token.next;
    }
  } else {
    while (token.kind != TokenKind.TK_eof && !consume(";")) {
      token = token.next;
    }
  }
}

Node* parse_conditional_block(bool is_top_level, bool active) {
  Node* block = null;
  if (!is_top_level) {
    block = cast(Node*) calloc(1, Node.sizeof);
    block.kind = NodeKind.NK_block;
  }
  NodeList* stmts = null;
  if (block) {
    stmts = &block.statements;
  }

  if (active) {
    if (consume("{")) {
      while (!consume("}")) {
        if (is_top_level) {
          parse_top_level();
        } else {
          stmts = push_back(stmts, stmt());
        }
      }
    } else {
      if (is_top_level) {
        parse_top_level();
      } else {
        stmts = push_back(stmts, stmt());
      }
    }
    if (consume("else")) {
      skip_statement();
    }
  } else {
    skip_statement();
    if (consume("else")) {
      if (consume("{")) {
        while (!consume("}")) {
          if (is_top_level) {
            parse_top_level();
          } else {
            stmts = push_back(stmts, stmt());
          }
        }
      } else {
        if (is_top_level) {
          parse_top_level();
        } else {
          stmts = push_back(stmts, stmt());
        }
      }
    }
  }
  return block;
}

Node* parse_version(bool is_top_level) {
  expect("version");
  expect("(");
  Token* ident = consume_ident();
  if (!ident) error_at(token.str, "version identifier expected");
  expect(")");
  return parse_conditional_block(is_top_level, is_version_active(ident));
}

Node* parse_debug(bool is_top_level) {
  expect("debug");
  return parse_conditional_block(is_top_level, is_debug_active());
}

Node* parse_static_if(bool is_top_level) {
  expect("static");
  expect("if");
  expect("(");
  Node* cond = expr();
  expect(")");
  int val = eval_const_expr(cond);
  return parse_conditional_block(is_top_level, val != 0);
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
  } else if (token.kind == TokenKind.TK_float_literal) {
    node = new_node(NodeKind.NK_float_num);
    node.ident = token;
    token = token.next;
  } else if (is_type_expression_start(token)) {
    bool is_prop = is_type_property_expression(token);
    
    if (is_prop) {
      Type t;
      parse_type(&t);
      expect(".");
      if (consume("sizeof")) {
        node = new_node_num(get_type_size(&t));
      } else if (consume("init")) {
        node = new_node_num(0);
      } else if (consume("alignof")) {
        node = new_node_num(get_type_alignment(&t));
      } else {
        error_at(token.str, "unknown type property");
      }
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
        char* base_name = cast(char*) calloc(1, tok.len + 1);
        memcpy(base_name, tok.str, tok.len);
        
        Token* final_tok = tok;
        if (is_token("!")) {
          char* mangled = resolve_template_instantiation(base_name);
          final_tok = cast(Token*) calloc(1, Token.sizeof);
          final_tok.kind = TokenKind.TK_identifier;
          final_tok.str = mangled;
          final_tok.len = cast(int) strlen(mangled);
        }
        
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
        node.ident = final_tok;
      }
    }
    else {
      node = new_node_num(expect_number());
    }
  }

  // Parse postfix operators x[y] and x.y
  for (;;) {
    if (consume("[")) {
      Node* start_expr = expr();
      if (consume("..")) {
        Node* slice = new_node(NodeKind.NK_slice);
        slice.lhs = node; // target (array, pointer, or slice)
        slice.rhs = start_expr; // start index
        slice.cond = expr(); // end index
        expect("]");
        node = slice;
      } else {
        Node* idx = new_node(NodeKind.NK_index);
        idx.lhs = node;
        idx.rhs = start_expr;
        expect("]");
        node = idx;
      }
    } else if (consume(".")) {
      Token* mem_tok;
      if (consume("sizeof")) {
        mem_tok = cast(Token*) calloc(1, Token.sizeof);
        mem_tok.kind = TokenKind.TK_identifier;
        mem_tok.str = cast(char*) "sizeof";
        mem_tok.len = 6;
      } else {
        mem_tok = consume_ident();
        if (!mem_tok) error_at(token.str, "member name expected");
      }
      
      if (consume("(")) {
        Node* call = new_node(NodeKind.NK_funcall);
        call.lhs = new_node(NodeKind.NK_dot);
        call.lhs.lhs = node;
        call.lhs.ident = mem_tok;
        NodeList* args = &call.args;
        while (!consume(")")) {
          args = push_back(args, expr());
          bool _ = consume(",");
        }
        node = call;
      } else {
        Node* dot_node = new_node(NodeKind.NK_dot);
        dot_node.lhs = node;
        dot_node.ident = mem_tok;
        node = dot_node;
      }
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
  if (consume("~")) {
    Node* node = new_node(NodeKind.NK_bitwise_not);
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
    else if (consume("%")) {
      node = new_node_binop(NodeKind.NK_mod, node, unary());
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
 * Parses a shift expression (<<, >>).
 * EBNF: shift = add ("<<" add | ">>" add)*
 */
Node* parse_shift() {
  Node* node = parse_add();
  for (;;) {
    if (consume("<<")) {
      node = new_node_binop(NodeKind.NK_lshift, node, parse_add());
    }
    else if (consume(">>")) {
      node = new_node_binop(NodeKind.NK_rshift, node, parse_add());
    }
    else {
      return node;
    }
  }
}

/**
 * Parses a relational expression (<, <=, >, >=).
 * EBNF: relational = shift ("<" shift | "<=" shift | ">" shift | ">=" shift)*
 */
Node* relational() {
  Node* node = parse_shift();
  for (;;) {
    if (consume("<")) {
      node = new_node_binop(NodeKind.NK_lt_op, node, parse_shift());
    }
    else if (consume("<=")) {
      node = new_node_binop(NodeKind.NK_le, node, parse_shift());
    }
    else if (consume(">")) {
      node = new_node_binop(NodeKind.NK_lt_op, parse_shift(), node);
    }
    else if (consume(">=")) {
      node = new_node_binop(NodeKind.NK_le, parse_shift(), node);
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
 * Parses a bitwise AND expression (&).
 * EBNF: bitwise_and = equality ("&" equality)*
 */
Node* parse_bitwise_and() {
  Node* node = equality();
  for (;;) {
    if (consume("&")) {
      node = new_node_binop(NodeKind.NK_bitwise_and, node, equality());
    } else {
      return node;
    }
  }
}

/**
 * Parses a bitwise XOR expression (^).
 * EBNF: bitwise_xor = bitwise_and ("^" bitwise_and)*
 */
Node* parse_bitwise_xor() {
  Node* node = parse_bitwise_and();
  for (;;) {
    if (consume("^")) {
      node = new_node_binop(NodeKind.NK_bitwise_xor, node, parse_bitwise_and());
    } else {
      return node;
    }
  }
}

/**
 * Parses a bitwise OR expression (|).
 * EBNF: bitwise_or = bitwise_xor ("|" bitwise_xor)*
 */
Node* parse_bitwise_or() {
  Node* node = parse_bitwise_xor();
  for (;;) {
    if (consume("|")) {
      node = new_node_binop(NodeKind.NK_bitwise_or, node, parse_bitwise_xor());
    } else {
      return node;
    }
  }
}

/**
 * Parses a logical AND expression (&&).
 * EBNF: logical_and = bitwise_or ("&&" bitwise_or)*
 */
Node* parse_logical_and() {
  Node* node = parse_bitwise_or();
  for (;;) {
    if (consume("&&")) {
      node = new_node_binop(NodeKind.NK_logical_and, node, parse_bitwise_or());
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
 * Parses a ternary expression (cond ? then : else).
 * EBNF: ternary = logical_or ("?" expr ":" ternary)?
 */
Node* parse_ternary() {
  Node* cond = parse_logical_or();
  if (consume("?")) {
    Node* node = new_node(NodeKind.NK_ternary);
    node.cond = cond;
    node.then = expr();
    expect(":");
    node.else_ = parse_ternary();
    return node;
  }
  return cond;
}

/**
 * Parses an assignment expression (=).
 * EBNF: assign = ternary ("=" assign)?
 */
Node* parse_assign() {
  Node* node = parse_ternary();
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
  if (token && token.len == 4 && strncmp(token.str, "auto", 4) == 0) {
    Token* t = token.next;
    if (t && t.kind == TokenKind.TK_identifier && t.next && t.next.len == 1 && t.next.str[0] == '=') {
      return true;
    }
  }
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
    if (!tok || !is_type_start(tok)) return false;
    tok = tok.next;
    if (tok && tok.len == 1 && tok.str[0] == '!') {
      tok = tok.next;
      if (tok && tok.len == 1 && tok.str[0] == '(') {
        int nest = 1;
        tok = tok.next;
        while (tok && tok.kind != TokenKind.TK_eof) {
          if (tok.len == 1 && tok.str[0] == '(') nest++;
          else if (tok.len == 1 && tok.str[0] == ')') {
            nest--;
            if (nest == 0) {
              tok = tok.next;
              break;
            }
          }
          tok = tok.next;
        }
      } else {
        if (tok) tok = tok.next;
        while (tok && tok.len == 1 && tok.str[0] == '*') {
          tok = tok.next;
        }
      }
    }
  }
  while (tok && tok.len == 1 && tok.str[0] == '*') {
    tok = tok.next;
  }
  while (tok && tok.len == 1 && tok.str[0] == '[') {
    tok = tok.next;
    if (tok && (tok.kind == TokenKind.TK_num || tok.kind == TokenKind.TK_identifier)) tok = tok.next;
    if (tok && tok.len == 1 && tok.str[0] == ']') {
      tok = tok.next;
    } else {
      break;
    }
  }
  return tok && tok.kind == TokenKind.TK_identifier;
}

/**
 * Parses a statement.
 * EBNF: stmt = expr ";" | "{" stmt* "}" | "if" "(" expr ")" stmt ("else" stmt)? | "while" "(" expr ")" stmt | "for" "(" expr? ";" expr? ";" expr? ")" stmt | "return" expr ";" | Type ident ( "=" expr )? ";"
 */
Node* stmt() {
  if (is_token("alias")) {
    parse_alias();
    Node* dummy = cast(Node*) calloc(1, Node.sizeof);
    dummy.kind = NodeKind.NK_block;
    return dummy;
  }
  if (is_token("static")) {
    if (token.next && token.next.len == 6 && strncmp(token.next.str, "assert", 6) == 0) {
      parse_static_assert();
      Node* dummy = cast(Node*) calloc(1, Node.sizeof);
      dummy.kind = NodeKind.NK_block;
      return dummy;
    }
    if (token.next && token.next.len == 2 && strncmp(token.next.str, "if", 2) == 0) {
      return parse_static_if(false);
    }
    error_at(token.str, "static assert or static if expected");
  }
  if (is_token("version")) {
    return parse_version(false);
  }
  if (is_token("debug")) {
    return parse_debug(false);
  }
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
    if (consume("auto")) {
      t.name = "auto";
      t.ptr_depth = 0;
      t.array_dims = 0;
    } else {
      parse_type(&t);
    }
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
  else if (consume("switch")) {
    Node* node = new_node(NodeKind.NK_switch_);
    expect("(");
    node.lhs = expr();
    expect(")");
    node.rhs = stmt();
    return node;
  }
  else if (consume("case")) {
    Node* node = new_node(NodeKind.NK_case_);
    int val;
    Token* tok = consume_ident();
    if (tok) {
      if (!lookup_constant(tok, &val)) {
        error_at(tok.str, "unknown case constant");
      }
    } else {
      val = expect_number();
    }
    node.val = val;
    expect(":");
    return node;
  }
  else if (consume("default")) {
    Node* node = new_node(NodeKind.NK_default_);
    expect(":");
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
    
    if (is_token("(")) {
      char[256] mangled;
      snprintf(&mangled[0], 256, "_D_struct_%s_%.*s", name, mem_ident.len, mem_ident.str);
      char* mangled_name = cast(char*) calloc(1, strlen(&mangled[0]) + 1);
      strcpy(mangled_name, &mangled[0]);
      
      Token* fn_tok = cast(Token*) calloc(1, Token.sizeof);
      fn_tok.kind = TokenKind.TK_identifier;
      fn_tok.str = mangled_name;
      fn_tok.len = cast(int) strlen(mangled_name);
      
      Node* fn = parse_function(&t, fn_tok, name, false);
      add_to_code(fn);
      continue;
    }
    
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
 * Parses a template block declaration.
 */
void parse_template() {
  expect("template");
  Token* name_tok = consume_ident();
  if (!name_tok) {
    error_at(token.str, "template name expected");
  }
  expect("(");
  Token* param_tok = consume_ident();
  if (!param_tok) {
    error_at(token.str, "template parameter name expected");
  }
  expect(")");
  expect("{");
  
  Token* start = token;
  Token* end = null;
  int nest = 1;
  while (token && token.kind != TokenKind.TK_eof) {
    if (token.len == 1 && token.str[0] == '{') {
      nest++;
    } else if (token.len == 1 && token.str[0] == '}') {
      nest--;
      if (nest == 0) {
        end = token;
        token = token.next;
        break;
      }
    }
    token = token.next;
  }
  
  if (nest != 0) {
    error_at(start.str, "unclosed template body");
  }
  
  assert(registered_templates_count < 50, "registered_templates overflow");
  
  char* name = cast(char*) calloc(1, name_tok.len + 1);
  memcpy(name, name_tok.str, name_tok.len);
  
  char* param_name = cast(char*) calloc(1, param_tok.len + 1);
  memcpy(param_name, param_tok.str, param_tok.len);
  
  registered_templates[registered_templates_count].name = name;
  registered_templates[registered_templates_count].param_name = param_name;
  registered_templates[registered_templates_count].body_start = start;
  registered_templates[registered_templates_count].body_end = end;
  registered_templates_count++;
}

TemplateSymbol* find_template(const(char)* name) {
  for (int i = 0; i < registered_templates_count; i++) {
    if (strcmp(registered_templates[i].name, name) == 0) {
      return &registered_templates[i];
    }
  }
  return null;
}

bool is_type_start(Token* tok) {
  if (!tok) return false;
  if (is_type_name(tok.str, tok.len)) return true;
  Token* next = tok.next;
  if (next && next.len == 1 && next.str[0] == '!') {
    char* name = cast(char*) calloc(1, tok.len + 1);
    memcpy(name, tok.str, tok.len);
    if (find_template(name)) {
      return true;
    }
  }
  return false;
}

bool is_type_expression_start(Token* tok) {
  if (!is_type_start(tok)) return false;
  Token* t = tok;
  t = t.next;
  if (t && t.len == 1 && t.str[0] == '!') {
    t = t.next;
    if (t && t.len == 1 && t.str[0] == '(') {
      int nest = 1;
      t = t.next;
      while (t && t.kind != TokenKind.TK_eof) {
        if (t.len == 1 && t.str[0] == '(') nest++;
        else if (t.len == 1 && t.str[0] == ')') {
          nest--;
          if (nest == 0) {
            t = t.next;
            break;
          }
        }
        t = t.next;
      }
    } else {
      if (t) t = t.next;
      while (t && t.len == 1 && t.str[0] == '*') {
        t = t.next;
      }
    }
  }
  while (t && t.len == 1 && t.str[0] == '*') {
    t = t.next;
  }
  while (t && t.len == 1 && t.str[0] == '[') {
    t = t.next;
    if (t && (t.kind == TokenKind.TK_num || t.kind == TokenKind.TK_identifier)) t = t.next;
    if (t && t.len == 1 && t.str[0] == ']') {
      t = t.next;
    } else {
      break;
    }
  }
  return t && t.len == 1 && t.str[0] == '.';
}

bool is_type_property_expression(Token* tok) {
  if (!is_type_start(tok)) return false;
  Token* t = tok;
  t = t.next;
  if (t && t.len == 1 && t.str[0] == '!') {
    t = t.next;
    if (t && t.len == 1 && t.str[0] == '(') {
      int nest = 1;
      t = t.next;
      while (t && t.kind != TokenKind.TK_eof) {
        if (t.len == 1 && t.str[0] == '(') nest++;
        else if (t.len == 1 && t.str[0] == ')') {
          nest--;
          if (nest == 0) {
            t = t.next;
            break;
          }
        }
        t = t.next;
      }
    } else {
      if (t) t = t.next;
      while (t && t.len == 1 && t.str[0] == '*') {
        t = t.next;
      }
    }
  }
  while (t && t.len == 1 && t.str[0] == '*') {
    t = t.next;
  }
  if (t && t.len == 1 && t.str[0] == '.') {
    t = t.next;
    if (t && (t.len == 6 && strncmp(t.str, "sizeof", 6) == 0 ||
              t.len == 4 && strncmp(t.str, "init", 4) == 0 ||
              t.len == 7 && strncmp(t.str, "alignof", 7) == 0)) {
      return true;
    }
  }
  return false;
}

Token* type_to_tokens(Type* t) {
  Token* head = cast(Token*) calloc(1, Token.sizeof);
  head.kind = TokenKind.TK_identifier;
  head.str = cast(char*) t.name;
  head.len = cast(int) strlen(t.name);
  
  Token* curr = head;
  for (int i = 0; i < t.ptr_depth; i++) {
    Token* p = cast(Token*) calloc(1, Token.sizeof);
    p.kind = TokenKind.TK_reserved;
    p.str = cast(char*) "*";
    p.len = 1;
    curr.next = p;
    curr = p;
  }
  for (int i = 0; i < t.array_dims; i++) {
    Token* ob = cast(Token*) calloc(1, Token.sizeof);
    ob.kind = TokenKind.TK_reserved;
    ob.str = cast(char*) "[";
    ob.len = 1;
    curr.next = ob;
    curr = ob;
    
    char[20] buf;
    sprintf(&buf[0], "%d", t.array_sizes[i]);
    char* size_str = cast(char*) calloc(1, strlen(&buf[0]) + 1);
    strcpy(size_str, &buf[0]);
    
    Token* sz = cast(Token*) calloc(1, Token.sizeof);
    sz.kind = TokenKind.TK_num;
    sz.str = size_str;
    sz.len = cast(int) strlen(size_str);
    curr.next = sz;
    curr = sz;
    
    Token* cb = cast(Token*) calloc(1, Token.sizeof);
    cb.kind = TokenKind.TK_reserved;
    cb.str = cast(char*) "]";
    cb.len = 1;
    curr.next = cb;
    curr = cb;
  }
  return head;
}

char* mangle_template_name(const(char)* tmpl_name, Type* arg_type) {
  char[200] buf;
  char[100] type_mangled;
  int len = 0;
  for (int i = 0; arg_type.name[i]; i++) {
    char c = arg_type.name[i];
    if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) {
      type_mangled[len++] = c;
    } else {
      type_mangled[len++] = '_';
    }
  }
  for (int i = 0; i < arg_type.ptr_depth; i++) {
    type_mangled[len++] = 'p';
  }
  for (int i = 0; i < arg_type.array_dims; i++) {
    type_mangled[len++] = 'a';
    int sz = arg_type.array_sizes[i];
    char[20] sz_buf;
    sprintf(&sz_buf[0], "%d", sz);
    for (int j = 0; sz_buf[j]; j++) {
      type_mangled[len++] = sz_buf[j];
    }
  }
  type_mangled[len] = '\0';
  
  sprintf(&buf[0], "%s_%s", tmpl_name, &type_mangled[0]);
  char* res = cast(char*) calloc(1, strlen(&buf[0]) + 1);
  strcpy(res, &buf[0]);
  return res;
}

Token* copy_and_substitute(TemplateSymbol* tmpl, Type* arg_type) {
  Token* arg_tokens = type_to_tokens(arg_type);
  char* mangled_name = mangle_template_name(tmpl.name, arg_type);
  int mangled_len = cast(int) strlen(mangled_name);
  
  Token* new_head = null;
  Token* prev = null;
  
  for (Token* curr = tmpl.body_start; curr && curr != tmpl.body_end; curr = curr.next) {
    Token* p;
    if (curr.kind == TokenKind.TK_identifier && curr.len == strlen(tmpl.param_name) && strncmp(curr.str, tmpl.param_name, curr.len) == 0) {
      Token* arg_head = null;
      Token* arg_prev = null;
      for (Token* ac = arg_tokens; ac; ac = ac.next) {
        Token* at = cast(Token*) calloc(1, Token.sizeof);
        at.kind = ac.kind;
        at.str = ac.str;
        at.len = ac.len;
        if (!arg_head) arg_head = at;
        if (arg_prev) arg_prev.next = at;
        arg_prev = at;
      }
      p = arg_head;
      if (!new_head) new_head = p;
      if (prev) prev.next = p;
      prev = arg_prev;
    } 
    else if (curr.kind == TokenKind.TK_identifier && curr.len == strlen(tmpl.name) && strncmp(curr.str, tmpl.name, curr.len) == 0) {
      p = cast(Token*) calloc(1, Token.sizeof);
      p.kind = TokenKind.TK_identifier;
      p.str = mangled_name;
      p.len = mangled_len;
      p.val = curr.val;
      if (!new_head) new_head = p;
      if (prev) prev.next = p;
      prev = p;
    } 
    else {
      p = cast(Token*) calloc(1, Token.sizeof);
      p.kind = curr.kind;
      p.str = curr.str;
      p.len = curr.len;
      p.val = curr.val;
      if (!new_head) new_head = p;
      if (prev) prev.next = p;
      prev = p;
    }
  }
  return new_head;
}

char* resolve_template_instantiation(const(char)* base_name) {
  TemplateSymbol* tmpl = find_template(base_name);
  if (!tmpl) return cast(char*) base_name;
  
  expect("!");
  Type arg_type;
  if (consume("(")) {
    parse_type(&arg_type);
    expect(")");
  } else {
    Token* tok = consume_ident();
    if (!tok) error_at(token.str, "template argument type expected");
    arg_type.name = cast(char*) calloc(1, tok.len + 1);
    memcpy(cast(char*)arg_type.name, tok.str, tok.len);
    arg_type.ptr_depth = 0;
    arg_type.array_dims = 0;
    while (consume("*")) {
      arg_type.ptr_depth++;
    }
  }
  
  char* name = mangle_template_name(tmpl.name, &arg_type);
  if (!is_type_name(name, cast(int) strlen(name))) {
    bool func_registered = false;
    for (int i = 0; i < registered_functions_count; i++) {
      if (strcmp(registered_functions[i].name, name) == 0) {
        func_registered = true;
        break;
      }
    }
    
    if (!func_registered) {
      Token* inst_tokens = copy_and_substitute(tmpl, &arg_type);
      Token* tail = inst_tokens;
      while (tail.next) {
        tail = tail.next;
      }
      tail.next = token;
      
      token = inst_tokens;
      while (token && token != tail.next) {
        if (consume(";")) continue;
        if (is_token("struct")) {
          parse_struct();
          continue;
        }
        if (is_token("enum")) {
          parse_enum();
          continue;
        }
        if (is_type_name(token.str, token.len)) {
          Type decl_type;
          parse_type(&decl_type);
          Token* decl_ident = consume_ident();
          if (!decl_ident) error_at(token.str, "identifier expected in template body");
          if (is_token("(")) {
            add_to_code(parse_function(&decl_type, decl_ident, null, false));
          } else {
            Node* gvar = new_node(NodeKind.NK_gvar_decl);
            gvar.type = decl_type;
            gvar.ident = decl_ident;
            if (consume("=")) {
              gvar.lhs = expr();
            }
            expect(";");
            add_to_code(gvar);
          }
        } else {
          error_at(token.str, "invalid declaration in template body");
        }
      }
    }
  }
  return name;
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
Node* parse_function(Type* ret_type, Token* func_name, const(char)* struct_name, bool is_extern_c) {
  Node* node = new_node(NodeKind.NK_defun);
  node.ident = func_name;
  node.return_type = *ret_type;
  node.is_extern_c = is_extern_c;
  
  expect("(");
  int i = 0;
  if (struct_name) {
    Token* this_tok = cast(Token*) calloc(1, Token.sizeof);
    this_tok.kind = TokenKind.TK_identifier;
    this_tok.str = cast(char*) "this";
    this_tok.len = 4;
    node.params[0] = this_tok;
    node.params_types[0].name = struct_name;
    node.params_types[0].ptr_depth = 1;
    node.params_types[0].array_dims = 0;
    i = 1;
  }
  
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
  
  char* original_name = cast(char*) calloc(1, func_name.len + 1);
  memcpy(original_name, func_name.str, func_name.len);
  
  char* mangled;
  if (is_extern_c || struct_name || strcmp(original_name, "main") == 0) {
    mangled = original_name;
  } else {
    mangled = mangle_function_name(original_name, &node.params_types[0], i, false);
  }
  node.mangled_name = mangled;
  
  register_function(mangled, original_name, is_extern_c || (struct_name != null), node.is_variadic, i, ret_type, &node.params_types[0]);

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
void parse_top_level() {
  if (consume(";")) {
    return;
  }
  if (consume("unittest")) {
    stmt();
    return;
  }
  if (is_token("struct")) {
    parse_struct();
    return;
  }
  if (is_token("enum")) {
    parse_enum();
    return;
  }
  if (is_token("template")) {
    parse_template();
    return;
  }
  if (is_token("alias")) {
    parse_alias();
    return;
  }
  if (is_token("static")) {
    if (token.next && token.next.len == 6 && strncmp(token.next.str, "assert", 6) == 0) {
      parse_static_assert();
      return;
    }
    if (token.next && token.next.len == 2 && strncmp(token.next.str, "if", 2) == 0) {
      parse_static_if(true);
      return;
    }
    error_at(token.str, "static assert or static if expected");
  }
  if (is_token("version")) {
    parse_version(true);
    return;
  }
  if (is_token("debug")) {
    parse_debug(true);
    return;
  }
  
  if (is_token("auto")) {
    expect("auto");
    Token* ident = consume_ident();
    if (!ident) {
      error_at(token.str, "identifier expected at top level");
    }
    Node* gvar = new_node(NodeKind.NK_gvar_decl);
    gvar.type.name = "auto";
    gvar.type.ptr_depth = 0;
    gvar.type.array_dims = 0;
    gvar.ident = ident;
    expect("=");
    gvar.lhs = expr();
    expect(";");
    add_to_code(gvar);
    return;
  }
  
  bool is_extern_c = false;
  if (is_token("extern")) {
    while (consume("extern")) {
      if (consume("(")) {
        Token* tok = consume_ident();
        if (!tok || tok.len != 1 || tok.str[0] != 'C') {
          error_at(token.str, "Expected 'C'");
        }
        expect(")");
      }
      is_extern_c = true;
    }
  }
  
  if (is_type_name(token.str, token.len) || is_type_start(token)) {
    Type t;
    parse_type(&t);
    Token* ident = consume_ident();
    if (!ident) {
      error_at(token.str, "identifier expected at top level");
    }
    if (is_token("(")) {
      add_to_code(parse_function(&t, ident, null, is_extern_c));
    } else {
      Node* gvar = new_node(NodeKind.NK_gvar_decl);
      gvar.type = t;
      gvar.ident = ident;
      gvar.is_extern_c = is_extern_c;
      if (consume("=")) {
        gvar.lhs = expr();
      }
      expect(";");
      add_to_code(gvar);
    }
  } else {
    error_at(token.str, "type name expected at top level");
  }
}

void program() {
  init_types();
  while (!at_eof()) {
    parse_top_level();
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

  // Test Modulo & Bitwise Operators parsing
  user_input = cast(char*) "x % y;";
  token = tokenize(user_input);
  Node* mod_node = stmt();
  assert(mod_node != null);
  assert(mod_node.kind == NodeKind.NK_mod);

  user_input = cast(char*) "~x;";
  token = tokenize(user_input);
  Node* not_node = stmt();
  assert(not_node != null);
  assert(not_node.kind == NodeKind.NK_bitwise_not);

  user_input = cast(char*) "x << y;";
  token = tokenize(user_input);
  Node* shl_node = stmt();
  assert(shl_node != null);
  assert(shl_node.kind == NodeKind.NK_lshift);

  user_input = cast(char*) "x & y == z;";
  token = tokenize(user_input);
  Node* prec_node = stmt();
  assert(prec_node != null);
  assert(prec_node.kind == NodeKind.NK_bitwise_and);
  assert(prec_node.rhs.kind == NodeKind.NK_eq);

  // Test switch parsing
  user_input = cast(char*) "switch (x) { case 1: break; default: break; }";
  token = tokenize(user_input);
  Node* sw_node = stmt();
  assert(sw_node != null);
  assert(sw_node.kind == NodeKind.NK_switch_);

  // Test template declaration parsing
  registered_templates_count = 0;
  registered_structs_count = 0;
  registered_functions_count = 0;
  user_input = cast(char*) "template Stack(T) { struct Stack { T[10] data; } }";
  token = tokenize(user_input);
  program();
  assert(registered_templates_count == 1);
  assert(strcmp(registered_templates[0].name, "Stack") == 0);
  assert(strcmp(registered_templates[0].param_name, "T") == 0);

  // Test type instantiation
  user_input = cast(char*) "Stack!int s;";
  token = tokenize(user_input);
  Node* var_decl = stmt();
  assert(var_decl != null);
  assert(var_decl.kind == NodeKind.NK_var_decl);
  assert(strcmp(var_decl.type.name, "Stack_int") == 0);
  assert(registered_structs_count == 1);
  assert(strcmp(registered_structs[0].name, "Stack_int") == 0);

  // Test template function instantiation
  user_input = cast(char*) "template swap(T) { void swap(T* a, T* b) {} }";
  token = tokenize(user_input);
  program();
  assert(registered_templates_count == 2);
  
  user_input = cast(char*) "swap!char(x, y);";
  token = tokenize(user_input);
  Node* call_node = stmt();
  assert(call_node != null);
  assert(call_node.kind == NodeKind.NK_funcall);
  assert(strncmp(call_node.ident.str, "swap_char", call_node.ident.len) == 0);
  assert(registered_functions_count == 1);
  assert(strcmp(registered_functions[0].unmangled_name, "swap_char") == 0);
  // Test alias parsing and resolution
  registered_aliases_count = 0;
  user_input = cast(char*) "alias myint = int; alias pint = int*;";
  token = tokenize(user_input);
  program();
  assert(registered_aliases_count == 2);
  assert(strcmp(registered_aliases[0].alias_name, "myint") == 0);
  assert(strcmp(registered_aliases[0].target_type.name, "int") == 0);
  assert(registered_aliases[0].target_type.ptr_depth == 0);
  assert(strcmp(registered_aliases[1].alias_name, "pint") == 0);
  assert(strcmp(registered_aliases[1].target_type.name, "int") == 0);
  assert(registered_aliases[1].target_type.ptr_depth == 1);

  user_input = cast(char*) "myint x;";
  token = tokenize(user_input);
  Node* alias_var1 = stmt();
  assert(alias_var1 != null);
  assert(strcmp(alias_var1.type.name, "int") == 0);
  assert(alias_var1.type.ptr_depth == 0);

  user_input = cast(char*) "pint* y;";
  token = tokenize(user_input);
  Node* alias_var2 = stmt();
  assert(alias_var2 != null);
  assert(strcmp(alias_var2.type.name, "int") == 0);
  assert(alias_var2.type.ptr_depth == 2);

  // Test static assert parsing and evaluation
  user_input = cast(char*) "static assert(1 == 1); static assert(2 * 3 == 6, \"error msg\");";
  token = tokenize(user_input);
  program();

  user_input = cast(char*) "5 * 5 - 20 == 5";
  token = tokenize(user_input);
  Node* const_node = expr();
  assert(eval_const_expr(const_node) == 1);

  // Test .init and .alignof properties
  user_input = cast(char*) "int.init;";
  token = tokenize(user_input);
  Node* init_node = stmt();
  assert(init_node != null && init_node.kind == NodeKind.NK_num && init_node.val == 0);

  user_input = cast(char*) "int*.alignof;";
  token = tokenize(user_input);
  Node* align_node = stmt();
  assert(align_node != null && align_node.kind == NodeKind.NK_num && align_node.val == 8);

  // Test conditional compilation version & debug
  registered_functions_count = 0;
  user_input = cast(char*) "version(Posix) { void posix_func() {} } version(Windows) { void win_func() {} } else { void other_func() {} }";
  token = tokenize(user_input);
  program();
  assert(registered_functions_count == 2);
  assert(strcmp(registered_functions[0].unmangled_name, "posix_func") == 0);
  assert(strcmp(registered_functions[1].unmangled_name, "other_func") == 0);

  // Test auto declaration parsing
  user_input = cast(char*) "auto val = 123;";
  token = tokenize(user_input);
  Node* auto_node = stmt();
  assert(auto_node != null && auto_node.kind == NodeKind.NK_var_decl);
  assert(strcmp(auto_node.type.name, "auto") == 0);

  // Test static if parsing
  registered_functions_count = 0;
  user_input = cast(char*) "static if (5 * 2 == 10) { void true_func() {} } else { void false_func() {} }";
  token = tokenize(user_input);
  program();
  assert(registered_functions_count == 1);
  assert(strcmp(registered_functions[0].unmangled_name, "true_func") == 0);

  registered_functions_count = 0;
  user_input = cast(char*) "static if (3 > 5) { void true_func() {} } else { void false_func() {} }";
  token = tokenize(user_input);
  program();
  assert(registered_functions_count == 1);
  assert(strcmp(registered_functions[0].unmangled_name, "false_func") == 0);

  // Test member function parsing inside struct
  registered_functions_count = 0;
  user_input = cast(char*) "struct MyStruct { int val; int get_val() { return val; } }";
  token = tokenize(user_input);
  program();
  assert(registered_functions_count == 1);
  assert(strcmp(registered_functions[0].name, "_D_struct_MyStruct_get_val") == 0);
  assert(registered_functions[0].num_params == 1);

  // Test slice type parsing and slice expression parsing
  user_input = cast(char*) "int[] slice_var; slice_var = arr[1 .. 5];";
  token = tokenize(user_input);
  Node* s1 = stmt();
  assert(s1 != null && s1.kind == NodeKind.NK_var_decl && s1.type.is_slice);
  assert(strcmp(s1.type.name, "int") == 0);
  assert(s1.type.ptr_depth == 0);

  Node* s2 = stmt();
  assert(s2 != null && s2.kind == NodeKind.NK_assign && s2.rhs.kind == NodeKind.NK_slice);
  assert(strncmp(s2.rhs.lhs.ident.str, "arr", 3) == 0);
  assert(s2.rhs.rhs.kind == NodeKind.NK_num && s2.rhs.rhs.val == 1);
  assert(s2.rhs.cond.kind == NodeKind.NK_num && s2.rhs.cond.val == 5);

  // Test ternary operator parsing
  user_input = cast(char*) "val = cond ? 10 : 20;";
  token = tokenize(user_input);
  Node* tern = stmt();
  assert(tern != null && tern.kind == NodeKind.NK_assign && tern.rhs.kind == NodeKind.NK_ternary);
  assert(strncmp(tern.rhs.cond.ident.str, "cond", 4) == 0);
  assert(tern.rhs.then.kind == NodeKind.NK_num && tern.rhs.then.val == 10);
  assert(tern.rhs.else_.kind == NodeKind.NK_num && tern.rhs.else_.val == 20);

  // Test float and double type parsing, sizeof, and alignof
  user_input = cast(char*) "float x; double y; int fs = float.sizeof; int da = double.alignof;";
  token = tokenize(user_input);
  Node* f1 = stmt();
  assert(f1 != null && f1.kind == NodeKind.NK_var_decl && strcmp(f1.type.name, "float") == 0);
  Node* f2 = stmt();
  assert(f2 != null && f2.kind == NodeKind.NK_var_decl && strcmp(f2.type.name, "double") == 0);
  
  Node* f3 = stmt();
  assert(f3 != null && f3.kind == NodeKind.NK_var_decl && f3.lhs != null && f3.lhs.kind == NodeKind.NK_num && f3.lhs.val == 4);
  
  Node* f4 = stmt();
  assert(f4 != null && f4.kind == NodeKind.NK_var_decl && f4.lhs != null && f4.lhs.kind == NodeKind.NK_num && f4.lhs.val == 8);

  // Test float and double literal parsing
  user_input = cast(char*) "float a = 3.14f; double b = 0.5e-2;";
  token = tokenize(user_input);
  Node* fl1 = stmt();
  assert(fl1 != null && fl1.kind == NodeKind.NK_var_decl && strcmp(fl1.type.name, "float") == 0);
  assert(fl1.lhs != null && fl1.lhs.kind == NodeKind.NK_float_num);
  assert(strncmp(fl1.lhs.ident.str, "3.14f", 5) == 0);

  Node* fl2 = stmt();
  assert(fl2 != null && fl2.kind == NodeKind.NK_var_decl && strcmp(fl2.type.name, "double") == 0);
  assert(fl2.lhs != null && fl2.lhs.kind == NodeKind.NK_float_num);
  assert(strncmp(fl2.lhs.ident.str, "0.5e-2", 6) == 0);

  // Test function overloading parsing and mangling
  registered_functions_count = 0;
  user_input = cast(char*) "void my_print(int x) {} void my_print(double y) {} extern (C) void printf(char* f, ...);";
  token = tokenize(user_input);
  program();
  assert(registered_functions_count == 3);
  
  FunctionSymbol* fs_printf = find_function("printf");
  assert(fs_printf != null && fs_printf.is_extern_c);
  assert(strcmp(fs_printf.name, "printf") == 0);
  
  FunctionSymbol* fs1 = find_function("_D_my_print_i");
  assert(fs1 != null && !fs1.is_extern_c);
  assert(strcmp(fs1.unmangled_name, "my_print") == 0);
  
  FunctionSymbol* fs2 = find_function("_D_my_print_d");
  assert(fs2 != null && !fs2.is_extern_c);
  assert(strcmp(fs2.unmangled_name, "my_print") == 0);
}


