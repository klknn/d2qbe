extern (C) void* malloc(long size);
extern (C) int printf(const char* format, ...);

extern (C) int main() {
    long n;
    long nv;
    long c;
    long cmax;
    long* mem;

    mem = cast(long*) malloc(8 * 1000000);

    cmax = 0;
    for (nv = 1; nv < 1000000; nv++) {
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
    printf("max steps: %ld\n", cmax);
    return 0;
}
