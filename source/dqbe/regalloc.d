module dqbe.regalloc;

import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.string;

import dqbe.parse;
import dqbe.tokenize;
import dqbe.codegen;

char* my_strdup(const char* str) {
  if (!str) return null;
  int len = cast(int) strlen(str);
  char* copy = cast(char*) malloc(len + 1);
  strcpy(copy, str);
  return copy;
}

struct BasicBlock {
  char* label;
  int start_inst_idx; // inclusive
  int end_inst_idx;   // exclusive
  
  BasicBlock*[200] predecessors;
  int pred_count;
  BasicBlock*[200] successors;
  int succ_count;
  
  bool[10000] live_in;
  bool[10000] live_out;
  bool[10000] use;
  bool[10000] def;
}

__gshared BasicBlock[1000] blocks;
__gshared int blocks_count = 0;

struct TempInfo {
  char* name;
  char type; // 'w', 'l', 's', 'd'
  
  int start_point;
  int end_point;
  
  int assigned_reg; // -1 if spilled, or index of register
  int spill_offset; // stack offset if spilled
}

__gshared TempInfo[10000] temps;
__gshared int temps_count = 0;

__gshared const(char)*[5] gpr_callee_saved;
__gshared const(char)*[2] gpr_caller_saved;
__gshared const(char)*[6] fpr_caller_saved;
__gshared int phi_tmp_counter = 0;

void init_regalloc() {
  gpr_callee_saved[0] = "%rbx";
  gpr_callee_saved[1] = "%r12";
  gpr_callee_saved[2] = "%r13";
  gpr_callee_saved[3] = "%r14";
  gpr_callee_saved[4] = "%r15";
  
  gpr_caller_saved[0] = "%r10";
  gpr_caller_saved[1] = "%r11";
  
  fpr_caller_saved[0] = "%xmm8";
  fpr_caller_saved[1] = "%xmm9";
  fpr_caller_saved[2] = "%xmm10";
  fpr_caller_saved[3] = "%xmm11";
  fpr_caller_saved[4] = "%xmm12";
  fpr_caller_saved[5] = "%xmm13";
}

int get_temp_idx_no_type(const char* name) {
  return get_temp_idx(name, '0');
}

int get_temp_idx(const char* name, char type) {
  if (!name || name[0] != '%') return -1;
  for (int i = 0; i < temps_count; i++) {
    if (strcmp(temps[i].name, name) == 0) {
      if (type != '0' && temps[i].type == '0') {
        temps[i].type = type;
      }
      return i;
    }
  }
  assert(temps_count < 10000);
  temps[temps_count].name = my_strdup(name);
  temps[temps_count].type = type;
  temps[temps_count].start_point = 999999;
  temps[temps_count].end_point = -1;
  temps[temps_count].assigned_reg = -1;
  temps[temps_count].spill_offset = -1;
  return temps_count++;
}

const(char)* get_allocated_register(const char* name, char type) {
  if (!name || name[0] != '%') return null;
  for (int i = 0; i < temps_count; i++) {
    if (strcmp(temps[i].name, name) == 0) {
      int reg_idx = temps[i].assigned_reg;
      if (reg_idx == -1) return null;
      
      bool is_float = (temps[i].type == 's' || temps[i].type == 'd');
      if (is_float) {
        return fpr_caller_saved[reg_idx];
      } else {
        if (reg_idx < 5) {
          if (type == 'w') {
            if (reg_idx == 0) return "%ebx";
            if (reg_idx == 1) return "%r12d";
            if (reg_idx == 2) return "%r13d";
            if (reg_idx == 3) return "%r14d";
            if (reg_idx == 4) return "%r15d";
          } else {
            return gpr_callee_saved[reg_idx];
          }
        } else {
          if (type == 'w') {
            if (reg_idx == 5) return "%r10d";
            if (reg_idx == 6) return "%r11d";
          } else {
            return gpr_caller_saved[reg_idx - 5];
          }
        }
      }
    }
  }
  return null;
}

