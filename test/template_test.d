extern (C) int printf(const char* format, ...);

template Stack(T) {
    struct Stack {
        T[5] data;
        int top;
    }
}

template swap(T) {
    void swap(T* a, T* b) {
        T tmp = *a;
        *a = *b;
        *b = tmp;
    }
}

extern (C) int main() {
    // Test struct template instantiation
    Stack!int s;
    s.top = 0;
    s.data[0] = 42;
    assert(s.data[0] == 42);
    assert(Stack!int.sizeof == 24); // 5 * 4 (data) + 4 (top) = 24 bytes

    Stack!(char*) s2;
    s2.top = 10;
    assert(s2.top == 10);
    assert(Stack!(char*).sizeof == 48); // 5 * 8 (data) + 8 (top aligned) = 48 bytes

    // Test function template instantiation
    int x = 100;
    int y = 200;
    swap!int(&x, &y);
    assert(x == 200);
    assert(y == 100);

    char a = 65; // 'A'
    char b = 66; // 'B'
    swap!char(&a, &b);
    assert(a == 66);
    assert(b == 65);

    printf("Template tests passed!\n");
    return 0;
}
