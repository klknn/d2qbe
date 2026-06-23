module dqbe.codegen;

import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.string;

import dqbe.tokenize;
import dqbe.parse;
import dqbe.regalloc : perform_register_allocation, get_allocated_register;

struct TempMap {
  char* name;
  int offset;
}

__gshared TempMap[10000] temp_offsets;
__gshared int temp_offsets_count = 0;


struct RegCache {
  char[32] temp_name;
  char[16] phys_reg;
}
__gshared RegCache[16] reg_cache;
__gshared int reg_cache_count = 0;

void clear_cache() {
  reg_cache_count = 0;
}

void invalidate_cache(const char* phys) {
  for (int i = 0; i < reg_cache_count; i++) {
    bool match = false;
    if (strcmp(reg_cache[i].phys_reg.ptr, phys) == 0) {
      match = true;
    } else {
      int len1 = cast(int) strlen(reg_cache[i].phys_reg.ptr);
      int len2 = cast(int) strlen(phys);
      if (len1 >= 3 && len2 >= 3 && strcmp(reg_cache[i].phys_reg.ptr + len1 - 2, phys + len2 - 2) == 0) {
        match = true;
      }
    }
    if (match) {
      for (int j = i; j < reg_cache_count - 1; j++) {
        reg_cache[j] = reg_cache[j+1];
      }
      reg_cache_count--;
      i--;
    }
  }
}

void update_cache(const char* temp, const char* phys) {
  if (!temp || !phys) return;
  invalidate_cache(phys);
  if (reg_cache_count < 16) {
    strncpy(reg_cache[reg_cache_count].temp_name.ptr, temp, 31);
    strncpy(reg_cache[reg_cache_count].phys_reg.ptr, phys, 15);
    reg_cache_count++;
  }
}

const(char)* lookup_cache(const char* temp) {
  for (int i = 0; i < reg_cache_count; i++) {
    if (strcmp(reg_cache[i].temp_name.ptr, temp) == 0) {
      return reg_cache[i].phys_reg.ptr;
    }
  }
  return null;
}

struct VarMap {
  char* name;
  int offset;
}

__gshared VarMap[5000] var_offsets;
__gshared int var_offsets_count = 0;
__gshared int stack_offset_counter = 0;

void reset_offsets() {
  temp_offsets_count = 0;
  var_offsets_count = 0;
  stack_offset_counter = 40;
}

void emit_epilogue(FILE* f) {
  fprintf(f, "  movq -8(%%rbp), %%rbx\n");
  fprintf(f, "  movq -16(%%rbp), %%r12\n");
  fprintf(f, "  movq -24(%%rbp), %%r13\n");
  fprintf(f, "  movq -32(%%rbp), %%r14\n");
  fprintf(f, "  movq -40(%%rbp), %%r15\n");
  fprintf(f, "  leave\n");
  fprintf(f, "  ret\n");
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
  stack_offset_counter = stack_offset_counter + 8; // 8 bytes for every temporary
  
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
  stack_offset_counter = stack_offset_counter + size;
  
  assert(var_offsets_count < 5000);
  var_offsets[var_offsets_count].name = cast(char*) name;
  var_offsets[var_offsets_count].offset = ret_offset;
  var_offsets_count++;
  return ret_offset;
}

bool is_same_phys_reg(const char* reg1, const char* reg2) {
  if (strcmp(reg1, reg2) == 0) return true;
  
  const(char)* r1 = reg1;
  const(char)* r2 = reg2;
  if (r1[0] == '%') r1++;
  if (r2[0] == '%') r2++;
  
  if ((r1[0] == 'r' || r1[0] == 'e') && (r2[0] == 'r' || r2[0] == 'e')) {
    if (strcmp(r1 + 1, r2 + 1) == 0) return true;
  }
  
  int len1 = cast(int) strlen(r1);
  int len2 = cast(int) strlen(r2);
  if (len1 > 0 && r1[len1 - 1] == 'd') len1--;
  if (len2 > 0 && r2[len2 - 1] == 'd') len2--;
  
  if (len1 == len2 && strncmp(r1, r2, len1) == 0) return true;
  
  return false;
}

