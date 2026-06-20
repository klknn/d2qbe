module d2qbe.codegen;

import core.stdc.stdio;
import core.stdc.string;
import core.stdc.stdlib;

import d2qbe.parse;
import d2qbe.tokenize;

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
  t.array_size = 0;
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

char current_loop_type() {
  if (loop_stack_count == 0) {
    error("continue or break statement not within loop");
  }
  return loop_stack[loop_stack_count - 1].type;
}

int current_loop_id() {
  if (loop_stack_count == 0) {
    error("continue or break statement not within loop");
  }
  return loop_stack[loop_stack_count - 1].id;
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
  printf("# DEBUG: add_local '%.*s' type '%s' ptr_depth=%d array_size=%d\n",
         ident.len, ident.str, type_name, type.ptr_depth, type.array_size);
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
  t.array_size = 0;
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
  t.array_size = 0;
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
    get_local_type(node.ident, out_type);
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
  *out_type = t;
}

/**
 * Recursively collects all local variables declared in a function AST.
 */
void collect_locals(Node* node) {
  if (!node) return;
  if (node.kind == NodeKind.NK_var_decl) {
    add_local(node.ident, &node.type);
  }
  else if (node.kind == NodeKind.NK_assign && node.lhs.kind == NodeKind.NK_lvar) {
    if (!is_global(node.lhs.ident)) {
      Type rhs_type;
      infer_type(node.rhs, &rhs_type);
      add_local(node.lhs.ident, &rhs_type);
    }
  }
  else if (node.kind == NodeKind.NK_lvar) {
    if (!is_global(node.ident)) {
      Type t;
      t.name = "int";
      t.ptr_depth = 0;
      t.array_size = 0;
      add_local(node.ident, &t);
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
  t.array_size = 0;
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
    if (base.array_size > 0) {
      t.ptr_depth = base.ptr_depth;
      t.array_size = 0;
    } else {
      int depth = 0;
      if (base.ptr_depth > 0) depth = base.ptr_depth - 1;
      t.ptr_depth = depth;
      t.array_size = 0;
    }
    *out_type = t;
    return;
  }
  if (node.kind == NodeKind.NK_assign) {
    get_expr_type(node.lhs, out_type);
    return;
  }
  if (node.kind == NodeKind.NK_dot) {
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
      if (lt.array_size > 0) {
        l = gen_addr(node.lhs);
      } else {
        l = gen(node.lhs);
      }
      int r = gen(node.rhs);
      Type tmp_type;
      tmp_type.name = lt.name;
      if (lt.array_size > 0) {
        tmp_type.ptr_depth = lt.ptr_depth;
      } else {
        tmp_type.ptr_depth = lt.ptr_depth - 1;
      }
      tmp_type.array_size = 0;
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
    if (m.type.array_size > 0) {
      array_len = m.type.array_size;
    }
    Type elem_type = m.type;
    elem_type.array_size = 0;
    int elem_size = get_type_size(&elem_type);
    
    for (int j = 0; j < array_len; j++) {
      int elem_lhs_addr = mem_lhs_addr;
      int elem_rhs_addr = mem_rhs_addr;
      if (m.type.array_size > 0 && j > 0) {
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
    tmp_type.array_size = 0;
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
      char type = current_loop_type();
      int id = current_loop_id();
      if (type == 'w') {
        printf("  jmp @cond%d\n", id);
      } else if (type == 'f') {
        printf("  jmp @forpost%d\n", id);
      }
      return 0;
    }
  if (node.kind == NodeKind.NK_break_) {
      char type = current_loop_type();
      int id = current_loop_id();
      if (type == 'w') {
        printf("  jmp @break%d\n", id);
      } else if (type == 'f') {
        printf("  jmp @forend%d\n", id);
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
  if (node.kind == NodeKind.NK_block) {
      int ret = 0;
      NodeList* stmts = &node.statements;
      while (stmts) {
        ret = gen(stmts.value);
        if (ends_with_return(stmts.value)) {
          break;
        }
        stmts = stmts.next;
      }
      return ret;
    }
  if (node.kind == NodeKind.NK_funcall) {
      int[20] args_vars;
      int n_arg = 0;
      for (NodeList* args = &node.args; args.value; args = args.next) {
        args_vars[n_arg] = gen(args.value);
        n_arg++;
      }
      assert(n_arg < 20);
      
      char* name = cast(char*) calloc(1, node.ident.len + 1);
      memcpy(name, node.ident.str, node.ident.len);
      FunctionSymbol* fs = find_function(name);
      if (!fs) {
        printf("# DEBUG: gen(funcall) '%s' NOT FOUND in registered_functions!\n", name);
      } else {
        const(char)* ret_name = fs.return_type.name;
        if (!ret_name) ret_name = "null";
        printf("# DEBUG: gen(funcall) '%s' FOUND ret='%s' ptr_depth=%d\n",
               name, ret_name, fs.return_type.ptr_depth);
      }

      char ret_type = 'w';
      if (fs && fs.return_type.ptr_depth > 0) {
        ret_type = 'l';
      }
      int res = next_reg();
      printf("  %%t%d =%c call $%.*s(", res, ret_type, node.ident.len, node.ident.str);
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
        tmp_type.array_size = 0;
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
        tmp_type.array_size = 0;
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
        tmp_type.array_size = 0;
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
        tmp_type.array_size = 0;
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
  if (node.kind == NodeKind.NK_dot) {
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
}


