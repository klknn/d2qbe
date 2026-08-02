module dqbe.wasm;

import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.string;

import dqbe.parse;
import dqbe.tokenize;

enum ubyte WASM_I32 = 0x7f;
enum ubyte WASM_FUNC = 0x60;
enum ubyte WASM_END = 0x0b;
enum ubyte WASM_RETURN = 0x0f;
enum ubyte WASM_CALL = 0x10;
enum ubyte WASM_LOCAL_GET = 0x20;
enum ubyte WASM_LOCAL_SET = 0x21;
enum ubyte WASM_I32_CONST = 0x41;
enum ubyte WASM_GLOBAL_GET = 0x23;
enum ubyte WASM_GLOBAL_SET = 0x24;
enum ubyte WASM_I32_LOAD = 0x28;
enum ubyte WASM_I32_LOAD8_U = 0x2d;
enum ubyte WASM_I32_STORE = 0x36;
enum ubyte WASM_UNREACHABLE = 0x00;
enum ubyte WASM_LOOP = 0x03;
enum ubyte WASM_IF = 0x04;
enum ubyte WASM_ELSE = 0x05;
enum ubyte WASM_BR = 0x0c;
enum ubyte WASM_EMPTY_BLOCK = 0x40;

struct ByteBuffer {
  ubyte* data;
  int length;
  int capacity;
}

void wasm_error(const char* message) {
  fprintf(stderr, "wasm backend: %s\n", message);
}

bool reserve(ref ByteBuffer buffer, int extra) {
  if (extra < 0 || buffer.length > int.max - extra) {
    wasm_error("binary output is too large");
    return false;
  }
  int required = buffer.length + extra;
  if (required <= buffer.capacity) return true;

  int capacity = buffer.capacity == 0 ? 256 : buffer.capacity;
  while (capacity < required) {
    if (capacity > int.max / 2) {
      capacity = required;
      break;
    }
    capacity *= 2;
  }

  void* replacement = realloc(buffer.data, capacity);
  if (!replacement) {
    wasm_error("out of memory while writing module");
    return false;
  }
  buffer.data = cast(ubyte*) replacement;
  buffer.capacity = capacity;
  return true;
}

bool append_byte(ref ByteBuffer buffer, ubyte value) {
  if (!reserve(buffer, 1)) return false;
  buffer.data[buffer.length++] = value;
  return true;
}

bool append_bytes(ref ByteBuffer buffer, const(ubyte)* data, int length) {
  if (!reserve(buffer, length)) return false;
  memcpy(buffer.data + buffer.length, data, length);
  buffer.length += length;
  return true;
}

bool append_u32(ref ByteBuffer buffer, uint value) {
  do {
    ubyte encoded = cast(ubyte) (value & 0x7f);
    value >>= 7;
    if (value != 0) encoded |= 0x80;
    if (!append_byte(buffer, encoded)) return false;
  } while (value != 0);
  return true;
}

bool append_i32(ref ByteBuffer buffer, int value) {
  bool done = false;
  while (!done) {
    ubyte encoded = cast(ubyte) (value & 0x7f);
    value >>= 7;
    done = (value == 0 && (encoded & 0x40) == 0) ||
      (value == -1 && (encoded & 0x40) != 0);
    if (!done) encoded |= 0x80;
    if (!append_byte(buffer, encoded)) return false;
  }
  return true;
}

bool append_name(ref ByteBuffer buffer, const(char)* name) {
  int length = cast(int) strlen(name);
  if (!append_u32(buffer, cast(uint) length)) return false;
  return append_bytes(buffer, cast(const(ubyte)*) name, length);
}

bool append_section(ref ByteBuffer binary, ubyte id, ref ByteBuffer payload) {
  return append_byte(binary, id) && append_u32(binary, cast(uint) payload.length) &&
    append_bytes(binary, payload.data, payload.length);
}

void dispose(ref ByteBuffer buffer) {
  free(buffer.data);
  buffer.data = null;
  buffer.length = 0;
  buffer.capacity = 0;
}

