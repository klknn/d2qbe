// A D-only WASM-4 implementation of SameGame for d2qbe -t wasm4.
// Move the cursor with the D-pad, press Button 1 (X) to clear connected
// groups of 2+ matching tiles, and press Button 2 (Z) to deal a new board.

int[100] board;
int[100] selected;
int[100] queueX;
int[100] queueY;
int cursorX;
int cursorY;
int selectedCount;
int remainingCount;
int score;
int gameState;
int rngState;
int frameCount;
int previousInput;

int nextColor() {
  rngState = (rngState * 1664525 + 1013904223) & 2147483647;
  return ((rngState >> 8) % 3) + 1;
}

void floodSelect(int sx, int sy) {
  for (int i = 0; i < 100; i = i + 1) {
    selected[i] = 0;
  }
  selectedCount = 0;

  int startIdx = sy * 10 + sx;
  int target = board[startIdx];
  if (target == 0) {
    return;
  }

  int head = 0;
  int tail = 0;
  selected[startIdx] = 1;
  queueX[tail] = sx;
  queueY[tail] = sy;
  tail = tail + 1;

  while (head < tail) {
    int cx = queueX[head];
    int cy = queueY[head];
    head = head + 1;
    selectedCount = selectedCount + 1;

    if (cx > 0) {
      int ni = cy * 10 + (cx - 1);
      if (selected[ni] == 0) {
        if (board[ni] == target) {
          selected[ni] = 1;
          queueX[tail] = cx - 1;
          queueY[tail] = cy;
          tail = tail + 1;
        }
      }
    }
    if (cx < 9) {
      int ni = cy * 10 + (cx + 1);
      if (selected[ni] == 0) {
        if (board[ni] == target) {
          selected[ni] = 1;
          queueX[tail] = cx + 1;
          queueY[tail] = cy;
          tail = tail + 1;
        }
      }
    }
    if (cy > 0) {
      int ni = (cy - 1) * 10 + cx;
      if (selected[ni] == 0) {
        if (board[ni] == target) {
          selected[ni] = 1;
          queueX[tail] = cx;
          queueY[tail] = cy - 1;
          tail = tail + 1;
        }
      }
    }
    if (cy < 9) {
      int ni = (cy + 1) * 10 + cx;
      if (selected[ni] == 0) {
        if (board[ni] == target) {
          selected[ni] = 1;
          queueX[tail] = cx;
          queueY[tail] = cy + 1;
          tail = tail + 1;
        }
      }
    }
  }
}

void applyGravityAndShift() {
  for (int x = 0; x < 10; x = x + 1) {
    int writeY = 9;
    for (int y = 9; y >= 0; y = y - 1) {
      int val = board[y * 10 + x];
      if (val != 0) {
        board[writeY * 10 + x] = val;
        if (writeY != y) {
          board[y * 10 + x] = 0;
        }
        writeY = writeY - 1;
      }
    }
    while (writeY >= 0) {
      board[writeY * 10 + x] = 0;
      writeY = writeY - 1;
    }
  }

  int writeX = 0;
  for (int x = 0; x < 10; x = x + 1) {
    if (board[90 + x] != 0) {
      if (writeX != x) {
        for (int y = 0; y < 10; y = y + 1) {
          board[y * 10 + writeX] = board[y * 10 + x];
          board[y * 10 + x] = 0;
        }
      }
      writeX = writeX + 1;
    }
  }
}

void checkGameState() {
  int rem = 0;
  int hasMove = 0;
  for (int y = 0; y < 10; y = y + 1) {
    for (int x = 0; x < 10; x = x + 1) {
      int val = board[y * 10 + x];
      if (val != 0) {
        rem = rem + 1;
        if (x < 9) {
          if (board[y * 10 + (x + 1)] == val) {
            hasMove = 1;
          }
        }
        if (y < 9) {
          if (board[(y + 1) * 10 + x] == val) {
            hasMove = 1;
          }
        }
      }
    }
  }
  remainingCount = rem;
  if (rem == 0) {
    gameState = 2;
  } else {
    if (hasMove == 0) {
      gameState = 1;
    } else {
      gameState = 0;
    }
  }
}

void resetGame() {
  for (int i = 0; i < 100; i = i + 1) {
    board[i] = nextColor();
  }
  cursorX = 4;
  cursorY = 4;
  score = 0;
  gameState = 0;
  remainingCount = 100;
  floodSelect(cursorX, cursorY);
}

