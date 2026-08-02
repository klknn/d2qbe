module dqbe.codegen;

import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.string;

import dqbe.tokenize;
import dqbe.parse;
import dqbe.regalloc : perform_register_allocation, get_allocated_register, init_regalloc;
import dqbe.sysv;
import dqbe.win64;
import dqbe.arm64_abi;

enum {
  TARGET_OS_SYSV,
  TARGET_OS_WINDOWS
}

version(Windows) {
  __gshared int target_os = TARGET_OS_WINDOWS;
} else {
  __gshared int target_os = TARGET_OS_SYSV;
}

enum TargetArch {
  X86_64,
  ARM64
}

version(AArch64) {
  __gshared TargetArch target_arch = TargetArch.ARM64;
} else version(ARM) {
  __gshared TargetArch target_arch = TargetArch.ARM64;
} else {
  __gshared TargetArch target_arch = TargetArch.X86_64;
}

version(OSX) {
  __gshared bool target_apple = true;
} else version(Darwin) {
  __gshared bool target_apple = true;
} else {
  __gshared bool target_apple = false;
}

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
    if (is_same_phys_reg(reg_cache[i].phys_reg.ptr, phys)) {
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
  if (target_arch == TargetArch.ARM64) {
    stack_offset_counter = 0;
  } else {
    stack_offset_counter = 40;
  }
}