bool supported_function(FunctionDef* fn) {
  if (fn.ret_type != 'w' && fn.ret_type != '0') {
    wasm_error("M1 supports only w or void function results");
    return false;
  }
  for (int i = 0; i < fn.params_count; i++) {
    if (fn.params[i].type != 'w') {
      wasm_error("M1 supports only w function parameters");
      return false;
    }
  }
  return true;
}

int find_function(const char* name) {
  for (int i = 0; i < program_functions_count; i++) {
    if (strcmp(program_functions[i].name, name) == 0) return i;
  }
  return -1;
}

int local_index(FunctionDef* fn, const char* name) {
  for (int i = 0; i < fn.params_count; i++) {
    if (strcmp(fn.params[i].name, name) == 0) return i;
  }

  int next_index = fn.params_count;
  for (int i = 0; i < fn.inst_count; i++) {
    Instruction* inst = &fn.instructions[i];
    if (inst.kind == InstKind.IK_assign) {
      if (strcmp(inst.dest, name) == 0) return next_index;
      next_index++;
    }
  }
  return -1;
}

int local_count(FunctionDef* fn) {
  int count = 0;
  for (int i = 0; i < fn.inst_count; i++) {
    if (fn.instructions[i].kind == InstKind.IK_assign) count++;
  }
  return count;
}

bool append_data_item(ref ByteBuffer bytes, DataItem* item) {
  if (item.type == 'b') {
    if (item.val_str[0] != '"') {
      return append_byte(bytes, cast(ubyte) strtol(item.val_str, null, 10));
    }
    int length = cast(int) strlen(item.val_str);
    if (length < 2 || item.val_str[length - 1] != '"') {
      wasm_error("unterminated data string");
      return false;
    }
    for (int i = 1; i < length - 1; i++) {
      char value = item.val_str[i];
      if (value == '\\') {
        i++;
        if (i >= length - 1) {
          wasm_error("invalid data string escape");
          return false;
        }
        char escaped = item.val_str[i];
        if (escaped == 'n') value = '\n';
        else if (escaped == 'r') value = '\r';
        else if (escaped == 't') value = '\t';
        else if (escaped == '0') value = 0;
        else if (escaped == '\\' || escaped == '"') value = escaped;
        else {
          wasm_error("unsupported data string escape");
          return false;
        }
      }
      if (!append_byte(bytes, cast(ubyte) value)) return false;
    }
    return true;
  }
  if (item.type == 'z') {
    int count = cast(int) strtol(item.val_str, null, 10);
    if (count < 0) {
      wasm_error("data zero fill must be non-negative");
      return false;
    }
    for (int i = 0; i < count; i++) if (!append_byte(bytes, 0)) return false;
    return true;
  }
  if (item.type == 'w') {
    uint value = cast(uint) strtol(item.val_str, null, 10);
    for (int i = 0; i < 4; i++) {
      if (!append_byte(bytes, cast(ubyte) (value >> (i * 8)))) return false;
    }
    return true;
  }
  wasm_error("wasm data supports only b, w, and z items");
  return false;
}

bool append_data_definition(ref ByteBuffer bytes, DataDef* definition) {
  for (int i = 0; i < definition.items_count; i++) {
    if (!append_data_item(bytes, &definition.items[i])) return false;
  }
  return true;
}

int static_data_size() {
  ByteBuffer bytes;
  for (int i = 0; i < program_data_count; i++) {
    if (!append_data_definition(bytes, &program_data[i])) {
      dispose(bytes);
      return -1;
    }
  }
  int size = bytes.length;
  dispose(bytes);
  return size;
}

bool find_data_offset(const char* name, ref int offset) {
  int current_offset = 0;
  for (int i = 0; i < program_data_count; i++) {
    if (strcmp(program_data[i].name, name) == 0) {
      offset = current_offset;
      return true;
    }
    ByteBuffer bytes;
    if (!append_data_definition(bytes, &program_data[i])) {
      dispose(bytes);
      return false;
    }
    current_offset += bytes.length;
    dispose(bytes);
  }
  return false;
}

