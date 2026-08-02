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
    wasm_error("globals are not supported in wasm M1");
    return false;
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

bool append_function_body(ref ByteBuffer code, FunctionDef* fn) {
  ByteBuffer body;
  int locals = local_count(fn);
  if (!append_u32(body, cast(uint) locals)) return false;
  for (int i = 0; i < locals; i++) {
    if (!append_u32(body, 1) || !append_byte(body, WASM_I32)) {
      dispose(body);
      return false;
    }
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
    if (inst.kind == InstKind.IK_ret) {
      if (fn.ret_type == 'w') {
        if (!inst.arg1 || !append_value(body, fn, inst.arg1)) {
          dispose(body);
          return false;
        }
      } else if (inst.arg1) {
        wasm_error("void function cannot return a value");
        dispose(body);
        return false;
      }
      if (!append_byte(body, WASM_RETURN)) {
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
  if (program_data_count != 0) {
    wasm_error("data definitions are not supported in wasm M1");
    return false;
  }
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

  int exports = 0;
  for (int i = 0; i < program_functions_count; i++) if (program_functions[i].is_export) exports++;
  ByteBuffer export_section;
  ok = ok && append_u32(export_section, cast(uint) exports);
  for (int i = 0; ok && i < program_functions_count; i++) {
    FunctionDef* fn = &program_functions[i];
    if (!fn.is_export) continue;
    ok = append_name(export_section, fn.name + 1) && append_byte(export_section, 0) &&
      append_u32(export_section, cast(uint) i);
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
