module d2qbe.app;

import core.stdc.stdio;

import d2qbe.codegen;
import d2qbe.parse;

extern (C)
int main(int argc, char** argv) {
  if (argc != 2) {
    fprintf(stderr, "wrong number of args\n");
    return 1;
  }

  user_input = argv[1];
  token = tokenize(argv[1]);
  program();

  printf("export function w $main() {\n");
  printf("@main\n");
  int ret = 0;
  for (int i = 0; code[i]; i++) {
    ret = gen(code[i], ret);
  }
  printf("}\n");

  return 0;
}
