module d2qbe.codegen;

import core.stdc.stdio;
import core.stdc.string;
import core.stdc.stdlib;

import d2qbe.parse;
import d2qbe.tokenize;

struct LocalVar {
  const(char)* name;
  Type type;
}

LocalVar[200] locals;
int locals_count = 0;

void add_local(const(Token)* ident, Type type) {
  for (int i = 0; i < locals_count; i++) {
    if (strlen(locals[i].name) == ident.len && strncmp(locals[i].name, ident.str, ident.len) == 0) {
      return;
    }
  }
  char* name = cast(char*) calloc(1, ident.len + 1);
  memcpy(name, ident.str, ident.len);
  locals[locals_count].name = name;
  locals[locals_count].type = type;
  locals_count++;
}

Type get_local_type(const(Token)* ident) {
  for (int i = 0; i < locals_count; i++) {
    if (strlen(locals[i].name) == ident.len && strncmp(locals[i].name, ident.str, ident.len) == 0) {
      if (locals[i].type.name == null) {
        locals[i].type.name = "int";
      }
      return locals[i].type;
    }
  }
  Type t;
  t.name = "int";
  t.ptr_depth = 0;
  t.array_size = 0;
  return t;
}

Type infer_type(Node* node) {
  Type t;
  t.name = "int";
  t.ptr_depth = 0;
  t.array_size = 0;
  if (!node) return t;
  if (node.kind == NodeKind.addr) {
    Type base = infer_type(node.lhs);
    t.name = base.name;
    t.ptr_depth = base.ptr_depth + 1;
    return t;
  }
  if (node.kind == NodeKind.lvar) {
    return get_local_type(node.ident);
  }
  if (node.kind == NodeKind.deref) {
    Type base = infer_type(node.lhs);
    t.name = base.name;
    t.ptr_depth = (base.ptr_depth > 0) ? base.ptr_depth - 1 : 0;
    return t;
  }
  return t;
}

void collect_locals(Node* node) {
  if (!node) return;
  if (node.kind == NodeKind.var_decl) {
    add_local(node.ident, node.type);
  }
  else if (node.kind == NodeKind.assign && node.lhs.kind == NodeKind.lvar) {
    Type rhs_type = infer_type(node.rhs);
    add_local(node.lhs.ident, rhs_type);
  }
  else if (node.kind == NodeKind.lvar) {
    Type t;
    t.name = "int";
    t.ptr_depth = 0;
    t.array_size = 0;
    add_local(node.ident, t);
  }
  collect_locals(node.lhs);
  collect_locals(node.rhs);
  collect_locals(node.begin);
  collect_locals(node.cond);
  collect_locals(node.then);
  collect_locals(node.else_);
  collect_locals(node.advance);
  
  if (node.kind == NodeKind.block) {
    for (NodeList* stmts = &node.statements; stmts; stmts = stmts.next) {
      collect_locals(stmts.value);
    }
  }
}

// Tracks whether register %ti is 'w' (word) or 'l' (long)
char[2000] reg_types;

bool is_returned(Node* node) {
  if (!node) {
    return false;
  }
  if (node.kind == NodeKind.return_) {
    return true;
  }
  if (node.kind == NodeKind.block) {
    for (NodeList* stmts = &node.statements; stmts; stmts = stmts.next) {
      if (is_returned(stmts.value)) {
        return true;
      }
    }
  }
  return false;
}

int gen_binop(Node* node, int ret_var, const char* binop) {
  int l = gen(node.lhs, ret_var);
  int r = gen(node.rhs, l);
  printf("  %%t%d =w %s %%t%d, %%t%d\n", r + 1, binop, l, r);
  reg_types[r + 1] = 'w';
  return r + 1;
}

int get_type_size(Type t) {
  if (t.ptr_depth > 0) {
    return 8;
  }
  if (strcmp(t.name, "int") == 0) {
    return 4;
  }
  if (strcmp(t.name, "char") == 0 || strcmp(t.name, "bool") == 0) {
    return 1;
  }
  return 4;
}

