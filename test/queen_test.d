extern (C) void* calloc(int num, int size);
extern (C) int printf(const char* format, ...);

int Q;
int N;
int** t;

void print_board() {
    int x;
    int y;

    for (y = 0; y < Q; y++) {
        for (x = 0; x < Q; x++) {
            if (t[x][y])
                printf(" Q");
            else
                printf(" .");
        }
        printf("\n");
    }
    printf("\n");
}

int chk(int x, int y) {
    int i;
    int r;

    r = 0;
    for (i = 0; i < Q; i++) {
        r = r + t[x][i];
        r = r + t[i][y];
        if (x + i < Q && y + i < Q)
            r = r + t[x + i][y + i];
        if (x + i < Q && y - i >= 0)
            r = r + t[x + i][y - i];
        if (x - i >= 0 && y + i < Q)
            r = r + t[x - i][y + i];
        if (x - i >= 0 && y - i >= 0)
            r = r + t[x - i][y - i];
    }
    return r;
}

void go(int y) {
    int x;

    if (y == Q) {
        print_board();
        N++;
        return;
    }
    for (x = 0; x < Q; x++) {
        if (chk(x, y) == 0) {
            t[x][y]++;
            go(y + 1);
            t[x][y]--;
        }
    }
}

int main() {
    int i;

    Q = 8;
    t = cast(int**) calloc(Q, int*.sizeof);
    for (i = 0; i < Q; i++) {
        t[i] = cast(int*) calloc(Q, int.sizeof);
    }
    go(0);
    printf("found %d solutions\n", N);
    assert(N == 92);
    return 0;
}
