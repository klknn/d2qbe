module d2qbe.app;

import d2qbe.codegen;
import d2qbe.parse;
import d2qbe.tokenize;
import d2qbe.c_declarations;

extern (C) void* get_stderr();

extern (C)
int main(int argc, char** argv) {
  if (argc != 2) {
    fprintf(get_stderr(), "wrong number of args\n");
    return 1;
  }

  char* input_str = argv[1];
  void* f_in = fopen(argv[1], "r");
  if (f_in) {
    fseek(f_in, 0, 2);
    int size = cast(int) ftell(f_in);
    fseek(f_in, 0, 0);
    char* buf = cast(char*) calloc(1, size + 1);
    int read_bytes = cast(int) fread(buf, 1, size, f_in);
    buf[read_bytes] = 0;
    fclose(f_in);
    input_str = buf;
  }

  user_input = input_str;
  token = tokenize(input_str);
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
