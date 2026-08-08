int cursorX = 72;
int cursorY = 72;
int placedX = 80;
int placedY = 96;

extern(C) void start() {
  setPalette(14540253, 11566474, 4361074, 2172450);
}

extern(C) void update() {
  int input = readGamepad();
  if (input & 16) { cursorX = cursorX - 4; }
  if (input & 32) { cursorX = cursorX + 4; }
  if (input & 64) { cursorY = cursorY - 4; }
  if (cursorX < 0) { cursorX = 0; }
  if (cursorX > 144) { cursorX = 144; }
  if (cursorY < 0) { cursorY = 0; }
  if (cursorY > 128) { cursorY = 128; }
  if (input & 1) { placedX = cursorX; placedY = cursorY; }

  setDrawColors(1);
  rect(0, 0, 160, 160);
  setDrawColors(2);
  rect(0, 104, 160, 56);
  setDrawColors(3);
  for (int x = 0; x < 160; x = x + 32) {
    rect(x + 8, 72, 16, 32);
    rect(x, 64, 32, 16);
  }
  setDrawColors(4);
  rect(placedX, placedY, 16, 16);
  setDrawColors(2);
  rect(cursorX, cursorY, 16, 2);
  rect(cursorX, cursorY + 14, 16, 2);
  rect(cursorX, cursorY, 2, 16);
  rect(cursorX + 14, cursorY, 2, 16);
}