void insert_instruction(FunctionDef* fn, int idx, Instruction inst) {
  assert(fn.inst_count < 10000);
  for (int i = fn.inst_count; i > idx; i--) {
    fn.instructions[i] = fn.instructions[i - 1];
  }
  fn.instructions[idx] = inst;
  fn.inst_count++;
}

int find_block_terminator_index(FunctionDef* fn, const char* label_name) {
  for (int i = 0; i < fn.inst_count; i++) {
    if (fn.instructions[i].kind == InstKind.IK_label &&
        strcmp(fn.instructions[i].label, label_name) == 0) {
      for (int j = i + 1; j < fn.inst_count; j++) {
        if (fn.instructions[j].kind == InstKind.IK_label) {
          return j - 1;
        }
      }
      return fn.inst_count - 1;
    }
  }
  return -1;
}

void resolve_phi_nodes(FunctionDef* fn) {
  Instruction[100] phi_instructions;
  int phi_count = 0;
  
  for (int i = 0; i < fn.inst_count; i++) {
    if (fn.instructions[i].kind == InstKind.IK_phi) {
      assert(phi_count < 100);
      phi_instructions[phi_count++] = fn.instructions[i];
      
      for (int j = i; j < fn.inst_count - 1; j++) {
        fn.instructions[j] = fn.instructions[j + 1];
      }
      fn.inst_count--;
      i--;
    }
  }
  
  for (int i = 0; i < phi_count; i++) {
    Instruction* phi = &phi_instructions[i];
    
    for (int j = 0; j < phi.phi_args_count; j++) {
      const char* pred_label = phi.phi_args[j].label;
      const char* pred_val = phi.phi_args[j].value;
      
      char[64] tmp_name;
      sprintf(tmp_name.ptr, "%%phi_t%d", ++phi_tmp_counter);
      char* tmp_name_copy = my_strdup(tmp_name.ptr);
      
      Instruction copy_to_tmp;
      memset(&copy_to_tmp, 0, copy_to_tmp.sizeof);
      copy_to_tmp.kind = InstKind.IK_assign;
      copy_to_tmp.dest = tmp_name_copy;
      copy_to_tmp.dest_type = phi.dest_type;
      copy_to_tmp.op = my_strdup("copy");
      copy_to_tmp.arg1 = my_strdup(pred_val);
      
      Instruction copy_to_dest;
      memset(&copy_to_dest, 0, copy_to_dest.sizeof);
      copy_to_dest.kind = InstKind.IK_assign;
      copy_to_dest.dest = my_strdup(phi.dest);
      copy_to_dest.dest_type = phi.dest_type;
      copy_to_dest.op = my_strdup("copy");
      copy_to_dest.arg1 = tmp_name_copy;
      
      int term_idx = find_block_terminator_index(fn, pred_label);
      if (term_idx != -1) {
        insert_instruction(fn, term_idx, copy_to_dest);
        insert_instruction(fn, term_idx, copy_to_tmp);
      }
    }
  }
}

BasicBlock* find_block_by_label(const char* label) {
  for (int i = 0; i < blocks_count; i++) {
    if (strcmp(blocks[i].label, label) == 0) {
      return &blocks[i];
    }
  }
  return null;
}

void add_successor(BasicBlock* from, BasicBlock* to) {
  for (int i = 0; i < from.succ_count; i++) {
    if (from.successors[i] == to) return;
  }
  assert(from.succ_count < 200);
  from.successors[from.succ_count++] = to;
  
  for (int i = 0; i < to.pred_count; i++) {
    if (to.predecessors[i] == from) return;
  }
  assert(to.pred_count < 200);
  to.predecessors[to.pred_count++] = from;
}

