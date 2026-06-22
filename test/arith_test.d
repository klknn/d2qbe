extern (C) int printf(const char* format, ...);
static assert(5 * 5 == 25);

static if (int.sizeof == 4) {
  int get_static_if_val() { return 777; }
} else {
  int get_static_if_val() { return 888; }
}

struct Counter {
  int count;
  void init_val(int start) {
    count = start;
  }
  void increment() {
    count = count + 1;
  }
  int get_count() {
    return count;
  }
}

auto global_auto_val = 500;

version(Posix) {
  int get_os_val() { return 100; }
}
version(Windows) {
  int get_os_val() { return 200; }
}

int g_destroyed_count = 0;

struct RaiiTester {
  int id;
  this(int val) {
    id = val;
  }
  ~this() {
    g_destroyed_count = g_destroyed_count + 1;
  }
}

int test_raii_return() {
  RaiiTester r2 = RaiiTester(99);
  assert(r2.id == 99);
  return 123;
}

int main() {
    // Arithmetic & basic operations
    assert(5+20-4 == 21);
    assert(12 + 34 - 5 == 41);
    assert(5+6*7 == 47);
    assert(5*(9-6) == 15);
    assert((3+5)/2 == 4);
    assert(-10+20 == 10);
    assert(- -10 == 10);
    assert(- - +10 == 10);

    // Equality and comparison
    assert((0==1) == 0);
    assert((42==42) == 1);
    assert((0!=1) == 1);
    assert((42!=42) == 0);
    assert((0<1) == 1);
    assert((1<1) == 0);
    assert((2<1) == 0);
    assert((0<=1) == 1);
    assert((1<=1) == 1);
    assert((2<=1) == 0);
    assert((1>0) == 1);
    assert((1>1) == 0);
    assert((1>2) == 0);
    assert((1>=0) == 1);
    assert((1>=1) == 1);
    assert((1>=2) == 0);

    // Modulo and bitwise operators
    assert(10 % 4 == 2);
    assert(10 % 2 == 0);
    assert(5 % 2 == 1);
    assert((2 & 3) == 2);
    assert((2 & 1) == 0);
    assert((1 | 2) == 3);
    assert((2 | 2) == 2);
    assert((2 ^ 3) == 1);
    assert((2 ^ 2) == 0);
    assert(10 << 2 == 40);
    assert(10 >> 2 == 2);
    assert(3 >> 1 == 1);
    assert((~-1) == 0);
    assert((~0) == -1);
    // Compound assignment operators
    int ca_val = 10;
    ca_val += 5;
    assert(ca_val == 15);
    ca_val -= 3;
    assert(ca_val == 12);
    ca_val *= 2;
    assert(ca_val == 24);
    ca_val /= 4;
    assert(ca_val == 6);
    ca_val %= 4;
    assert(ca_val == 2);
    ca_val &= 3;
    assert(ca_val == 2);
    ca_val |= 4;
    assert(ca_val == 6);
    ca_val ^= 2;
    assert(ca_val == 4);
    ca_val <<= 2;
    assert(ca_val == 16);
    ca_val >>= 1;
    assert(ca_val == 8);

    assert((2 & (1 == 0)) == 0);

    // Type sizes
    assert(int.sizeof == 4);
    assert(int*.sizeof == 8);
    assert(char.sizeof == 1);
    assert(bool.sizeof == 1);

    // Aliases
    alias myint = int;
    alias pint = int*;
    myint x_val = 100;
    pint y_ptr = &x_val;
    assert(*y_ptr == 100);

    // Static asserts
    static assert(1 == 1);
    static assert(10 * 2 == 20, "10 * 2 must be 20");
    static assert(int.sizeof == 4);
    static assert(int.init == 0);
    static assert(int*.alignof == 8);

    assert(char.init == 0);
    assert(char.alignof == 1);

    // Conditional compilation
    version(Posix) {
      assert(get_os_val() == 100);
    }
    version(Windows) {
      assert(get_os_val() == 200);
    } else {
      assert(get_os_val() == 100);
    }

    // Type Inference (auto)
    auto local_auto_val = 250;
    assert(local_auto_val * 2 == global_auto_val);

    auto local_auto_ptr = &local_auto_val;
    assert(*local_auto_ptr == 250);

    // Static if
    static if (char.sizeof == 1) {
      assert(get_static_if_val() == 777);
    } else {
      assert(get_static_if_val() == 888);
    }

    // Struct member functions
    Counter c;
    c.init_val(10);
    assert(c.get_count() == 10);
    c.increment();
    assert(c.get_count() == 11);

    // Member function with pointers
    Counter* c_ptr = &c;
    c_ptr.increment();
    assert(c_ptr.get_count() == 12);

    // Slices and slicing
    int[5] arr;
    arr[0] = 100;
    arr[1] = 200;
    arr[2] = 300;
    arr[3] = 400;
    arr[4] = 500;

    int[] sl = arr[1 .. 4];
    assert(sl.length == 3);
    assert(sl[0] == 200);
    assert(sl[1] == 300);
    assert(sl[2] == 400);

    // Slice assignment and modifications
    sl[1] = 999;
    assert(arr[2] == 999);

    int[] sl2 = sl[1 .. 3];
    assert(sl2.length == 2);
    assert(sl2[0] == 999);
    assert(sl2[1] == 400);

    // Ternary operator tests
    int val1 = 10;
    int val2 = 20;
    int res1 = (val1 < val2) ? 100 : 200;
    assert(res1 == 100);
    int res2 = (val1 > val2) ? 300 : 400;
    assert(res2 == 400);

    // Ternary with slices
    int[] tern_sl = (val1 < val2) ? sl : sl2;
    assert(tern_sl.length == 3);
    assert(tern_sl[0] == 200);

    // Float and double tests
    float f1 = 1.5f;
    float f2 = 2.5f;
    float f3 = f1 + f2;
    assert(f3 > 3.9f && f3 < 4.1f);

    double d1 = 10.0;
    double d2 = 3.0;
    double d3 = d1 / d2;
    assert(d3 > 3.33 && d3 < 3.34);

    // RAII / Constructor & Destructor tests
    assert(g_destroyed_count == 0);
    {
      RaiiTester r1 = RaiiTester(42);
      assert(r1.id == 42);
      assert(g_destroyed_count == 0);
    }
    // Block exit should call destructor!
    assert(g_destroyed_count == 1);

    // Test destruction on return
    int ret_val = test_raii_return();
    assert(ret_val == 123);
    assert(g_destroyed_count == 2);

    printf("Arithmetic and basic operator tests passed!\n");
    return 0;
}
