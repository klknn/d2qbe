module d2qbe.codegen;

import core.stdc.stdio;

import d2qbe.parse;

void gen_lval(Node* node) {
  if (node.kind != NodeKind.lvar) {
    error("Variable expected in lhs.");
  }
}

bool is_returned(Node* node) {
  if (!node) {
    return false;
  }
  if (node.kind == NodeKind.return_) {
    return true;
  }
  if (node.kind == NodeKind.block) {
    while (node) {
      if (is_returned(node.block_list)) {
        return true;
      }
      node = node.block_list;
    }
  }
  return false;
}

int gen_binop(Node* node, int ret_var, const char* binop) {
  int l = gen(node.lhs, ret_var);
  int r = gen(node.rhs, l);
  printf("  %%t%d =w %s %%t%d, %%t%d\n", r + 1, binop, l, r);
  return r + 1;
}

int gen(Node* node, int ret_var) {
  if (!node) {
    return ret_var;
  }
  final switch (node.kind) {
  case NodeKind.num: {
      printf("  %%t%d =w copy %d\n", ret_var + 1, node.val);
      return ret_var + 1;
    }
  case NodeKind.lvar: {
      printf("  %%t%d =w copy %%%s\n", ret_var + 1, node.ident);
      return ret_var + 1;
    }
  case NodeKind.assign: {
      if (node.lhs.kind != NodeKind.lvar) {
        error("Variable expected in lhs");
      }
      int rhs = gen(node.rhs, ret_var);
      printf("  %%%s =w copy %%t%d\n", node.lhs.ident, rhs);
      return rhs;
    }
  case NodeKind.return_: {
      int lhs = gen(node.lhs, ret_var);
      printf("  ret %%t%d\n", lhs);
      return lhs;
    }
  case NodeKind.if_: {
      int cond = gen(node.cond, ret_var);
      printf("  jnz %%t%d, @then%d, @else%d\n", cond, ret_var, ret_var);
      printf("@then%d\n", ret_var);
      int then = gen(node.then, cond);
      int ret = then;
      if (!is_returned(node.then)) {
        printf("  jmp @endif%d\n", ret_var); // To skip the else block.
      }
      printf("@else%d\n", ret_var);
      ret = gen(node.else_, then);
      if (node.then.kind != NodeKind.return_) {
        printf("@endif%d\n", ret_var); // From the then block.
      }
      return ret;
    }
  case NodeKind.while_: {
      printf("@cond%d\n", ret_var);
      int cond = gen(node.cond, ret_var);
      printf("  jnz %%t%d, @body%d, @break%d\n", cond, ret_var, ret_var);
      printf("@body%d\n", ret_var);
      int then = gen(node.then, cond);
      printf("  jmp @cond%d\n", ret_var);
      printf("@break%d\n", ret_var);
      return then;
    }
  case NodeKind.for_: {
      int ret = gen(node.begin, ret_var);
      printf("@forcond%d\n", ret_var);
      if (node.cond) {
        ret = gen(node.cond, ret);
        printf("  jnz %%t%d, @forthen%d, @forend%d\n", ret, ret_var, ret_var);
      }
      printf("@forthen%d\n", ret_var);
      ret = gen(node.then, ret);
      ret = gen(node.advance, ret);
      printf("  jmp @forcond%d\n", ret_var);
      printf("@forend%d\n", ret_var);
      return ret;
    }
  case NodeKind.block: {
      while (node) {
        ret_var = gen(node.block_list, ret_var);
        node = node.block_list;
      }
      return ret_var;
    }
  case NodeKind.funcall:
    printf("%%t%d =w call $%s()\n", ret_var, node.ident);
    return ret_var + 1;
  case NodeKind.add:
    return gen_binop(node, ret_var, "add");
  case NodeKind.sub:
    return gen_binop(node, ret_var, "sub");
  case NodeKind.mul:
    return gen_binop(node, ret_var, "mul");
  case NodeKind.div:
    return gen_binop(node, ret_var, "div");
  case NodeKind.lt:
    // c + common-operator (slt) + operand-type (w)
    return gen_binop(node, ret_var, "csltw");
  case NodeKind.le:
    return gen_binop(node, ret_var, "cslew");
  case NodeKind.eq:
    return gen_binop(node, ret_var, "ceqw");
  case NodeKind.ne:
    return gen_binop(node, ret_var, "cnew");
  }
}