void removeSelected() {
  if (selectedCount < 2) {
    return;
  }
  for (int i = 0; i < 100; i = i + 1) {
    if (selected[i] != 0) {
      board[i] = 0;
    }
  }
  int bonus = (selectedCount - 1) * (selectedCount - 1);
  score = score + bonus;
  applyGravityAndShift();
  checkGameState();
  floodSelect(cursorX, cursorY);
}

void drawTile(int x, int y, int color, int isSelected) {
  int px = 10 + x * 14;
  int py = 14 + y * 14;

  if (isSelected != 0) {
    if (selectedCount >= 2) {
      if ((frameCount & 16) == 0) {
        setDrawColors(4);
        rect(px - 1, py - 1, 14, 14);
      }
    }
  }

  if (color == 1) {
    setDrawColors(2);
    rect(px, py, 12, 12);
    setDrawColors(1);
    rect(px + 4, py + 4, 4, 4);
  }
  if (color == 2) {
    setDrawColors(3);
    rect(px, py, 12, 12);
    setDrawColors(1);
    rect(px + 2, py + 2, 8, 8);
    setDrawColors(3);
    rect(px + 4, py + 4, 4, 4);
  }
  if (color == 3) {
    setDrawColors(4);
    rect(px, py, 12, 12);
    setDrawColors(2);
    rect(px + 2, py + 5, 8, 2);
    rect(px + 5, py + 2, 2, 8);
  }
}

void drawCursor() {
  int px = 10 + cursorX * 14;
  int py = 14 + cursorY * 14;
  setDrawColors(4);
  rect(px - 1, py - 1, 14, 2);
  rect(px - 1, py + 11, 14, 2);
  rect(px - 1, py - 1, 2, 14);
  rect(px + 11, py - 1, 2, 14);
}

void drawGame() {
  setDrawColors(1);
  rect(0, 0, 160, 160);

  // Top progress bar: cleared tile ratio out of 100 tiles.
  setDrawColors(2);
  rect(10, 3, 140, 6);
  int clearedWidth = ((100 - remainingCount) * 136) / 100;
  if (clearedWidth > 0) {
    setDrawColors(4);
    rect(12, 5, clearedWidth, 2);
  }

  for (int y = 0; y < 10; y = y + 1) {
    for (int x = 0; x < 10; x = x + 1) {
      int idx = y * 10 + x;
      int color = board[idx];
      if (color != 0) {
        drawTile(x, y, color, selected[idx]);
      }
    }
  }

  drawCursor();

  if (gameState == 1) {
    setDrawColors(4);
    rect(24, 68, 112, 24);
    setDrawColors(1);
    rect(28, 72, 104, 16);
    setDrawColors(3);
    rect(40, 78, 80, 4);
  }
  if (gameState == 2) {
    setDrawColors(4);
    rect(20, 64, 120, 32);
    setDrawColors(2);
    rect(24, 68, 112, 24);
    setDrawColors(4);
    rect(36, 76, 88, 8);
  }
}

int isPressed(int input, int mask) {
  if ((input & mask) != 0) {
    if ((previousInput & mask) == 0) {
      return 1;
    }
  }
  return 0;
}

extern(C) void start() {
  setPalette(15790335, 10444734, 4276545, 1387333);
  rngState = 1234567;
  frameCount = 0;
  previousInput = 0;
  resetGame();
}

extern(C) void update() {
  int input = readGamepad();
  frameCount = frameCount + 1;

  if (isPressed(input, 2) != 0) {
    rngState = rngState + frameCount * 17 + 31;
    resetGame();
    drawGame();
    previousInput = input;
    return;
  }

  if (gameState != 0) {
    if (isPressed(input, 1) != 0) {
      rngState = rngState + frameCount * 29 + 13;
      resetGame();
    }
    drawGame();
    previousInput = input;
    return;
  }

  int moved = 0;
  if (isPressed(input, 16) != 0) {
    cursorX = cursorX - 1;
    if (cursorX < 0) { cursorX = 9; }
    moved = 1;
  }
  if (isPressed(input, 32) != 0) {
    cursorX = cursorX + 1;
    if (cursorX > 9) { cursorX = 0; }
    moved = 1;
  }
  if (isPressed(input, 64) != 0) {
    cursorY = cursorY - 1;
    if (cursorY < 0) { cursorY = 9; }
    moved = 1;
  }
  if (isPressed(input, 128) != 0) {
    cursorY = cursorY + 1;
    if (cursorY > 9) { cursorY = 0; }
    moved = 1;
  }
  if (moved != 0) {
    floodSelect(cursorX, cursorY);
  }

  if (isPressed(input, 1) != 0) {
    removeSelected();
  }

  drawGame();
  previousInput = input;
}
