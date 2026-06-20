module dqbe.codegen;

import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.string;

import dqbe.tokenize;
import dqbe.parse;

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
