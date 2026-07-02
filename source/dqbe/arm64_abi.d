module dqbe.arm64_abi;

import core.stdc.string : strcmp;

const(char)* arm64_get_arg_reg_32(int idx) {
  if (idx >= 0 && idx < 8) {
    if (idx == 0) return "w0";
    if (idx == 1) return "w1";
    if (idx == 2) return "w2";
    if (idx == 3) return "w3";
    if (idx == 4) return "w4";
    if (idx == 5) return "w5";
    if (idx == 6) return "w6";
    if (idx == 7) return "w7";
  }
  return null;
}

const(char)* arm64_get_arg_reg_64(int idx) {
  if (idx >= 0 && idx < 8) {
    if (idx == 0) return "x0";
    if (idx == 1) return "x1";
    if (idx == 2) return "x2";
    if (idx == 3) return "x3";
    if (idx == 4) return "x4";
    if (idx == 5) return "x5";
    if (idx == 6) return "x6";
    if (idx == 7) return "x7";
  }
  return null;
}

const(char)* arm64_get_float_arg_reg(int idx, char type) {
  if (idx >= 0 && idx < 8) {
    char prefix = (type == 's') ? 's' : 'd';
    if (prefix == 's') {
      if (idx == 0) return "s0";
      if (idx == 1) return "s1";
      if (idx == 2) return "s2";
      if (idx == 3) return "s3";
      if (idx == 4) return "s4";
      if (idx == 5) return "s5";
      if (idx == 6) return "s6";
      if (idx == 7) return "s7";
    } else {
      if (idx == 0) return "d0";
      if (idx == 1) return "d1";
      if (idx == 2) return "d2";
      if (idx == 3) return "d3";
      if (idx == 4) return "d4";
      if (idx == 5) return "d5";
      if (idx == 6) return "d6";
      if (idx == 7) return "d7";
    }
  }
  return null;
}

const(char)* arm64_get_param_reg(int arg_idx, char type, int int_arg_idx, int float_arg_idx) {
  if (type == 'w') {
    return arm64_get_arg_reg_32(int_arg_idx);
  } else if (type == 'l') {
    return arm64_get_arg_reg_64(int_arg_idx);
  } else if (type == 's' || type == 'd') {
    return arm64_get_float_arg_reg(float_arg_idx, type);
  }
  return null;
}
