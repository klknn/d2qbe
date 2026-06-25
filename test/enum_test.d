enum Val = 42;

enum {
  A,
  B = 10,
  C
}

extern (C) int main() {
  assert(Val == 42);
  assert(A == 0);
  assert(B == 10);
  assert(C == 11);
  return 0;
}
