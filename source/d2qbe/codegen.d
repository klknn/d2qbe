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
  }
}

int gen(Node* node, int ret_var) {
  if (node.kind == NodeKind.num) {
    printf("  %%t%d =w copy %d\n", ret_var + 1, node.val);
    return ret_var + 1;
  }
  int l = gen(node.lhs, ret_var);
  int r = gen(node.rhs, l);
  printf("  %%t%d =w %s %%t%d, %%t%d\n", r + 1, node_kind_to_str(node.kind), l, r);
  return r + 1;
}
