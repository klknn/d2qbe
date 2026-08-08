// Minimal WASM-4 binding for d2qbe's betterC subset.
// The console exposes drawing as env imports and input/display state in memory.

extern(C) void rect(int x, int y, int width, int height);

void setPalette(int first, int second, int third, int fourth) {
  *(cast(int*) 4) = first;
  *(cast(int*) 8) = second;
  *(cast(int*) 12) = third;
  *(cast(int*) 16) = fourth;
}

void setDrawColors(int colors) {
  *(cast(char*) 20) = colors;
  *(cast(char*) 21) = 0;
}

int readGamepad() {
  return *(cast(char*) 22);
}