void emit_epilogue(FILE* f) {
  if (target_arch == TargetArch.ARM64) {
    fprintf(f, "  mov sp, x29\n");
    fprintf(f, "  ldp x19, x20, [sp, #16]\n");
    fprintf(f, "  ldp x21, x22, [sp, #32]\n");
    fprintf(f, "  ldp x23, x24, [sp, #48]\n");
    fprintf(f, "  ldp x25, x26, [sp, #64]\n");
    fprintf(f, "  ldp x27, x28, [sp, #80]\n");
    fprintf(f, "  ldp x29, x30, [sp], #96\n");
    fprintf(f, "  ret\n");
  } else {
    fprintf(f, "  movq -8(%%rbp), %%rbx\n");
    fprintf(f, "  movq -16(%%rbp), %%r12\n");
    fprintf(f, "  movq -24(%%rbp), %%r13\n");
    fprintf(f, "  movq -32(%%rbp), %%r14\n");
    fprintf(f, "  movq -40(%%rbp), %%r15\n");
    fprintf(f, "  leave\n");
    fprintf(f, "  ret\n");
  }
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
  if (prepass_done) {
    fprintf(get_stderr(), "WARNING_LATE_ALLOC: fn=%s, name=%s -> %d\n", current_fn_name ? current_fn_name : "null", name, stack_offset_counter);
  }
  
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
  
  if (target_arch == TargetArch.ARM64) {
    const(char)* r1 = reg1;
    const(char)* r2 = reg2;
    if ((r1[0] == 'w' || r1[0] == 'x' || r1[0] == 's' || r1[0] == 'd' || r1[0] == 'v') &&
        (r2[0] == 'w' || r2[0] == 'x' || r2[0] == 's' || r2[0] == 'd' || r2[0] == 'v')) {
      if (strcmp(r1 + 1, r2 + 1) == 0) return true;
    }
    return false;
  }
  
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

const(char)* get_phys_reg(const char* arg, char type) {
  if (arg[0] == '%') {
    const(char)* r = get_allocated_register(arg, type);
    if (r) return r;
    return lookup_cache(arg);
  }
  return null;
}

void load_binary_args(const char* arg1, const char* arg2, const char* reg1, const char* reg2, int type, FILE* f) {
  const(char)* r1 = get_phys_reg(arg1, cast(char) type);
  const(char)* r2 = get_phys_reg(arg2, cast(char) type);

  if (r1 && r2 && is_same_phys_reg(r1, reg2) && is_same_phys_reg(r2, reg1)) {
    // Swap situation
    bool is_double = (type == 'd');
    bool is_float = (type == 's');
    bool is_long = (type == 'l');
    
    if (is_double) {
      fprintf(f, "  fmov d18, %s\n", reg1);
      load_arg(arg1, reg1, type, f);
      fprintf(f, "  fmov %s, d18\n", reg2);
    } else if (is_float) {
      fprintf(f, "  fmov s18, %s\n", reg1);
      load_arg(arg1, reg1, type, f);
      fprintf(f, "  fmov %s, s18\n", reg2);
    } else if (is_long) {
      fprintf(f, "  mov x11, %s\n", reg1);
      load_arg(arg1, reg1, type, f);
      fprintf(f, "  mov %s, x11\n", reg2);
    } else {
      fprintf(f, "  mov w11, %s\n", reg1);
      load_arg(arg1, reg1, type, f);
      fprintf(f, "  mov %s, w11\n", reg2);
    }
  } else if (r2 && is_same_phys_reg(r2, reg1)) {
    // Conflict on reg1: load reg2 first
    load_arg(arg2, reg2, type, f);
    load_arg(arg1, reg1, type, f);
  } else {
    // Normal order
    load_arg(arg1, reg1, type, f);
    load_arg(arg2, reg2, type, f);
  }
}

void load_arg(const char* arg, const char* reg, int type, FILE* f) {
  import core.stdc.stdio : fprintf, stderr;
  fprintf(stderr, "DEBUG_LOAD_ARG_ENTRY: arg=%s, reg=%s\n", arg ? arg : "null", reg ? reg : "null");
  if (arg[0] == '%') {
    fprintf(stderr, "DEBUG_CALL_GET_REG: calling get_allocated_register for %s\n", arg);
    const(char)* alloc_reg = get_allocated_register(arg, cast(char) type);
    if (alloc_reg) {
      if (is_same_phys_reg(alloc_reg, reg)) {
        return;
      }
      if (target_arch == TargetArch.ARM64) {
        bool is_float = (type == 's' || type == 'd');
        if (is_float) {
          fprintf(f, "  fmov %s, %s\n", reg, alloc_reg);
        } else {
          fprintf(f, "  mov %s, %s\n", reg, alloc_reg);
        }
      } else {
        if (type == 'w') {
          fprintf(f, "  movl %s, %s\n", alloc_reg, reg);
        } else if (type == 'l') {
          fprintf(f, "  movq %s, %s\n", alloc_reg, reg);
        } else if (type == 's') {
          fprintf(f, "  movss %s, %s\n", alloc_reg, reg);
        } else if (type == 'd') {
          fprintf(f, "  movsd %s, %s\n", alloc_reg, reg);
        }
      }
      invalidate_cache(reg);
      return;
    }
    const(char)* cached_reg = lookup_cache(arg);
    if (cached_reg) {
      if (is_same_phys_reg(cached_reg, reg)) {
        return;
      }
      if (target_arch == TargetArch.ARM64) {
        bool is_float = (type == 's' || type == 'd');
        if (is_float) {
          fprintf(f, "  fmov %s, %s\n", reg, cached_reg);
        } else {
          fprintf(f, "  mov %s, %s\n", reg, cached_reg);
        }
        update_cache(arg, reg);
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
    if (target_arch == TargetArch.ARM64) {
      if (offset > 256) {
        fprintf(f, "  mov x16, #-%d\n", offset);
        fprintf(f, "  add x16, x29, x16\n");
        fprintf(f, "  ldr %s, [x16]\n", reg);
      } else {
        fprintf(f, "  ldur %s, [x29, #-%d]\n", reg, offset);
      }
    } else {
      if (type == 'w') {
        fprintf(f, "  movl -%d(%%rbp), %s\n", offset, reg);
      } else if (type == 'l') {
        fprintf(f, "  movq -%d(%%rbp), %s\n", offset, reg);
      } else if (type == 's') {
        fprintf(f, "  movss -%d(%%rbp), %s\n", offset, reg);
      } else if (type == 'd') {
        fprintf(f, "  movsd -%d(%%rbp), %s\n", offset, reg);
      }
    }
    update_cache(arg, reg);
  } else if (arg[0] == '$') {
    // Global address
    invalidate_cache(reg);
    if (target_arch == TargetArch.ARM64) {
      if (target_apple) {
        fprintf(f, "  adrp %s, _%s@page\n", reg, arg + 1);
        fprintf(f, "  add %s, %s, _%s@pageoff\n", reg, reg, arg + 1);
      } else {
        fprintf(f, "  adrp %s, %s\n", reg, arg + 1);
        fprintf(f, "  add %s, %s, #:lo12:%s\n", reg, reg, arg + 1);
      }
    } else {
      if (target_apple) {
        fprintf(f, "  leaq _%s(%%rip), %s\n", arg + 1, reg);
      } else {
        fprintf(f, "  leaq %s(%%rip), %s\n", arg + 1, reg);
      }
    }
  } else {
    invalidate_cache(reg);
    // Number literal or Float literal
    if (strncmp(arg, "s_", 2) == 0) {
      double val = strtod(arg + 2, null);
      float val_f = cast(float) val;
      int* bits = cast(int*) &val_f;
      if (target_arch == TargetArch.ARM64) {
        // Temp float constant load
        fprintf(f, "  ldr w17, =%u\n", *bits);
        fprintf(f, "  fmov %s, w17\n", reg);
      } else {
        invalidate_cache("%eax");
        fprintf(f, "  movl $%u, %%eax\n", *bits);
        fprintf(f, "  movd %%eax, %s\n", reg);
      }
    } else if (strncmp(arg, "d_", 2) == 0) {
      double val = strtod(arg + 2, null);
      long* bits = cast(long*) &val;
      if (target_arch == TargetArch.ARM64) {
        // Temp double constant load
        fprintf(f, "  ldr x17, =%lld\n", *bits);
        fprintf(f, "  fmov %s, x17\n", reg);
      } else {
        invalidate_cache("%rax");
        fprintf(f, "  movabsq $%lld, %%rax\n", *bits);
        fprintf(f, "  movq %%rax, %s\n", reg);
      }
    } else {
      // Raw integer literal
      if (target_arch == TargetArch.ARM64) {
        fprintf(f, "  mov %s, #%s\n", reg, arg);
      } else {
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
}

void store_reg(const char* dest, const char* reg, int type, FILE* f) {
  const(char)* alloc_reg = get_allocated_register(dest, cast(char) type);
  if (alloc_reg) {
    if (is_same_phys_reg(alloc_reg, reg)) {
      return;
    }
    if (target_arch == TargetArch.ARM64) {
      bool is_float = (type == 's' || type == 'd');
      if (is_float) {
        fprintf(f, "  fmov %s, %s\n", alloc_reg, reg);
      } else {
        fprintf(f, "  mov %s, %s\n", alloc_reg, reg);
      }
    } else {
      if (type == 'w') {
        fprintf(f, "  movl %s, %s\n", reg, alloc_reg);
      } else if (type == 'l') {
        fprintf(f, "  movq %s, %s\n", reg, alloc_reg);
      } else if (type == 's') {
        fprintf(f, "  movss %s, %s\n", reg, alloc_reg);
      } else if (type == 'd') {
        fprintf(f, "  movsd %s, %s\n", reg, alloc_reg);
      }
    }
    invalidate_cache(alloc_reg);
    return;
  }
  int offset = get_temp_offset(dest);
  if (target_arch == TargetArch.ARM64) {
    if (offset > 256) {
      fprintf(f, "  mov x16, #-%d\n", offset);
      fprintf(f, "  add x16, x29, x16\n");
      fprintf(f, "  str %s, [x16]\n", reg);
    } else {
      fprintf(f, "  stur %s, [x29, #-%d]\n", reg, offset);
    }
  } else {
    if (type == 'w') {
      fprintf(f, "  movl %s, -%d(%%rbp)\n", reg, offset);
    } else if (type == 'l') {
      fprintf(f, "  movq %s, -%d(%%rbp)\n", reg, offset);
    } else if (type == 's') {
      fprintf(f, "  movss %s, -%d(%%rbp)\n", reg, offset);
    } else if (type == 'd') {
      fprintf(f, "  movsd %s, -%d(%%rbp)\n", reg, offset);
    }
  }
  update_cache(dest, reg);
}

const(char)* get_arg_reg_32(int idx) {
  if (target_arch == TargetArch.ARM64) {
    return arm64_get_arg_reg_32(idx);
  }
  if (target_os == TARGET_OS_WINDOWS) {
    return win64_get_arg_reg_32(idx);
  } else {
    return sysv_get_arg_reg_32(idx);
  }
}

const(char)* get_arg_reg_64(int idx) {
  if (target_arch == TargetArch.ARM64) {
    return arm64_get_arg_reg_64(idx);
  }
  if (target_os == TARGET_OS_WINDOWS) {
    return win64_get_arg_reg_64(idx);
  } else {
    return sysv_get_arg_reg_64(idx);
  }
}

const(char)* get_float_arg_reg(int idx) {
  if (target_arch == TargetArch.ARM64) {
    return arm64_get_float_arg_reg(idx, 's');
  }
  if (target_os == TARGET_OS_WINDOWS) {
    return win64_get_float_arg_reg(idx);
  } else {
    return sysv_get_float_arg_reg(idx);
  }
}

const(char)* get_param_reg(int arg_idx, char type, int int_arg_idx, int float_arg_idx) {
  if (target_arch == TargetArch.ARM64) {
    return arm64_get_param_reg(arg_idx, type, int_arg_idx, float_arg_idx);
  }
  if (target_os == TARGET_OS_WINDOWS) {
    return win64_get_param_reg(arg_idx, type, int_arg_idx, float_arg_idx);
  } else {
    return sysv_get_param_reg(arg_idx, type, int_arg_idx, float_arg_idx);
  }
}

int align_to_16(int size) {
  return ((size + 15) / 16) * 16;
}

int stack_argument_count(Instruction* inst) {
  int int_arg_idx = 0;
  int float_arg_idx = 0;
  int count = 0;
  for (int i = 0; i < inst.call_args_count; i++) {
    char type = inst.call_args[i].type;
    const(char)* reg = get_param_reg(i, type, int_arg_idx, float_arg_idx);
    if (type == 'w' || type == 'l') int_arg_idx++;
    else if (type == 's' || type == 'd') float_arg_idx++;
    if (!reg) count++;
  }
  return count;
}

int outgoing_stack_size(Instruction* inst) {
  int size = stack_argument_count(inst) * 8;
  if (target_arch == TargetArch.X86_64 && target_os == TARGET_OS_WINDOWS) {
    size += 32; // Required Win64 shadow space.
  }
  return align_to_16(size);
}

void reserve_outgoing_stack(int size, FILE* f) {
  if (size == 0) return;
  if (target_arch == TargetArch.ARM64) {
    fprintf(f, "  sub sp, sp, #%d\n", size);
  } else {
    fprintf(f, "  subq $%d, %%rsp\n", size);
  }
}

void release_outgoing_stack(int size, FILE* f) {
  if (size == 0) return;
  if (target_arch == TargetArch.ARM64) {
    fprintf(f, "  add sp, sp, #%d\n", size);
  } else {
    fprintf(f, "  addq $%d, %%rsp\n", size);
  }
}

void store_outgoing_stack_arg(const char* arg, char type, int stack_arg_idx, FILE* f) {
  int offset = stack_arg_idx * 8;
  if (target_arch == TargetArch.X86_64 && target_os == TARGET_OS_WINDOWS) {
    offset += 32; // Stack arguments follow the Win64 shadow space.
  }

  if (target_arch == TargetArch.ARM64) {
    if (type == 'w') {
      load_arg(arg, "w9", type, f);
      fprintf(f, "  str w9, [sp, #%d]\n", offset);
    } else if (type == 'l') {
      load_arg(arg, "x9", type, f);
      fprintf(f, "  str x9, [sp, #%d]\n", offset);
    } else if (type == 's') {
      load_arg(arg, "s16", type, f);
      fprintf(f, "  str s16, [sp, #%d]\n", offset);
    } else if (type == 'd') {
      load_arg(arg, "d16", type, f);
      fprintf(f, "  str d16, [sp, #%d]\n", offset);
    }
  } else {
    if (type == 'w') {
      load_arg(arg, "%eax", type, f);
      fprintf(f, "  movl %%eax, %d(%%rsp)\n", offset);
    } else if (type == 'l') {
      load_arg(arg, "%rax", type, f);
      fprintf(f, "  movq %%rax, %d(%%rsp)\n", offset);
    } else if (type == 's') {
      load_arg(arg, "%xmm0", type, f);
      fprintf(f, "  movss %%xmm0, %d(%%rsp)\n", offset);
    } else if (type == 'd') {
      load_arg(arg, "%xmm0", type, f);
      fprintf(f, "  movsd %%xmm0, %d(%%rsp)\n", offset);
    }
  }
}

void setup_call_args(Instruction* inst, FILE* f) {
  int int_arg_idx = 0;
  int float_arg_idx = 0;
  int stack_arg_idx = 0;
  for (int i = 0; i < inst.call_args_count; i++) {
    char type = inst.call_args[i].type;
    const(char)* reg = get_param_reg(i, type, int_arg_idx, float_arg_idx);
    if (type == 'w' || type == 'l') int_arg_idx++;
    else if (type == 's' || type == 'd') float_arg_idx++;

    if (reg) {
      load_arg(inst.call_args[i].name, reg, type, f);
    } else {
      store_outgoing_stack_arg(inst.call_args[i].name, type, stack_arg_idx, f);
      stack_arg_idx++;
    }
  }
}

int incoming_stack_arg_offset(int stack_arg_idx) {
  if (target_arch == TargetArch.ARM64) {
    return 96 + stack_arg_idx * 8;
  }
  if (target_os == TARGET_OS_WINDOWS) {
    return 48 + stack_arg_idx * 8;
  }
  return 16 + stack_arg_idx * 8;
}

void load_incoming_stack_arg(const char* dest, char type, int stack_arg_idx, FILE* f) {
  int offset = incoming_stack_arg_offset(stack_arg_idx);
  if (target_arch == TargetArch.ARM64) {
    if (type == 'w') {
      fprintf(f, "  ldr w9, [x29, #%d]\n", offset);
      store_reg(dest, "w9", type, f);
    } else if (type == 'l') {
      fprintf(f, "  ldr x9, [x29, #%d]\n", offset);
      store_reg(dest, "x9", type, f);
    } else if (type == 's') {
      fprintf(f, "  ldr s16, [x29, #%d]\n", offset);
      store_reg(dest, "s16", type, f);
    } else if (type == 'd') {
      fprintf(f, "  ldr d16, [x29, #%d]\n", offset);
      store_reg(dest, "d16", type, f);
    }
  } else {
    if (type == 'w') {
      fprintf(f, "  movl %d(%%rbp), %%eax\n", offset);
      store_reg(dest, "%eax", type, f);
    } else if (type == 'l') {
      fprintf(f, "  movq %d(%%rbp), %%rax\n", offset);
      store_reg(dest, "%rax", type, f);
    } else if (type == 's') {
      fprintf(f, "  movss %d(%%rbp), %%xmm0\n", offset);
      store_reg(dest, "%xmm0", type, f);
    } else if (type == 'd') {
      fprintf(f, "  movsd %d(%%rbp), %%xmm0\n", offset);
      store_reg(dest, "%xmm0", type, f);
    }
  }
}

__gshared bool prepass_done = false;
const(char)* current_fn_name;

void gen_instruction(Instruction* inst, int fn_ret_type, FILE* f) {
  if (inst.kind == InstKind.IK_label) {
    fprintf(f, ".L%s_%s:\n", current_fn_name, inst.label + 1);
    clear_cache();
    return;
  }
  
  if (inst.kind == InstKind.IK_jmp) {
    if (target_arch == TargetArch.ARM64) {
      fprintf(f, "  b .L%s_%s\n", current_fn_name, inst.label + 1);
    } else {
      fprintf(f, "  jmp .L%s_%s\n", current_fn_name, inst.label + 1);
    }
    clear_cache();
    return;
  }
  
  if (inst.kind == InstKind.IK_jnz) {
    if (target_arch == TargetArch.ARM64) {
      load_arg(inst.arg1, "w9", 'w', f);
      fprintf(f, "  cbnz w9, .L%s_%s\n", current_fn_name, inst.label + 1);
      fprintf(f, "  b .L%s_%s\n", current_fn_name, inst.label_else + 1);
    } else {
      load_arg(inst.arg1, "%eax", 'w', f);
      fprintf(f, "  cmpl $0, %%eax\n");
      fprintf(f, "  jne .L%s_%s\n", current_fn_name, inst.label + 1);
      fprintf(f, "  jmp .L%s_%s\n", current_fn_name, inst.label_else + 1);
    }
    clear_cache();
    return;
  }
  
  if (inst.kind == InstKind.IK_ret) {
    if (inst.arg1) {
      if (fn_ret_type == 'w') {
        load_arg(inst.arg1, (target_arch == TargetArch.ARM64) ? "w0" : "%eax", 'w', f);
      } else if (fn_ret_type == 'l') {
        load_arg(inst.arg1, (target_arch == TargetArch.ARM64) ? "x0" : "%rax", 'l', f);
      } else if (fn_ret_type == 's') {
        load_arg(inst.arg1, (target_arch == TargetArch.ARM64) ? "s0" : "%xmm0", 's', f);
      } else if (fn_ret_type == 'd') {
        load_arg(inst.arg1, (target_arch == TargetArch.ARM64) ? "d0" : "%xmm0", 'd', f);
      }
    }
    emit_epilogue(f);
    return;
  }
  
  if (inst.kind == InstKind.IK_store) {
    // storew %val, %ptr
    char type = inst.op[5]; // 'b', 'h', 'w', 'l', 's', 'd'
    if (target_arch == TargetArch.ARM64) {
      if (type == 'b') {
        load_arg(inst.arg1, "w9", 'w', f);
        load_arg(inst.arg2, "x10", 'l', f);
        fprintf(f, "  strb w9, [x10]\n");
      } else if (type == 'w') {
        load_arg(inst.arg1, "w9", 'w', f);
        load_arg(inst.arg2, "x10", 'l', f);
        fprintf(f, "  str w9, [x10]\n");
      } else if (type == 'l') {
        load_arg(inst.arg1, "x9", 'l', f);
        load_arg(inst.arg2, "x10", 'l', f);
        fprintf(f, "  str x9, [x10]\n");
      } else if (type == 's') {
        load_arg(inst.arg1, "s16", 's', f);
        load_arg(inst.arg2, "x10", 'l', f);
        fprintf(f, "  str s16, [x10]\n");
      } else if (type == 'd') {
        load_arg(inst.arg1, "d16", 'd', f);
        load_arg(inst.arg2, "x10", 'l', f);
        fprintf(f, "  str d16, [x10]\n");
      }
    } else {
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
    }
    return;
  }
  
  if (inst.kind == InstKind.IK_call) {
    // Void call
    int call_stack_size = outgoing_stack_size(inst);
    reserve_outgoing_stack(call_stack_size, f);
    setup_call_args(inst, f);
    if (target_arch == TargetArch.ARM64) {
      if (target_apple) {
        fprintf(f, "  bl _%s\n", inst.arg1 + 1);
      } else {
        fprintf(f, "  bl %s\n", inst.arg1 + 1);
      }
    } else {
      if (target_os == TARGET_OS_SYSV) {
        int float_arg_count = 0;
        for (int i = 0; i < inst.call_args_count; i++) {
          if (inst.call_args[i].type == 's' || inst.call_args[i].type == 'd') float_arg_count++;
        }
        fprintf(f, "  movb $%d, %%al\n", float_arg_count);
      }
      if (target_apple) {
        fprintf(f, "  call _%s\n", inst.arg1 + 1);
      } else {
        fprintf(f, "  call %s\n", inst.arg1 + 1);
      }
    }
    release_outgoing_stack(call_stack_size, f);
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
      if (target_arch == TargetArch.ARM64) {
        if (var_offset > 4095) {
          fprintf(f, "  mov x16, #%d\n", var_offset);
          fprintf(f, "  sub x9, x29, x16\n");
        } else {
          fprintf(f, "  sub x9, x29, #%d\n", var_offset);
        }
        store_reg(inst.dest, "x9", 'l', f);
      } else {
        fprintf(f, "  leaq -%d(%%rbp), %%rax\n", var_offset);
        store_reg(inst.dest, "%rax", 'l', f);
      }
      return;
    }
    
    if (strcmp(inst.op, "copy") == 0) {
      if (inst.dest_type == 'w') {
        load_arg(inst.arg1, (target_arch == TargetArch.ARM64) ? "w9" : "%eax", 'w', f);
        store_reg(inst.dest, (target_arch == TargetArch.ARM64) ? "w9" : "%eax", 'w', f);
      } else if (inst.dest_type == 'l') {
        load_arg(inst.arg1, (target_arch == TargetArch.ARM64) ? "x9" : "%rax", 'l', f);
        store_reg(inst.dest, (target_arch == TargetArch.ARM64) ? "x9" : "%rax", 'l', f);
      } else if (inst.dest_type == 's') {
        load_arg(inst.arg1, (target_arch == TargetArch.ARM64) ? "s16" : "%xmm0", 's', f);
        store_reg(inst.dest, (target_arch == TargetArch.ARM64) ? "s16" : "%xmm0", 's', f);
      } else if (inst.dest_type == 'd') {
        load_arg(inst.arg1, (target_arch == TargetArch.ARM64) ? "d16" : "%xmm0", 'd', f);
        store_reg(inst.dest, (target_arch == TargetArch.ARM64) ? "d16" : "%xmm0", 'd', f);
      }
      return;
    }
    
    if (strcmp(inst.op, "extsw") == 0) {
      if (target_arch == TargetArch.ARM64) {
        load_arg(inst.arg1, "w9", 'w', f);
        fprintf(f, "  sxtw x9, w9\n");
        store_reg(inst.dest, "x9", 'l', f);
      } else {
        load_arg(inst.arg1, "%eax", 'w', f);
        fprintf(f, "  movslq %%eax, %%rax\n");
        store_reg(inst.dest, "%rax", 'l', f);
      }
      return;
    }
    
    if (strncmp(inst.op, "load", 4) == 0) {
      // loadw, loadub, loadl, loads, loadd
      if (target_arch == TargetArch.ARM64) {
        load_arg(inst.arg1, "x9", 'l', f);
        if (strcmp(inst.op, "loadub") == 0) {
          fprintf(f, "  ldrb w10, [x9]\n");
          store_reg(inst.dest, "w10", 'w', f);
        } else if (strcmp(inst.op, "loadw") == 0) {
          fprintf(f, "  ldr w10, [x9]\n");
          store_reg(inst.dest, "w10", 'w', f);
        } else if (strcmp(inst.op, "loadl") == 0) {
          fprintf(f, "  ldr x10, [x9]\n");
          store_reg(inst.dest, "x10", 'l', f);
        } else if (strcmp(inst.op, "loads") == 0) {
          fprintf(f, "  ldr s16, [x9]\n");
          store_reg(inst.dest, "s16", 's', f);
        } else if (strcmp(inst.op, "loadd") == 0) {
          fprintf(f, "  ldr d16, [x9]\n");
          store_reg(inst.dest, "d16", 'd', f);
        }
      } else {
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
      }
      return;
    }
    
    if (strcmp(inst.op, "exts") == 0) {
      if (target_arch == TargetArch.ARM64) {
        load_arg(inst.arg1, "s16", 's', f);
        fprintf(f, "  fcvt d16, s16\n");
        store_reg(inst.dest, "d16", 'd', f);
      } else {
        load_arg(inst.arg1, "%xmm0", 's', f);
        fprintf(f, "  cvtss2sd %%xmm0, %%xmm0\n");
        store_reg(inst.dest, "%xmm0", 'd', f);
      }
      return;
    }
    
    if (strcmp(inst.op, "truncd") == 0) {
      if (target_arch == TargetArch.ARM64) {
        load_arg(inst.arg1, "d16", 'd', f);
        fprintf(f, "  fcvt s16, d16\n");
        store_reg(inst.dest, "s16", 's', f);
      } else {
        load_arg(inst.arg1, "%xmm0", 'd', f);
        fprintf(f, "  cvtsd2ss %%xmm0, %%xmm0\n");
        store_reg(inst.dest, "%xmm0", 's', f);
      }
      return;
    }
    
    if (strcmp(inst.op, "stosi") == 0) {
      if (target_arch == TargetArch.ARM64) {
        load_arg(inst.arg1, "s16", 's', f);
        fprintf(f, "  fcvtzs w10, s16\n");
        store_reg(inst.dest, "w10", 'w', f);
      } else {
        load_arg(inst.arg1, "%xmm0", 's', f);
        fprintf(f, "  cvttss2si %%xmm0, %%eax\n");
        store_reg(inst.dest, "%eax", 'w', f);
      }
      return;
    }
    
    if (strcmp(inst.op, "dtosi") == 0) {
      if (target_arch == TargetArch.ARM64) {
        load_arg(inst.arg1, "d16", 'd', f);
        fprintf(f, "  fcvtzs w10, d16\n");
        store_reg(inst.dest, "w10", 'w', f);
      } else {
        load_arg(inst.arg1, "%xmm0", 'd', f);
        fprintf(f, "  cvttsd2si %%xmm0, %%eax\n");
        store_reg(inst.dest, "%eax", 'w', f);
      }
      return;
    }
    
    if (strcmp(inst.op, "swtof") == 0) {
      if (target_arch == TargetArch.ARM64) {
        load_arg(inst.arg1, "w9", 'w', f);
        if (inst.dest_type == 's') {
          fprintf(f, "  scvtf s16, w9\n");
          store_reg(inst.dest, "s16", 's', f);
        } else {
          fprintf(f, "  scvtf d16, w9\n");
          store_reg(inst.dest, "d16", 'd', f);
        }
      } else {
        load_arg(inst.arg1, "%eax", 'w', f);
        if (inst.dest_type == 's') {
          fprintf(f, "  cvtsi2ss %%eax, %%xmm0\n");
          store_reg(inst.dest, "%xmm0", 's', f);
        } else {
          fprintf(f, "  cvtsi2sd %%eax, %%xmm0\n");
          store_reg(inst.dest, "%xmm0", 'd', f);
        }
      }
      return;
    }
    
    if (strcmp(inst.op, "sltof") == 0) {
      if (target_arch == TargetArch.ARM64) {
        load_arg(inst.arg1, "x9", 'l', f);
        if (inst.dest_type == 's') {
          fprintf(f, "  scvtf s16, x9\n");
          store_reg(inst.dest, "s16", 's', f);
        } else {
          fprintf(f, "  scvtf d16, x9\n");
          store_reg(inst.dest, "d16", 'd', f);
        }
      } else {
        load_arg(inst.arg1, "%rax", 'l', f);
        if (inst.dest_type == 's') {
          fprintf(f, "  cvtsi2ss %%rax, %%xmm0\n");
          store_reg(inst.dest, "%xmm0", 's', f);
        } else {
          fprintf(f, "  cvtsi2sd %%rax, %%xmm0\n");
          store_reg(inst.dest, "%xmm0", 'd', f);
        }
      }
      return;
    }
    
    if (strcmp(inst.op, "cast") == 0) {
      if (target_arch == TargetArch.ARM64) {
        if (inst.dest_type == 'w') {
          load_arg(inst.arg1, "s16", 's', f);
          fprintf(f, "  fmov w10, s16\n");
          store_reg(inst.dest, "w10", 'w', f);
        } else if (inst.dest_type == 's') {
          load_arg(inst.arg1, "w9", 'w', f);
          fprintf(f, "  fmov s16, w9\n");
          store_reg(inst.dest, "s16", 's', f);
        } else if (inst.dest_type == 'l') {
          load_arg(inst.arg1, "d16", 'd', f);
          fprintf(f, "  fmov x10, d16\n");
          store_reg(inst.dest, "x10", 'l', f);
        } else if (inst.dest_type == 'd') {
          load_arg(inst.arg1, "x9", 'l', f);
          fprintf(f, "  fmov d16, x9\n");
          store_reg(inst.dest, "d16", 'd', f);
        }
      } else {
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
      }
      return;
    }
    
    if (strcmp(inst.op, "call") == 0) {
      // Function call with assignment
      int call_stack_size = outgoing_stack_size(inst);
      reserve_outgoing_stack(call_stack_size, f);
      setup_call_args(inst, f);
      if (target_arch == TargetArch.ARM64) {
        if (target_apple) {
          fprintf(f, "  bl _%s\n", inst.arg1 + 1);
        } else {
          fprintf(f, "  bl %s\n", inst.arg1 + 1);
        }
      } else {
        if (target_os == TARGET_OS_SYSV) {
          int float_arg_count = 0;
          for (int i = 0; i < inst.call_args_count; i++) {
            if (inst.call_args[i].type == 's' || inst.call_args[i].type == 'd') float_arg_count++;
          }
          fprintf(f, "  movb $%d, %%al\n", float_arg_count);
        }
        if (target_apple) {
          fprintf(f, "  call _%s\n", inst.arg1 + 1);
        } else {
          fprintf(f, "  call %s\n", inst.arg1 + 1);
        }
      }
      release_outgoing_stack(call_stack_size, f);
      clear_cache();
      if (target_arch == TargetArch.ARM64) {
        if (inst.dest_type == 'w') {
          store_reg(inst.dest, "w0", 'w', f);
        } else if (inst.dest_type == 'l') {
          store_reg(inst.dest, "x0", 'l', f);
        } else if (inst.dest_type == 's') {
          store_reg(inst.dest, "s0", 's', f);
        } else if (inst.dest_type == 'd') {
          store_reg(inst.dest, "d0", 'd', f);
        }
      } else {
        if (inst.dest_type == 'w') {
          store_reg(inst.dest, "%eax", 'w', f);
        } else if (inst.dest_type == 'l') {
          store_reg(inst.dest, "%rax", 'l', f);
        } else if (inst.dest_type == 's') {
          store_reg(inst.dest, "%xmm0", 's', f);
        } else if (inst.dest_type == 'd') {
          store_reg(inst.dest, "%xmm0", 'd', f);
        }
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
        if (target_arch == TargetArch.ARM64) {
          load_binary_args(inst.arg1, inst.arg2, "w9", "w10", 'w', f);
          if (strcmp(inst.op, "add") == 0) {
            fprintf(f, "  add w9, w9, w10\n");
          } else if (strcmp(inst.op, "sub") == 0) {
            fprintf(f, "  sub w9, w9, w10\n");
          } else if (strcmp(inst.op, "mul") == 0) {
            fprintf(f, "  mul w9, w9, w10\n");
          } else if (strcmp(inst.op, "div") == 0) {
            fprintf(f, "  sdiv w9, w9, w10\n");
          } else if (strcmp(inst.op, "rem") == 0) {
            fprintf(f, "  sdiv w11, w9, w10\n");
            fprintf(f, "  msub w9, w11, w10, w9\n");
          } else if (strcmp(inst.op, "and") == 0) {
            fprintf(f, "  and w9, w9, w10\n");
          } else if (strcmp(inst.op, "or") == 0) {
            fprintf(f, "  orr w9, w9, w10\n");
          } else if (strcmp(inst.op, "xor") == 0) {
            fprintf(f, "  eor w9, w9, w10\n");
          } else if (strcmp(inst.op, "shl") == 0) {
            fprintf(f, "  lsl w9, w9, w10\n");
          } else if (strcmp(inst.op, "sar") == 0) {
            fprintf(f, "  asr w9, w9, w10\n");
          } else if (strcmp(inst.op, "shr") == 0) {
            fprintf(f, "  lsr w9, w9, w10\n");
          }
          store_reg(inst.dest, "w9", 'w', f);
        } else {
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
        }
      } else if (inst.dest_type == 'l') {
        if (target_arch == TargetArch.ARM64) {
          load_binary_args(inst.arg1, inst.arg2, "x9", "x10", 'l', f);
          if (strcmp(inst.op, "add") == 0) {
            fprintf(f, "  add x9, x9, x10\n");
          } else if (strcmp(inst.op, "sub") == 0) {
            fprintf(f, "  sub x9, x9, x10\n");
          } else if (strcmp(inst.op, "mul") == 0) {
            fprintf(f, "  mul x9, x9, x10\n");
          } else if (strcmp(inst.op, "div") == 0) {
            fprintf(f, "  sdiv x9, x9, x10\n");
          } else if (strcmp(inst.op, "rem") == 0) {
            fprintf(f, "  sdiv x11, x9, x10\n");
            fprintf(f, "  msub x9, x11, x10, x9\n");
          } else if (strcmp(inst.op, "and") == 0) {
            fprintf(f, "  and x9, x9, x10\n");
          } else if (strcmp(inst.op, "or") == 0) {
            fprintf(f, "  orr x9, x9, x10\n");
          } else if (strcmp(inst.op, "xor") == 0) {
            fprintf(f, "  eor x9, x9, x10\n");
          } else if (strcmp(inst.op, "shl") == 0) {
            fprintf(f, "  lsl x9, x9, x10\n");
          } else if (strcmp(inst.op, "sar") == 0) {
            fprintf(f, "  asr x9, x9, x10\n");
          } else if (strcmp(inst.op, "shr") == 0) {
            fprintf(f, "  lsr x9, x9, x10\n");
          }
          store_reg(inst.dest, "x9", 'l', f);
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
        }
      } else if (inst.dest_type == 's') {
        if (target_arch == TargetArch.ARM64) {
          load_binary_args(inst.arg1, inst.arg2, "s16", "s17", 's', f);
          if (strcmp(inst.op, "add") == 0) {
            fprintf(f, "  fadd s16, s16, s17\n");
          } else if (strcmp(inst.op, "sub") == 0) {
            fprintf(f, "  fsub s16, s16, s17\n");
          } else if (strcmp(inst.op, "mul") == 0) {
            fprintf(f, "  fmul s16, s16, s17\n");
          } else if (strcmp(inst.op, "div") == 0) {
            fprintf(f, "  fdiv s16, s16, s17\n");
          }
          store_reg(inst.dest, "s16", 's', f);
        } else {
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
        }
      } else if (inst.dest_type == 'd') {
        if (target_arch == TargetArch.ARM64) {
          load_binary_args(inst.arg1, inst.arg2, "d16", "d17", 'd', f);
          if (strcmp(inst.op, "add") == 0) {
            fprintf(f, "  fadd d16, d16, d17\n");
          } else if (strcmp(inst.op, "sub") == 0) {
            fprintf(f, "  fsub d16, d16, d17\n");
          } else if (strcmp(inst.op, "mul") == 0) {
            fprintf(f, "  fmul d16, d16, d17\n");
          } else if (strcmp(inst.op, "div") == 0) {
            fprintf(f, "  fdiv d16, d16, d17\n");
          }
          store_reg(inst.dest, "d16", 'd', f);
        } else {
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
        if (target_arch == TargetArch.ARM64) {
          const(char)* arm_cond = null;
          if (strcmp(set_op, "sete") == 0) arm_cond = "eq";
          else if (strcmp(set_op, "setne") == 0) arm_cond = "ne";
          else if (strcmp(set_op, "setl") == 0) arm_cond = "lt";
          else if (strcmp(set_op, "setle") == 0) arm_cond = "le";
          else if (strcmp(set_op, "setg") == 0) arm_cond = "gt";
          else if (strcmp(set_op, "setge") == 0) arm_cond = "ge";
          
          if (type == 'l') {
            load_binary_args(inst.arg1, inst.arg2, "x9", "x10", 'l', f);
            fprintf(f, "  cmp x9, x10\n");
          } else {
            load_binary_args(inst.arg1, inst.arg2, "w9", "w10", 'w', f);
            fprintf(f, "  cmp w9, w10\n");
          }
          fprintf(f, "  cset w9, %s\n", arm_cond);
          store_reg(inst.dest, "w9", 'w', f);
        } else {
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
        }
        return;
      }
    }
    
    // Floating point comparisons (ceqs, ceqd, cnes, cned, clts, cltd, cles, cled, cgts, cgtd, cges, cged)
    if (inst.op[0] == 'c' && (type == 's' || type == 'd') && op_len == 4) {
      if (target_arch == TargetArch.ARM64) {
        if (type == 's') {
          load_binary_args(inst.arg1, inst.arg2, "s16", "s17", 's', f);
          fprintf(f, "  fcmp s16, s17\n");
        } else {
          load_binary_args(inst.arg1, inst.arg2, "d16", "d17", 'd', f);
          fprintf(f, "  fcmp d16, d17\n");
        }
        const(char)* arm_cond = "";
        if (strncmp(inst.op, "ceq", 3) == 0) arm_cond = "eq";
        else if (strncmp(inst.op, "cne", 3) == 0) arm_cond = "ne";
        else if (strncmp(inst.op, "clt", 3) == 0) arm_cond = "mi";
        else if (strncmp(inst.op, "cle", 3) == 0) arm_cond = "ls";
        else if (strncmp(inst.op, "cgt", 3) == 0) arm_cond = "gt";
        else if (strncmp(inst.op, "cge", 3) == 0) arm_cond = "ge";
        
        fprintf(f, "  cset w9, %s\n", arm_cond);
        store_reg(inst.dest, "w9", 'w', f);
      } else {
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
      }
      return;
    }
    
    fprintf(get_stderr(), "Unknown assignment op: %s\n", inst.op);
    exit(1);
  }
}

void gen_function(FunctionDef* fn, FILE* f) {
  prepass_done = false;
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
  
  int total_frame = ((stack_offset_counter + 15) / 16) * 16;
  if (target_arch == TargetArch.X86_64 && target_os == TARGET_OS_WINDOWS) {
    total_frame = total_frame + 32; // Reserve 32 bytes of shadow space
  }
  int aligned_stack = total_frame;
  if (target_arch != TargetArch.ARM64) {
    int saved_regs_size = 40;
    aligned_stack = total_frame - saved_regs_size;
  }
  prepass_done = true;
  
  // Emit prologue
  if (fn.is_export) {
    if (target_apple) {
      fprintf(f, ".globl _%s\n", fn.name + 1);
    } else {
      fprintf(f, ".globl %s\n", fn.name + 1);
    }
  }
  if (target_apple) {
    fprintf(f, "_%s:\n", fn.name + 1);
  } else {
    fprintf(f, "%s:\n", fn.name + 1);
  }
  
  if (target_arch == TargetArch.ARM64) {
    fprintf(f, "  stp x29, x30, [sp, #-96]!\n");
    fprintf(f, "  mov x29, sp\n");
    fprintf(f, "  stp x19, x20, [sp, #16]\n");
    fprintf(f, "  stp x21, x22, [sp, #32]\n");
    fprintf(f, "  stp x23, x24, [sp, #48]\n");
    fprintf(f, "  stp x25, x26, [sp, #64]\n");
    fprintf(f, "  stp x27, x28, [sp, #80]\n");
    if (aligned_stack > 0) {
      if (aligned_stack > 4095) {
        fprintf(f, "  mov x16, #%d\n", aligned_stack);
        fprintf(f, "  sub sp, sp, x16\n");
      } else {
        fprintf(f, "  sub sp, sp, #%d\n", aligned_stack);
      }
    }
  } else {
    fprintf(f, "  pushq %%rbp\n");
    fprintf(f, "  movq %%rsp, %%rbp\n");
    fprintf(f, "  pushq %%rbx\n");
    fprintf(f, "  pushq %%r12\n");
    fprintf(f, "  pushq %%r13\n");
    fprintf(f, "  pushq %%r14\n");
    fprintf(f, "  pushq %%r15\n");
    if (aligned_stack > 0) {
      if (target_os == TARGET_OS_WINDOWS && aligned_stack >= 4096) {
        fprintf(f, "  movq $%d, %%rax\n", aligned_stack);
        fprintf(f, "  movq %%rsp, %%r11\n");
        fprintf(f, ".Lprobe_loop_%s:\n", fn.name + 1);
        fprintf(f, "  subq $4096, %%r11\n");
        fprintf(f, "  testq %%rax, (%%r11)\n");
        fprintf(f, "  subq $4096, %%rax\n");
        fprintf(f, "  cmpq $4096, %%rax\n");
        fprintf(f, "  jae .Lprobe_loop_%s\n", fn.name + 1);
        fprintf(f, "  subq %%rax, %%r11\n");
        fprintf(f, "  testq %%rax, (%%r11)\n");
        fprintf(f, "  movq %%r11, %%rsp\n");
      } else {
        fprintf(f, "  subq $%d, %%rsp\n", aligned_stack);
      }
    }
  }
  
  // Store parameter registers into their stack slots or allocated registers
  int int_arg_idx = 0;
  int float_arg_idx = 0;
  int stack_arg_idx = 0;
  for (int i = 0; i < fn.params_count; i++) {
    char type = fn.params[i].type;
    const(char)* src_reg = get_param_reg(i, type, int_arg_idx, float_arg_idx);
    if (type == 'w' || type == 'l') int_arg_idx++;
    else if (type == 's' || type == 'd') float_arg_idx++;

    if (src_reg) {
      store_reg(fn.params[i].name, src_reg, type, f);
    } else {
      load_incoming_stack_arg(fn.params[i].name, type, stack_arg_idx, f);
      stack_arg_idx++;
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
  if (target_apple) {
    fprintf(f, ".globl _%s\n", def.name + 1);
    fprintf(f, "_%s:\n", def.name + 1);
  } else {
    fprintf(f, ".globl %s\n", def.name + 1);
    fprintf(f, "%s:\n", def.name + 1);
  }
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
        if (target_apple) {
          fprintf(f, "  .quad _%s\n", item.val_str + 1);
        } else {
          fprintf(f, "  .quad %s\n", item.val_str + 1);
        }
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
  int original_target = target_os;
  TargetArch original_arch = target_arch;
  target_arch = TargetArch.X86_64;
  
  printf("  Testing TargetOS.sysv...\n");
  target_os = TARGET_OS_SYSV;
  assert(strcmp(get_arg_reg_32(0), "%edi") == 0);
  assert(strcmp(get_arg_reg_32(1), "%esi") == 0);
  assert(strcmp(get_arg_reg_32(2), "%edx") == 0);
  assert(strcmp(get_arg_reg_32(3), "%ecx") == 0);
  assert(strcmp(get_arg_reg_32(4), "%r8d") == 0);
  assert(strcmp(get_arg_reg_32(5), "%r9d") == 0);
  assert(get_arg_reg_32(6) == null);

  assert(strcmp(get_arg_reg_64(0), "%rdi") == 0);
  assert(strcmp(get_arg_reg_64(1), "%rsi") == 0);
  assert(strcmp(get_arg_reg_64(2), "%rdx") == 0);
  assert(strcmp(get_arg_reg_64(3), "%rcx") == 0);
  assert(strcmp(get_arg_reg_64(4), "%r8") == 0);
  assert(strcmp(get_arg_reg_64(5), "%r9") == 0);
  assert(get_arg_reg_64(6) == null);

  assert(strcmp(get_float_arg_reg(0), "%xmm0") == 0);
  assert(strcmp(get_float_arg_reg(7), "%xmm7") == 0);
  assert(get_float_arg_reg(8) == null);

  assert(strcmp(get_param_reg(0, 'w', 0, 0), "%edi") == 0);
  assert(strcmp(get_param_reg(1, 's', 0, 0), "%xmm0") == 0);
  assert(strcmp(get_param_reg(2, 'w', 1, 1), "%esi") == 0);

  printf("  Testing TargetOS.windows...\n");
  target_os = TARGET_OS_WINDOWS;
  assert(strcmp(get_arg_reg_32(0), "%ecx") == 0);
  assert(strcmp(get_arg_reg_32(1), "%edx") == 0);
  assert(strcmp(get_arg_reg_32(2), "%r8d") == 0);
  assert(strcmp(get_arg_reg_32(3), "%r9d") == 0);
  assert(get_arg_reg_32(4) == null);

  assert(strcmp(get_arg_reg_64(0), "%rcx") == 0);
  assert(strcmp(get_arg_reg_64(1), "%rdx") == 0);
  assert(strcmp(get_arg_reg_64(2), "%r8") == 0);
  assert(strcmp(get_arg_reg_64(3), "%r9") == 0);
  assert(get_arg_reg_64(4) == null);

  assert(strcmp(get_float_arg_reg(0), "%xmm0") == 0);
  assert(strcmp(get_float_arg_reg(1), "%xmm1") == 0);
  assert(strcmp(get_float_arg_reg(2), "%xmm2") == 0);
  assert(strcmp(get_float_arg_reg(3), "%xmm3") == 0);
  assert(get_float_arg_reg(4) == null);

  assert(strcmp(get_param_reg(0, 'w', 0, 0), "%ecx") == 0);
  assert(strcmp(get_param_reg(1, 's', 0, 0), "%xmm1") == 0);
  assert(strcmp(get_param_reg(2, 'w', 1, 1), "%r8d") == 0);
  assert(get_param_reg(4, 'w', 2, 1) == null);
  
  target_os = original_target;
  target_arch = original_arch;
}

unittest {
  TargetArch original_arch = target_arch;
  bool original_apple = target_apple;
  target_arch = TargetArch.X86_64;
  target_apple = false;
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
  target_arch = original_arch;
  target_apple = original_apple;
}

unittest {
  TargetArch original_arch = target_arch;
  target_arch = TargetArch.ARM64;
  
  // Test ARM64 register mappings
  assert(strcmp(get_arg_reg_32(0), "w0") == 0);
  assert(strcmp(get_arg_reg_32(7), "w7") == 0);
  assert(get_arg_reg_32(8) == null);

  assert(strcmp(get_arg_reg_64(0), "x0") == 0);
  assert(strcmp(get_arg_reg_64(7), "x7") == 0);
  assert(get_arg_reg_64(8) == null);

  assert(strcmp(get_param_reg(0, 'w', 0, 0), "w0") == 0);
  assert(strcmp(get_param_reg(1, 'l', 1, 0), "x1") == 0);
  assert(strcmp(get_param_reg(2, 's', 1, 0), "s0") == 0);
  assert(strcmp(get_param_reg(3, 'd', 1, 1), "d1") == 0);
  assert(get_param_reg(9, 'w', 8, 1) == null); // Stack argument (spilled)

  target_arch = original_arch;
}
