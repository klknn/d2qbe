import core.stdc.ctype;
import core.stdc.stdarg;
import core.stdc.stdio;
import core.stdc.string;
import core.stdc.stdlib;

enum TokenKind {
  reserved,
  num,
  eof,
}

struct Token {
  TokenKind kind;
  Token* next;
  int val;
  char* str;
}

Token* token;

// Reports an error like printf.
void error(const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  vfprintf(stderr, fmt, ap);
  fprintf(stderr, "\n");
  exit(1);
}

char *user_input;

void error_at(const char *loc, const char *fmt, ...) {
  // Display the error position in the line.
  int pos = cast(int) (loc - user_input);
  fprintf(stderr, "%s\n", user_input);
  for (int i = 0; i < pos; ++i) {
    fprintf(stderr, " "); // padding until pos.
  }
  // fprintf(stderr, "%*s", pos, " ");
  fprintf(stderr, "^ ");

  va_list ap;
  va_start(ap, fmt);
  vfprintf(stderr, fmt, ap);
  fprintf(stderr, "\n");
  exit(1);
}

// Consumes one token and returns true if the token is op.
bool consume(char op) {
  if (token.kind != TokenKind.reserved || token.str[0] != op) {
    return false;
  }
  token = token.next;
  return true;
}

void expect(char op) {
  if (!consume(op)) {
    error_at(token.str, "Expected token %c", op);
  }
}

int expect_number() {
  if (token.kind != TokenKind.num) {
    error_at(token.str, "Expected a number");
  }
  int val = token.val;
  token = token.next;
  return val;
}

bool at_eof() {
  return token.kind == TokenKind.eof;
}

Token* new_token(TokenKind kind, Token* cur, char* str) {
  Token* tok = cast(Token*) calloc(1, Token.sizeof);
  tok.kind = kind;
  tok.str = str;
  cur.next = tok;
  return tok;
}

Token* tokenize(char* p) {
  Token head;
  head.next = null;
  Token* cur = &head;
  while (*p) {
    if (isspace(*p)) {
      p++;
      continue;
    }
    if (*p == '+' || *p == '-') {
      cur = new_token(TokenKind.reserved, cur, p++);
      continue;
    }
    if (isdigit(*p)) {
      cur = new_token(TokenKind.num, cur, p);
      cur.val = cast(int) strtol(p, &p, 10);
      continue;
    }

    error_at(p, "Cannot tokenize.");
  }
  Token* _ = new_token(TokenKind.eof, cur, p);
  return head.next;
}

extern (C)
int main(int argc, char** argv) {
  if (argc != 2) {
    fprintf(stderr, "wrong number of args\n");
    return 1;
  }

  user_input = argv[1];
  token = tokenize(argv[1]);

  printf("export function w $main() {\n");
  printf("@main\n");
  printf("\t%%x =l alloc4 4\n"); // int;
  printf("\tstorew %d, %%x\n", expect_number()); // e.g. x = 1;
  int i = 0;
  while (!at_eof()) {
    printf("\t%%t%d =w loadw %%x\n", i);
    if (consume('+')) {
      printf("\t%%t%d =w add %%t%d, %d\n", i+1, i, expect_number());
    } else {
      expect('-');
      printf("\t%%t%d =w sub %%t%d, %d\n", i+1, i, expect_number());
    }
    i++;
    printf("\tstorew %%t%d, %%x\n", i++);
  }
  printf("\t%%t%d =w loadw %%x\n", i);
  printf("\tret %%t%d\n", i);
  printf("}\n");

  return 0;
}