Type get_expr_type(Node* node) {
  Type t;
  t.name = "int";
  t.ptr_depth = 0;
  t.array_size = 0;
  if (!node) return t;
  if (node.kind == NodeKind.num) {
    return t;
  }
  if (node.kind == NodeKind.lvar) {
    return get_local_type(node.ident);
  }
  if (node.kind == NodeKind.addr) {
    Type base = get_expr_type(node.lhs);
    t.name = base.name;
    t.ptr_depth = base.ptr_depth + 1;
    return t;
  }
  if (node.kind == NodeKind.deref) {
    Type base = get_expr_type(node.lhs);
    t.name = base.name;
    t.ptr_depth = (base.ptr_depth > 0) ? base.ptr_depth - 1 : 0;
    return t;
  }
  if (node.kind == NodeKind.cast_) {
    return node.type;
  }
  if (node.kind == NodeKind.index) {
    Type base = get_expr_type(node.lhs);
    t.name = base.name;
    t.ptr_depth = (base.ptr_depth > 0) ? base.ptr_depth - 1 : 0;
    return t;
  }
  if (node.kind == NodeKind.assign) {
    return get_expr_type(node.lhs);
  }
  if (node.kind == NodeKind.add || node.kind == NodeKind.sub) {
    Type lt = get_expr_type(node.lhs);
    Type rt = get_expr_type(node.rhs);
    if (lt.ptr_depth > 0) return lt;
    if (rt.ptr_depth > 0) return rt;
    return lt;
  }
  return t;
}

