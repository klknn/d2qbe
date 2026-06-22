extern (C) int printf(const char* format, ...);

extern (C) int main() {
    int n;
    int t;
    int c;
    int p;

    c = 0;
    n = 2;
    while (n < 250000) {
        t = 2;
        p = 1;
        while (t * t <= n) {
            if (n % t == 0) {
                p = 0;
                break;
            }
            t++;
        }
        if (p) {
            c++;
        }
        n++;
    }
    printf("primes count: %d\n", c);
    return 0;
}