void load_arg(const char* arg, const char* reg, int type, FILE* f) {
  if (arg[0] == '%') {
    const(char)* alloc_reg = get_allocated_register(arg, cast(char) type);
    if (alloc_reg) {
      if (is_same_phys_reg(alloc_reg, reg)) {
        return;
      }
      if (type == 'w') {
        fprintf(f, "  movl %s, %s\n", alloc_reg, reg);
      } else if (type == 'l') {
        fprintf(f, "  movq %s, %s\n", alloc_reg, reg);
      } else if (type == 's') {
        fprintf(f, "  movss %s, %s\n", alloc_reg, reg);
      } else if (type == 'd') {
        fprintf(f, "  movsd %s, %s\n", alloc_reg, reg);
      }
      invalidate_cache(reg);
      return;
    }
    const(char)* cached_reg = lookup_cache(arg);
    if (cached_reg) {
      if (is_same_phys_reg(cached_reg, reg)) {
        return;
      }
      bool compatible = false;
      if (cached_reg[0] == '%' && reg[0] == '%') {
        if (cached_reg[1] == 'x' && reg[1] == 'x') {
          compatible = true;
        } else if (cached_reg[1] != 'x' && reg[1] != 'x') {
          if (strlen(cached_reg) == strlen(reg)) {
            compatible = true;
          }
        }
      }
      if (compatible) {
        if (type == 'w') {
          fprintf(f, "  movl %s, %s\n", cached_reg, reg);
        } else if (type == 'l') {
          fprintf(f, "  movq %s, %s\n", cached_reg, reg);
        } else if (type == 's') {
          fprintf(f, "  movss %s, %s\n", cached_reg, reg);
        } else if (type == 'd') {
          fprintf(f, "  movsd %s, %s\n", cached_reg, reg);
        }
        update_cache(arg, reg);
        return;
      }
    }
    int offset = get_temp_offset(arg);
    if (type == 'w') {
      fprintf(f, "  movl -%d(%%rbp), %s\n", offset, reg);
    } else if (type == 'l') {
      fprintf(f, "  movq -%d(%%rbp), %s\n", offset, reg);
    } else if (type == 's') {
      fprintf(f, "  movss -%d(%%rbp), %s\n", offset, reg);
    } else if (type == 'd') {
      fprintf(f, "  movsd -%d(%%rbp), %s\n", offset, reg);
    }
    update_cache(arg, reg);
  } else if (arg[0] == '$') {
    // Global address
    invalidate_cache(reg);
    fprintf(f, "  leaq %s(%%rip), %s\n", arg + 1, reg);
  } else {
    invalidate_cache(reg);
    // Number literal or Float literal
    if (strncmp(arg, "s_", 2) == 0) {
      double val = strtod(arg + 2, null);
      float val_f = cast(float) val;
      int* bits = cast(int*) &val_f;
      invalidate_cache("%eax");
      fprintf(f, "  movl $%u, %%eax\n", *bits);
      fprintf(f, "  movd %%eax, %s\n", reg);
    } else if (strncmp(arg, "d_", 2) == 0) {
      double val = strtod(arg + 2, null);
      long* bits = cast(long*) &val;
      invalidate_cache("%rax");
      fprintf(f, "  movabsq $%ld, %%rax\n", *bits);
      fprintf(f, "  movq %%rax, %s\n", reg);
    } else {
      // Raw integer literal
      if (type == 'w') {
        fprintf(f, "  movl $%s, %s\n", arg, reg);
      } else if (type == 'l') {
        fprintf(f, "  movq $%s, %s\n", arg, reg);
      } else if (type == 's') {
        invalidate_cache("%eax");
        fprintf(f, "  movl $%s, %%eax\n", arg);
        fprintf(f, "  movd %%eax, %s\n", reg);
      } else if (type == 'd') {
        invalidate_cache("%rax");
        fprintf(f, "  movabsq $%s, %%rax\n", arg);
        fprintf(f, "  movq %%rax, %s\n", reg);
      }
    }
  }
}

