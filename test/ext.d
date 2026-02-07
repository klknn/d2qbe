import core.stdc.stdio;

extern (C) int foo() {
  return printf("foo\n");
}

extern (C) int foo1(int a1) {
  return printf("foo %d\n", a1);
}

extern (C) int foo2(int a1, int a2) {
  return printf("foo %d %d\n", a1, a2);
}
