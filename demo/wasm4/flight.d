int planeX = 72;
int planeY = 104;
int bank = 0;

extern(C) void start() {
  setPalette(12635647, 8193987, 5320483, 1518612);
}

extern(C) void update() {
  int input = readGamepad();
  if (input & 16) { planeX = planeX - 3; bank = -1; }
  if (input & 32) { planeX = planeX + 3; bank = 1; }
  if (input & 64) { planeY = planeY - 2; }
  if (planeX < 8) { planeX = 8; }
  if (planeX > 136) { planeX = 136; }
  if (planeY < 72) { planeY = 72; }
  if (planeY > 136) { planeY = 136; }

  setDrawColors(1);
  rect(0, 0, 160, 160);
  setDrawColors(2);
  rect(0, 80, 160, 80);
  setDrawColors(3);
  for (int row = 0; row < 5; row = row + 1) {
    int width = 24 + row * 24;
    int y = 84 + row * 16;
    rect(80 - width / 2, y, width, 2);
  }
  setDrawColors(4);
  rect(planeX + bank, planeY, 16, 4);
  rect(planeX + 6, planeY - 8, 4, 20);
  rect(planeX - 6, planeY + 4, 28, 3);
}