void build_cfg(FunctionDef* fn) {
  blocks_count = 0;
  BasicBlock* current_block = null;
  for (int i = 0; i < fn.inst_count; i++) {
    Instruction* inst = &fn.instructions[i];
    if (inst.kind == InstKind.IK_label) {
      if (current_block) {
        current_block.end_inst_idx = i;
      }
      assert(blocks_count < 1000);
      current_block = &blocks[blocks_count++];
      memset(current_block, 0, current_block.sizeof);
      current_block.label = inst.label;
      current_block.start_inst_idx = i + 1;
    }
  }
  if (current_block) {
    current_block.end_inst_idx = fn.inst_count;
  }
  
  for (int i = 0; i < blocks_count; i++) {
    BasicBlock* b = &blocks[i];
    int term_idx = b.end_inst_idx - 1;
    if (term_idx < b.start_inst_idx) continue;
    
    Instruction* term = &fn.instructions[term_idx];
    if (term.kind == InstKind.IK_jmp) {
      BasicBlock* succ = find_block_by_label(term.label);
      if (succ) add_successor(b, succ);
    } else if (term.kind == InstKind.IK_jnz) {
      BasicBlock* succ1 = find_block_by_label(term.label);
      BasicBlock* succ2 = find_block_by_label(term.label_else);
      if (succ1) add_successor(b, succ1);
      if (succ2) add_successor(b, succ2);
    } else if (term.kind == InstKind.IK_ret) {
      // Exit block
    } else {
      if (i + 1 < blocks_count) {
        add_successor(b, &blocks[i + 1]);
      }
    }
  }
}

void mark_use(FunctionDef* fn, BasicBlock* b, const char* arg, char type) {
  if (!arg || arg[0] != '%') return;
  int idx = get_temp_idx(arg, type);
  if (idx != -1) {
    if (!b.def[idx]) {
      b.use[idx] = true;
    }
  }
}

void mark_use_no_type(FunctionDef* fn, BasicBlock* b, const char* arg) {
  mark_use(fn, b, arg, '0');
}

void mark_def(FunctionDef* fn, BasicBlock* b, const char* dest, char type) {
  if (!dest || dest[0] != '%') return;
  int idx = get_temp_idx(dest, type);
  if (idx != -1) {
    if (!b.use[idx]) {
      b.def[idx] = true;
    }
  }
}

void compute_block_use_def(FunctionDef* fn, BasicBlock* b) {
  memset(b.use.ptr, 0, b.use.sizeof);
  memset(b.def.ptr, 0, b.def.sizeof);
  
  for (int i = b.start_inst_idx; i < b.end_inst_idx; i++) {
    Instruction* inst = &fn.instructions[i];
    
    if (inst.kind == InstKind.IK_assign) {
      if (strcmp(inst.op, "call") == 0) {
        for (int j = 0; j < inst.call_args_count; j++) {
          mark_use(fn, b, inst.call_args[j].name, inst.call_args[j].type);
        }
      } else {
        mark_use_no_type(fn, b, inst.arg1);
        mark_use_no_type(fn, b, inst.arg2);
      }
      mark_def(fn, b, inst.dest, inst.dest_type);
    } else if (inst.kind == InstKind.IK_store) {
      mark_use_no_type(fn, b, inst.arg1);
      mark_use_no_type(fn, b, inst.arg2);
    } else if (inst.kind == InstKind.IK_jnz) {
      mark_use_no_type(fn, b, inst.arg1);
    } else if (inst.kind == InstKind.IK_ret) {
      mark_use_no_type(fn, b, inst.arg1);
    } else if (inst.kind == InstKind.IK_call) {
      for (int j = 0; j < inst.call_args_count; j++) {
        mark_use(fn, b, inst.call_args[j].name, inst.call_args[j].type);
      }
    }
  }
}

