// C stdlib declarations
extern (C) void* calloc(int nmemb, int size);
extern (C) void* memcpy(void* dest, const void* src, int n);
extern (C) int strcmp(const char* s1, const char* s2);
extern (C) int strlen(const char* s);
extern (C) int strncmp(const char* s1, const char* s2, int n);
extern (C) int memcmp(const void* s1, const void* s2, int n);
extern (C) int strtol(const char* nptr, char** endptr, int base);
extern (C) int isspace(int c);
extern (C) int isdigit(int c);
extern (C) char* strchr(const char* s, int c);
extern (C) int printf(const char* format, ...);
extern (C) int fprintf(void* stream, const char* format, ...);
extern (C) void exit(int status);

extern (C) void* get_stderr();

enum null = 0;


extern (C) FILE* get_stderr();

enum TokenKind {
  TK_reserved,
  TK_identifier,
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
      startswith(p, "==") || startswith(p, "!=") ||
      startswith(p, "<=") || startswith(p, ">=") ||
      startswith(p, "&&") || startswith(p, "||") ||
      startswith(p, "++") || startswith(p, "--") ||
      startswith(p, "<<") || startswith(p, ">>")) {
      int len = 2;
      if (startswith(p, "...")) {
        len = 3;
      }
      cur = new_token(TokenKind.TK_reserved, cur, p, len);
      p = p + len;
      continue;
    }
    // single-punct reserved.
    if (strchr("+-*/()<>=;{},&.|[]!^~%:", *p)) {
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
}

struct Type {
  const(char)* name;
  int ptr_depth;
  int[5] array_sizes;
  int array_dims;
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
  if (t.ptr_depth > 0) return 8;
  if (strcmp(t.name, "int") == 0) return 4;
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
      Node* idx = new_node(NodeKind.NK_index);
      idx.lhs = node;
      idx.rhs = expr();
      expect("]");
      node = idx;
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
      
