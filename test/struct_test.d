struct Point {
  int x;
  int y;
}

struct Rect {
  Point p1;
  Point p2;
}

int main() {
  Point p;
  p.x = 10;
  p.y = 20;
  assert(p.x == 10);
  assert(p.y == 20);
  assert(Point.sizeof == 8);

  Point* ptr = &p;
  assert(ptr.x == 10);
  ptr.y = 30;
  assert(p.y == 30);

  Rect r;
  r.p1.x = 100;
  r.p2.y = 200;
  assert(r.p1.x == 100);
  assert(r.p2.y == 200);
  assert(Rect.sizeof == 16);

  Point p2;
  p2 = p;
  assert(p2.x == 10);
  assert(p2.y == 30);

  return 0;
}