void run_liveness_analysis(FunctionDef* fn) {
  for (int i = 0; i < blocks_count; i++) {
    compute_block_use_def(fn, &blocks[i]);
    memset(blocks[i].live_in.ptr, 0, blocks[i].live_in.sizeof);
    memset(blocks[i].live_out.ptr, 0, blocks[i].live_out.sizeof);
  }
  
  bool changed = true;
  while (changed) {
    changed = false;
    for (int i = blocks_count - 1; i >= 0; i--) {
      BasicBlock* b = &blocks[i];
      
      bool[10000] new_live_out;
      memset(new_live_out.ptr, 0, new_live_out.sizeof);
      for (int j = 0; j < b.succ_count; j++) {
        BasicBlock* succ = b.successors[j];
        for (int k = 0; k < temps_count; k++) {
          if (succ.live_in[k]) {
            new_live_out[k] = true;
          }
        }
      }
      
      bool[10000] new_live_in;
      for (int k = 0; k < temps_count; k++) {
        new_live_in[k] = b.use[k] || (new_live_out[k] && !b.def[k]);
      }
      
      for (int k = 0; k < temps_count; k++) {
        if (new_live_in[k] != b.live_in[k] || new_live_out[k] != b.live_out[k]) {
          changed = true;
          b.live_in[k] = new_live_in[k];
          b.live_out[k] = new_live_out[k];
        }
      }
    }
  }
}

bool spans_call(FunctionDef* fn, TempInfo* t) {
  for (int i = t.start_point; i <= t.end_point; i++) {
    Instruction* inst = &fn.instructions[i];
    if (inst.kind == InstKind.IK_call ||
        (inst.kind == InstKind.IK_assign && strcmp(inst.op, "call") == 0)) {
      return true;
    }
  }
  return false;
}

void update_range(const char* arg, int idx) {
  if (!arg || arg[0] != '%') return;
  int t_idx = get_temp_idx_no_type(arg);
  if (t_idx != -1) {
    if (idx < temps[t_idx].start_point) {
      temps[t_idx].start_point = idx;
    }
    if (idx > temps[t_idx].end_point) {
      temps[t_idx].end_point = idx;
    }
  }
}

void build_live_intervals(FunctionDef* fn) {
  for (int i = 0; i < temps_count; i++) {
    temps[i].start_point = 999999;
    temps[i].end_point = -1;
  }
  
  for (int i = 0; i < fn.inst_count; i++) {
    Instruction* inst = &fn.instructions[i];
    
    if (inst.kind == InstKind.IK_assign) {
      update_range(inst.dest, i);
      if (strcmp(inst.op, "call") == 0) {
        for (int j = 0; j < inst.call_args_count; j++) {
          update_range(inst.call_args[j].name, i);
        }
      } else {
        update_range(inst.arg1, i);
        update_range(inst.arg2, i);
      }
    } else if (inst.kind == InstKind.IK_store) {
      update_range(inst.arg1, i);
      update_range(inst.arg2, i);
    } else if (inst.kind == InstKind.IK_jnz) {
      update_range(inst.arg1, i);
    } else if (inst.kind == InstKind.IK_ret) {
      update_range(inst.arg1, i);
    } else if (inst.kind == InstKind.IK_call) {
      for (int j = 0; j < inst.call_args_count; j++) {
        update_range(inst.call_args[j].name, i);
      }
    }
  }
  
  for (int i = 0; i < blocks_count; i++) {
    BasicBlock* b = &blocks[i];
    int start = b.start_inst_idx;
    int end = b.end_inst_idx - 1;
    
    for (int k = 0; k < temps_count; k++) {
      if (b.live_in[k] || b.live_out[k]) {
        if (start < temps[k].start_point) {
          temps[k].start_point = start;
        }
        if (end > temps[k].end_point) {
          temps[k].end_point = end;
        }
      }
    }
  }
}

struct ActiveInterval {
  int temp_idx;
  int end_point;
}

