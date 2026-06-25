extern (C) int printf(const char* format, ...);

int test_switch(int x) {
    int res;
    res = 0;
    switch (x) {
        case 1:
            res = 10;
            break;
        case 2:
            res = 20;
            break;
        case 3:
            res = 35;
            break;
        case 4:
            res = res + 5;
            break;
        default:
            res = 100;
            break;
    }
    return res;
}

extern (C) int main() {
    assert(test_switch(1) == 10);
    assert(test_switch(2) == 20);
    assert(test_switch(3) == 35); // 30 + 5 (fallthrough to 4)
    assert(test_switch(4) == 5);  // 0 + 5
    assert(test_switch(5) == 100);
    printf("Switch tests passed!\n");
    return 0;
}
