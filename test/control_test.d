extern (C) int printf(const char* format, ...);
extern (C) int foo();
extern (C) int foo1(int a1);
extern (C) int foo2(int a1, int a2);

int fib(int x) {
    if (x <= 1)
        return 1;
    return fib(x - 1) + fib(x - 2);
}

int add(int a, int b) {
    return a + b;
}

int test_if(int x) {
    if (x > 10) {
        return 100;
    } else if (x > 5) {
        return 50;
    } else {
        return 0;
    }
}

int main() {
    // Variables
    int returnx = 12;
    assert(returnx == 12);
    int a = 12;
    assert(a == 12);
    assert(a + 1 == 13);
    int b = -2;
    assert(a + b == 10);
    a = 11;
    a = a + 1;
    assert(a == 12);
    int foo_var = 12;
    int bar_var = -2;
    assert(foo_var + bar_var == 10);

    // If conditions
    assert(test_if(20) == 100);
    assert(test_if(8) == 50);
    assert(test_if(2) == 0);

    // Loops
    int loop_a = 0;
    while (loop_a < 10) {
        loop_a = loop_a + 1;
    }
    assert(loop_a == 10);

    int loop_for = 0;
    for (int idx = 0; idx < 10; idx = idx + 1) {
        loop_for = loop_for + 1;
    }
    assert(loop_for == 10);

    // Break & Continue
    int i = 0;
    while (i < 10) {
        i = i + 1;
        if (i == 5) break;
    }
    assert(i == 5);

    int sum = 0;
    for (int idx = 0; idx < 10; idx = idx + 1) {
        if (idx == 5) continue;
        sum = sum + idx;
    }
    assert(sum == 40); // 0+1+2+3+4 + 6+7+8+9 = 40

    // Blocks
    {
        int block_val = 99;
        assert(block_val == 99);
    }

    // Pointers & Dereference
    int p_val = 12;
    int* p_ptr = &p_val;
    assert(*p_ptr == 12);
    *p_ptr = 42;
    assert(p_val == 42);

    int px = 5;
    int* py = &px;
    assert(*(py + 0) == 5);
    int* pz = py + 1;
    assert(pz - py == 1);
    assert(py[0] == 5);

    // Functions
    assert(fib(9) == 55);
    assert(add(2, 3) == 5);

    // External functions
    foo();
    foo1(1);
    foo2(1, 2);
    foo2(1 + 2, 2);
    foo1(foo());

    printf("Control flow and function tests passed!\n");
    return 0;
}