void store_reg(const char* dest, const char* reg, int type, FILE* f) {
  const(char)* alloc_reg = get_allocated_register(dest, cast(char) type);
  if (alloc_reg) {
    if (is_same_phys_reg(alloc_reg, reg)) {
      return;
    }
    if (type == 'w') {
      fprintf(f, "  movl %s, %s\n", reg, alloc_reg);
    } else if (type == 'l') {
      fprintf(f, "  movq %s, %s\n", reg, alloc_reg);
    } else if (type == 's') {
      fprintf(f, "  movss %s, %s\n", reg, alloc_reg);
    } else if (type == 'd') {
      fprintf(f, "  movsd %s, %s\n", reg, alloc_reg);
    }
    invalidate_cache(alloc_reg);
    return;
  }
  int offset = get_temp_offset(dest);
  if (type == 'w') {
    fprintf(f, "  movl %s, -%d(%%rbp)\n", reg, offset);
  } else if (type == 'l') {
    fprintf(f, "  movq %s, -%d(%%rbp)\n", reg, offset);
  } else if (type == 's') {
    fprintf(f, "  movss %s, -%d(%%rbp)\n", reg, offset);
  } else if (type == 'd') {
    fprintf(f, "  movsd %s, -%d(%%rbp)\n", reg, offset);
  }
  update_cache(dest, reg);
}

const(char)* get_arg_reg_32(int idx) {
  if (idx == 0) return "%edi";
  if (idx == 1) return "%esi";
  if (idx == 2) return "%edx";
  if (idx == 3) return "%ecx";
  if (idx == 4) return "%r8d";
  if (idx == 5) return "%r9d";
  return null;
}

const(char)* get_arg_reg_64(int idx) {
  if (idx == 0) return "%rdi";
  if (idx == 1) return "%rsi";
  if (idx == 2) return "%rdx";
  if (idx == 3) return "%rcx";
  if (idx == 4) return "%r8";
  if (idx == 5) return "%r9";
  return null;
}

const(char)* get_float_arg_reg(int idx) {
  if (idx == 0) return "%xmm0";
  if (idx == 1) return "%xmm1";
  if (idx == 2) return "%xmm2";
  if (idx == 3) return "%xmm3";
  if (idx == 4) return "%xmm4";
  if (idx == 5) return "%xmm5";
  if (idx == 6) return "%xmm6";
  if (idx == 7) return "%xmm7";
  return null;
}

const(char)* current_fn_name;

