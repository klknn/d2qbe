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
      p += 3;
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
      p += len;
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
      p += len;
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
      p += len;
      cur = new_token(TokenKind.TK_label, cur, start, cast(int)(p - start));
      continue;
    }

    // identifier (keywords, types, instruction ops)
    int ident_len = identifier_length(p);
    if (ident_len) {
      cur = new_token(TokenKind.TK_ident, cur, p, ident_len);
      p += ident_len;
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



enum InstKind {
  IK_label,
  IK_assign,
  IK_store,
  IK_jmp,
  IK_jnz,
  IK_ret,
  IK_call,
}

struct Variable {
  char* name;
  char type; // 'w', 'l', 'b'
}

struct Instruction {
  InstKind kind;
  char* label; // for IK_label, IK_jmp
  char* dest;  // for IK_assign
  char dest_type; // 'w', 'l', 'b'
  char* op;    // e.g. "add", "sub", "copy", "alloc4", "loadw", etc.
  char* arg1;  // first argument (can be %temp, $global, or constant)
  char* arg2;  // second argument
  char* label_else; // for IK_jnz
  
  Variable[20] call_args;
  int call_args_count;
}

struct FunctionDef {
  char* name;
  bool is_export;
  char ret_type; // 'w', 'l', '0' (none)
  Variable[20] params;
  int params_count;
  bool is_variadic;
  
  Instruction[5000] instructions;
  int inst_count;
}

struct DataItem {
  char type; // 'w', 'l', 'b', 'z'
  char* val_str; // string representation of number or string literal
}

struct DataDef {
  char* name;
  DataItem[100] items;
  int items_count;
}

FunctionDef[200] program_functions;
int program_functions_count = 0;

DataDef[2000] program_data;
int program_data_count = 0;

char* token_to_str(Token* tok) {
  if (!tok) return null;
  char* copy = cast(char*) calloc(1, tok.len + 1);
  memcpy(copy, tok.str, tok.len);
  return copy;
}

void parse_data() {
  expect("data");
  Token* name_tok = consume_kind(TokenKind.TK_global);
  if (!name_tok) {
    error("Expected global name starting with $ after 'data'");
  }
  
  DataDef def;
  def.name = token_to_str(name_tok);
  def.items_count = 0;
  
  expect("=");
  expect("{");
  
  while (!consume("}")) {
    Token* type_tok = consume_kind(TokenKind.TK_ident);
    if (!type_tok) {
      error("Expected data type inside block");
    }
    
    char type = type_tok.str[0]; // 'w', 'l', 'b', 'z'
    Token* val_tok = null;
    if (type == 'z') {
      // zero fill expects just a number
      val_tok = consume_kind(TokenKind.TK_num);
    } else if (type == 'b') {
      // byte can be a number or a string literal
      val_tok = consume_kind(TokenKind.TK_str_literal);
      if (!val_tok) {
        val_tok = consume_kind(TokenKind.TK_num);
      }
    } else {
      // word or long can be a number or a global address/reference
      val_tok = consume_kind(TokenKind.TK_num);
      if (!val_tok) {
        val_tok = consume_kind(TokenKind.TK_global);
      }
    }
    
    if (!val_tok) {
      error("Expected data value");
    }
    
    DataItem item;
    item.type = type;
    item.val_str = token_to_str(val_tok);
    
    assert(def.items_count < 100);
    def.items[def.items_count++] = item;
    
    consume(",");
  }
  
  assert(program_data_count < 2000);
  program_data[program_data_count++] = def;
}

void parse_function() {
  bool is_export = false;
  if (consume("export")) {
    is_export = true;
  }
  expect("function");
  
  char ret_type = '0';
  Token* ret_type_tok = consume_kind(TokenKind.TK_ident);
  if (ret_type_tok) {
    ret_type = ret_type_tok.str[0];
  }
  
  Token* name_tok = consume_kind(TokenKind.TK_global);
  if (!name_tok) {
    error("Expected function name after 'function'");
  }
  
  FunctionDef fn;
  fn.name = token_to_str(name_tok);
  fn.is_export = is_export;
  fn.ret_type = ret_type;
  fn.params_count = 0;
  fn.is_variadic = false;
  fn.inst_count = 0;
  
  expect("(");
  while (!consume(")")) {
    if (consume("...")) {
      fn.is_variadic = true;
      expect(")");
      break;
    }
    
    Token* type_tok = consume_kind(TokenKind.TK_ident);
    if (!type_tok) {
      error("Expected parameter type");
    }
    
    Token* param_tok = consume_kind(TokenKind.TK_temp);
    if (!param_tok) {
      error("Expected parameter name starting with %");
    }
    
    Variable var;
    var.name = token_to_str(param_tok);
    var.type = type_tok.str[0];
    
    assert(fn.params_count < 20);
    fn.params[fn.params_count++] = var;
    
    consume(",");
  }
  
  expect("{");
  
  while (!consume("}")) {
    // Check if label definition
    Token* label_tok = consume_kind(TokenKind.TK_label);
    if (label_tok) {
      Instruction inst;
      inst.kind = InstKind.IK_label;
      inst.label = token_to_str(label_tok);
      
      assert(fn.inst_count < 5000);
      fn.instructions[fn.inst_count++] = inst;
      continue;
    }
    
    // Check if store instruction
    Token* op_tok = consume_kind(TokenKind.TK_ident);
    if (op_tok && (strncmp(op_tok.str, "store", 5) == 0)) {
      Instruction inst;
      inst.kind = InstKind.IK_store;
      inst.op = token_to_str(op_tok);
      
      // store arg1, arg2
      Token* arg1_tok = consume_kind(TokenKind.TK_temp);
      if (!arg1_tok) arg1_tok = consume_kind(TokenKind.TK_num);
      if (!arg1_tok) error("Expected value to store");
      
      expect(",");
      
      Token* arg2_tok = consume_kind(TokenKind.TK_temp);
      if (!arg2_tok) error("Expected target address for store");
      
      inst.arg1 = token_to_str(arg1_tok);
      inst.arg2 = token_to_str(arg2_tok);
      
      assert(fn.inst_count < 5000);
      fn.instructions[fn.inst_count++] = inst;
      continue;
    }
    
    // Check if jmp instruction
    if (op_tok && (op_tok.len == 3 && strncmp(op_tok.str, "jmp", 3) == 0)) {
      Instruction inst;
      inst.kind = InstKind.IK_jmp;
      
      Token* label_target = consume_kind(TokenKind.TK_label);
      if (!label_target) error("Expected label target for jmp");
      
      inst.label = token_to_str(label_target);
      
      assert(fn.inst_count < 5000);
      fn.instructions[fn.inst_count++] = inst;
      continue;
    }
    
    // Check if jnz instruction
    if (op_tok && (op_tok.len == 3 && strncmp(op_tok.str, "jnz", 3) == 0)) {
      Instruction inst;
      inst.kind = InstKind.IK_jnz;
      
      Token* cond_tok = consume_kind(TokenKind.TK_temp);
      if (!cond_tok) error("Expected condition temp for jnz");
      
      expect(",");
      
      Token* label_then = consume_kind(TokenKind.TK_label);
      if (!label_then) error("Expected then label for jnz");
      
      expect(",");
      
      Token* label_else = consume_kind(TokenKind.TK_label);
      if (!label_else) error("Expected else label for jnz");
      
      inst.arg1 = token_to_str(cond_tok);
      inst.label = token_to_str(label_then);
      inst.label_else = token_to_str(label_else);
      
      assert(fn.inst_count < 5000);
      fn.instructions[fn.inst_count++] = inst;
      continue;
    }
    
    // Check if ret instruction
    if (op_tok && (op_tok.len == 3 && strncmp(op_tok.str, "ret", 3) == 0)) {
      Instruction inst;
      inst.kind = InstKind.IK_ret;
      
      Token* ret_val_tok = consume_kind(TokenKind.TK_temp);
      if (!ret_val_tok) ret_val_tok = consume_kind(TokenKind.TK_num);
      
      if (ret_val_tok) {
        inst.arg1 = token_to_str(ret_val_tok);
      }
      
      assert(fn.inst_count < 5000);
      fn.instructions[fn.inst_count++] = inst;
      continue;
    }
    
    // Check if call instruction (void call)
    if (op_tok && (op_tok.len == 4 && strncmp(op_tok.str, "call", 4) == 0)) {
      Instruction inst;
      inst.kind = InstKind.IK_call;
      
      Token* call_target = consume_kind(TokenKind.TK_global);
      if (!call_target) error("Expected call target function");
      
      inst.op = token_to_str(call_target);
      inst.call_args_count = 0;
      
      expect("(");
      while (!consume(")")) {
        Token* arg_type = consume_kind(TokenKind.TK_ident);
        if (!arg_type) error("Expected argument type in call");
        
        Token* arg_val = consume_kind(TokenKind.TK_temp);
        if (!arg_val) arg_val = consume_kind(TokenKind.TK_num);
        if (!arg_val) arg_val = consume_kind(TokenKind.TK_global);
        if (!arg_val) error("Expected argument value in call");
        
        Variable arg;
        arg.name = token_to_str(arg_val);
        arg.type = arg_type.str[0];
        
        assert(inst.call_args_count < 20);
        inst.call_args[inst.call_args_count++] = arg;
        
        consume(",");
      }
      
      assert(fn.inst_count < 5000);
      fn.instructions[fn.inst_count++] = inst;
      continue;
    }
    
    // Otherwise, must be assignment: %temp =type op ... or %temp =type call ...
    if (op_tok) {
      // Since we already consumed op_tok, wait, if it was TK_temp, we should have consumed it as TK_temp!
      // But we consumed TK_ident. So if it is an assignment, the first token is a temporary!
      // Ah! We did not check if the first token is a temporary!
      // Let's restructure the parsing of assignment / call:
      // We will put the consumed op_tok back or check its type.
      // Wait, we didn't consume a temp first. Let's look at the logic.
      // At the start of the loop body:
      // If we see a temp, it MUST be an assignment!
      // Let's implement that.
    }
    
    // Let's handle parsing by token checking
  }
}

// Let's rewrite the loop body of parse_function to be clean and correct
void parse_instruction_list(FunctionDef* fn) {
  while (!consume("}")) {
    Token* label_tok = consume_kind(TokenKind.TK_label);
    if (label_tok) {
      Instruction inst;
      inst.kind = InstKind.IK_label;
      inst.label = token_to_str(label_tok);
      fn.instructions[fn.inst_count++] = inst;
      continue;
    }
    
    Token* temp_tok = consume_kind(TokenKind.TK_temp);
    if (temp_tok) {
      // Assignment: %temp =type op ...
      expect("=");
      Token* type_tok = consume_kind(TokenKind.TK_ident);
      if (!type_tok) error("Expected assignment type");
      
      Instruction inst;
      inst.kind = InstKind.IK_assign;
      inst.dest = token_to_str(temp_tok);
      inst.dest_type = type_tok.str[0];
      
      Token* op_tok = consume_kind(TokenKind.TK_ident);
      if (!op_tok) error("Expected operation or call");
      
      if (op_tok.len == 4 && strncmp(op_tok.str, "call", 4) == 0) {
        inst.op = token_to_str(op_tok); // "call"
        Token* target = consume_kind(TokenKind.TK_global);
        if (!target) error("Expected call target global name");
        inst.arg1 = token_to_str(target);
        inst.call_args_count = 0;
        
        expect("(");
        while (!consume(")")) {
          if (consume("...")) {
            consume(",");
            continue;
          }
          Token* arg_type = consume_kind(TokenKind.TK_ident);
          if (!arg_type) error("Expected argument type in call");
          
          Token* arg_val = consume_kind(TokenKind.TK_temp);
          if (!arg_val) arg_val = consume_kind(TokenKind.TK_num);
          if (!arg_val) arg_val = consume_kind(TokenKind.TK_global);
          if (!arg_val) error("Expected argument value in call");
          
          Variable arg;
          arg.name = token_to_str(arg_val);
          arg.type = arg_type.str[0];
          
          assert(inst.call_args_count < 20);
          inst.call_args[inst.call_args_count++] = arg;
          
          consume(",");
        }
      } else {
        // regular operation (e.g. add, copy, loadw, alloc4)
        inst.op = token_to_str(op_tok);
        
        Token* arg1_tok = consume_kind(TokenKind.TK_temp);
        if (!arg1_tok) arg1_tok = consume_kind(TokenKind.TK_num);
        if (!arg1_tok) arg1_tok = consume_kind(TokenKind.TK_global);
        if (!arg1_tok) arg1_tok = consume_kind(TokenKind.TK_ident); // e.g. alloc4 expects a number or type? QBE IR says: alloc4 4
        
        if (arg1_tok) {
          inst.arg1 = token_to_str(arg1_tok);
        }
        
        if (consume(",")) {
          Token* arg2_tok = consume_kind(TokenKind.TK_temp);
          if (!arg2_tok) arg2_tok = consume_kind(TokenKind.TK_num);
          if (!arg2_tok) arg2_tok = consume_kind(TokenKind.TK_global);
          if (!arg2_tok) error("Expected second argument after comma");
          
          inst.arg2 = token_to_str(arg2_tok);
        }
      }
      
      assert(fn.inst_count < 5000);
      fn.instructions[fn.inst_count++] = inst;
      continue;
    }
    
    Token* op_tok = consume_kind(TokenKind.TK_ident);
    if (!op_tok) {
      error_at(token.str, "Expected instruction inside function");
    }
    
    if (strncmp(op_tok.str, "store", 5) == 0) {
      Instruction inst;
      inst.kind = InstKind.IK_store;
      inst.op = token_to_str(op_tok);
      
      Token* arg1_tok = consume_kind(TokenKind.TK_temp);
      if (!arg1_tok) arg1_tok = consume_kind(TokenKind.TK_num);
      if (!arg1_tok) error("Expected value to store");
      
      expect(",");
      
      Token* arg2_tok = consume_kind(TokenKind.TK_temp);
      if (!arg2_tok) error("Expected destination address for store");
      
      inst.arg1 = token_to_str(arg1_tok);
      inst.arg2 = token_to_str(arg2_tok);
      
      assert(fn.inst_count < 5000);
      fn.instructions[fn.inst_count++] = inst;
      continue;
    }
    
    if (op_tok.len == 3 && strncmp(op_tok.str, "jmp", 3) == 0) {
      Instruction inst;
      inst.kind = InstKind.IK_jmp;
      
      Token* label_target = consume_kind(TokenKind.TK_label);
      if (!label_target) error("Expected label target for jmp");
      
      inst.label = token_to_str(label_target);
      
      assert(fn.inst_count < 5000);
      fn.instructions[fn.inst_count++] = inst;
      continue;
    }
    
    if (op_tok.len == 3 && strncmp(op_tok.str, "jnz", 3) == 0) {
      Instruction inst;
      inst.kind = InstKind.IK_jnz;
      
      Token* cond_tok = consume_kind(TokenKind.TK_temp);
      if (!cond_tok) error("Expected condition temp for jnz");
      
      expect(",");
      
      Token* label_then = consume_kind(TokenKind.TK_label);
      if (!label_then) error("Expected then label for jnz");
      
      expect(",");
      
      Token* label_else = consume_kind(TokenKind.TK_label);
      if (!label_else) error("Expected else label for jnz");
      
      inst.arg1 = token_to_str(cond_tok);
      inst.label = token_to_str(label_then);
      inst.label_else = token_to_str(label_else);
      
      assert(fn.inst_count < 5000);
      fn.instructions[fn.inst_count++] = inst;
      continue;
    }
    
    if (op_tok.len == 3 && strncmp(op_tok.str, "ret", 3) == 0) {
      Instruction inst;
      inst.kind = InstKind.IK_ret;
      
      Token* ret_val_tok = consume_kind(TokenKind.TK_temp);
      if (!ret_val_tok) ret_val_tok = consume_kind(TokenKind.TK_num);
      
      if (ret_val_tok) {
        inst.arg1 = token_to_str(ret_val_tok);
      }
      
      assert(fn.inst_count < 5000);
      fn.instructions[fn.inst_count++] = inst;
      continue;
    }
    
    if (op_tok.len == 4 && strncmp(op_tok.str, "call", 4) == 0) {
      Instruction inst;
      inst.kind = InstKind.IK_call;
      inst.op = token_to_str(op_tok);
      
      Token* target = consume_kind(TokenKind.TK_global);
      if (!target) error("Expected call target global name");
      inst.arg1 = token_to_str(target);
      inst.call_args_count = 0;
      
      expect("(");
      while (!consume(")")) {
        if (consume("...")) {
          consume(",");
          continue;
        }
        Token* arg_type = consume_kind(TokenKind.TK_ident);
        if (!arg_type) error("Expected argument type in call");
        
        Token* arg_val = consume_kind(TokenKind.TK_temp);
        if (!arg_val) arg_val = consume_kind(TokenKind.TK_num);
        if (!arg_val) arg_val = consume_kind(TokenKind.TK_global);
        if (!arg_val) error("Expected argument value in call");
        
        Variable arg;
        arg.name = token_to_str(arg_val);
        arg.type = arg_type.str[0];
        
        assert(inst.call_args_count < 20);
        inst.call_args[inst.call_args_count++] = arg;
        
        consume(",");
      }
      
      assert(fn.inst_count < 5000);
      fn.instructions[fn.inst_count++] = inst;
      continue;
    }
    
    error_at(op_tok.str, "Unknown QBE instruction");
  }
}

void parse_program() {
  program_functions_count = 0;
  program_data_count = 0;
  
  while (!at_eof()) {
    if (is_token("data")) {
      parse_data();
      continue;
    }
    if (is_token("export") || is_token("function")) {
      FunctionDef fn;
      fn.inst_count = 0;
      fn.params_count = 0;
      
      bool is_export = false;
      if (consume("export")) {
        is_export = true;
      }
      expect("function");
      
      char ret_type = '0';
      Token* ret_type_tok = consume_kind(TokenKind.TK_ident);
      if (ret_type_tok) {
        ret_type = ret_type_tok.str[0];
      }
      
      Token* name_tok = consume_kind(TokenKind.TK_global);
      if (!name_tok) {
        error("Expected function name");
      }
      
      fn.name = token_to_str(name_tok);
      fn.is_export = is_export;
      fn.ret_type = ret_type;
      
      expect("(");
      while (!consume(")")) {
        if (consume("...")) {
          fn.is_variadic = true;
          expect(")");
          break;
        }
        
        Token* type_tok = consume_kind(TokenKind.TK_ident);
        if (!type_tok) error("Expected param type");
        
        Token* param_tok = consume_kind(TokenKind.TK_temp);
        if (!param_tok) error("Expected param name");
        
        Variable var;
        var.name = token_to_str(param_tok);
        var.type = type_tok.str[0];
        
        assert(fn.params_count < 20);
        fn.params[fn.params_count++] = var;
        
        consume(",");
      }
      
      expect("{");
      parse_instruction_list(&fn);
      
      assert(program_functions_count < 200);
      program_functions[program_functions_count++] = fn;
      continue;
    }
    
    error_at(token.str, "Expected top-level QBE declaration (data or function)");
  }
}

unittest {
  char* input = cast(char*) "\n    data $g = { w 42 }\n    data $str = { b \"hello\\n\", b 0 }\n    \n    export function w $add(w %a, w %b) {\n    @start\n      %t1 =w add %a, %b\n      ret %t1\n    }\n  ";
  
  token = tokenize(input);
  parse_program();
  
  assert(program_data_count == 2);
  assert(strcmp(program_data[0].name, "$g") == 0);
  assert(program_data[0].items_count == 1);
  assert(program_data[0].items[0].type == 'w');
  assert(strcmp(program_data[0].items[0].val_str, "42") == 0);
  
  assert(strcmp(program_data[1].name, "$str") == 0);
  assert(program_data[1].items_count == 2);
  assert(program_data[1].items[0].type == 'b');
  assert(strcmp(program_data[1].items[0].val_str, "\"hello\\n\"") == 0);
  
  assert(program_functions_count == 1);
  FunctionDef* fn = &program_functions[0];
  assert(strcmp(fn.name, "$add") == 0);
  assert(fn.is_export == true);
  assert(fn.ret_type == 'w');
  assert(fn.params_count == 2);
  assert(strcmp(fn.params[0].name, "%a") == 0);
  
  assert(fn.inst_count == 3);
  assert(fn.instructions[0].kind == InstKind.IK_label);
  assert(strcmp(fn.instructions[0].label, "@start") == 0);
  
  assert(fn.instructions[1].kind == InstKind.IK_assign);
  assert(strcmp(fn.instructions[1].dest, "%t1") == 0);
  assert(fn.instructions[1].dest_type == 'w');
  assert(strcmp(fn.instructions[1].op, "add") == 0);
  assert(strcmp(fn.instructions[1].arg1, "%a") == 0);
  assert(strcmp(fn.instructions[1].arg2, "%b") == 0);
  
  assert(fn.instructions[2].kind == InstKind.IK_ret);
  assert(strcmp(fn.instructions[2].arg1, "%t1") == 0);
}



struct TempMap {
  char* name;
  int offset;
}

TempMap[10000] temp_offsets;
int temp_offsets_count = 0;

struct VarMap {
  char* name;
  int offset;
}

VarMap[5000] var_offsets;
int var_offsets_count = 0;

int stack_offset_counter = 0;

void reset_offsets() {
  temp_offsets_count = 0;
  var_offsets_count = 0;
  stack_offset_counter = 0;
}

int get_temp_offset(const char* name) {
  for (int i = 0; i < temp_offsets_count; i++) {
    if (strcmp(temp_offsets[i].name, name) == 0) {
      if (current_fn_name && strcmp(current_fn_name, "parse_function") == 0) {
        fprintf(get_stderr(), "MATCH: %s -> %d\n", name, temp_offsets[i].offset);
      }
      return temp_offsets[i].offset;
    }
  }
  
  // Allocate new slot
  stack_offset_counter += 8; // 8 bytes for every temporary
  
  if (current_fn_name && strcmp(current_fn_name, "parse_function") == 0) {
    fprintf(get_stderr(), "MAP: %s -> %d (count=%d)\n", name, stack_offset_counter, temp_offsets_count);
  }
  
  assert(temp_offsets_count < 10000);
  temp_offsets[temp_offsets_count].name = cast(char*) name;
  temp_offsets[temp_offsets_count].offset = stack_offset_counter;
  temp_offsets_count++;
  return stack_offset_counter;
}

int get_var_offset(const char* name, int size, int align_) {
  for (int i = 0; i < var_offsets_count; i++) {
    if (strcmp(var_offsets[i].name, name) == 0) {
      return var_offsets[i].offset;
    }
  }
  
  // Align stack counter
  stack_offset_counter = ((stack_offset_counter + align_ - 1) / align_) * align_;
  int ret_offset = stack_offset_counter + size;
  stack_offset_counter += size;
  
  assert(var_offsets_count < 5000);
  var_offsets[var_offsets_count].name = cast(char*) name;
  var_offsets[var_offsets_count].offset = ret_offset;
  var_offsets_count++;
  return ret_offset;
}

void load_arg(const char* arg, const char* reg, char type, FILE* f) {
  if (arg[0] == '%') {
    int offset = get_temp_offset(arg);
    if (type == 'w') {
      fprintf(f, "  movl -%d(%%rbp), %s\n", offset, reg);
    } else {
      fprintf(f, "  movq -%d(%%rbp), %s\n", offset, reg);
    }
  } else if (arg[0] == '$') {
    // Global address
    fprintf(f, "  leaq %s(%%rip), %s\n", arg + 1, reg);
  } else {
    // Number literal
    if (type == 'w') {
      fprintf(f, "  movl $%s, %s\n", arg, reg);
    } else {
      fprintf(f, "  movq $%s, %s\n", arg, reg);
    }
  }
}

void store_reg(const char* dest, const char* reg, char type, FILE* f) {
  int offset = get_temp_offset(dest);
  if (type == 'w') {
    fprintf(f, "  movl %s, -%d(%%rbp)\n", reg, offset);
  } else {
    fprintf(f, "  movq %s, -%d(%%rbp)\n", reg, offset);
  }
}

const char*[6] arg_regs_32 = ["%edi", "%esi", "%edx", "%ecx", "%r8d", "%r9d"];
const char*[6] arg_regs_64 = ["%rdi", "%rsi", "%rdx", "%rcx", "%r8", "%r9"];

const(char)* current_fn_name;

void gen_instruction(Instruction* inst, char fn_ret_type, FILE* f) {
  if (inst.kind == InstKind.IK_label) {
    fprintf(f, ".L%s_%s:\n", current_fn_name, inst.label + 1);
    return;
  }
  
  if (inst.kind == InstKind.IK_jmp) {
    fprintf(f, "  jmp .L%s_%s\n", current_fn_name, inst.label + 1);
    return;
  }
  
  if (inst.kind == InstKind.IK_jnz) {
    load_arg(inst.arg1, "%eax", 'w', f);
    fprintf(f, "  cmpl $0, %%eax\n");
    fprintf(f, "  jne .L%s_%s\n", current_fn_name, inst.label + 1);
    fprintf(f, "  jmp .L%s_%s\n", current_fn_name, inst.label_else + 1);
    return;
  }
  
  if (inst.kind == InstKind.IK_ret) {
    if (inst.arg1) {
      if (fn_ret_type == 'w') {
        load_arg(inst.arg1, "%eax", 'w', f);
      } else {
        load_arg(inst.arg1, "%rax", 'l', f);
      }
    }
    fprintf(f, "  leave\n");
    fprintf(f, "  ret\n");
    return;
  }
  
  if (inst.kind == InstKind.IK_store) {
    // storew %val, %ptr
    char type = inst.op[5]; // 'b', 'h', 'w', 'l'
    if (type == 'b') {
      load_arg(inst.arg1, "%edx", 'w', f);
      load_arg(inst.arg2, "%rax", 'l', f);
      fprintf(f, "  movb %%dl, (%%rax)\n");
    } else if (type == 'w') {
      load_arg(inst.arg1, "%edx", 'w', f);
      load_arg(inst.arg2, "%rax", 'l', f);
      fprintf(f, "  movl %%edx, (%%rax)\n");
    } else if (type == 'l') {
      load_arg(inst.arg1, "%rdx", 'l', f);
      load_arg(inst.arg2, "%rax", 'l', f);
      fprintf(f, "  movq %%rdx, (%%rax)\n");
    }
    return;
  }
  
  if (inst.kind == InstKind.IK_call) {
    // Void call
    // Set up parameters
    for (int i = 0; i < inst.call_args_count && i < 6; i++) {
      if (inst.call_args[i].type == 'w') {
        load_arg(inst.call_args[i].name, arg_regs_32[i], 'w', f);
      } else {
        load_arg(inst.call_args[i].name, arg_regs_64[i], 'l', f);
      }
    }
    fprintf(f, "  call %s\n", inst.arg1 + 1);
    return;
  }
  
  if (inst.kind == InstKind.IK_assign) {
    if (strcmp(inst.op, "alloc4") == 0 || strcmp(inst.op, "alloc8") == 0 || strcmp(inst.op, "alloc16") == 0) {
      int size = atoi(inst.arg1);
      int align_ = 4;
      if (strcmp(inst.op, "alloc8") == 0) align_ = 8;
      else if (strcmp(inst.op, "alloc16") == 0) align_ = 16;
      
      int var_offset = get_var_offset(inst.dest, size, align_);
      fprintf(f, "  leaq -%d(%%rbp), %%rax\n", var_offset);
      store_reg(inst.dest, "%rax", 'l', f);
      return;
    }
    
    if (strcmp(inst.op, "copy") == 0) {
      if (inst.dest_type == 'w') {
        load_arg(inst.arg1, "%eax", 'w', f);
        store_reg(inst.dest, "%eax", 'w', f);
      } else {
        load_arg(inst.arg1, "%rax", 'l', f);
        store_reg(inst.dest, "%rax", 'l', f);
      }
      return;
    }
    
    if (strcmp(inst.op, "extsw") == 0) {
      load_arg(inst.arg1, "%eax", 'w', f);
      fprintf(f, "  movslq %%eax, %%rax\n");
      store_reg(inst.dest, "%rax", 'l', f);
      return;
    }
    
    if (strncmp(inst.op, "load", 4) == 0) {
      // loadw, loadub, loadl
      load_arg(inst.arg1, "%rax", 'l', f);
      if (strcmp(inst.op, "loadub") == 0) {
        fprintf(f, "  movzbl (%%rax), %%eax\n");
        store_reg(inst.dest, "%eax", 'w', f);
      } else if (strcmp(inst.op, "loadw") == 0) {
        fprintf(f, "  movl (%%rax), %%eax\n");
        store_reg(inst.dest, "%eax", 'w', f);
      } else if (strcmp(inst.op, "loadl") == 0) {
        fprintf(f, "  movq (%%rax), %%rax\n");
        store_reg(inst.dest, "%rax", 'l', f);
      }
      return;
    }
    
    if (strcmp(inst.op, "call") == 0) {
      // Function call with assignment
      for (int i = 0; i < inst.call_args_count && i < 6; i++) {
        if (inst.call_args[i].type == 'w') {
          load_arg(inst.call_args[i].name, arg_regs_32[i], 'w', f);
        } else {
          load_arg(inst.call_args[i].name, arg_regs_64[i], 'l', f);
        }
      }
      fprintf(f, "  call %s\n", inst.arg1 + 1);
      if (inst.dest_type == 'w') {
        store_reg(inst.dest, "%eax", 'w', f);
      } else {
        store_reg(inst.dest, "%rax", 'l', f);
      }
      return;
    }
    
    // Arithmetic & comparison operations
    if (strcmp(inst.op, "add") == 0 || strcmp(inst.op, "sub") == 0 ||
        strcmp(inst.op, "mul") == 0 || strcmp(inst.op, "div") == 0 ||
        strcmp(inst.op, "rem") == 0 || strcmp(inst.op, "and") == 0 ||
        strcmp(inst.op, "or") == 0 || strcmp(inst.op, "xor") == 0 ||
        strcmp(inst.op, "shl") == 0 || strcmp(inst.op, "sar") == 0) {
      if (inst.dest_type == 'w') {
        load_arg(inst.arg1, "%eax", 'w', f);
        load_arg(inst.arg2, "%ecx", 'w', f);
        if (strcmp(inst.op, "add") == 0) {
          fprintf(f, "  addl %%ecx, %%eax\n");
        } else if (strcmp(inst.op, "sub") == 0) {
          fprintf(f, "  subl %%ecx, %%eax\n");
        } else if (strcmp(inst.op, "mul") == 0) {
          fprintf(f, "  imull %%ecx, %%eax\n");
        } else if (strcmp(inst.op, "div") == 0) {
          fprintf(f, "  cltd\n");
          fprintf(f, "  idivl %%ecx\n");
        } else if (strcmp(inst.op, "rem") == 0) {
          fprintf(f, "  cltd\n");
          fprintf(f, "  idivl %%ecx\n");
          fprintf(f, "  movl %%edx, %%eax\n");
        } else if (strcmp(inst.op, "and") == 0) {
          fprintf(f, "  andl %%ecx, %%eax\n");
        } else if (strcmp(inst.op, "or") == 0) {
          fprintf(f, "  orl %%ecx, %%eax\n");
        } else if (strcmp(inst.op, "xor") == 0) {
          fprintf(f, "  xorl %%ecx, %%eax\n");
        } else if (strcmp(inst.op, "shl") == 0) {
          fprintf(f, "  shll %%cl, %%eax\n");
        } else if (strcmp(inst.op, "sar") == 0) {
          fprintf(f, "  sarl %%cl, %%eax\n");
        }
        store_reg(inst.dest, "%eax", 'w', f);
      } else {
        load_arg(inst.arg1, "%rax", 'l', f);
        load_arg(inst.arg2, "%rcx", 'l', f);
        if (strcmp(inst.op, "add") == 0) {
          fprintf(f, "  addq %%rcx, %%rax\n");
        } else if (strcmp(inst.op, "sub") == 0) {
          fprintf(f, "  subq %%rcx, %%rax\n");
        } else if (strcmp(inst.op, "mul") == 0) {
          fprintf(f, "  imulq %%rcx, %%rax\n");
        } else if (strcmp(inst.op, "div") == 0) {
          fprintf(f, "  cqto\n");
          fprintf(f, "  idivq %%rcx\n");
        } else if (strcmp(inst.op, "rem") == 0) {
          fprintf(f, "  cqto\n");
          fprintf(f, "  idivq %%rcx\n");
          fprintf(f, "  movq %%rdx, %%rax\n");
        } else if (strcmp(inst.op, "and") == 0) {
          fprintf(f, "  andq %%rcx, %%rax\n");
        } else if (strcmp(inst.op, "or") == 0) {
          fprintf(f, "  orq %%rcx, %%rax\n");
        } else if (strcmp(inst.op, "xor") == 0) {
          fprintf(f, "  xorq %%rcx, %%rax\n");
        } else if (strcmp(inst.op, "shl") == 0) {
          fprintf(f, "  shlq %%cl, %%rax\n");
        } else if (strcmp(inst.op, "sar") == 0) {
          fprintf(f, "  sarq %%cl, %%rax\n");
        }
        store_reg(inst.dest, "%rax", 'l', f);
      }
      return;
    }
    
    // Comparisons
    if (strcmp(inst.op, "csltw") == 0 || strcmp(inst.op, "cslew") == 0 ||
        strcmp(inst.op, "ceqw") == 0 || strcmp(inst.op, "cnew") == 0) {
      load_arg(inst.arg1, "%eax", 'w', f);
      load_arg(inst.arg2, "%ecx", 'w', f);
      fprintf(f, "  cmpl %%ecx, %%eax\n");
      
      const(char)* set_op = "";
      if (strcmp(inst.op, "csltw") == 0) set_op = "setl";
      else if (strcmp(inst.op, "cslew") == 0) set_op = "setle";
      else if (strcmp(inst.op, "ceqw") == 0) set_op = "sete";
      else if (strcmp(inst.op, "cnew") == 0) set_op = "setne";
      
      fprintf(f, "  %s %%al\n", set_op);
      fprintf(f, "  movzbl %%al, %%eax\n");
      store_reg(inst.dest, "%eax", 'w', f);
      return;
    }
    
    // Comparisons 64-bit (ceqb, ceql, cnewl, etc.)
    if (strcmp(inst.op, "ceql") == 0 || strcmp(inst.op, "cnewl") == 0) {
      load_arg(inst.arg1, "%rax", 'l', f);
      load_arg(inst.arg2, "%rcx", 'l', f);
      fprintf(f, "  cmpq %%rcx, %%rax\n");
      
      const(char)* set_op = "";
      if (strcmp(inst.op, "ceql") == 0) set_op = "sete";
      else if (strcmp(inst.op, "cnewl") == 0) set_op = "setne";
      
      fprintf(f, "  %s %%al\n", set_op);
      fprintf(f, "  movzbl %%al, %%eax\n");
      store_reg(inst.dest, "%eax", 'w', f);
      return;
    }
    
    // comparisons ceqw and cnew for registers of other types
    if (strncmp(inst.op, "ceq", 3) == 0 || strncmp(inst.op, "cnew", 4) == 0) {
      char type = inst.op[3]; // 'w' or 'l'
      const(char)* set_op = "";
      if (strncmp(inst.op, "ceq", 3) == 0) {
        set_op = "sete";
        type = inst.op[3];
      } else {
        set_op = "setne";
        type = inst.op[4];
      }
      
      if (type == 'l') {
        load_arg(inst.arg1, "%rax", 'l', f);
        load_arg(inst.arg2, "%rcx", 'l', f);
        fprintf(f, "  cmpq %%rcx, %%rax\n");
      } else {
        load_arg(inst.arg1, "%eax", 'w', f);
        load_arg(inst.arg2, "%ecx", 'w', f);
        fprintf(f, "  cmpl %%ecx, %%eax\n");
      }
      
      fprintf(f, "  %s %%al\n", set_op);
      fprintf(f, "  movzbl %%al, %%eax\n");
      store_reg(inst.dest, "%eax", 'w', f);
      return;
    }
    
    fprintf(get_stderr(), "Unknown assignment op: %s\n", inst.op);
    exit(1);
  }
}

void gen_function(FunctionDef* fn, FILE* f) {
  reset_offsets();
  current_fn_name = fn.name + 1;
  
  // First pass: Assign stack slots to all temporaries in the function
  // Parameters
  for (int i = 0; i < fn.params_count; i++) {
    get_temp_offset(fn.params[i].name);
  }
  // Instruction destinations
  for (int i = 0; i < fn.inst_count; i++) {
    if (fn.instructions[i].kind == InstKind.IK_assign) {
      get_temp_offset(fn.instructions[i].dest);
    }
  }
  
  // Second pass: Scan for alloc instructions to allocate variable storage
  for (int i = 0; i < fn.inst_count; i++) {
    Instruction* inst = &fn.instructions[i];
    if (inst.kind == InstKind.IK_assign &&
        (strcmp(inst.op, "alloc4") == 0 || strcmp(inst.op, "alloc8") == 0 || strcmp(inst.op, "alloc16") == 0)) {
      int size = atoi(inst.arg1);
      int align_ = 4;
      if (strcmp(inst.op, "alloc8") == 0) align_ = 8;
      else if (strcmp(inst.op, "alloc16") == 0) align_ = 16;
      get_var_offset(inst.dest, size, align_);
    }
  }
  
  // Align total stack size to 16 bytes for ABI compliance
  int aligned_stack = ((stack_offset_counter + 15) / 16) * 16;
  
  // Emit prologue
  if (fn.is_export) {
    fprintf(f, ".globl %s\n", fn.name + 1);
  }
  fprintf(f, "%s:\n", fn.name + 1);
  fprintf(f, "  pushq %%rbp\n");
  fprintf(f, "  movq %%rsp, %%rbp\n");
  if (aligned_stack > 0) {
    fprintf(f, "  subq $%d, %%rsp\n", aligned_stack);
  }
  
  // Store parameter registers into their stack slots
  for (int i = 0; i < fn.params_count && i < 6; i++) {
    int offset = get_temp_offset(fn.params[i].name);
    if (fn.params[i].type == 'w') {
      fprintf(f, "  movl %s, -%d(%%rbp)\n", arg_regs_32[i], offset);
    } else {
      fprintf(f, "  movq %s, -%d(%%rbp)\n", arg_regs_64[i], offset);
    }
  }
  
  // Generate code for instructions
  bool ends_with_ret = false;
  for (int i = 0; i < fn.inst_count; i++) {
    gen_instruction(&fn.instructions[i], fn.ret_type, f);
    if (fn.instructions[i].kind == InstKind.IK_ret) {
      ends_with_ret = true;
    }
  }
  
  // Epilogue if not ended with ret
  if (!ends_with_ret) {
    fprintf(f, "  leave\n");
    fprintf(f, "  ret\n");
  }
}

void gen_data(DataDef* def, FILE* f) {
  fprintf(f, ".globl %s\n", def.name + 1);
  fprintf(f, "%s:\n", def.name + 1);
  for (int i = 0; i < def.items_count; i++) {
    DataItem* item = &def.items[i];
    if (item.type == 'b') {
      if (item.val_str[0] == '"') {
        fprintf(f, "  .ascii %s\n", item.val_str);
      } else {
        fprintf(f, "  .byte %s\n", item.val_str);
      }
    } else if (item.type == 'w') {
      fprintf(f, "  .long %s\n", item.val_str);
    } else if (item.type == 'l') {
      if (item.val_str[0] == '$') {
        fprintf(f, "  .quad %s\n", item.val_str + 1);
      } else {
        fprintf(f, "  .quad %s\n", item.val_str);
      }
    } else if (item.type == 'z') {
      fprintf(f, "  .zero %s\n", item.val_str);
    }
  }
}

void gen_program(FILE* f) {
  fprintf(f, ".data\n");
  for (int i = 0; i < program_data_count; i++) {
    gen_data(&program_data[i], f);
  }
  
  fprintf(f, ".text\n");
  for (int i = 0; i < program_functions_count; i++) {
    gen_function(&program_functions[i], f);
  }
}

unittest {
  char* input = cast(char*) "\n    data $g = { w 42 }\n    data $str = { b \"hello\\n\", b 0 }\n    \n    export function w $add(w %a, w %b) {\n    @start\n      %t1 =w add %a, %b\n      ret %t1\n    }\n  ";
  
  token = tokenize(input);
  parse_program();
  
  FILE* f = fopen("tmp_test.s", "w");
  assert(f != null);
  gen_program(f);
  fclose(f);
  
  // Read file back and verify contents
  f = fopen("tmp_test.s", "r");
  assert(f != null);
  
  char[256] line;
  bool found_globl_g = false;
  bool found_add_label = false;
  bool found_addl = false;
  
  while (fgets(&line[0], 256, f)) {
    if (strstr(&line[0], ".globl g")) found_globl_g = true;
    if (strstr(&line[0], "add:")) found_add_label = true;
    if (strstr(&line[0], "addl")) found_addl = true;
  }
  fclose(f);
  
  remove("tmp_test.s");
  
  assert(found_globl_g);
  assert(found_add_label);
  assert(found_addl);
}



extern (C)
int main(int argc, char** argv) {
  // Read all inputs from stdin
  size_t capacity = 4 * 1024 * 1024; // 4MB starting capacity
  char* buf = cast(char*) malloc(capacity);
  if (!buf) {
    fprintf(stderr, "Out of memory allocating input buffer\n");
    return 1;
  }
  
  size_t len = 0;
  while (true) {
    size_t read_bytes = fread(buf + len, 1, 4096, stdin);
    if (read_bytes == 0) {
      break;
    }
    len += read_bytes;
    if (len + 4096 >= capacity) {
      capacity *= 2;
      buf = cast(char*) realloc(buf, capacity);
      if (!buf) {
        fprintf(stderr, "Out of memory reallocating input buffer\n");
        return 1;
      }
    }
  }
  buf[len] = '\0';
  
  token = tokenize(buf);
  parse_program();
  gen_program(stdout);
  
  free(buf);
  return 0;
}
