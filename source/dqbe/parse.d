module dqbe.parse;

import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.string;

import dqbe.tokenize;

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
  
  Instruction[1000] instructions;
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

__gshared FunctionDef[100] program_functions;
__gshared int program_functions_count = 0;

__gshared DataDef[500] program_data;
__gshared int program_data_count = 0;

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
  
  assert(program_data_count < 500);
  DataDef* def = &program_data[program_data_count++];
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
      
      assert(fn.inst_count < 1000);
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
      
      assert(fn.inst_count < 1000);
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
      
      assert(fn.inst_count < 1000);
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
      
      assert(fn.inst_count < 1000);
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
      
      assert(fn.inst_count < 1000);
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
      
      assert(fn.inst_count < 1000);
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
      memset(&inst, 0, inst.sizeof);
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
      memset(&inst, 0, inst.sizeof);
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
      
      assert(fn.inst_count < 1000);
      fn.instructions[fn.inst_count++] = inst;
      continue;
    }
    
    Token* op_tok = consume_kind(TokenKind.TK_ident);
    if (!op_tok) {
      error_at(token.str, "Expected instruction inside function");
    }
    
    if (strncmp(op_tok.str, "store", 5) == 0) {
      Instruction inst;
      memset(&inst, 0, inst.sizeof);
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
      
      assert(fn.inst_count < 1000);
      fn.instructions[fn.inst_count++] = inst;
      continue;
    }
    
    if (op_tok.len == 3 && strncmp(op_tok.str, "jmp", 3) == 0) {
      Instruction inst;
      memset(&inst, 0, inst.sizeof);
      inst.kind = InstKind.IK_jmp;
      
      Token* label_target = consume_kind(TokenKind.TK_label);
      if (!label_target) error("Expected label target for jmp");
      
      inst.label = token_to_str(label_target);
      
      assert(fn.inst_count < 1000);
      fn.instructions[fn.inst_count++] = inst;
      continue;
    }
    
    if (op_tok.len == 3 && strncmp(op_tok.str, "jnz", 3) == 0) {
      Instruction inst;
      memset(&inst, 0, inst.sizeof);
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
      
      assert(fn.inst_count < 1000);
      fn.instructions[fn.inst_count++] = inst;
      continue;
    }
    
    if (op_tok.len == 3 && strncmp(op_tok.str, "ret", 3) == 0) {
      Instruction inst;
      memset(&inst, 0, inst.sizeof);
      inst.kind = InstKind.IK_ret;
      
      Token* ret_val_tok = consume_kind(TokenKind.TK_temp);
      if (!ret_val_tok) ret_val_tok = consume_kind(TokenKind.TK_num);
      
      if (ret_val_tok) {
        inst.arg1 = token_to_str(ret_val_tok);
      }
      
      assert(fn.inst_count < 1000);
      fn.instructions[fn.inst_count++] = inst;
      continue;
    }
    
    if (op_tok.len == 4 && strncmp(op_tok.str, "call", 4) == 0) {
      Instruction inst;
      memset(&inst, 0, inst.sizeof);
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
      
      assert(fn.inst_count < 1000);
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
      assert(program_functions_count < 100);
      FunctionDef* fn = &program_functions[program_functions_count++];
      fn.inst_count = 0;
      fn.params_count = 0;
      fn.is_variadic = false;
      
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
      parse_instruction_list(fn);
      
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