int gen(Node* node, int ret_var) {
  if (!node) {
    return ret_var;
  }
  final switch (node.kind) {
  case NodeKind.addr:
    if (node.lhs.kind != NodeKind.lvar) {
      error("lvalue expected for &");
    }
    printf("  %%t%d =l copy %%%.*s_addr\n", ret_var + 1, node.lhs.ident.len, node.lhs.ident.str);
    reg_types[ret_var + 1] = 'l';
    return ret_var + 1;
  case NodeKind.deref: {
    int addr = gen(node.lhs, ret_var);
    printf("  %%t%d =w loadw %%t%d\n", addr + 1, addr);
    reg_types[addr + 1] = 'w';
    return addr + 1;
  }
  case NodeKind.num: {
      printf("  %%t%d =w copy %d\n", ret_var + 1, node.val);
      reg_types[ret_var + 1] = 'w';
      return ret_var + 1;
    }
  case NodeKind.lvar: {
      Type t = get_local_type(node.ident);
      if (t.ptr_depth > 0) {
        printf("  %%t%d =l loadl %%%.*s_addr\n", ret_var + 1, node.ident.len, node.ident.str);
        reg_types[ret_var + 1] = 'l';
      } else {
        printf("  %%t%d =w loadw %%%.*s_addr\n", ret_var + 1, node.ident.len, node.ident.str);
        reg_types[ret_var + 1] = 'w';
      }
      return ret_var + 1;
    }
  case NodeKind.assign: {
      int rhs = gen(node.rhs, ret_var);
      if (node.lhs.kind == NodeKind.lvar) {
        Type t = get_local_type(node.lhs.ident);
        if (t.ptr_depth > 0) {
          printf("  storel %%t%d, %%%.*s_addr\n", rhs, node.lhs.ident.len, node.lhs.ident.str);
        } else {
          printf("  storew %%t%d, %%%.*s_addr\n", rhs, node.lhs.ident.len, node.lhs.ident.str);
        }
        return rhs;
      }
      if (node.lhs.kind == NodeKind.deref) {
        int addr = gen(node.lhs.lhs, rhs);
        printf("  storew %%t%d, %%t%d\n", rhs, addr);
        return addr;
      }
      if (node.lhs.kind == NodeKind.index) {
        Type lt = get_expr_type(node.lhs.lhs);
        int l = gen(node.lhs.lhs, rhs);
        int r = gen(node.lhs.rhs, l);
        int scale = get_type_size(Type(lt.name, lt.ptr_depth - 1, 0));
        int offset_reg = r;
        int cur = r;
        if (scale > 1) {
          printf("  %%t%d =w mul %%t%d, %d\n", cur + 1, r, scale);
          cur++;
          offset_reg = cur;
        }
        printf("  %%t%d =l extsw %%t%d\n", cur + 1, offset_reg);
        cur++;
        printf("  %%t%d =l add %%t%d, %%t%d\n", cur + 1, l, cur);
        cur++;
        Type elem_type = Type(lt.name, lt.ptr_depth - 1, 0);
        if (elem_type.ptr_depth > 0) {
          printf("  storel %%t%d, %%t%d\n", rhs, cur);
        } else {
          printf("  storew %%t%d, %%t%d\n", rhs, cur);
        }
        return cur;
      }
      error("Variable expected in lhs");
      return rhs;
    }
  case NodeKind.var_decl: {
      if (node.lhs) {
        int rhs = gen(node.lhs, ret_var);
        Type t = get_local_type(node.ident);
        if (t.ptr_depth > 0) {
          printf("  storel %%t%d, %%%.*s_addr\n", rhs, node.ident.len, node.ident.str);
        } else {
          printf("  storew %%t%d, %%%.*s_addr\n", rhs, node.ident.len, node.ident.str);
        }
        return rhs;
      }
      return ret_var;
    }
  case NodeKind.gvar_decl: {
      return ret_var;
    }
  case NodeKind.cast_: {
      int lhs = gen(node.lhs, ret_var);
      char tgt_char = (node.type.ptr_depth > 0) ? 'l' : 'w';
      char src_char = reg_types[lhs];
      if (src_char != 'w' && src_char != 'l') src_char = 'w';
      if (tgt_char == src_char) {
        printf("  %%t%d =%c copy %%t%d\n", lhs + 1, tgt_char, lhs);
      } else if (tgt_char == 'l') {
        printf("  %%t%d =l extsw %%t%d\n", lhs + 1, lhs);
      } else {
        printf("  %%t%d =w copy %%t%d\n", lhs + 1, lhs);
      }
      reg_types[lhs + 1] = tgt_char;
      return lhs + 1;
    }
  case NodeKind.index: {
      Type lt = get_expr_type(node.lhs);
      int l = gen(node.lhs, ret_var);
      int r = gen(node.rhs, l);
      int scale = get_type_size(Type(lt.name, lt.ptr_depth - 1, 0));
      int offset_reg = r;
      int cur = r;
      if (scale > 1) {
        printf("  %%t%d =w mul %%t%d, %d\n", cur + 1, r, scale);
        cur++;
        offset_reg = cur;
      }
      printf("  %%t%d =l extsw %%t%d\n", cur + 1, offset_reg);
      cur++;
      printf("  %%t%d =l add %%t%d, %%t%d\n", cur + 1, l, cur);
      cur++;
      Type elem_type = Type(lt.name, lt.ptr_depth - 1, 0);
      if (elem_type.ptr_depth > 0) {
        printf("  %%t%d =l loadl %%t%d\n", cur + 1, cur);
        reg_types[cur + 1] = 'l';
      } else {
        printf("  %%t%d =w loadw %%t%d\n", cur + 1, cur);
        reg_types[cur + 1] = 'w';
      }
      return cur + 1;
    }
  case NodeKind.return_: {
      int lhs = gen(node.lhs, ret_var);
      printf("  ret %%t%d\n", lhs);
      return lhs;
    }
  case NodeKind.if_: {
      int cond = gen(node.cond, ret_var);
      printf("  jnz %%t%d, @then%d, @else%d\n", cond, ret_var, ret_var);
      printf("@then%d\n", ret_var);
      int then = gen(node.then, cond);
      int ret = then;
      if (!is_returned(node.then)) {
        printf("  jmp @endif%d\n", ret_var);
      }
      printf("@else%d\n", ret_var);
      ret = gen(node.else_, then);
      if (node.then.kind != NodeKind.return_) {
        printf("@endif%d\n", ret_var);
      }
      return ret;
    }
  case NodeKind.while_: {
      printf("@cond%d\n", ret_var);
      int cond = gen(node.cond, ret_var);
      printf("  jnz %%t%d, @body%d, @break%d\n", cond, ret_var, ret_var);
      printf("@body%d\n", ret_var);
      int then = gen(node.then, cond);
      printf("  jmp @cond%d\n", ret_var);
      printf("@break%d\n", ret_var);
      return then;
    }
  case NodeKind.for_: {
      int ret = gen(node.begin, ret_var);
      printf("@forcond%d\n", ret_var);
      if (node.cond) {
        ret = gen(node.cond, ret);
        printf("  jnz %%t%d, @forthen%d, @forend%d\n", ret, ret_var, ret_var);
      }
      printf("@forthen%d\n", ret_var);
      ret = gen(node.then, ret);
      ret = gen(node.advance, ret);
      printf("  jmp @forcond%d\n", ret_var);
      printf("@forend%d\n", ret_var);
      return ret;
    }
  case NodeKind.block: {
      NodeList* stmts = &node.statements;
      while (stmts) {
        ret_var = gen(stmts.value, ret_var);
        stmts = stmts.next;
      }
      return ret_var;
    }
  case NodeKind.funcall: {
      int arg_ret = ret_var;
      int[20] args_vars;
      int n_arg = 0;
      for (NodeList* args = &node.args; args.value; args = args.next) {
        arg_ret = gen(args.value, arg_ret);
        args_vars[n_arg] = arg_ret;
        n_arg += 1;
      }
      assert(n_arg < args_vars.length);
      printf("  %%t%d =w call $%.*s(", arg_ret + 1, node.ident.len, node.ident.str);
      for (int i = 0; i < n_arg; ++i) {
        char c = reg_types[args_vars[i]];
        if (c != 'w' && c != 'l') c = 'w';
        printf("%c %%t%d", c, args_vars[i]);
        if (i != n_arg - 1) {
          printf(", ");
        }
      }
      printf(")\n");
      reg_types[arg_ret + 1] = 'w';
      return arg_ret + 1;
    }
  case NodeKind.defun: {
      if (node.is_decl_only) {
        return ret_var;
      }
      
      locals_count = 0;
      for (int i = 0; node.params[i]; ++i) {
        add_local(node.params[i], node.params_types[i]);
      }
      collect_locals(node.then);
      
      const(char)* ret_type_str = (node.return_type.ptr_depth > 0) ? "l" : "w";
      printf("export function %s $%.*s(", ret_type_str, node.ident.len, node.ident.str);
      for (int i = 0; node.params[i]; ++i) {
        const(Token)* p = node.params[i];
        Type t = node.params_types[i];
        const(char)* t_str = (t.ptr_depth > 0) ? "l" : "w";
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
        if (t.ptr_depth > 0) {
          printf("  %%%.*s_addr =l alloc8 8\n", cast(int)strlen(locals[i].name), locals[i].name);
        } else {
          printf("  %%%.*s_addr =l alloc4 4\n", cast(int)strlen(locals[i].name), locals[i].name);
        }
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
      
      ret_var = gen(node.then, ret_var);
      printf("}\n");
      return ret_var;
    }
  case NodeKind.add: {
      Type lt = get_expr_type(node.lhs);
      Type rt = get_expr_type(node.rhs);
      if (lt.ptr_depth > 0) {
        int l = gen(node.lhs, ret_var);
        int r = gen(node.rhs, l);
        int scale = get_type_size(Type(lt.name, lt.ptr_depth - 1, 0));
        int offset_reg = r;
        int cur = r;
        if (scale > 1) {
          printf("  %%t%d =w mul %%t%d, %d\n", cur + 1, r, scale);
          cur++;
          offset_reg = cur;
        }
        printf("  %%t%d =l extsw %%t%d\n", cur + 1, offset_reg);
        cur++;
        printf("  %%t%d =l add %%t%d, %%t%d\n", cur + 1, l, cur);
        reg_types[cur + 1] = 'l';
        return cur + 1;
      }
      if (rt.ptr_depth > 0) {
        int l = gen(node.lhs, ret_var);
        int r = gen(node.rhs, l);
        int scale = get_type_size(Type(rt.name, rt.ptr_depth - 1, 0));
        int offset_reg = l;
        int cur = r;
        if (scale > 1) {
          printf("  %%t%d =w mul %%t%d, %d\n", cur + 1, l, scale);
          cur++;
          offset_reg = cur;
        }
        printf("  %%t%d =l extsw %%t%d\n", cur + 1, offset_reg);
        cur++;
        printf("  %%t%d =l add %%t%d, %%t%d\n", cur + 1, r, cur);
        reg_types[cur + 1] = 'l';
        return cur + 1;
      }
      return gen_binop(node, ret_var, "add");
    }
  case NodeKind.sub: {
      Type lt = get_expr_type(node.lhs);
      Type rt = get_expr_type(node.rhs);
      if (lt.ptr_depth > 0 && rt.ptr_depth > 0) {
        int l = gen(node.lhs, ret_var);
        int r = gen(node.rhs, l);
        printf("  %%t%d =l sub %%t%d, %%t%d\n", r + 1, l, r);
        int scale = get_type_size(Type(lt.name, lt.ptr_depth - 1, 0));
        int cur = r + 1;
        if (scale > 1) {
          printf("  %%t%d =l div %%t%d, %d\n", cur + 1, cur, scale);
          cur++;
        }
        printf("  %%t%d =w copy %%t%d\n", cur + 1, cur);
        reg_types[cur + 1] = 'w';
        return cur + 1;
      }
      if (lt.ptr_depth > 0) {
        int l = gen(node.lhs, ret_var);
        int r = gen(node.rhs, l);
        int scale = get_type_size(Type(lt.name, lt.ptr_depth - 1, 0));
        int offset_reg = r;
        int cur = r;
        if (scale > 1) {
          printf("  %%t%d =w mul %%t%d, %d\n", cur + 1, r, scale);
          cur++;
          offset_reg = cur;
        }
        printf("  %%t%d =l extsw %%t%d\n", cur + 1, offset_reg);
        cur++;
        printf("  %%t%d =l sub %%t%d, %%t%d\n", cur + 1, l, cur);
        reg_types[cur + 1] = 'l';
        return cur + 1;
      }
      return gen_binop(node, ret_var, "sub");
    }
  case NodeKind.mul:
    return gen_binop(node, ret_var, "mul");
  case NodeKind.div:
    return gen_binop(node, ret_var, "div");
  case NodeKind.lt:
    return gen_binop(node, ret_var, "csltw");
  case NodeKind.le:
    return gen_binop(node, ret_var, "cslew");
  case NodeKind.eq:
    return gen_binop(node, ret_var, "ceqw");
  case NodeKind.ne:
    return gen_binop(node, ret_var, "cnew");
  }
}

unittest {
  Node* var1 = new_node(NodeKind.var_decl);
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
  Node* var2 = new_node(NodeKind.lvar);
  var2.ident = &t1; // "abc"
  
  Node* addr = new_node(NodeKind.addr);
  addr.lhs = var2; // &abc
  
  Node* assign = new_node(NodeKind.assign);
  Token t2;
  t2.str = cast(char*) "b";
  t2.len = 1;
  assign.lhs = new_node(NodeKind.lvar);
  assign.lhs.ident = &t2;
  assign.rhs = addr;
  
  collect_locals(assign);
  Type b_type = get_local_type(&t2);
  assert(strcmp(b_type.name, "int") == 0);
  assert(b_type.ptr_depth == 1); // should be int*
}


