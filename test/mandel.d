extern (C) int putchar(int c);

int mandel(double x, double y) {
  double cr = y - 0.5;
  double ci = x;
  int i = 0;
  double zr = 0.0;
  double zi = 0.0;
  while (i < 1000) {
    i = i + 1;
    double tmp = zr * zi;
    double zr2 = zr * zr;
    double zi2 = zi * zi;
    double zrx = zr2 - zi2;
    double zr1 = zrx + cr;
    double zix = tmp + tmp;
    double zi1 = zix + ci;
    double sum = zi2 + zr2;
    if (sum > 16.0) {
      return i;
    }
    zr = zr1;
    zi = zi1;
  }
  return 0;
}

extern (C) int main() {
  int count = 0;
  while (count < 50) {
    count = count + 1;
    double y = -1.0;
    while (y <= 1.0) {
      double x = -1.0;
      while (x <= 1.0) {
        int i = mandel(x, y);
        if (i != 0) {
          putchar(32); // ' '
        } else {
          putchar(42); // '*'
        }
        x = x + 0.032;
      }
      putchar(10); // '\n'
      y = y + 0.032;
    }
  }
  return 0;
}
