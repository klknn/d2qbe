extern (C) int printf(const char* format, ...);

struct S {
    int[2][2] mat;
}

extern (C) int main() {
    int[3][2] arr;
    
    // Assign values
    arr[0][0] = 10;
    arr[0][1] = 20;
    arr[0][2] = 30;
    
    arr[1][0] = 40;
    arr[1][1] = 50;
    arr[1][2] = 60;
    
    // Verify values
    assert(arr[0][0] == 10);
    assert(arr[0][1] == 20);
    assert(arr[0][2] == 30);
    
    assert(arr[1][0] == 40);
    assert(arr[1][1] == 50);
    assert(arr[1][2] == 60);
    
    // Verify layout size
    assert(arr.sizeof == 24); // 2 * 3 * 4 = 24 bytes
    
    // Verify pointer access
    int* p = &arr[0][0];
    assert(*(p + 0) == 10);
    assert(*(p + 1) == 20);
    assert(*(p + 2) == 30);
    assert(*(p + 3) == 40);
    assert(*(p + 4) == 50);
    assert(*(p + 5) == 60);

    // Multidimensional struct array test
    S s;
    s.mat[0][0] = 1;
    s.mat[0][1] = 2;
    s.mat[1][0] = 3;
    s.mat[1][1] = 4;
    
    assert(s.mat[0][0] == 1);
    assert(s.mat[0][1] == 2);
    assert(s.mat[1][0] == 3);
    assert(s.mat[1][1] == 4);
    assert(S.sizeof == 16);
    
    // Assign struct containing multidimensional array
    S s2;
    s2 = s;
    assert(s2.mat[0][0] == 1);
    assert(s2.mat[0][1] == 2);
    assert(s2.mat[1][0] == 3);
    assert(s2.mat[1][1] == 4);

    printf("Multidimensional static array tests passed!\n");
    return 0;
}
