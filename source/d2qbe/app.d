module d2qbe.app;

import core.stdc.stdio;
import core.stdc.string;

import d2qbe.codegen;
import d2qbe.parse;
import d2qbe.tokenize;

extern (C) FILE* get_stderr();

extern (C)
int main(int argc, char** argv) {
  if (argc != 2) {
    fprintf(get_stderr(), "wrong number of args\n");
    return 1;
  }

  user_input = argv[1];
  token = tokenize(argv[1]);
  printf("# DEBUG: tokens:\n");
  Token* tok = token;
  while (tok) {
    printf("# DEBUG:   token '%.*s' kind=%d\n", tok.len, tok.str, tok.kind);
    tok = tok.next;
  }
  program();
  printf("# DEBUG: code_count=%d\n", code_count);

  int ret = 0;
  for (int i = 0; code[i]; i++) {
    if (code[i].kind == NodeKind.NK_gvar_decl) {
      if (code[i].type.name && strcmp(code[i].type.name, "auto") == 0) {
        Type inferred;
        infer_type(code[i].lhs, &inferred);
        code[i].type = inferred;
      }
      add_global(code[i].ident, &code[i].type);
    }
  }
  for (int i = 0; code[i]; i++) {
    gen(code[i]);
  }
  gen_strings();

  return 0;
}
