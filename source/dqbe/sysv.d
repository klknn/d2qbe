/**
 * Module for System V AMD64 ABI calling convention logic.
 *
 * System V AMD64 ABI Specifications:
 * 1. Integer/Pointer Arguments:
 *    - The first 6 integer/pointer arguments are passed in registers:
 *      %rdi, %rsi, %rdx, %rcx, %r8, %r9 (64-bit)
 *      %edi, %esi, %edx, %ecx, %r8d, %r9d (32-bit)
 *    - Additional integer arguments are passed on the stack.
 *
 * 2. Floating-Point Arguments:
 *    - The first 8 float/double arguments are passed in SSE registers:
 *      %xmm0, %xmm1, %xmm2, %xmm3, %xmm4, %xmm5, %xmm6, %xmm7
 *    - Additional floating-point arguments are passed on the stack.
 *
 * 3. Stack Alignment:
 *    - The stack pointer (%rsp) must be 16-byte aligned before any 'call' instruction.
 *    - Upon entering the callee, the stack pointer is offset by 8 bytes (due to the pushed return address).
 *
 * 4. Register Preservation (Callee-Saved):
 *    - %rbx, %rsp, %rbp, %r12, %r13, %r14, %r15 are callee-saved (must be preserved).
 *    - All other general-purpose registers and SSE registers are caller-saved (scratch).
 *
 * 5. Varargs / Variable Arguments:
 *    - For variadic calls, the number of floating-point arguments passed in vector registers
 *      must be loaded into the %al register (lower 8 bits of %rax) before the call.
 *
 * 6. Return Values:
 *    - Integers/pointers: returned in %rax (64-bit) or %eax (32-bit).
 *    - Floats/doubles: returned in %xmm0.
 */
module dqbe.sysv;

import core.stdc.string : strcmp;

/**
 * Returns the 32-bit physical register name for the given integer parameter index.
 *
 * Params:
 *   idx = The 0-indexed count of integer arguments seen so far.
 * Returns: The register name string, or null if the argument is passed on the stack (idx >= 6).
 */
const(char)* sysv_get_arg_reg_32(int idx) {
  if (idx == 0) return "%edi";
  if (idx == 1) return "%esi";
  if (idx == 2) return "%edx";
  if (idx == 3) return "%ecx";
  if (idx == 4) return "%r8d";
  if (idx == 5) return "%r9d";
  return null;
}

/**
 * Returns the 64-bit physical register name for the given integer/pointer parameter index.
 *
 * Params:
 *   idx = The 0-indexed count of integer/pointer arguments seen so far.
 * Returns: The register name string, or null if the argument is passed on the stack (idx >= 6).
 */
const(char)* sysv_get_arg_reg_64(int idx) {
  if (idx == 0) return "%rdi";
  if (idx == 1) return "%rsi";
  if (idx == 2) return "%rdx";
  if (idx == 3) return "%rcx";
  if (idx == 4) return "%r8";
  if (idx == 5) return "%r9";
  return null;
}

/**
 * Returns the float register name for the given floating-point parameter index.
 *
 * Params:
 *   idx = The 0-indexed count of floating-point arguments seen so far.
 * Returns: The SSE register name string, or null if the argument is passed on the stack (idx >= 8).
 */
const(char)* sysv_get_float_arg_reg(int idx) {
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

/**
 * Maps a parameter to its physical register on System V ABI.
 *
 * Params:
 *   arg_idx = The overall 0-indexed parameter index in the parameter list.
 *   type = The QBE type character ('w', 'l', 's', 'd').
 *   int_arg_idx = The 0-indexed count of integer arguments seen so far.
 *   float_arg_idx = The 0-indexed count of floating-point arguments seen so far.
 * Returns: The register name string, or null if the parameter is passed on the stack.
 */
const(char)* sysv_get_param_reg(int arg_idx, char type, int int_arg_idx, int float_arg_idx) {
  if (type == 'w') {
    return sysv_get_arg_reg_32(int_arg_idx);
  } else if (type == 'l') {
    return sysv_get_arg_reg_64(int_arg_idx);
  } else if (type == 's' || type == 'd') {
    return sysv_get_float_arg_reg(float_arg_idx);
  }
  return null;
}
