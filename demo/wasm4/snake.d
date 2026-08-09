// A D port of the core mechanics in WASM-4's official Snake tutorial.
// The game state, input handling, collision, and drawing all run in the cart.

int[400] snakeX;
int[400] snakeY;
int snakeLength;
int directionX;
int directionY;
int fruitX;
int fruitY;
int moveClock;
int gameOver;
int previousInput;

void resetGame() {
  snakeLength = 3;
  snakeX[0] = 10;
  snakeY[0] = 10;
  snakeX[1] = 9;
  snakeY[1] = 10;
  snakeX[2] = 8;
  snakeY[2] = 10;
  directionX = 1;
  directionY = 0;
  fruitX = 15;
  fruitY = 10;
  moveClock = 0;
  gameOver = 0;
}

void moveFruit() {
  fruitX = fruitX + 7;
  if (fruitX >= 20) { fruitX = fruitX - 20; }
  fruitY = fruitY + 11;
  if (fruitY >= 20) { fruitY = fruitY - 20; }
}

void readDirection(int input) {
  if (input & 16) {
    if (directionX != 1) { directionX = -1; directionY = 0; }
  }
  if (input & 32) {
    if (directionX != -1) { directionX = 1; directionY = 0; }
  }
  if (input & 64) {
    if (directionY != 1) { directionX = 0; directionY = -1; }
  }
  if (input & 128) {
    if (directionY != -1) { directionX = 0; directionY = 1; }
  }
}

void moveSnake() {
  for (int i = snakeLength - 1; i > 0; i = i - 1) {
    snakeX[i] = snakeX[i - 1];
    snakeY[i] = snakeY[i - 1];
  }

  snakeX[0] = snakeX[0] + directionX;
  snakeY[0] = snakeY[0] + directionY;
  if (snakeX[0] < 0) { snakeX[0] = 19; }
  if (snakeX[0] >= 20) { snakeX[0] = 0; }
  if (snakeY[0] < 0) { snakeY[0] = 19; }
  if (snakeY[0] >= 20) { snakeY[0] = 0; }
}

void checkCollision() {
  for (int i = 1; i < snakeLength; i = i + 1) {
    if (snakeX[0] == snakeX[i]) {
      if (snakeY[0] == snakeY[i]) { gameOver = 1; }
    }
  }
}

void checkFruit() {
  if (snakeX[0] == fruitX) {
    if (snakeY[0] == fruitY) {
      if (snakeLength < 400) { snakeLength = snakeLength + 1; }
      moveFruit();
    }
  }
}

void drawGame() {
  setDrawColors(1);
  rect(0, 0, 160, 160);

  setDrawColors(4);
  rect(fruitX * 8 + 1, fruitY * 8 + 1, 6, 6);

  setDrawColors(3);
  for (int i = snakeLength - 1; i > 0; i = i - 1) {
    rect(snakeX[i] * 8 + 1, snakeY[i] * 8 + 1, 6, 6);
  }
  setDrawColors(2);
  rect(snakeX[0] * 8 + 1, snakeY[0] * 8 + 1, 6, 6);

  if (gameOver) {
    setDrawColors(4);
    rect(24, 68, 112, 24);
    setDrawColors(1);
    rect(28, 72, 104, 16);
  }
}

extern(C) void start() {
  setPalette(15790335, 10444734, 4276545, 1387333);
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

  readDirection(input);
  previousInput = input;
  moveClock = moveClock + 1;
  if (moveClock >= 8) {
    moveClock = 0;
    moveSnake();
    checkCollision();
    checkFruit();
  }
  drawGame();
}
