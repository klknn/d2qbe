module d2qbe.codegen;

import core.stdc.stdio;

import d2qbe.parse;

const(char)* node_kind_to_str(NodeKind kind) {
  final switch (kind) {
  case NodeKind.add:
    return "add";
  case NodeKind.sub:
    return "sub";
  case NodeKind.mul:
    return "mul";
  case NodeKind.div:
    return "div";
  case NodeKind.lt:
    // c + common-operator (slt) + operand-type (w)
    return "csltw";
  case NodeKind.le:
    return "cslew";
  case NodeKind.eq:
    return "ceqw";
  case NodeKind.ne:
    return "cnew";
  case NodeKind.num:
    return "num";
  case NodeKind.assign:
  case NodeKind.lvar:
  case NodeKind.return_:
  case NodeKind.if_:
  case NodeKind.for_:
  case NodeKind.while_:
    assert(false);
  }
}

void gen_lval(Node* node) {
  if (node.kind != NodeKind.lvar) {
    error("Variable expected in lhs.");
  }
}

int gen(Node* node, int ret_var) {
  if (node.kind == NodeKind.num) {
    printf("  %%t%d =w copy %d\n", ret_var + 1, node.val);
    return ret_var + 1;
  }
  if (node.kind == NodeKind.lvar) {
    printf("  %%t%d =w copy %%%s\n", ret_var + 1, node.ident);
    return ret_var + 1;
  }
  if (node.kind == NodeKind.assign) {
    if (node.lhs.kind != NodeKind.lvar) {
      error("Variable expected in lhs");
    }
    int rhs = gen(node.rhs, ret_var);
    printf("  %%%s =w copy %%t%d\n", node.lhs.ident, rhs);
    return rhs;
  }
  if (node.kind == NodeKind.return_) {
    int lhs = gen(node.lhs, ret_var);
    printf("  ret %%t%d\n", lhs);
    return lhs;
  }
  if (node.kind == NodeKind.if_) {
    int cond = gen(node.cond, ret_var);
    printf("  jnz %%t%d, @then%d, @else%d\n", cond, ret_var, ret_var);
    printf("@then%d\n", ret_var);
    int then = gen(node.then, cond);
    int ret = then;
    if (node.then.kind != NodeKind.return_) {
      printf("  jmp @endif%d\n", ret_var);
    }
    printf("@else%d\n", ret_var);
    if (node.else_) {
      ret = gen(node.else_, then);
    }
    if (node.then.kind != NodeKind.return_) {
      printf("@endif%d\n", ret_var);
    }
    return ret;
  }
  if (node.kind == NodeKind.while_) {
    printf("@cond%d\n", ret_var);
    int cond = gen(node.cond, ret_var);
    printf("  jnz %%t%d, @body%d, @break%d\n", cond, ret_var, ret_var);
    printf("@body%d\n", ret_var);
    int then = gen(node.then, cond);
    printf("  jmp @cond%d\n", ret_var);
    printf("@break%d\n", ret_var);
    return then;
  }
  int l = gen(node.lhs, ret_var);
  int r = gen(node.rhs, l);
  printf("  %%t%d =w %s %%t%d, %%t%d\n", r + 1, node_kind_to_str(node.kind), l, r);
  return r + 1;
}