bool append_value(ref ByteBuffer body, FunctionDef* fn, const char* value) {
  if (value[0] == '%') {
    int index = local_index(fn, value);
    if (index < 0) {
      wasm_error("temporary has no local slot");
      return false;
    }
    return append_byte(body, WASM_LOCAL_GET) && append_u32(body, cast(uint) index);
  }
  if (value[0] == '$') {
    int offset;
    if (!find_data_offset(value, offset)) {
      wasm_error("global is undefined or has unsupported data");
      return false;
    }
    return append_byte(body, WASM_I32_CONST) && append_i32(body, offset);
  }
  return append_byte(body, WASM_I32_CONST) && append_i32(body, cast(int) strtol(value, null, 10));
}

ubyte binary_opcode(const char* op) {
  if (strcmp(op, "add") == 0) return 0x6a;
  if (strcmp(op, "sub") == 0) return 0x6b;
  if (strcmp(op, "mul") == 0) return 0x6c;
  if (strcmp(op, "div") == 0) return 0x6d;
  if (strcmp(op, "rem") == 0) return 0x6f;
  if (strcmp(op, "and") == 0) return 0x71;
  if (strcmp(op, "or") == 0) return 0x72;
  if (strcmp(op, "xor") == 0) return 0x73;
  if (strcmp(op, "shl") == 0) return 0x74;
  if (strcmp(op, "sar") == 0) return 0x75;
  if (strcmp(op, "shr") == 0) return 0x76;
  if (strcmp(op, "ceqw") == 0) return 0x46;
  if (strcmp(op, "cnew") == 0) return 0x47;
  if (strcmp(op, "csltw") == 0) return 0x48;
  if (strcmp(op, "csgtw") == 0) return 0x4a;
  if (strcmp(op, "cslew") == 0) return 0x4c;
  if (strcmp(op, "csgew") == 0) return 0x4e;
  return 0;
}

bool append_assign(ref ByteBuffer body, FunctionDef* fn, Instruction* inst) {
  if (inst.dest_type != 'w') {
    wasm_error("M1 supports only w assignment results");
    return false;
  }

  if (strcmp(inst.op, "copy") == 0) {
    if (!append_value(body, fn, inst.arg1)) return false;
  } else if (strncmp(inst.op, "alloc", 5) == 0) {
    int alignment = 0;
    if (strcmp(inst.op, "alloc4") == 0) alignment = 4;
    else if (strcmp(inst.op, "alloc8") == 0) alignment = 8;
    else {
      wasm_error("unsupported allocation alignment");
      return false;
    }
    int size = cast(int) strtol(inst.arg1, null, 10);
    if (size < 0) {
      wasm_error("allocation size must be non-negative");
      return false;
    }
    if (!append_byte(body, WASM_GLOBAL_GET) || !append_u32(body, 0) ||
        !append_byte(body, WASM_I32_CONST) || !append_i32(body, alignment - 1) ||
        !append_byte(body, 0x6a) || !append_byte(body, WASM_I32_CONST) ||
        !append_i32(body, -alignment) || !append_byte(body, 0x71)) return false;

    int destination = local_index(fn, inst.dest);
    if (destination < 0 || !append_byte(body, WASM_LOCAL_SET) ||
        !append_u32(body, cast(uint) destination) || !append_byte(body, WASM_LOCAL_GET) ||
        !append_u32(body, cast(uint) destination) || !append_byte(body, WASM_I32_CONST) ||
        !append_i32(body, size) || !append_byte(body, 0x6a) ||
        !append_byte(body, WASM_GLOBAL_SET) || !append_u32(body, 0)) return false;
    return true;
  } else if (strcmp(inst.op, "loadw") == 0) {
    if (!append_value(body, fn, inst.arg1) || !append_byte(body, WASM_I32_LOAD) ||
        !append_u32(body, 2) || !append_u32(body, 0)) return false;
  } else if (strcmp(inst.op, "loadub") == 0) {
    if (!append_value(body, fn, inst.arg1) || !append_byte(body, WASM_I32_LOAD8_U) ||
        !append_u32(body, 0) || !append_u32(body, 0)) return false;
  } else if (strcmp(inst.op, "call") == 0) {
    int target = find_function(inst.arg1);
    if (target < 0) {
      wasm_error("call target is undefined");
      return false;
    }
    for (int i = 0; i < inst.call_args_count; i++) {
      if (inst.call_args[i].type != 'w' || !append_value(body, fn, inst.call_args[i].name)) {
        wasm_error("M1 supports only w call arguments");
        return false;
      }
    }
    if (!append_byte(body, WASM_CALL) || !append_u32(body, cast(uint) target)) return false;
  } else {
    ubyte opcode = binary_opcode(inst.op);
    if (opcode == 0) {
      wasm_error("unsupported assignment operation in wasm M1");
      return false;
    }
    if (!append_value(body, fn, inst.arg1) || !append_value(body, fn, inst.arg2) ||
        !append_byte(body, opcode)) return false;
  }

  int destination = local_index(fn, inst.dest);
  return destination >= 0 && append_byte(body, WASM_LOCAL_SET) &&
    append_u32(body, cast(uint) destination);
}

