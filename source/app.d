import core.stdc.stdio;
import core.stdc.stdlib;

extern (C)
int main(int argc, char** argv) {
  if (argc != 2) {
    fprintf(stderr, "wrong number of args\n");
    return 1;
  }

  printf("export function w $main() {\n");
  printf("@start\n");
  printf("	ret %s\n", argv[1]);
  printf("}\n");

  return 0;
}