void gen_instruction(Instruction* inst, int fn_ret_type, FILE* f) {
  if (inst.kind == InstKind.IK_label) {
    fprintf(f, ".L%s_%s:\n", current_fn_name, inst.label + 1);
    clear_cache();
    return;
  }
  
  if (inst.kind == InstKind.IK_jmp) {
    fprintf(f, "  jmp .L%s_%s\n", current_fn_name, inst.label + 1);
    clear_cache();
    return;
  }
  
  if (inst.kind == InstKind.IK_jnz) {
    load_arg(inst.arg1, "%eax", 'w', f);
    fprintf(f, "  cmpl $0, %%eax\n");
    fprintf(f, "  jne .L%s_%s\n", current_fn_name, inst.label + 1);
    fprintf(f, "  jmp .L%s_%s\n", current_fn_name, inst.label_else + 1);
    clear_cache();
    return;
  }
  
  if (inst.kind == InstKind.IK_ret) {
    if (inst.arg1) {
      if (fn_ret_type == 'w') {
        load_arg(inst.arg1, "%eax", 'w', f);
      } else if (fn_ret_type == 'l') {
        load_arg(inst.arg1, "%rax", 'l', f);
      } else if (fn_ret_type == 's') {
        load_arg(inst.arg1, "%xmm0", 's', f);
      } else if (fn_ret_type == 'd') {
        load_arg(inst.arg1, "%xmm0", 'd', f);
      }
    }
    emit_epilogue(f);
    return;
  }
  
  if (inst.kind == InstKind.IK_store) {
    // storew %val, %ptr
    char type = inst.op[5]; // 'b', 'h', 'w', 'l', 's', 'd'
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
    } else if (type == 's') {
      load_arg(inst.arg1, "%xmm0", 's', f);
      load_arg(inst.arg2, "%rax", 'l', f);
      fprintf(f, "  movss %%xmm0, (%%rax)\n");
    } else if (type == 'd') {
      load_arg(inst.arg1, "%xmm0", 'd', f);
      load_arg(inst.arg2, "%rax", 'l', f);
      fprintf(f, "  movsd %%xmm0, (%%rax)\n");
    }
    return;
  }
  
  if (inst.kind == InstKind.IK_call) {
    // Void call
    // Set up parameters
    int int_arg_idx = 0;
    int float_arg_idx = 0;
    for (int i = 0; i < inst.call_args_count && i < 20; i++) {
      char type = inst.call_args[i].type;
      if (type == 'w') {
        if (int_arg_idx < 6) {
          load_arg(inst.call_args[i].name, get_arg_reg_32(int_arg_idx++), 'w', f);
        }
      } else if (type == 'l') {
        if (int_arg_idx < 6) {
          load_arg(inst.call_args[i].name, get_arg_reg_64(int_arg_idx++), 'l', f);
        }
      } else if (type == 's') {
        if (float_arg_idx < 8) {
          load_arg(inst.call_args[i].name, get_float_arg_reg(float_arg_idx++), 's', f);
        }
      } else if (type == 'd') {
        if (float_arg_idx < 8) {
          load_arg(inst.call_args[i].name, get_float_arg_reg(float_arg_idx++), 'd', f);
        }
      }
    }
    fprintf(f, "  movb $%d, %%al\n", float_arg_idx);
    fprintf(f, "  call %s\n", inst.arg1 + 1);
    clear_cache();
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
      } else if (inst.dest_type == 'l') {
        load_arg(inst.arg1, "%rax", 'l', f);
        store_reg(inst.dest, "%rax", 'l', f);
      } else if (inst.dest_type == 's') {
        load_arg(inst.arg1, "%xmm0", 's', f);
        store_reg(inst.dest, "%xmm0", 's', f);
      } else if (inst.dest_type == 'd') {
        load_arg(inst.arg1, "%xmm0", 'd', f);
        store_reg(inst.dest, "%xmm0", 'd', f);
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
      // loadw, loadub, loadl, loads, loadd
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
      } else if (strcmp(inst.op, "loads") == 0) {
        fprintf(f, "  movss (%%rax), %%xmm0\n");
        store_reg(inst.dest, "%xmm0", 's', f);
      } else if (strcmp(inst.op, "loadd") == 0) {
        fprintf(f, "  movsd (%%rax), %%xmm0\n");
        store_reg(inst.dest, "%xmm0", 'd', f);
      }
      return;
    }
    
    if (strcmp(inst.op, "exts") == 0) {
      load_arg(inst.arg1, "%xmm0", 's', f);
      fprintf(f, "  cvtss2sd %%xmm0, %%xmm0\n");
      store_reg(inst.dest, "%xmm0", 'd', f);
      return;
    }
    
    if (strcmp(inst.op, "truncd") == 0) {
      load_arg(inst.arg1, "%xmm0", 'd', f);
      fprintf(f, "  cvtsd2ss %%xmm0, %%xmm0\n");
      store_reg(inst.dest, "%xmm0", 's', f);
      return;
    }
    
    if (strcmp(inst.op, "stosi") == 0) {
      load_arg(inst.arg1, "%xmm0", 's', f);
      fprintf(f, "  cvttss2si %%xmm0, %%eax\n");
      store_reg(inst.dest, "%eax", 'w', f);
      return;
    }
    
    if (strcmp(inst.op, "dtosi") == 0) {
      load_arg(inst.arg1, "%xmm0", 'd', f);
      fprintf(f, "  cvttsd2si %%xmm0, %%eax\n");
      store_reg(inst.dest, "%eax", 'w', f);
      return;
    }
    
    if (strcmp(inst.op, "swtof") == 0) {
      load_arg(inst.arg1, "%eax", 'w', f);
      if (inst.dest_type == 's') {
        fprintf(f, "  cvtsi2ss %%eax, %%xmm0\n");
        store_reg(inst.dest, "%xmm0", 's', f);
      } else {
        fprintf(f, "  cvtsi2sd %%eax, %%xmm0\n");
        store_reg(inst.dest, "%xmm0", 'd', f);
      }
      return;
    }
    
    if (strcmp(inst.op, "sltof") == 0) {
      load_arg(inst.arg1, "%rax", 'l', f);
      if (inst.dest_type == 's') {
        fprintf(f, "  cvtsi2ss %%rax, %%xmm0\n");
        store_reg(inst.dest, "%xmm0", 's', f);
      } else {
        fprintf(f, "  cvtsi2sd %%rax, %%xmm0\n");
        store_reg(inst.dest, "%xmm0", 'd', f);
      }
      return;
    }
    
    if (strcmp(inst.op, "cast") == 0) {
      if (inst.dest_type == 'w') {
        load_arg(inst.arg1, "%xmm0", 's', f);
        fprintf(f, "  movd %%xmm0, %%eax\n");
        store_reg(inst.dest, "%eax", 'w', f);
      } else if (inst.dest_type == 's') {
        load_arg(inst.arg1, "%eax", 'w', f);
        fprintf(f, "  movd %%eax, %%xmm0\n");
        store_reg(inst.dest, "%xmm0", 's', f);
      } else if (inst.dest_type == 'l') {
        load_arg(inst.arg1, "%xmm0", 'd', f);
        fprintf(f, "  movq %%xmm0, %%rax\n");
        store_reg(inst.dest, "%rax", 'l', f);
      } else if (inst.dest_type == 'd') {
        load_arg(inst.arg1, "%rax", 'l', f);
        fprintf(f, "  movq %%rax, %%xmm0\n");
        store_reg(inst.dest, "%xmm0", 'd', f);
      }
      return;
    }
    
    if (strcmp(inst.op, "call") == 0) {
      // Function call with assignment
      int int_arg_idx = 0;
      int float_arg_idx = 0;
      for (int i = 0; i < inst.call_args_count && i < 20; i++) {
        char type = inst.call_args[i].type;
        if (type == 'w') {
          if (int_arg_idx < 6) {
            load_arg(inst.call_args[i].name, get_arg_reg_32(int_arg_idx++), 'w', f);
          }
        } else if (type == 'l') {
          if (int_arg_idx < 6) {
            load_arg(inst.call_args[i].name, get_arg_reg_64(int_arg_idx++), 'l', f);
          }
        } else if (type == 's') {
          if (float_arg_idx < 8) {
            load_arg(inst.call_args[i].name, get_float_arg_reg(float_arg_idx++), 's', f);
          }
        } else if (type == 'd') {
          if (float_arg_idx < 8) {
            load_arg(inst.call_args[i].name, get_float_arg_reg(float_arg_idx++), 'd', f);
          }
        }
      }
      fprintf(f, "  movb $%d, %%al\n", float_arg_idx);
      fprintf(f, "  call %s\n", inst.arg1 + 1);
      clear_cache();
      if (inst.dest_type == 'w') {
        store_reg(inst.dest, "%eax", 'w', f);
      } else if (inst.dest_type == 'l') {
        store_reg(inst.dest, "%rax", 'l', f);
      } else if (inst.dest_type == 's') {
        store_reg(inst.dest, "%xmm0", 's', f);
      } else if (inst.dest_type == 'd') {
        store_reg(inst.dest, "%xmm0", 'd', f);
      }
      return;
    }
    
    // Arithmetic & comparison operations
    if (strcmp(inst.op, "add") == 0 || strcmp(inst.op, "sub") == 0 ||
        strcmp(inst.op, "mul") == 0 || strcmp(inst.op, "div") == 0 ||
        strcmp(inst.op, "rem") == 0 || strcmp(inst.op, "and") == 0 ||
        strcmp(inst.op, "or") == 0 || strcmp(inst.op, "xor") == 0 ||
        strcmp(inst.op, "shl") == 0 || strcmp(inst.op, "sar") == 0 ||
        strcmp(inst.op, "shr") == 0) {
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
          invalidate_cache("%edx");
          fprintf(f, "  cltd\n");
          fprintf(f, "  idivl %%ecx\n");
        } else if (strcmp(inst.op, "rem") == 0) {
          invalidate_cache("%edx");
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
        } else if (strcmp(inst.op, "shr") == 0) {
          fprintf(f, "  shrl %%cl, %%eax\n");
        }
        store_reg(inst.dest, "%eax", 'w', f);
      } else if (inst.dest_type == 'l') {
        load_arg(inst.arg1, "%rax", 'l', f);
        load_arg(inst.arg2, "%rcx", 'l', f);
        if (strcmp(inst.op, "add") == 0) {
          fprintf(f, "  addq %%rcx, %%rax\n");
        } else if (strcmp(inst.op, "sub") == 0) {
          fprintf(f, "  subq %%rcx, %%rax\n");
        } else if (strcmp(inst.op, "mul") == 0) {
          fprintf(f, "  imulq %%rcx, %%rax\n");
        } else if (strcmp(inst.op, "div") == 0) {
          invalidate_cache("%rdx");
          fprintf(f, "  cqto\n");
          fprintf(f, "  idivq %%rcx\n");
        } else if (strcmp(inst.op, "rem") == 0) {
          invalidate_cache("%rdx");
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
        } else if (strcmp(inst.op, "shr") == 0) {
          fprintf(f, "  shrq %%cl, %%rax\n");
        }
        store_reg(inst.dest, "%rax", 'l', f);
      } else if (inst.dest_type == 's') {
        load_arg(inst.arg1, "%xmm0", 's', f);
        load_arg(inst.arg2, "%xmm1", 's', f);
        if (strcmp(inst.op, "add") == 0) {
          fprintf(f, "  addss %%xmm1, %%xmm0\n");
        } else if (strcmp(inst.op, "sub") == 0) {
          fprintf(f, "  subss %%xmm1, %%xmm0\n");
        } else if (strcmp(inst.op, "mul") == 0) {
          fprintf(f, "  mulss %%xmm1, %%xmm0\n");
        } else if (strcmp(inst.op, "div") == 0) {
          fprintf(f, "  divss %%xmm1, %%xmm0\n");
        }
        store_reg(inst.dest, "%xmm0", 's', f);
      } else if (inst.dest_type == 'd') {
        load_arg(inst.arg1, "%xmm0", 'd', f);
        load_arg(inst.arg2, "%xmm1", 'd', f);
        if (strcmp(inst.op, "add") == 0) {
          fprintf(f, "  addsd %%xmm1, %%xmm0\n");
        } else if (strcmp(inst.op, "sub") == 0) {
          fprintf(f, "  subsd %%xmm1, %%xmm0\n");
        } else if (strcmp(inst.op, "mul") == 0) {
          fprintf(f, "  mulsd %%xmm1, %%xmm0\n");
        } else if (strcmp(inst.op, "div") == 0) {
          fprintf(f, "  divsd %%xmm1, %%xmm0\n");
        }
        store_reg(inst.dest, "%xmm0", 'd', f);
      }
      return;
    }
    
    // Integer comparisons (ceqw, ceql, cnew, cnel, csltw, csltl, cslew, cslel, csgtw, csgtl, csgew, csgel)
    int op_len = cast(int) strlen(inst.op);
    char type = inst.op[op_len - 1]; // 'w', 'l', 's', 'd'
    
    if (inst.op[0] == 'c' && (type == 'w' || type == 'l') && (inst.op[1] == 'e' || inst.op[1] == 'n' || inst.op[1] == 's')) {
      const(char)* set_op = null;
      if (strncmp(inst.op, "ceq", 3) == 0) set_op = "sete";
      else if (strncmp(inst.op, "cne", 3) == 0) set_op = "setne";
      else if (strncmp(inst.op, "cslt", 4) == 0) set_op = "setl";
      else if (strncmp(inst.op, "csle", 4) == 0) set_op = "setle";
      else if (strncmp(inst.op, "csgt", 4) == 0) set_op = "setg";
      else if (strncmp(inst.op, "csge", 4) == 0) set_op = "setge";
      
      if (set_op) {
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
    }
    
    // Floating point comparisons (ceqs, ceqd, cnes, cned, clts, cltd, cles, cled, cgts, cgtd, cges, cged)
    if (inst.op[0] == 'c' && (type == 's' || type == 'd') && op_len == 4) {
      if (type == 's') {
        load_arg(inst.arg1, "%xmm0", 's', f);
        load_arg(inst.arg2, "%xmm1", 's', f);
        fprintf(f, "  ucomiss %%xmm1, %%xmm0\n");
      } else {
        load_arg(inst.arg1, "%xmm0", 'd', f);
        load_arg(inst.arg2, "%xmm1", 'd', f);
        fprintf(f, "  ucomisd %%xmm1, %%xmm0\n");
      }
      
      const(char)* set_op = "";
      if (strncmp(inst.op, "ceq", 3) == 0) set_op = "sete";
      else if (strncmp(inst.op, "cne", 3) == 0) set_op = "setne";
      else if (strncmp(inst.op, "clt", 3) == 0) set_op = "setb";
      else if (strncmp(inst.op, "cle", 3) == 0) set_op = "setbe";
      else if (strncmp(inst.op, "cgt", 3) == 0) set_op = "seta";
      else if (strncmp(inst.op, "cge", 3) == 0) set_op = "setae";
      
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
  fprintf(f, "  pushq %%rbx\n");
  fprintf(f, "  pushq %%r12\n");
  fprintf(f, "  pushq %%r13\n");
  fprintf(f, "  pushq %%r14\n");
  fprintf(f, "  pushq %%r15\n");
  if (aligned_stack > 0) {
    fprintf(f, "  subq $%d, %%rsp\n", aligned_stack);
  }
  
  // Store parameter registers into their stack slots or allocated registers
  int int_arg_idx = 0;
  int float_arg_idx = 0;
  for (int i = 0; i < fn.params_count; i++) {
    const(char)* alloc_reg = get_allocated_register(fn.params[i].name, fn.params[i].type);
    int offset = get_temp_offset(fn.params[i].name);
    if (fn.params[i].type == 'w') {
      if (int_arg_idx < 6) {
        const(char)* src_reg = get_arg_reg_32(int_arg_idx++);
        if (alloc_reg) {
          fprintf(f, "  movl %s, %s\n", src_reg, alloc_reg);
        } else {
          fprintf(f, "  movl %s, -%d(%%rbp)\n", src_reg, offset);
        }
      }
    } else if (fn.params[i].type == 'l') {
      if (int_arg_idx < 6) {
        const(char)* src_reg = get_arg_reg_64(int_arg_idx++);
        if (alloc_reg) {
          fprintf(f, "  movq %s, %s\n", src_reg, alloc_reg);
        } else {
          fprintf(f, "  movq %s, -%d(%%rbp)\n", src_reg, offset);
        }
      }
    } else if (fn.params[i].type == 's') {
      if (float_arg_idx < 8) {
        const(char)* src_reg = get_float_arg_reg(float_arg_idx++);
        if (alloc_reg) {
          fprintf(f, "  movss %s, %s\n", src_reg, alloc_reg);
        } else {
          fprintf(f, "  movss %s, -%d(%%rbp)\n", src_reg, offset);
        }
      }
    } else if (fn.params[i].type == 'd') {
      if (float_arg_idx < 8) {
        const(char)* src_reg = get_float_arg_reg(float_arg_idx++);
        if (alloc_reg) {
          fprintf(f, "  movsd %s, %s\n", src_reg, alloc_reg);
        } else {
          fprintf(f, "  movsd %s, -%d(%%rbp)\n", src_reg, offset);
        }
      }
    }
  }
  
  // Generate code for instructions
  clear_cache();
  bool ends_with_ret = false;
  for (int i = 0; i < fn.inst_count; i++) {
    gen_instruction(&fn.instructions[i], fn.ret_type, f);
    if (fn.instructions[i].kind == InstKind.IK_ret) {
      ends_with_ret = true;
    }
  }
  
  // Epilogue if not ended with ret
  if (!ends_with_ret) {
    emit_epilogue(f);
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
    perform_register_allocation(&program_functions[i]);
    gen_function(&program_functions[i], f);
  }
}

unittest {
  import dqbe.regalloc : init_regalloc;
  init_regalloc();
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