bool append_store(ref ByteBuffer body, FunctionDef* fn, Instruction* inst) {
  if (strcmp(inst.op, "storew") != 0) {
    wasm_error("only storew is supported by wasm memory M2");
    return false;
  }
  return append_value(body, fn, inst.arg2) && append_value(body, fn, inst.arg1) &&
    append_byte(body, WASM_I32_STORE) && append_u32(body, 2) && append_u32(body, 0);
}

bool program_uses_memory() {
  if (program_data_count != 0) return true;
  for (int i = 0; i < program_functions_count; i++) {
    FunctionDef* fn = &program_functions[i];
    for (int j = 0; j < fn.inst_count; j++) {
      Instruction* inst = &fn.instructions[j];
      if (inst.kind == InstKind.IK_store ||
          (inst.kind == InstKind.IK_assign &&
           (strcmp(inst.op, "loadw") == 0 || strcmp(inst.op, "loadub") == 0 ||
            strncmp(inst.op, "alloc", 5) == 0))) {
        return true;
      }
    }
  }
  return false;
}

struct WasmBlock {
  char* label;
  int start;
  int end;
}

bool append_return(ref ByteBuffer body, FunctionDef* fn, Instruction* inst) {
  if (fn.ret_type == 'w') {
    if (!inst.arg1 || !append_value(body, fn, inst.arg1)) return false;
  } else if (inst.arg1) {
    wasm_error("void function cannot return a value");
    return false;
  }
  return append_byte(body, WASM_RETURN);
}

bool append_next_block(ref ByteBuffer body, int program_counter, int block) {
  return append_byte(body, WASM_I32_CONST) && append_i32(body, block) &&
    append_byte(body, WASM_LOCAL_SET) && append_u32(body, cast(uint) program_counter) &&
    append_byte(body, WASM_BR) && append_u32(body, 1);
}

int find_block(WasmBlock[10000]* blocks, int block_count, const(char)* label) {
  for (int i = 0; i < block_count; i++) {
    if (strcmp(blocks[0][i].label, label) == 0) return i;
  }
  return -1;
}

