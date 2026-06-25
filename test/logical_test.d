enum MyEnum {
  Foo = 100,
  Bar
}

void void_func(int* p) {
  *p = 42;
  return;
}

int assign(int* p, int val) {
  *p = val;
  return val;
}

extern (C) int main() {
  assert(MyEnum.Foo == 100);
  assert(MyEnum.Bar == 101);
  assert((1 && 1) == 1);
  assert((1 && 0) == 0);
  assert((0 && 1) == 0);
  assert((0 && 0) == 0);

  assert((1 || 1) == 1);
  assert((1 || 0) == 1);
  assert((0 || 1) == 1);
  assert((0 || 0) == 0);

  // Nested
  assert((1 && 1 && 1) == 1);
  assert((1 && 1 && 0) == 0);
  assert((0 || 0 || 1) == 1);

  // Short-circuiting verification
  int x = 0;
  int* p = &x;
  
  // if LHS is false, RHS should NOT be evaluated
  int res = 0 && assign(p, 1);
  assert(x == 0);
  assert(res == 0);

  // if LHS is true, RHS SHOULD be evaluated
  res = 1 && assign(p, 2);
  assert(x == 2);
  assert(res == 1);
  
  // if LHS is true, RHS should NOT be evaluated for OR
  x = 0;
  res = 1 || assign(p, 3);
  assert(x == 0);
  assert(res == 1);

  // if LHS is false, RHS SHOULD be evaluated for OR
  res = 0 || assign(p, 4);
  assert(x == 4);
  assert(res == 1);

  // Logical NOT
  assert(!1 == 0);
  assert(!0 == 1);
  assert(!!1 == 1);
  assert(!!0 == 0);

  // Character literals
  assert('a' == 97);
  assert('\n' == 10);
  assert('\'' == 39);
  assert('\\' == 92);

  // Increment/Decrement
  int i = 10;
  assert(i++ == 10);
  assert(i == 11);
  assert(++i == 12);
  assert(i == 12);
  
  assert(i-- == 12);
  assert(i == 11);
  assert(--i == 10);
  assert(i == 10);
  
  int x2 = 10;
  int* px = &x2;
  int* px2 = px;
  px++;
  assert(px - px2 == 1);

  int vx = 0;
  void_func(&vx);
  assert(vx == 42);

  return 0;
}