      Node* fn = parse_function(&t, fn_tok, name);
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
            add_to_code(parse_function(&decl_type, decl_ident, null));
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
Node* parse_function(Type* ret_type, Token* func_name, const(char)* struct_name) {
  Node* node = new_node(NodeKind.NK_defun);
  node.ident = func_name;
  node.return_type = *ret_type;
  
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
  
  if (is_type_name(token.str, token.len) || is_type_start(token)) {
    Type t;
    parse_type(&t);
    Token* ident = consume_ident();
    if (!ident) {
      error_at(token.str, "identifier expected at top level");
    }
    if (is_token("(")) {
      add_to_code(parse_function(&t, ident, null));
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
  assert(strcmp(registered_functions[0].name, "swap_char") == 0);
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
  assert(strcmp(registered_functions[0].name, "posix_func") == 0);
  assert(strcmp(registered_functions[1].name, "other_func") == 0);

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
  assert(strcmp(registered_functions[0].name, "true_func") == 0);

  registered_functions_count = 0;
  user_input = cast(char*) "static if (3 > 5) { void true_func() {} } else { void false_func() {} }";
  token = tokenize(user_input);
  program();
  assert(registered_functions_count == 1);
  assert(strcmp(registered_functions[0].name, "false_func") == 0);

  // Test member function parsing inside struct
  registered_functions_count = 0;
  user_input = cast(char*) "struct MyStruct { int val; int get_val() { return val; } }";
  token = tokenize(user_input);
  program();
  assert(registered_functions_count == 1);
  assert(strcmp(registered_functions[0].name, "_D_struct_MyStruct_get_val") == 0);
  assert(registered_functions[0].num_params == 1);
}





const(char)*[500] string_pool;
int string_pool_count = 0;

/**
 * Adds a string literal to the string pool if it doesn't already exist.
 * Returns: index of the string literal in the pool.
 */
int add_string_literal(const(Token)* tok) {
  for (int i = 0; i < string_pool_count; i++) {
    if (strlen(string_pool[i]) == tok.len && strncmp(string_pool[i], tok.str, tok.len) == 0) {
      return i;
    }
  }
  assert(string_pool_count < 500, "string_pool overflow");
  char* copy = cast(char*) calloc(1, tok.len + 1);
  memcpy(copy, tok.str, tok.len);
  string_pool[string_pool_count] = copy;
  return string_pool_count++;
}

/**
 * Generates QBE data definitions for all string literals in the pool.
 */
void gen_strings() {
  for (int i = 0; i < string_pool_count; i++) {
    printf("data $str%d = { b \"%.*s\", b 0 }\n", i, cast(int)strlen(string_pool[i]), string_pool[i]);
  }
}

struct GlobalVar {
  const(char)* name;
  Type type;
}

GlobalVar[200] globals;
int globals_count = 0;

/**
 * Adds a global variable to the registry.
 */
void add_global(const(Token)* ident, Type* type) {
  for (int i = 0; i < globals_count; i++) {
    if (strlen(globals[i].name) == ident.len && strncmp(globals[i].name, ident.str, ident.len) == 0) {
      return;
    }
  }
  assert(globals_count < 200, "globals overflow");
  char* name = cast(char*) calloc(1, ident.len + 1);
  memcpy(name, ident.str, ident.len);
  globals[globals_count].name = name;
  globals[globals_count].type = *type;
  globals_count++;
}

/**
 * Checks if the given identifier refers to a global variable.
 */
bool is_global(const(Token)* ident) {
  for (int i = 0; i < globals_count; i++) {
    if (strlen(globals[i].name) == ident.len && strncmp(globals[i].name, ident.str, ident.len) == 0) {
      return true;
    }
  }
  return false;
}

/**
 * Retrieves the type of a global variable.
 * Returns: the type of the global variable, or default int if not found.
 */
void get_global_type(const(Token)* ident, Type* out_type) {
  for (int i = 0; i < globals_count; i++) {
    if (strlen(globals[i].name) == ident.len && strncmp(globals[i].name, ident.str, ident.len) == 0) {
      *out_type = globals[i].type;
      return;
    }
  }
  Type t;
  t.name = "int";
  t.ptr_depth = 0;
  t.array_dims = 0;
  *out_type = t;
}

struct LocalVar {
  const(char)* name;
  Type type;
}

LocalVar[200] locals;
int locals_count = 0;
Node* current_fn;

struct LoopLabels {
  char type; // 'w' or 'f'
  int id;
}
LoopLabels[100] loop_stack;
int loop_stack_count = 0;

void push_loop(char type, int id) {
  assert(loop_stack_count < 100, "loop_stack overflow");
  loop_stack[loop_stack_count].type = type;
  loop_stack[loop_stack_count].id = id;
  loop_stack_count++;
}

void pop_loop() {
  assert(loop_stack_count > 0, "loop_stack underflow");
  loop_stack_count--;
}

char current_break_type() {
  if (loop_stack_count == 0) {
    error("break statement not within loop or switch");
  }
  return loop_stack[loop_stack_count - 1].type;
}

int current_break_id() {
  if (loop_stack_count == 0) {
    error("break statement not within loop or switch");
  }
  return loop_stack[loop_stack_count - 1].id;
}

char current_continue_type() {
  for (int i = loop_stack_count - 1; i >= 0; i--) {
    if (loop_stack[i].type != 's') {
      return loop_stack[i].type;
    }
  }
  error("continue statement not within loop");
  return 0;
}

int current_continue_id() {
  for (int i = loop_stack_count - 1; i >= 0; i--) {
    if (loop_stack[i].type != 's') {
      return loop_stack[i].id;
    }
  }
  error("continue statement not within loop");
  return 0;
}

/**
 * Adds a local variable to the registry.
 */
void add_local(const(Token)* ident, Type* type) {
  for (int i = 0; i < locals_count; i++) {
    if (strlen(locals[i].name) == ident.len && strncmp(locals[i].name, ident.str, ident.len) == 0) {
      return;
    }
  }
  assert(locals_count < 200, "locals overflow");
  char* name = cast(char*) calloc(1, ident.len + 1);
  memcpy(name, ident.str, ident.len);
  locals[locals_count].name = name;
  locals[locals_count].type = *type;
  const(char)* type_name = type.name;
  if (!type_name) type_name = "null";
  printf("# DEBUG: add_local '%.*s' type '%s' ptr_depth=%d array_dims=%d outer_size=%d\n",
         ident.len, ident.str, type_name, type.ptr_depth, type.array_dims, type.array_sizes[0]);
  locals_count++;
}

/**
 * Checks if the given identifier refers to a local variable in the current function.
 */
bool is_local(const(Token)* ident) {
  for (int i = 0; i < locals_count; i++) {
    if (strlen(locals[i].name) == ident.len && strncmp(locals[i].name, ident.str, ident.len) == 0) {
      return true;
    }
  }
  return false;
}

bool has_local(const(Token)* ident) {
  for (int i = 0; i < locals_count; i++) {
    if (strlen(locals[i].name) == ident.len && strncmp(locals[i].name, ident.str, ident.len) == 0) {
      return true;
    }
  }
  return false;
}

bool get_local_type_silent(const(char)* name, Type* out_type) {
  for (int i = 0; i < locals_count; i++) {
    if (strcmp(locals[i].name, name) == 0) {
      *out_type = locals[i].type;
      return true;
    }
  }
  return false;
}

Member* find_member_by_token(StructType* st, const(Token)* ident) {
  for (int i = 0; i < st.members_count; i++) {
    if (strlen(st.members[i].name) == ident.len && strncmp(st.members[i].name, ident.str, ident.len) == 0) {
      return &st.members[i];
    }
  }
  return null;
}

/**
 * Retrieves the type of a local (or global) variable.
 * Returns: the type of the variable, or default int if not found.
 */
void get_local_type(const(Token)* ident, Type* out_type) {
  for (int i = 0; i < locals_count; i++) {
    if (strlen(locals[i].name) == ident.len && strncmp(locals[i].name, ident.str, ident.len) == 0) {
      if (locals[i].type.name == null) {
        locals[i].type.name = "int";
      }
      const(char)* type_name = locals[i].type.name;
      if (!type_name) type_name = "null";
      printf("# DEBUG: get_local_type '%.*s' -> '%s' ptr_depth=%d\n",
             ident.len, ident.str, type_name, locals[i].type.ptr_depth);
      *out_type = locals[i].type;
      return;
    }
  }
  if (is_global(ident)) {
    get_global_type(ident, out_type);
    const(char)* gtype_name = out_type.name;
    if (!gtype_name) gtype_name = "null";
    printf("# DEBUG: get_local_type '%.*s' -> GLOBAL '%s' ptr_depth=%d\n",
           ident.len, ident.str, gtype_name, out_type.ptr_depth);
    return;
  }
  Type t;
  t.name = "int";
  t.ptr_depth = 0;
  t.array_dims = 0;
  printf("# DEBUG: get_local_type '%.*s' -> DEFAULT 'int'\n", ident.len, ident.str);
  *out_type = t;
}

/**
 * Infens the type of an expression node (limited to address-of and dereference).
 */
void infer_type(Node* node, Type* out_type) {
  Type t;
  t.name = "int";
  t.ptr_depth = 0;
  t.array_dims = 0;
  if (!node) {
    *out_type = t;
    return;
  }
  if (node.kind == NodeKind.NK_addr) {
    Type base;
    infer_type(node.lhs, &base);
    t.name = base.name;
    t.ptr_depth = base.ptr_depth + 1;
    *out_type = t;
    return;
  }
  if (node.kind == NodeKind.NK_lvar) {
    if (has_local(node.ident) || is_global(node.ident)) {
      get_local_type(node.ident, out_type);
    } else {
      Type this_type;
      if (get_local_type_silent("this", &this_type)) {
        StructType* st = find_struct(this_type.name);
        if (st) {
          Member* m = find_member_by_token(st, node.ident);
          if (m) {
            *out_type = m.type;
            return;
          }
        }
      }
      get_local_type(node.ident, out_type);
    }
    return;
  }
  if (node.kind == NodeKind.NK_deref) {
    Type base;
    infer_type(node.lhs, &base);
    t.name = base.name;
    int depth = 0;
    if (base.ptr_depth > 0) depth = base.ptr_depth - 1;
    t.ptr_depth = depth;
    *out_type = t;
    return;
  }
  if (node.kind == NodeKind.NK_str_literal) {
    t.name = "char";
    t.ptr_depth = 1;
    *out_type = t;
    return;
  }
  if (node.kind == NodeKind.NK_cast_) {
    *out_type = node.type;
    return;
  }
  if (node.kind == NodeKind.NK_index) {
    Type base;
    infer_type(node.lhs, &base);
    t.name = base.name;
    int depth = 0;
    if (base.ptr_depth > 0) depth = base.ptr_depth - 1;
    t.ptr_depth = depth;
    *out_type = t;
    return;
  }
  if (node.kind == NodeKind.NK_funcall) {
    char* name = cast(char*) calloc(1, node.ident.len + 1);
    memcpy(name, node.ident.str, node.ident.len);
    FunctionSymbol* fs = find_function(name);
    if (fs) {
      *out_type = fs.return_type;
    }
    return;
  }
  *out_type = t;
}

/**
 * Recursively collects all local variables declared in a function AST.
 */
void collect_locals(Node* node) {
  if (!node) return;
  if (node.kind == NodeKind.NK_var_decl) {
    if (node.type.name && strcmp(node.type.name, "auto") == 0) {
      Type inferred;
      infer_type(node.lhs, &inferred);
      node.type = inferred;
    }
    add_local(node.ident, &node.type);
  }
  else if (node.kind == NodeKind.NK_assign && node.lhs.kind == NodeKind.NK_lvar) {
    if (!is_global(node.lhs.ident) && !has_local(node.lhs.ident)) {
      bool is_implicit_member = false;
      Type this_type;
      if (get_local_type_silent("this", &this_type)) {
        StructType* st = find_struct(this_type.name);
        if (st) {
          Member* m = find_member_by_token(st, node.lhs.ident);
          if (m) {
            is_implicit_member = true;
          }
        }
      }
      if (!is_implicit_member) {
        Type rhs_type;
        infer_type(node.rhs, &rhs_type);
        add_local(node.lhs.ident, &rhs_type);
      }
    }
  }
  else if (node.kind == NodeKind.NK_lvar) {
    if (!is_global(node.ident) && !has_local(node.ident)) {
      bool is_implicit_member = false;
      Type this_type;
      if (get_local_type_silent("this", &this_type)) {
        StructType* st = find_struct(this_type.name);
        if (st) {
          Member* m = find_member_by_token(st, node.ident);
          if (m) {
            is_implicit_member = true;
          }
        }
      }
      if (!is_implicit_member) {
        Type t;
        t.name = "int";
        t.ptr_depth = 0;
        t.array_dims = 0;
        add_local(node.ident, &t);
      }
    }
  }
  collect_locals(node.lhs);
  collect_locals(node.rhs);
  collect_locals(node.begin);
  collect_locals(node.cond);
  collect_locals(node.then);
  collect_locals(node.else_);
  collect_locals(node.advance);
  
  if (node.kind == NodeKind.NK_block) {
    for (NodeList* stmts = &node.statements; stmts; stmts = stmts.next) {
      collect_locals(stmts.value);
    }
  }
}

// Tracks whether register %ti is 'w' (word) or 'l' (long)
char[10000] reg_types;

int reg_counter = 0;

/**
 * Allocates and returns the next temporary register index.
 */
int next_reg() {
  assert(reg_counter < 9999, "register counter overflow");
  return ++reg_counter;
}

/**
 * Records the type of a temporary register.
 */
void set_reg_type(int reg, char type) {
  assert(reg < 10000, "reg_types write overflow");
  reg_types[reg] = type;
}

/**
 * Retrieves the recorded type of a temporary register.
 */
char get_reg_type(int reg) {
  assert(reg < 10000, "reg_types read overflow");
  return reg_types[reg];
}

/**
 * Checks if a node (or any statement inside it) is a return statement.
 */
bool is_returned(Node* node) {
  if (!node) {
    return false;
  }
  if (node.kind == NodeKind.NK_return_) {
    return true;
  }
  if (node.kind == NodeKind.NK_block) {
    for (NodeList* stmts = &node.statements; stmts; stmts = stmts.next) {
      if (is_returned(stmts.value)) {
        return true;
      }
    }
  }
  return false;
}

/**
 * Checks if a node (or block) ends with a return statement.
 */
bool ends_with_return(Node* node) {
  if (!node) {
    return false;
  }
  if (node.kind == NodeKind.NK_return_ || node.kind == NodeKind.NK_break_ || node.kind == NodeKind.NK_continue_) {
    return true;
  }
  if (node.kind == NodeKind.NK_block) {
    Node* last = null;
    for (NodeList* stmts = &node.statements; stmts; stmts = stmts.next) {
      if (stmts.value) {
        last = stmts.value;
      }
    }
    return ends_with_return(last);
  }
  if (node.kind == NodeKind.NK_if_) {
    return ends_with_return(node.then) && ends_with_return(node.else_);
  }
  return false;
}

/**
 * Generates QBE IR for a binary operator node.
 * Returns: the register index holding the result.
 */
int gen_binop(Node* node, const char* binop) {
  int l = gen(node.lhs);
  int r = gen(node.rhs);
  int res = next_reg();
  printf("  %%t%d =w %s %%t%d, %%t%d\n", res, binop, l, r);
  set_reg_type(res, 'w');
  return res;
}

/**
 * Resolves the type of an expression node.
 */
void get_expr_type(Node* node, Type* out_type) {
  Type t;
  t.name = "int";
  t.ptr_depth = 0;
  t.array_dims = 0;
  if (!node) {
    *out_type = t;
    return;
  }
  if (node.kind == NodeKind.NK_num) {
    *out_type = t;
    return;
  }
  if (node.kind == NodeKind.NK_funcall) {
    char* name = cast(char*) calloc(1, node.ident.len + 1);
    memcpy(name, node.ident.str, node.ident.len);
    FunctionSymbol* fs = find_function(name);
    if (fs) {
      *out_type = fs.return_type;
      return;
    }
    *out_type = t;
    return;
  }
  if (node.kind == NodeKind.NK_lvar) {
    get_local_type(node.ident, out_type);
    return;
  }
  if (node.kind == NodeKind.NK_addr) {
    Type base;
    get_expr_type(node.lhs, &base);
    t.name = base.name;
    t.ptr_depth = base.ptr_depth + 1;
    *out_type = t;
    return;
  }
  if (node.kind == NodeKind.NK_deref) {
    Type base;
    get_expr_type(node.lhs, &base);
    t.name = base.name;
    int depth = 0;
    if (base.ptr_depth > 0) depth = base.ptr_depth - 1;
    t.ptr_depth = depth;
    *out_type = t;
    return;
  }
  if (node.kind == NodeKind.NK_cast_) {
    *out_type = node.type;
    return;
  }
  if (node.kind == NodeKind.NK_index) {
    Type base;
    get_expr_type(node.lhs, &base);
    t.name = base.name;
    if (base.array_dims > 0) {
      t.ptr_depth = base.ptr_depth;
      t.array_dims = base.array_dims - 1;
      for (int i = 0; i < t.array_dims; i++) {
        t.array_sizes[i] = base.array_sizes[i + 1];
      }
    } else {
      int depth = 0;
      if (base.ptr_depth > 0) depth = base.ptr_depth - 1;
      t.ptr_depth = depth;
      t.array_dims = 0;
    }
    *out_type = t;
    return;
  }
  if (node.kind == NodeKind.NK_assign) {
    get_expr_type(node.lhs, out_type);
    return;
  }
  if (node.kind == NodeKind.NK_dot) {
    if (node.ident.len == 6 && strncmp(node.ident.str, "sizeof", 6) == 0) {
      t.name = "int";
      t.ptr_depth = 0;
      t.array_dims = 0;
      *out_type = t;
      return;
    }
    Type lt;
    get_expr_type(node.lhs, &lt);
    StructType* st = find_struct(lt.name);
    if (st) {
      Member* m = find_member(st, node.ident);
      if (m) {
        *out_type = m.type;
        return;
      }
    }
    char[100] buf;
    const(char)* name = lt.name;
    if (!name) name = "null";
    snprintf(&buf[0], 100, "struct type expected for member access in get_expr_type, got '%s'", name);
    error(&buf[0]);
    *out_type = t;
    return;
  }
  if (node.kind == NodeKind.NK_add || node.kind == NodeKind.NK_sub) {
    Type lt;
    get_expr_type(node.lhs, &lt);
    Type rt;
    get_expr_type(node.rhs, &rt);
    if (lt.ptr_depth > 0) {
      *out_type = lt;
      return;
    }
    if (rt.ptr_depth > 0) {
      *out_type = rt;
      return;
    }
    *out_type = lt;
    return;
  }
  *out_type = t;
}
/**
 * Generates QBE IR to calculate the address of an lvalue expression.
 * Returns: the register index holding the calculated address.
 */
int gen_addr(Node* node) {
  if (node.kind == NodeKind.NK_lvar) {
    if (!has_local(node.ident) && !is_global(node.ident)) {
      Type this_type;
      if (get_local_type_silent("this", &this_type)) {
        StructType* st = find_struct(this_type.name);
        if (st) {
          Member* m = find_member_by_token(st, node.ident);
          if (m) {
            int this_reg = next_reg();
            printf("  %%t%d =l loadl %%this_addr\n", this_reg);
            set_reg_type(this_reg, 'l');
            if (m.offset == 0) {
              return this_reg;
            }
            int res = next_reg();
            printf("  %%t%d =l add %%t%d, %d\n", res, this_reg, m.offset);
            set_reg_type(res, 'l');
            return res;
          }
        }
      }
    }
    
    int res = next_reg();
    if (!is_local(node.ident) && is_global(node.ident)) {
      printf("  %%t%d =l copy $%.*s\n", res, node.ident.len, node.ident.str);
    } else {
      printf("  %%t%d =l copy %%%.*s_addr\n", res, node.ident.len, node.ident.str);
    }
    set_reg_type(res, 'l');
    return res;
  }
  if (node.kind == NodeKind.NK_deref) {
    return gen(node.lhs);
  }
  if (node.kind == NodeKind.NK_index) {
      Type lt;
      get_expr_type(node.lhs, &lt);
      int l;
      if (lt.array_dims > 0) {
        l = gen_addr(node.lhs);
      } else {
        l = gen(node.lhs);
      }
      int r = gen(node.rhs);
      Type tmp_type;
      tmp_type.name = lt.name;
      if (lt.array_dims > 0) {
        tmp_type.ptr_depth = lt.ptr_depth;
        tmp_type.array_dims = lt.array_dims - 1;
        for (int i = 0; i < tmp_type.array_dims; i++) {
          tmp_type.array_sizes[i] = lt.array_sizes[i + 1];
        }
      } else {
        tmp_type.ptr_depth = lt.ptr_depth - 1;
        tmp_type.array_dims = 0;
      }
      int scale = get_type_size(&tmp_type);
      int offset_reg = r;
      if (scale > 1) {
        int mul_res = next_reg();
        printf("  %%t%d =w mul %%t%d, %d\n", mul_res, r, scale);
        offset_reg = mul_res;
      }
      int ext_res = next_reg();
      printf("  %%t%d =l extsw %%t%d\n", ext_res, offset_reg);
      int add_res = next_reg();
      printf("  %%t%d =l add %%t%d, %%t%d\n", add_res, l, ext_res);
      set_reg_type(add_res, 'l');
      return add_res;
  }
  if (node.kind == NodeKind.NK_dot) {
    if (node.ident.len == 6 && strncmp(node.ident.str, "sizeof", 6) == 0) {
      error("sizeof property has no address");
    }
    Type lt;
    get_expr_type(node.lhs, &lt);
    StructType* st = find_struct(lt.name);
    if (!st) {
      char[100] buf;
      const(char)* name = lt.name;
      if (!name) name = "null";
      snprintf(&buf[0], 100, "struct type expected for member access, got '%s'", name);
      error(&buf[0]);
    }
    Member* m = find_member(st, node.ident);
    if (!m) {
      char[100] buf;
      snprintf(&buf[0], 100, "member '%.*s' not found in struct '%s'",
               node.ident.len, node.ident.str, st.name);
      error(&buf[0]);
    }
    
    int struct_addr;
    if (lt.ptr_depth > 0) {
      struct_addr = gen(node.lhs);
    } else {
      struct_addr = gen_addr(node.lhs);
    }
    
    if (m.offset == 0) {
      return struct_addr;
    }
    int res = next_reg();
    printf("  %%t%d =l add %%t%d, %d\n", res, struct_addr, m.offset);
    set_reg_type(res, 'l');
    return res;
  }
  error("lvalue expected");
  return 0;
}

/**
 * Emits QBE IR to load a value of type `t` from the address in `addr_reg`.
 * Returns: the register index holding the loaded value.
 */
int emit_load(int addr_reg, Type* t) {
  int size = get_type_size(t);
  int ret = next_reg();
  if (t.ptr_depth > 0) {
    printf("  %%t%d =l loadl %%t%d\n", ret, addr_reg);
    set_reg_type(ret, 'l');
  } else if (size == 1) {
    printf("  %%t%d =w loadub %%t%d\n", ret, addr_reg);
    set_reg_type(ret, 'w');
  } else if (size == 4) {
    printf("  %%t%d =w loadw %%t%d\n", ret, addr_reg);
    set_reg_type(ret, 'w');
  } else {
    char[100] buf;
    const(char)* tname = t.name;
    if (!tname) tname = "null";
    snprintf(&buf[0], 100, "cannot load struct value directly: '%s' ptr_depth=%d", tname, t.ptr_depth);
    error(&buf[0]);
  }
  return ret;
}

/**
 * Emits QBE IR to store a value from `val_reg` to the address in `addr_reg`.
 */
void emit_store(int val_reg, int addr_reg, Type* t) {
  int size = get_type_size(t);
  if (t.ptr_depth > 0) {
    char val_type = get_reg_type(val_reg);
    if (val_type == 'w') {
      int ext_res = next_reg();
      printf("  %%t%d =l extsw %%t%d\n", ext_res, val_reg);
      set_reg_type(ext_res, 'l');
      val_reg = ext_res;
    }
    printf("  storel %%t%d, %%t%d\n", val_reg, addr_reg);
  } else if (size == 1) {
    printf("  storeb %%t%d, %%t%d\n", val_reg, addr_reg);
  } else if (size == 4) {
    printf("  storew %%t%d, %%t%d\n", val_reg, addr_reg);
  } else {
    error("cannot store struct value directly");
  }
}

/**
 * Generates QBE IR to copy struct members recursively (for struct assignment).
 */
void copy_struct_members(const(char)* struct_name, int lhs_addr_reg, int rhs_addr_reg) {
  StructType* st = find_struct(struct_name);
  for (int i = 0; i < st.members_count; i++) {
    Member* m = &st.members[i];
    
    int mem_lhs_addr = next_reg();
    printf("  %%t%d =l add %%t%d, %d\n", mem_lhs_addr, lhs_addr_reg, m.offset);
    set_reg_type(mem_lhs_addr, 'l');
    
    int mem_rhs_addr = next_reg();
    printf("  %%t%d =l add %%t%d, %d\n", mem_rhs_addr, rhs_addr_reg, m.offset);
    set_reg_type(mem_rhs_addr, 'l');
    
    int array_len = 1;
    if (m.type.array_dims > 0) {
      for (int j = 0; j < m.type.array_dims; j++) {
        array_len = array_len * m.type.array_sizes[j];
      }
    }
    Type elem_type = m.type;
    elem_type.array_dims = 0;
    int elem_size = get_type_size(&elem_type);
    
    for (int j = 0; j < array_len; j++) {
      int elem_lhs_addr = mem_lhs_addr;
      int elem_rhs_addr = mem_rhs_addr;
      if (m.type.array_dims > 0 && j > 0) {
        elem_lhs_addr = next_reg();
        printf("  %%t%d =l add %%t%d, %d\n", elem_lhs_addr, mem_lhs_addr, j * elem_size);
        set_reg_type(elem_lhs_addr, 'l');
        
        elem_rhs_addr = next_reg();
        printf("  %%t%d =l add %%t%d, %d\n", elem_rhs_addr, mem_rhs_addr, j * elem_size);
        set_reg_type(elem_rhs_addr, 'l');
      }
      
      if (elem_type.ptr_depth == 0 && find_struct(elem_type.name)) {
        copy_struct_members(elem_type.name, elem_lhs_addr, elem_rhs_addr);
      } else {
        int val = emit_load(elem_rhs_addr, &elem_type);
        emit_store(val, elem_lhs_addr, &elem_type);
      }
    }
  }
}

int gen_inc_dec(Node* node, bool is_inc, bool is_prefix) {
  int addr = gen_addr(node.lhs);
  Type t;
  get_expr_type(node.lhs, &t);
  int val = emit_load(addr, &t);
  
  int scale = 1;
  if (t.ptr_depth > 0) {
    Type tmp_type;
    tmp_type.name = t.name;
    tmp_type.ptr_depth = t.ptr_depth - 1;
    tmp_type.array_dims = 0;
    scale = get_type_size(&tmp_type);
  }
  
  char qbe_type = get_reg_type(val);
  if (qbe_type != 'w' && qbe_type != 'l') qbe_type = 'w';
  
  int new_val = next_reg();
  if (is_inc) {
    printf("  %%t%d =%c add %%t%d, %d\n", new_val, qbe_type, val, scale);
  } else {
    printf("  %%t%d =%c sub %%t%d, %d\n", new_val, qbe_type, val, scale);
  }
  set_reg_type(new_val, qbe_type);
  
  emit_store(new_val, addr, &t);
  
  if (is_prefix) {
    return new_val;
  } else {
    return val;
  }
}


/**
 * Recursively generates QBE IR for the given AST node.
 * Returns: the register index holding the result of the node expression, or 0 if none.
 */
int gen(Node* node) {
  if (!node) {
    return 0;
  }
  printf("# DEBUG: gen node=%p kind=%d\n", node, node.kind);
  if (node.kind == NodeKind.NK_continue_) {
      char type = current_continue_type();
      int id = current_continue_id();
      if (type == 'w') {
        printf("  jmp @cond%d\n", id);
      } else if (type == 'f') {
        printf("  jmp @forpost%d\n", id);
      }
      return 0;
    }
  if (node.kind == NodeKind.NK_break_) {
      char type = current_break_type();
      int id = current_break_id();
      if (type == 'w') {
        printf("  jmp @break%d\n", id);
      } else if (type == 'f') {
        printf("  jmp @forend%d\n", id);
      } else if (type == 's') {
        printf("  jmp @switch_end%d\n", id);
      }
      return 0;
    }
    if (node.kind == NodeKind.NK_addr) {
      return gen_addr(node.lhs);
    }
  if (node.kind == NodeKind.NK_deref) {
    int addr = gen(node.lhs);
    Type t;
    get_expr_type(node, &t);
    return emit_load(addr, &t);
  }
  if (node.kind == NodeKind.NK_num) {
      int res = next_reg();
      printf("  %%t%d =w copy %d\n", res, node.val);
      set_reg_type(res, 'w');
      return res;
    }
  if (node.kind == NodeKind.NK_lvar) {
      int addr = gen_addr(node);
      Type t;
      get_local_type(node.ident, &t);
      return emit_load(addr, &t);
    }
  if (node.kind == NodeKind.NK_assign) {
      Type lt;
      get_expr_type(node.lhs, &lt);
      if (lt.ptr_depth == 0 && find_struct(lt.name)) {
        int lhs_addr = gen_addr(node.lhs);
        int rhs_addr = gen_addr(node.rhs);
        copy_struct_members(lt.name, lhs_addr, rhs_addr);
        return rhs_addr;
      } else {
        int rhs = gen(node.rhs);
        int lhs_addr = gen_addr(node.lhs);
        emit_store(rhs, lhs_addr, &lt);
        return rhs;
      }
    }
  if (node.kind == NodeKind.NK_var_decl) {
      if (node.lhs) {
        Type t;
        get_local_type(node.ident, &t);
        Node lvar_node;
        lvar_node.kind = NodeKind.NK_lvar;
        lvar_node.ident = node.ident;
        int lhs_addr = gen_addr(&lvar_node);
        if (t.ptr_depth == 0 && find_struct(t.name)) {
          int rhs_addr = gen_addr(node.lhs);
          copy_struct_members(t.name, lhs_addr, rhs_addr);
          return rhs_addr;
        } else {
          int rhs = gen(node.lhs);
          emit_store(rhs, lhs_addr, &t);
          return rhs;
        }
      }
      return 0;
    }
  if (node.kind == NodeKind.NK_gvar_decl) {
      int size = get_type_size(&node.type);
      printf("data $%.*s = ", node.ident.len, node.ident.str);
      if (node.lhs && node.lhs.kind == NodeKind.NK_num) {
        char c = 'w';
        if (node.type.ptr_depth > 0) {
          c = 'l';
        }
        if (strcmp(node.type.name, "char") == 0 || strcmp(node.type.name, "bool") == 0) {
          c = 'b';
        }
        printf("{ %c %d }\n", c, node.lhs.val);
      } else {
        printf("{ z %d }\n", size);
      }
      return 0;
    }
  if (node.kind == NodeKind.NK_str_literal) {
      int idx = add_string_literal(node.ident);
      int res = next_reg();
      printf("  %%t%d =l copy $str%d\n", res, idx);
      set_reg_type(res, 'l');
      return res;
    }
  if (node.kind == NodeKind.NK_cast_) {
      int lhs = gen(node.lhs);
      char tgt_char = 'w';
      if (node.type.ptr_depth > 0) {
        tgt_char = 'l';
      }
      char src_char = get_reg_type(lhs);
      if (src_char != 'w' && src_char != 'l') src_char = 'w';
      int res = next_reg();
      if (tgt_char == src_char) {
        printf("  %%t%d =%c copy %%t%d\n", res, tgt_char, lhs);
      } else if (tgt_char == 'l') {
        printf("  %%t%d =l extsw %%t%d\n", res, lhs);
      } else {
        printf("  %%t%d =w copy %%t%d\n", res, lhs);
      }
      set_reg_type(res, tgt_char);
      return res;
    }
  if (node.kind == NodeKind.NK_index) {
      int addr = gen_addr(node);
      Type t;
      get_expr_type(node, &t);
      return emit_load(addr, &t);
    }
  if (node.kind == NodeKind.NK_assert_) {
      int cond = gen(node.cond);
      int label_id = next_reg();
      printf("  jnz %%t%d, @assert_ok%d, @assert_fail%d\n", cond, label_id, label_id);
      printf("@assert_fail%d\n", label_id);
      printf("  call $exit(w 1)\n");
      printf("@assert_ok%d\n", label_id);
      return cond;
    }
  if (node.kind == NodeKind.NK_return_) {
      if (node.lhs) {
        int lhs = gen(node.lhs);
        char lhs_type = get_reg_type(lhs);
        char fn_ret_type = 'w';
        if (current_fn.return_type.ptr_depth > 0) {
          fn_ret_type = 'l';
        }
        if (fn_ret_type == 'l' && lhs_type == 'w') {
          int ext_res = next_reg();
          printf("  %%t%d =l extsw %%t%d\n", ext_res, lhs);
          set_reg_type(ext_res, 'l');
          lhs = ext_res;
        }
        printf("  ret %%t%d\n", lhs);
        return lhs;
      } else {
        printf("  ret\n");
        return 0;
      }
    }
  if (node.kind == NodeKind.NK_if_) {
      int cond = gen(node.cond);
      int label_id = next_reg();
      printf("  jnz %%t%d, @then%d, @else%d\n", cond, label_id, label_id);
      printf("@then%d\n", label_id);
      int then = gen(node.then);
      if (!ends_with_return(node.then)) {
        printf("  jmp @endif%d\n", label_id);
      }
      printf("@else%d\n", label_id);
      int else_val = gen(node.else_);
      if (!ends_with_return(node.then) || !ends_with_return(node.else_)) {
        printf("@endif%d\n", label_id);
      }
      return then;
    }
  if (node.kind == NodeKind.NK_while_) {
      int label_id = next_reg();
      printf("@cond%d\n", label_id);
      int cond = gen(node.cond);
      printf("  jnz %%t%d, @body%d, @break%d\n", cond, label_id, label_id);
      printf("@body%d\n", label_id);
      push_loop('w', label_id);
      int then = gen(node.then);
      pop_loop();
      printf("  jmp @cond%d\n", label_id);
      printf("@break%d\n", label_id);
      return then;
    }
  if (node.kind == NodeKind.NK_for_) {
      int label_id = next_reg();
      gen(node.begin);
      printf("@forcond%d\n", label_id);
      if (node.cond) {
        int cond = gen(node.cond);
        printf("  jnz %%t%d, @forthen%d, @forend%d\n", cond, label_id, label_id);
      }
      printf("@forthen%d\n", label_id);
      push_loop('f', label_id);
      gen(node.then);
      pop_loop();
      printf("@forpost%d\n", label_id);
      gen(node.advance);
      printf("  jmp @forcond%d\n", label_id);
      printf("@forend%d\n", label_id);
      return 0;
    }
  if (node.kind == NodeKind.NK_switch_) {
      int label_id = next_reg();
      int cond = gen(node.lhs);
      
      int[100] case_vals;
      int case_count = 0;
      bool has_default = false;
      
      if (node.rhs && node.rhs.kind == NodeKind.NK_block) {
        for (NodeList* curr = &node.rhs.statements; curr && curr.value; curr = curr.next) {
          if (curr.value.kind == NodeKind.NK_case_) {
            case_vals[case_count] = curr.value.val;
            case_count++;
          } else if (curr.value.kind == NodeKind.NK_default_) {
            has_default = true;
          }
        }
      }
      
      for (int i = 0; i < case_count; i++) {
        int comp = next_reg();
        printf("  %%t%d =w ceqw %%t%d, %d\n", comp, cond, case_vals[i]);
        set_reg_type(comp, 'w');
        
        int branch_label = next_reg();
        if (i == case_count - 1) {
          if (has_default) {
            printf("  jnz %%t%d, @switch%d_case_%d, @switch%d_default\n", comp, label_id, case_vals[i], label_id);
          } else {
            printf("  jnz %%t%d, @switch%d_case_%d, @switch_end%d\n", comp, label_id, case_vals[i], label_id);
          }
        } else {
          printf("  jnz %%t%d, @switch%d_case_%d, @switch%d_check%d\n", comp, label_id, case_vals[i], label_id, branch_label);
          printf("@switch%d_check%d\n", label_id, branch_label);
        }
      }
      
      if (case_count == 0) {
        if (has_default) {
          printf("  jmp @switch%d_default\n", label_id);
        } else {
          printf("  jmp @switch_end%d\n", label_id);
        }
      }
      
      push_loop('s', label_id);
      int body_val = gen(node.rhs);
      pop_loop();
      
      printf("@switch_end%d\n", label_id);
      return body_val;
    }
  if (node.kind == NodeKind.NK_block) {
      int ret = 0;
      bool dead = false;
      NodeList* stmts = &node.statements;
      while (stmts) {
        if (stmts.value) {
          if (stmts.value.kind == NodeKind.NK_case_ || stmts.value.kind == NodeKind.NK_default_) {
            dead = false;
          }
          if (!dead) {
            ret = gen(stmts.value);
            if (ends_with_return(stmts.value)) {
              dead = true;
            }
          }
        }
        stmts = stmts.next;
      }
      return ret;
    }
  if (node.kind == NodeKind.NK_funcall) {
      int[21] args_vars;
      int n_arg = 0;
      FunctionSymbol* fs = null;
      char* mangled_func_name = null;
      int mangled_func_len = 0;

      if (node.lhs) {
        Type lt;
        get_expr_type(node.lhs.lhs, &lt);
        
        int this_addr;
        if (lt.ptr_depth > 0) {
          this_addr = gen(node.lhs.lhs);
        } else {
          this_addr = gen_addr(node.lhs.lhs);
        }
        args_vars[0] = this_addr;
        n_arg = 1;
        
        char[256] mangled;
        snprintf(&mangled[0], 256, "_D_struct_%s_%.*s", lt.name, node.lhs.ident.len, node.lhs.ident.str);
        mangled_func_name = cast(char*) calloc(1, strlen(&mangled[0]) + 1);
        strcpy(mangled_func_name, &mangled[0]);
        mangled_func_len = cast(int) strlen(mangled_func_name);
        
        fs = find_function(mangled_func_name);
      } else {
        char* name = cast(char*) calloc(1, node.ident.len + 1);
        memcpy(name, node.ident.str, node.ident.len);
        mangled_func_name = name;
        mangled_func_len = node.ident.len;
        fs = find_function(name);
      }

      for (NodeList* args = &node.args; args.value; args = args.next) {
        args_vars[n_arg] = gen(args.value);
        n_arg++;
      }
      assert(n_arg < 21);
      
      if (!fs) {
        printf("# DEBUG: gen(funcall) '%s' NOT FOUND in registered_functions!\n", mangled_func_name);
      } else {
        const(char)* ret_name = fs.return_type.name;
        if (!ret_name) ret_name = "null";
        printf("# DEBUG: gen(funcall) '%s' FOUND ret='%s' ptr_depth=%d\n",
               mangled_func_name, ret_name, fs.return_type.ptr_depth);
      }

      char ret_type = 'w';
      if (fs && fs.return_type.ptr_depth > 0) {
        ret_type = 'l';
      }
      int res = next_reg();
      printf("  %%t%d =%c call $%.*s(", res, ret_type, mangled_func_len, mangled_func_name);
      for (int i = 0; i < n_arg; ++i) {
        if (fs && fs.is_variadic && i == fs.num_params) {
          printf("..., ");
        }
        char c = get_reg_type(args_vars[i]);
        if (c != 'w' && c != 'l') c = 'w';
        printf("%c %%t%d", c, args_vars[i]);
        if (i != n_arg - 1) {
          printf(", ");
        }
      }
      printf(")\n");
      set_reg_type(res, ret_type);
      return res;
    }
  if (node.kind == NodeKind.NK_defun) {
      if (node.is_decl_only) {
        return 0;
      }
      current_fn = node;
      
      reg_counter = 0;
      
      locals_count = 0;
      for (int i = 0; node.params[i]; ++i) {
        add_local(node.params[i], &node.params_types[i]);
      }
      collect_locals(node.then);
      
      const(char)* ret_type_str = "w";
      if (node.return_type.ptr_depth > 0) {
        ret_type_str = "l";
      }
      printf("export function %s $%.*s(", ret_type_str, node.ident.len, node.ident.str);
      for (int i = 0; node.params[i]; ++i) {
        const(Token)* p = node.params[i];
        Type t = node.params_types[i];
        const(char)* t_str = "w";
        if (t.ptr_depth > 0) {
          t_str = "l";
        }
        printf("%s %%%.*s", t_str, p.len, p.str);
        if (node.params[i + 1]) {
          printf(", ");
        }
      }
      if (node.is_variadic) {
        printf(", ...");
      }
      printf(") {\n@%.*s\n", node.ident.len, node.ident.str);
      
      // Emit stack allocations for all variables and parameters
      for (int i = 0; i < locals_count; ++i) {
        Type t = locals[i].type;
        int size = get_type_size(&t);
        int align_ = get_type_alignment(&t);
        int qbe_align = 4;
        if (align_ > 8) qbe_align = 16;
        else if (align_ > 4) qbe_align = 8;
        printf("  %%%.*s_addr =l alloc%d %d\n", cast(int)strlen(locals[i].name), locals[i].name, qbe_align, size);
      }
      
      // Store incoming parameters into stack slots
      for (int i = 0; node.params[i]; ++i) {
        const(Token)* p = node.params[i];
        Type t = node.params_types[i];
        if (t.ptr_depth > 0) {
          printf("  storel %%%.*s, %%%.*s_addr\n", p.len, p.str, p.len, p.str);
        } else {
          printf("  storew %%%.*s, %%%.*s_addr\n", p.len, p.str, p.len, p.str);
        }
      }
      
      gen(node.then);
      if (!ends_with_return(node.then)) {
        printf("  ret\n");
      }
      printf("}\n");
      return 0;
    }
  if (node.kind == NodeKind.NK_add) {
      Type lt; get_expr_type(node.lhs, &lt);
      Type rt; get_expr_type(node.rhs, &rt);
      if (lt.ptr_depth > 0) {
        int l = gen(node.lhs);
        int r = gen(node.rhs);
        Type tmp_type;
        tmp_type.name = lt.name;
        tmp_type.ptr_depth = lt.ptr_depth - 1;
        tmp_type.array_dims = 0;
        int scale = get_type_size(&tmp_type);
        int offset_reg = r;
        if (scale > 1) {
          int mul_res = next_reg();
          printf("  %%t%d =w mul %%t%d, %d\n", mul_res, r, scale);
          offset_reg = mul_res;
        }
        int ext_res = next_reg();
        printf("  %%t%d =l extsw %%t%d\n", ext_res, offset_reg);
        int add_res = next_reg();
        printf("  %%t%d =l add %%t%d, %%t%d\n", add_res, l, ext_res);
        set_reg_type(add_res, 'l');
        return add_res;
      }
      if (rt.ptr_depth > 0) {
        int l = gen(node.lhs);
        int r = gen(node.rhs);
        Type tmp_type;
        tmp_type.name = rt.name;
        tmp_type.ptr_depth = rt.ptr_depth - 1;
        tmp_type.array_dims = 0;
        int scale = get_type_size(&tmp_type);
        int offset_reg = l;
        if (scale > 1) {
          int mul_res = next_reg();
          printf("  %%t%d =w mul %%t%d, %d\n", mul_res, l, scale);
          offset_reg = mul_res;
        }
        int ext_res = next_reg();
        printf("  %%t%d =l extsw %%t%d\n", ext_res, offset_reg);
        int add_res = next_reg();
        printf("  %%t%d =l add %%t%d, %%t%d\n", add_res, r, ext_res);
        set_reg_type(add_res, 'l');
        return add_res;
      }
      return gen_binop(node, "add");
    }
  if (node.kind == NodeKind.NK_sub) {
      Type lt; get_expr_type(node.lhs, &lt);
      Type rt; get_expr_type(node.rhs, &rt);
      if (lt.ptr_depth > 0 && rt.ptr_depth > 0) {
        int l = gen(node.lhs);
        int r = gen(node.rhs);
        int sub_res = next_reg();
        printf("  %%t%d =l sub %%t%d, %%t%d\n", sub_res, l, r);
        Type tmp_type;
        tmp_type.name = lt.name;
        tmp_type.ptr_depth = lt.ptr_depth - 1;
        tmp_type.array_dims = 0;
        int scale = get_type_size(&tmp_type);
        int div_res = sub_res;
        if (scale > 1) {
          div_res = next_reg();
          printf("  %%t%d =l div %%t%d, %d\n", div_res, sub_res, scale);
        }
        int copy_res = next_reg();
        printf("  %%t%d =w copy %%t%d\n", copy_res, div_res);
        set_reg_type(copy_res, 'w');
        return copy_res;
      }
      if (lt.ptr_depth > 0) {
        int l = gen(node.lhs);
        int r = gen(node.rhs);
        Type tmp_type;
        tmp_type.name = lt.name;
        tmp_type.ptr_depth = lt.ptr_depth - 1;
        tmp_type.array_dims = 0;
        int scale = get_type_size(&tmp_type);
        int offset_reg = r;
        if (scale > 1) {
          int mul_res = next_reg();
          printf("  %%t%d =w mul %%t%d, %d\n", mul_res, r, scale);
          offset_reg = mul_res;
        }
        int ext_res = next_reg();
        printf("  %%t%d =l extsw %%t%d\n", ext_res, offset_reg);
        int sub_res = next_reg();
        printf("  %%t%d =l sub %%t%d, %%t%d\n", sub_res, l, ext_res);
        set_reg_type(sub_res, 'l');
        return sub_res;
      }
      return gen_binop(node, "sub");
    }
  if (node.kind == NodeKind.NK_mul) {
      return gen_binop(node, "mul");
    }
  if (node.kind == NodeKind.NK_div) {
      return gen_binop(node, "div");
    }
  if (node.kind == NodeKind.NK_mod) {
      return gen_binop(node, "rem");
    }
  if (node.kind == NodeKind.NK_bitwise_and) {
      return gen_binop(node, "and");
    }
  if (node.kind == NodeKind.NK_bitwise_or) {
      return gen_binop(node, "or");
    }
  if (node.kind == NodeKind.NK_bitwise_xor) {
      return gen_binop(node, "xor");
    }
  if (node.kind == NodeKind.NK_lshift) {
      return gen_binop(node, "shl");
    }
  if (node.kind == NodeKind.NK_rshift) {
      return gen_binop(node, "sar");
    }
  if (node.kind == NodeKind.NK_lt_op) {
      return gen_binop(node, "csltw");
    }
  if (node.kind == NodeKind.NK_le) {
      return gen_binop(node, "cslew");
    }
  if (node.kind == NodeKind.NK_eq) {
      return gen_binop(node, "ceqw");
    }
  if (node.kind == NodeKind.NK_ne) {
      return gen_binop(node, "cnew");
    }
  if (node.kind == NodeKind.NK_logical_and) {
      int addr = next_reg();
      printf("  %%t%d =l alloc4 4\n", addr);
      set_reg_type(addr, 'l');
      
      int label_id = next_reg();
      int l = gen(node.lhs);
      printf("  jnz %%t%d, @and_eval_b%d, @and_false%d\n", l, label_id, label_id);
      
      printf("@and_eval_b%d\n", label_id);
      int r = gen(node.rhs);
      int r_bool = next_reg();
      printf("  %%t%d =w cnew %%t%d, 0\n", r_bool, r);
      set_reg_type(r_bool, 'w');
      printf("  storew %%t%d, %%t%d\n", r_bool, addr);
      printf("  jmp @and_end%d\n", label_id);
      
      printf("@and_false%d\n", label_id);
      int zero = next_reg();
      printf("  %%t%d =w copy 0\n", zero);
      set_reg_type(zero, 'w');
      printf("  storew %%t%d, %%t%d\n", zero, addr);
      printf("  jmp @and_end%d\n", label_id);
      
      printf("@and_end%d\n", label_id);
      int res = next_reg();
      printf("  %%t%d =w loadw %%t%d\n", res, addr);
      set_reg_type(res, 'w');
      return res;
    }
  if (node.kind == NodeKind.NK_logical_or) {
      int addr = next_reg();
      printf("  %%t%d =l alloc4 4\n", addr);
      set_reg_type(addr, 'l');
      
      int label_id = next_reg();
      int l = gen(node.lhs);
      printf("  jnz %%t%d, @or_true%d, @or_eval_b%d\n", l, label_id, label_id);
      
      printf("@or_eval_b%d\n", label_id);
      int r = gen(node.rhs);
      int r_bool = next_reg();
      printf("  %%t%d =w cnew %%t%d, 0\n", r_bool, r);
      set_reg_type(r_bool, 'w');
      printf("  storew %%t%d, %%t%d\n", r_bool, addr);
      printf("  jmp @or_end%d\n", label_id);
      
      printf("@or_true%d\n", label_id);
      int one = next_reg();
      printf("  %%t%d =w copy 1\n", one);
      set_reg_type(one, 'w');
      printf("  storew %%t%d, %%t%d\n", one, addr);
      printf("  jmp @or_end%d\n", label_id);
      
      printf("@or_end%d\n", label_id);
      int res = next_reg();
      printf("  %%t%d =w loadw %%t%d\n", res, addr);
      set_reg_type(res, 'w');
      return res;
    }
  if (node.kind == NodeKind.NK_logical_not) {
      int val = gen(node.lhs);
      int res = next_reg();
      char c = get_reg_type(val);
      if (c != 'w' && c != 'l') c = 'w';
      printf("  %%t%d =w ceq%c %%t%d, 0\n", res, c, val);
      set_reg_type(res, 'w');
      return res;
    }
  if (node.kind == NodeKind.NK_bitwise_not) {
      int val = gen(node.lhs);
      int res = next_reg();
      printf("  %%t%d =w xor %%t%d, -1\n", res, val);
      set_reg_type(res, 'w');
      return res;
    }
  if (node.kind == NodeKind.NK_dot) {
      if (node.ident.len == 6 && strncmp(node.ident.str, "sizeof", 6) == 0) {
        int res = next_reg();
        Type t;
        get_expr_type(node.lhs, &t);
        printf("  %%t%d =w copy %d\n", res, get_type_size(&t));
        set_reg_type(res, 'w');
        return res;
      }
      int addr = gen_addr(node);
      Type t;
      get_expr_type(node, &t);
      return emit_load(addr, &t);
    }
  if (node.kind == NodeKind.NK_pre_inc) {
      return gen_inc_dec(node, true, true);
    }
  if (node.kind == NodeKind.NK_pre_dec) {
      return gen_inc_dec(node, false, true);
    }
  if (node.kind == NodeKind.NK_post_inc) {
      return gen_inc_dec(node, true, false);
    }
  if (node.kind == NodeKind.NK_post_dec) {
      return gen_inc_dec(node, false, false);
    }
  if (node.kind == NodeKind.NK_case_) {
      int sw_id = current_break_id();
      printf("@switch%d_case_%d\n", sw_id, node.val);
      return 0;
    }
  if (node.kind == NodeKind.NK_default_) {
      int sw_id = current_break_id();
      printf("@switch%d_default\n", sw_id);
      return 0;
    }
  assert(0);
}

unittest {
  Node* var1 = new_node(NodeKind.NK_var_decl);
  Token t1;
  t1.str = cast(char*) "abc";
  t1.len = 3;
  var1.ident = &t1;
  var1.type.name = "int";
  
  locals_count = 0;
  collect_locals(var1);
  assert(locals_count == 1);
  assert(strcmp(locals[0].name, "abc") == 0);
  assert(strcmp(locals[0].type.name, "int") == 0);

  // Test type inference: b = &abc
  Node* var2 = new_node(NodeKind.NK_lvar);
  var2.ident = &t1; // "abc"
  
  Node* addr = new_node(NodeKind.NK_addr);
  addr.lhs = var2; // &abc
  
  Node* assign = new_node(NodeKind.NK_assign);
  Token t2;
  t2.str = cast(char*) "b";
  t2.len = 1;
  assign.lhs = new_node(NodeKind.NK_lvar);
  assign.lhs.ident = &t2;
  assign.rhs = addr;
  
  collect_locals(assign);
  Type b_type;
  get_local_type(&t2, &b_type);
  assert(strcmp(b_type.name, "int") == 0);
  assert(b_type.ptr_depth == 1); // should be int*

  // Test auto local variable type inference in collect_locals
  Token t_auto;
  t_auto.str = cast(char*) "auto_var";
  t_auto.len = 8;
  
  Node* auto_decl = new_node(NodeKind.NK_var_decl);
  auto_decl.ident = &t_auto;
  auto_decl.type.name = "auto";
  auto_decl.lhs = new_node_num(42); // auto auto_var = 42;

  collect_locals(auto_decl);
  Type auto_type;
  get_local_type(&t_auto, &auto_type);
  assert(strcmp(auto_type.name, "int") == 0);
  assert(auto_type.ptr_depth == 0);
}





extern (C) FILE* get_stderr();

extern (C)
int main(int argc, char** argv) {
  if (argc != 2) {
    fprintf(get_stderr(), "wrong number of args\n");
    return 1;
  }

  user_input = argv[1];
  token = tokenize(argv[1]);
  printf("# DEBUG: tokens:\n");
  Token* tok = token;
  while (tok) {
    printf("# DEBUG:   token '%.*s' kind=%d\n", tok.len, tok.str, tok.kind);
    tok = tok.next;
  }
  program();
  printf("# DEBUG: code_count=%d\n", code_count);

  int ret = 0;
  for (int i = 0; code[i]; i++) {
    if (code[i].kind == NodeKind.NK_gvar_decl) {
      if (code[i].type.name && strcmp(code[i].type.name, "auto") == 0) {
        Type inferred;
        infer_type(code[i].lhs, &inferred);
        code[i].type = inferred;
      }
      add_global(code[i].ident, &code[i].type);
    }
  }
  for (int i = 0; code[i]; i++) {
    gen(code[i]);
  }
  gen_strings();

  return 0;
}