bool append_dispatcher_body(ref ByteBuffer body, FunctionDef* fn, int program_counter) {
  WasmBlock[10000] blocks;
  int block_count = 0;
  for (int i = 0; i < fn.inst_count; i++) {
    Instruction* inst = &fn.instructions[i];
    if (inst.kind != InstKind.IK_label) continue;
    if (block_count == blocks.length) {
      wasm_error("too many basic blocks");
      return false;
    }
    if (block_count != 0) blocks[block_count - 1].end = i;
    blocks[block_count].label = inst.label;
    blocks[block_count].start = i + 1;
    block_count++;
  }
  if (block_count == 0 || blocks[0].start != 1) {
    wasm_error("control-flow function must begin with a label");
    return false;
  }
  blocks[block_count - 1].end = fn.inst_count;

  if (!append_byte(body, WASM_I32_CONST) || !append_i32(body, 0) ||
      !append_byte(body, WASM_LOCAL_SET) ||
      !append_u32(body, cast(uint) program_counter) ||
      !append_byte(body, WASM_LOOP) || !append_byte(body, WASM_EMPTY_BLOCK)) {
    return false;
  }

  for (int block = 0; block < block_count; block++) {
    if (!append_byte(body, WASM_LOCAL_GET) ||
        !append_u32(body, cast(uint) program_counter) ||
        !append_byte(body, WASM_I32_CONST) || !append_i32(body, block) ||
        !append_byte(body, 0x46) || !append_byte(body, WASM_IF) ||
        !append_byte(body, WASM_EMPTY_BLOCK)) {
      return false;
    }

    bool terminates = false;
    for (int i = blocks[block].start; i < blocks[block].end; i++) {
      Instruction* inst = &fn.instructions[i];
      if (inst.kind == InstKind.IK_assign) {
        if (!append_assign(body, fn, inst)) return false;
        continue;
      }
      if (inst.kind == InstKind.IK_store) {
        if (!append_store(body, fn, inst)) return false;
        continue;
      }
      if (inst.kind == InstKind.IK_ret) {
        if (!append_return(body, fn, inst)) return false;
        terminates = true;
        continue;
      }
      if (inst.kind == InstKind.IK_jmp) {
        int target = find_block(&blocks, block_count, inst.label);
        if (target < 0) {
          wasm_error("jump target is undefined");
          return false;
        }
        if (!append_next_block(body, program_counter, target)) return false;
        terminates = true;
        continue;
      }
      if (inst.kind == InstKind.IK_jnz) {
        int then_target = find_block(&blocks, block_count, inst.label);
        int else_target = find_block(&blocks, block_count, inst.label_else);
        if (then_target < 0 || else_target < 0) {
          wasm_error("conditional jump target is undefined");
          return false;
        }
        if (!append_value(body, fn, inst.arg1) || !append_byte(body, WASM_IF) ||
            !append_byte(body, WASM_EMPTY_BLOCK) ||
            !append_byte(body, WASM_I32_CONST) || !append_i32(body, then_target) ||
            !append_byte(body, WASM_LOCAL_SET) ||
            !append_u32(body, cast(uint) program_counter) ||
            !append_byte(body, WASM_ELSE) ||
            !append_byte(body, WASM_I32_CONST) || !append_i32(body, else_target) ||
            !append_byte(body, WASM_LOCAL_SET) ||
            !append_u32(body, cast(uint) program_counter) ||
            !append_byte(body, WASM_END) || !append_byte(body, WASM_BR) ||
            !append_u32(body, 1)) {
          return false;
        }
        terminates = true;
        continue;
      }
      wasm_error("unsupported instruction in wasm control-flow lowering");
      return false;
    }

    if (!terminates) {
      if (block + 1 == block_count) {
        wasm_error("last basic block has no terminator");
        return false;
      }
      if (!append_next_block(body, program_counter, block + 1)) return false;
    }
    if (!append_byte(body, WASM_END)) return false;
  }

  return append_byte(body, WASM_UNREACHABLE) && append_byte(body, WASM_END);
}

bool needs_dispatcher(FunctionDef* fn) {
  for (int i = 0; i < fn.inst_count; i++) {
    InstKind kind = fn.instructions[i].kind;
    if (kind == InstKind.IK_jmp || kind == InstKind.IK_jnz) return true;
  }
  int labels = 0;
  for (int i = 0; i < fn.inst_count; i++) {
    if (fn.instructions[i].kind == InstKind.IK_label) labels++;
  }
  return labels > 1;
}

