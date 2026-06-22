extern (C) void* malloc(int size);
extern (C) int printf(const char* format, ...);

extern (C) int main() {
    int n;
    int nv;
    int c;
    int cmax;
    int* mem;

    mem = cast(int*) malloc(4 * 10000000);

    cmax = 0;
    for (nv = 1; nv < 10000000; nv++) {
        n = nv;
        c = 0;
        while (n != 1) {
            if (n < nv) {
                c = c + mem[n];
                break;
            }
            if (n & 1)
                n = 3 * n + 1;
            else
                n = n / 2;
            c++;
        }
        mem[nv] = c;
        if (c > cmax)
            cmax = c;
    }
    printf("max steps: %d\n", cmax);
    return 0;
}
