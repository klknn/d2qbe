// A dependency-free D port inspired by Shigeki Karita's wasm4-puyo.
// It deliberately replaces the original env.rand dependency with nextColor().

int[72] board;
int[72] marks;
int markNumber;
int pairAX;
int pairAY;
int pairBX;
int pairBY;
int pairAColor;
int pairBColor;
int colorSeed;
int frameClock;
int previousInput;
int gameOver;
int score;
int chain;

int cellIndex(int x, int y) {
  return y * 6 + x;
}

int isFree(int x, int y) {
  if (x < 0) { return 0; }
  if (x >= 6) { return 0; }
  if (y < 0) { return 0; }
  if (y >= 12) { return 0; }
  if (board[cellIndex(x, y)] != 0) { return 0; }
  return 1;
}

int nextColor() {
  colorSeed = colorSeed + 1;
  if (colorSeed > 3) { colorSeed = 1; }
  return colorSeed + 1;
}

void newPair() {
  pairAX = 2;
  pairAY = 0;
  pairBX = 3;
  pairBY = 0;
  pairAColor = nextColor();
  pairBColor = nextColor();
  if (isFree(pairAX, pairAY) == 0) { gameOver = 1; }
  if (isFree(pairBX, pairBY) == 0) { gameOver = 1; }
}

void resetGame() {
  for (int i = 0; i < 72; i = i + 1) {
    board[i] = 0;
    marks[i] = 0;
  }
  markNumber = 0;
  colorSeed = 0;
  frameClock = 0;
  previousInput = 0;
  gameOver = 0;
  score = 0;
  chain = 0;
  newPair();
}

int canMove(int dx, int dy) {
  if (isFree(pairAX + dx, pairAY + dy) == 0) { return 0; }
  if (isFree(pairBX + dx, pairBY + dy) == 0) { return 0; }
  return 1;
}

void movePair(int dx, int dy) {
  if (canMove(dx, dy)) {
    pairAX = pairAX + dx;
    pairAY = pairAY + dy;
    pairBX = pairBX + dx;
    pairBY = pairBY + dy;
  }
}

void rotatePair() {
  int dx = pairBX - pairAX;
  int dy = pairBY - pairAY;
  int nextX = pairAX - dy;
  int nextY = pairAY + dx;
  if (isFree(nextX, nextY)) {
    pairBX = nextX;
    pairBY = nextY;
  }
}

int flood(int x, int y, int color, int id) {
  if (x < 0) { return 0; }
  if (x >= 6) { return 0; }
  if (y < 0) { return 0; }
  if (y >= 12) { return 0; }
  int index = cellIndex(x, y);
  if (board[index] != color) { return 0; }
  if (marks[index] == id) { return 0; }
  marks[index] = id;
  return 1 + flood(x - 1, y, color, id) + flood(x + 1, y, color, id) +
    flood(x, y - 1, color, id) + flood(x, y + 1, color, id);
}

int clearGroups() {
  int total = 0;
  for (int y = 0; y < 12; y = y + 1) {
    for (int x = 0; x < 6; x = x + 1) {
      int index = cellIndex(x, y);
      int color = board[index];
      if (color != 0) {
        markNumber = markNumber + 1;
        int count = flood(x, y, color, markNumber);
        if (count >= 4) {
          for (int i = 0; i < 72; i = i + 1) {
            if (marks[i] == markNumber) { board[i] = 0; }
          }
          total = total + count;
        }
      }
    }
  }
  return total;
}

void applyGravity() {
  for (int x = 0; x < 6; x = x + 1) {
    int writeY = 11;
    for (int y = 11; y >= 0; y = y - 1) {
      int index = cellIndex(x, y);
      if (board[index] != 0) {
        int color = board[index];
        board[cellIndex(x, writeY)] = color;
        if (writeY != y) { board[index] = 0; }
        writeY = writeY - 1;
      }
    }
    for (int y = writeY; y >= 0; y = y - 1) {
      board[cellIndex(x, y)] = 0;
    }
  }
}

void resolveBoard() {
  chain = 0;
  int cleared = clearGroups();
  while (cleared > 0) {
    chain = chain + 1;
    score = score + cleared * chain * 10;
    applyGravity();
    cleared = clearGroups();
  }
}

void lockPair() {
  board[cellIndex(pairAX, pairAY)] = pairAColor;
  board[cellIndex(pairBX, pairBY)] = pairBColor;
  resolveBoard();
  newPair();
}

void fallPair() {
  if (canMove(0, 1)) {
    movePair(0, 1);
  } else {
    lockPair();
  }
}

void drawCell(int x, int y, int color) {
  setDrawColors(color);
  rect(56 + x * 8 + 1, 32 + y * 8 + 1, 6, 6);
}

void drawGame() {
  setDrawColors(1);
  rect(0, 0, 160, 160);
  setDrawColors(4);
  rect(52, 28, 56, 100);
  setDrawColors(1);
  rect(54, 30, 52, 96);

  for (int y = 0; y < 12; y = y + 1) {
    for (int x = 0; x < 6; x = x + 1) {
      int color = board[cellIndex(x, y)];
      if (color != 0) { drawCell(x, y, color); }
    }
  }
  if (gameOver == 0) {
    drawCell(pairAX, pairAY, pairAColor);
    drawCell(pairBX, pairBY, pairBColor);
  } else {
    setDrawColors(4);
    rect(32, 72, 96, 16);
  }
}

extern(C) void start() {
  setPalette(16772754, 10068477, 15493999, 4851576);
  resetGame();
}

extern(C) void update() {
  int input = readGamepad();
  if (gameOver) {
    if (input & 1) { resetGame(); }
    drawGame();
    previousInput = input;
    return;
  }

  int pressed = input & (input ^ previousInput);
  if (pressed & 16) { movePair(-1, 0); }
  if (pressed & 32) { movePair(1, 0); }
  if (pressed & 64) { rotatePair(); }
  previousInput = input;

  frameClock = frameClock + 1;
  int rate = 14;
  if (input & 128) { rate = 2; }
  if (frameClock >= rate) {
    frameClock = 0;
    fallPair();
  }
  drawGame();
}