void linear_scan_reg_alloc(FunctionDef* fn) {
  int[10000] sorted_temps;
  int sorted_count = 0;
  for (int i = 0; i < temps_count; i++) {
    if (temps[i].start_point <= temps[i].end_point) {
      sorted_temps[sorted_count++] = i;
    }
  }
  
  for (int i = 0; i < sorted_count; i++) {
    for (int j = i + 1; j < sorted_count; j++) {
      if (temps[sorted_temps[i]].start_point > temps[sorted_temps[j]].start_point) {
        int tmp = sorted_temps[i];
        sorted_temps[i] = sorted_temps[j];
        sorted_temps[j] = tmp;
      }
    }
  }
  
  bool[5] gpr_callee_occupied;
  bool[2] gpr_caller_occupied;
  bool[6] fpr_occupied;
  
  for (int r = 0; r < 5; r++) gpr_callee_occupied[r] = false;
  for (int r = 0; r < 2; r++) gpr_caller_occupied[r] = false;
  for (int r = 0; r < 6; r++) fpr_occupied[r] = false;
  
  ActiveInterval[32] active;
  int active_count = 0;
  
  int next_spill_offset = 48;
  
  for (int i = 0; i < sorted_count; i++) {
    int t_idx = sorted_temps[i];
    TempInfo* t = &temps[t_idx];
    
    for (int j = 0; j < active_count; j++) {
      int active_t_idx = active[j].temp_idx;
      if (temps[active_t_idx].end_point < t.start_point) {
        int reg_idx = temps[active_t_idx].assigned_reg;
        if (reg_idx != -1) {
          char r_type = temps[active_t_idx].type;
          if (r_type == 's' || r_type == 'd') {
            fpr_occupied[reg_idx] = false;
          } else {
            if (reg_idx < 5) {
              gpr_callee_occupied[reg_idx] = false;
            } else {
              gpr_caller_occupied[reg_idx - 5] = false;
            }
          }
        }
        for (int k = j; k < active_count - 1; k++) {
          active[k] = active[k + 1];
        }
        active_count--;
        j--;
      }
    }
    
    bool is_float = (t.type == 's' || t.type == 'd');
    bool has_call = spans_call(fn, t);
    
    int assigned = -1;
    
    if (is_float) {
      if (has_call) {
        assigned = -1;
      } else {
        for (int r = 0; r < 6; r++) {
          if (!fpr_occupied[r]) {
            fpr_occupied[r] = true;
            assigned = r;
            break;
          }
        }
      }
    } else {
      if (has_call) {
        for (int r = 0; r < 5; r++) {
          if (!gpr_callee_occupied[r]) {
            gpr_callee_occupied[r] = true;
            assigned = r;
            break;
          }
        }
      } else {
        for (int r = 0; r < 5; r++) {
          if (!gpr_callee_occupied[r]) {
            gpr_callee_occupied[r] = true;
            assigned = r;
            break;
          }
        }
        if (assigned == -1) {
          for (int r = 0; r < 2; r++) {
            if (!gpr_caller_occupied[r]) {
              gpr_caller_occupied[r] = true;
              assigned = r + 5;
              break;
            }
          }
        }
      }
    }
    
    if (assigned != -1) {
      t.assigned_reg = assigned;
      assert(active_count < 32);
      active[active_count].temp_idx = t_idx;
      active[active_count].end_point = t.end_point;
      active_count++;
    } else {
      t.assigned_reg = -1;
      t.spill_offset = next_spill_offset;
      next_spill_offset += 8;
    }
  }
  
  stack_offset_counter = next_spill_offset;
}

void sync_spill_offsets() {
  temp_offsets_count = 0;
  for (int i = 0; i < temps_count; i++) {
    if (temps[i].assigned_reg == -1 && temps[i].spill_offset != -1) {
      temp_offsets[temp_offsets_count].name = temps[i].name;
      temp_offsets[temp_offsets_count].offset = temps[i].spill_offset;
      temp_offsets_count++;
    }
  }
}

void perform_register_allocation(FunctionDef* fn) {
  temps_count = 0;
  resolve_phi_nodes(fn);
  build_cfg(fn);
  run_liveness_analysis(fn);
  build_live_intervals(fn);
  linear_scan_reg_alloc(fn);
  sync_spill_offsets();
}
