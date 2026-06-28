/**
 * Module for Microsoft Windows x64 ABI calling convention logic.
 *
 * Microsoft x64 ABI Specifications:
 * 1. Register Arguments (4-Register Limit):
 *    - Only the first 4 arguments are passed in registers.
 *    - The register assignment is strictly *positional* based on the 0-indexed parameter slot:
 *      - Parameter 0: %rcx / %ecx (int/ptr) or %xmm0 (float/double)
 *      - Parameter 1: %rdx / %edx (int/ptr) or %xmm1 (float/double)
 *      - Parameter 2: %r8  / %r8d  (int/ptr) or %xmm2 (float/double)
 *      - Parameter 3: %r9  / %r9d  (int/ptr) or %xmm3 (float/double)
 *    - Slot consumption is type-neutral. If Parameter 0 is float and Parameter 1 is integer:
 *      Parameter 0 goes to %xmm0, and Parameter 1 goes to %rdx (not %rcx).
 *    - Parameters 4 and above are passed on the stack.
 *
 * 2. Shadow Space (Home Space):
 *    - The caller is required to allocate 32 bytes of "shadow space" (scratch space for 4 registers)
 *      on the stack immediately before executing a 'call' instruction.
 *    - The space must be allocated even if the callee has fewer than 4 parameters.
 *    - The callee may use this 32-byte area to spill the register arguments if necessary.
 *
 * 3. Stack Alignment:
 *    - The stack pointer (%rsp) must be 16-byte aligned before any 'call' instruction.
 *    - Since the return address is 8 bytes, upon entry to the callee, the stack pointer is
 *      offset by 8 bytes (i.e. %rsp is 16-byte aligned + 8).
 *
 * 4. Register Preservation (Callee-Saved):
 *    - General-purpose: %rbx, %rbp, %rdi, %rsi, %rsp, %r12, %r13, %r14, %r15 are callee-saved.
 *    - Floating-point: %xmm6 through %xmm15 are callee-saved.
 *    - All other registers (%rax, %rcx, %rdx, %r8-%r11, %xmm0-%xmm5) are caller-saved (scratch).
 *
 * 5. Varargs / Variable Arguments:
 *    - For variadic calls, float/double arguments passed in vector registers (%xmm0-%xmm3)
 *      must *also* be duplicated into their corresponding integer registers (%rcx, %rdx, %r8, %r9).
 *
 * 6. Return Values:
 *    - Integers/pointers: returned in %rax (64-bit) or %eax (32-bit).
 *    - Floats/doubles: returned in %xmm0.
 */
module dqbe.win64;

import core.stdc.string : strcmp;

/**
 * Returns the 32-bit physical register name for the given positional argument slot.
 *
 * Params:
 *   idx = The positional argument slot (0-indexed).
 * Returns: The register name string, or null if the argument slot is passed on stack (idx >= 4).
 */
const(char)* win64_get_arg_reg_32(int idx) {
  if (idx == 0) return "%ecx";
  if (idx == 1) return "%edx";
  if (idx == 2) return "%r8d";
  if (idx == 3) return "%r9d";
  return null;
}

/**
 * Returns the 64-bit physical register name for the given positional argument slot.
 *
 * Params:
 *   idx = The positional argument slot (0-indexed).
 * Returns: The register name string, or null if the argument slot is passed on stack (idx >= 4).
 */
const(char)* win64_get_arg_reg_64(int idx) {
  if (idx == 0) return "%rcx";
  if (idx == 1) return "%rdx";
  if (idx == 2) return "%r8";
  if (idx == 3) return "%r9";
  return null;
}

/**
 * Returns the float register name for the given positional argument slot.
 *
 * Params:
 *   idx = The positional argument slot (0-indexed).
 * Returns: The SSE register name string, or null if the argument slot is passed on stack (idx >= 4).
 */
const(char)* win64_get_float_arg_reg(int idx) {
  if (idx == 0) return "%xmm0";
  if (idx == 1) return "%xmm1";
  if (idx == 2) return "%xmm2";
  if (idx == 3) return "%xmm3";
  return null;
}

/**
 * Maps a parameter to its physical register on Windows x64 ABI.
 *
 * Params:
 *   arg_idx = The overall 0-indexed parameter index in the parameter list.
 *   type = The QBE type character ('w', 'l', 's', 'd').
 *   int_arg_idx = Ignored (Windows uses positional slots).
 *   float_arg_idx = Ignored (Windows uses positional slots).
 * Returns: The register name string, or null if the parameter is passed on the stack.
 */
const(char)* win64_get_param_reg(int arg_idx, char type, int int_arg_idx, int float_arg_idx) {
  if (arg_idx >= 4) return null;
  if (type == 'w') {
    return win64_get_arg_reg_32(arg_idx);
  } else if (type == 'l') {
    return win64_get_arg_reg_64(arg_idx);
  } else if (type == 's' || type == 'd') {
    return win64_get_float_arg_reg(arg_idx);
  }
  return null;
}
