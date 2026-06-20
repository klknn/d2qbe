extern (C) int printf(const char* format, ...);
static assert(5 * 5 == 25);

auto global_auto_val = 500;

version(Posix) {
  int get_os_val() { return 100; }
}
version(Windows) {
  int get_os_val() { return 200; }
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

    printf("Arithmetic and basic operator tests passed!\n");
    return 0;
}