bool append_function_body(ref ByteBuffer code, FunctionDef* fn) {
  ByteBuffer body;
  bool dispatcher = needs_dispatcher(fn);
  int locals = local_count(fn) + (dispatcher ? 1 : 0);
  if (!append_u32(body, cast(uint) locals)) return false;
  for (int i = 0; i < locals; i++) {
    if (!append_u32(body, 1) || !append_byte(body, WASM_I32)) {
      dispose(body);
      return false;
    }
  }

  if (dispatcher) {
    if (!append_dispatcher_body(body, fn, fn.params_count + local_count(fn))) {
      dispose(body);
      return false;
    }
    if (!append_byte(body, WASM_END) || !append_u32(code, cast(uint) body.length) ||
        !append_bytes(code, body.data, body.length)) {
      dispose(body);
      return false;
    }
    dispose(body);
    return true;
  }

  bool has_return = false;
  for (int i = 0; i < fn.inst_count; i++) {
    Instruction* inst = &fn.instructions[i];
    if (inst.kind == InstKind.IK_label) {
      if (i != 0) {
        wasm_error("multiple basic blocks are not supported in wasm M1");
        dispose(body);
        return false;
      }
      continue;
    }
    if (inst.kind == InstKind.IK_assign) {
      if (!append_assign(body, fn, inst)) {
        dispose(body);
        return false;
      }
      continue;
    }
    if (inst.kind == InstKind.IK_store) {
      if (!append_store(body, fn, inst)) {
        dispose(body);
        return false;
      }
      continue;
    }
    if (inst.kind == InstKind.IK_ret) {
      if (!append_return(body, fn, inst)) {
        dispose(body);
        return false;
      }
      has_return = true;
      continue;
    }
    wasm_error("unsupported control flow or instruction in wasm M1");
    dispose(body);
    return false;
  }

  if (!has_return) {
    wasm_error("function has no return");
    dispose(body);
    return false;
  }
  if (!append_byte(body, WASM_END) || !append_u32(code, cast(uint) body.length) ||
      !append_bytes(code, body.data, body.length)) {
    dispose(body);
    return false;
  }
  dispose(body);
  return true;
}

bool emit_wasm_program(FILE* output) {
  if (program_functions_count == 0) {
    wasm_error("program contains no functions");
    return false;
  }
  int data_size = static_data_size();
  if (data_size < 0) return false;
  for (int i = 0; i < program_functions_count; i++) {
    if (!supported_function(&program_functions[i])) return false;
  }

  ByteBuffer binary;
  const(ubyte)[8] header = [0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00];
  if (!append_bytes(binary, &header[0], header.length)) {
    dispose(binary);
    return false;
  }

  ByteBuffer types;
  bool ok = append_u32(types, cast(uint) program_functions_count);
  for (int i = 0; ok && i < program_functions_count; i++) {
    FunctionDef* fn = &program_functions[i];
    ok = append_byte(types, WASM_FUNC) && append_u32(types, cast(uint) fn.params_count);
    for (int j = 0; ok && j < fn.params_count; j++) ok = append_byte(types, WASM_I32);
    ok = ok && append_u32(types, fn.ret_type == 'w' ? 1 : 0);
    if (fn.ret_type == 'w') ok = ok && append_byte(types, WASM_I32);
  }
  ok = ok && append_section(binary, 1, types);
  dispose(types);

  ByteBuffer functions;
  ok = ok && append_u32(functions, cast(uint) program_functions_count);
  for (int i = 0; ok && i < program_functions_count; i++) ok = append_u32(functions, cast(uint) i);
  ok = ok && append_section(binary, 3, functions);
  dispose(functions);

  bool has_memory = program_uses_memory();
  if (has_memory) {
    ByteBuffer memory;
    uint pages = cast(uint) ((data_size + 65535) / 65536);
    if (pages == 0) pages = 1;
    ok = ok && append_u32(memory, 1) && append_byte(memory, 0) && append_u32(memory, pages);
    ok = ok && append_section(binary, 5, memory);
    dispose(memory);

    ByteBuffer globals;
    ok = ok && append_u32(globals, 1) && append_byte(globals, WASM_I32) &&
      append_byte(globals, 1) && append_byte(globals, WASM_I32_CONST) &&
      append_i32(globals, data_size) && append_byte(globals, WASM_END);
    ok = ok && append_section(binary, 6, globals);
    dispose(globals);
  }

  int exports = has_memory ? 1 : 0;
  for (int i = 0; i < program_functions_count; i++) if (program_functions[i].is_export) exports++;
  ByteBuffer export_section;
  ok = ok && append_u32(export_section, cast(uint) exports);
  for (int i = 0; ok && i < program_functions_count; i++) {
    FunctionDef* fn = &program_functions[i];
    if (!fn.is_export) continue;
    ok = append_name(export_section, fn.name + 1) && append_byte(export_section, 0) &&
      append_u32(export_section, cast(uint) i);
  }
  if (has_memory) {
    ok = ok && append_name(export_section, "memory") && append_byte(export_section, 2) &&
      append_u32(export_section, 0);
  }
  ok = ok && append_section(binary, 7, export_section);
  dispose(export_section);

  ByteBuffer code;
  ok = ok && append_u32(code, cast(uint) program_functions_count);
  for (int i = 0; ok && i < program_functions_count; i++) {
    ok = append_function_body(code, &program_functions[i]);
  }
  ok = ok && append_section(binary, 10, code);
  dispose(code);

  if (program_data_count != 0) {
    ByteBuffer data;
    ok = ok && append_u32(data, cast(uint) program_data_count);
    int offset = 0;
    for (int i = 0; ok && i < program_data_count; i++) {
      ByteBuffer bytes;
      ok = append_data_definition(bytes, &program_data[i]);
      ok = ok && append_byte(data, 0) && append_byte(data, WASM_I32_CONST) &&
        append_i32(data, offset) && append_byte(data, WASM_END) &&
        append_u32(data, cast(uint) bytes.length) && append_bytes(data, bytes.data, bytes.length);
      offset += bytes.length;
      dispose(bytes);
    }
    ok = ok && append_section(binary, 11, data);
    dispose(data);
  }

  if (ok && fwrite(binary.data, 1, binary.length, output) != binary.length) {
    wasm_error("failed to write module");
    ok = false;
  }
  dispose(binary);
  return ok;
}

