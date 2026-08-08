int blockX = 72;
int blockY = 0;
int frameCount = 0;

extern(C) void start() {
  setPalette(15921906, 8172356, 2389319, 1776411);
}

extern(C) void update() {
  int input = readGamepad();
  if (input & 16) { blockX = blockX - 4; }
  if (input & 32) { blockX = blockX + 4; }
  if (input & 1) { blockY = blockY + 8; }
  if (blockX < 0) { blockX = 0; }
  if (blockX > 144) { blockX = 144; }

  frameCount = frameCount + 1;
  if (frameCount == 12) {
    blockY = blockY + 8;
    frameCount = 0;
  }
  if (blockY > 136) { blockY = 0; }

  setDrawColors(1);
  rect(0, 0, 160, 160);
  setDrawColors(4);
  for (int x = 0; x < 160; x = x + 16) {
    rect(x, 144, 15, 15);
  }
  setDrawColors(3);
  rect(blockX, blockY, 15, 15);
  rect(blockX + 16, blockY, 15, 15);
  rect(blockX, blockY + 16, 15, 15);
  rect(blockX + 16, blockY + 16, 15, 15);
}