unittest {
  char* input = cast(char*) "export function w $main() {\n@start\nret 42\n}\n";
  token = tokenize(input);
  parse_program();

  FILE* output = fopen("tmp_wasm_test.wasm", "wb");
  assert(output != null);
  assert(emit_wasm_program(output));
  fclose(output);

  output = fopen("tmp_wasm_test.wasm", "rb");
  assert(output != null);
  ubyte[38] binary;
  assert(fread(&binary[0], 1, binary.length, output) == binary.length);
  fclose(output);
  remove("tmp_wasm_test.wasm");

  const(ubyte)[38] expected = [
    0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
    0x01, 0x05, 0x01, 0x60, 0x00, 0x01, 0x7f,
    0x03, 0x02, 0x01, 0x00,
    0x07, 0x08, 0x01, 0x04, 'm', 'a', 'i', 'n', 0x00, 0x00,
    0x0a, 0x07, 0x01, 0x05, 0x00, 0x41, 0x2a, 0x0f, 0x0b,
  ];
  assert(binary == expected);
}

unittest {
  char* input = cast(char*) "export function w $main(w %condition) {\n@start\njnz %condition, @then, @else\n@then\nret 42\n@else\nret 7\n}\n";
  token = tokenize(input);
  parse_program();

  FILE* output = fopen("tmp_wasm_control_test.wasm", "wb");
  assert(output != null);
  assert(emit_wasm_program(output));
  fclose(output);
  remove("tmp_wasm_control_test.wasm");
}

unittest {
  char* input = cast(char*) "export function w $main() {\n@start\n%addr =w copy 0\nstorew 42, %addr\n%value =w loadw %addr\nret %value\n}\n";
  token = tokenize(input);
  parse_program();

  FILE* output = fopen("tmp_wasm_memory_test.wasm", "wb");
  assert(output != null);
  assert(emit_wasm_program(output));
  fclose(output);
  remove("tmp_wasm_memory_test.wasm");
}

unittest {
  char* input = cast(char*) "data $answer = { b 42 }\nexport function w $main() {\n@start\n%address =w copy $answer\nret %address\n}\n";
  token = tokenize(input);
  parse_program();

  FILE* output = fopen("tmp_wasm_data_test.wasm", "wb");
  assert(output != null);
  assert(emit_wasm_program(output));
  fclose(output);
  remove("tmp_wasm_data_test.wasm");
}
