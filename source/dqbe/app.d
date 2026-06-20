module dqbe.app;

import core.stdc.stdio;
import core.stdc.stdlib;

import dqbe.tokenize;
import dqbe.parse;
import dqbe.codegen;

extern (C)
int main(int argc, char** argv) {
  // Read all inputs from stdin
  int capacity = 4 * 1024 * 1024; // 4MB starting capacity
  char* buf = cast(char*) malloc(capacity);
  if (!buf) {
    fprintf(stderr, "Out of memory allocating input buffer\n");
    return 1;
  }
  
  int len = 0;
  while (true) {
    int read_bytes = fread(buf + len, 1, 4096, stdin);
    if (read_bytes == 0) {
      break;
    }
    len = len + read_bytes;
    if (len + 4096 >= capacity) {
      capacity = capacity * 2;
      buf = cast(char*) realloc(buf, capacity);
      if (!buf) {
        fprintf(stderr, "Out of memory reallocating input buffer\n");
        return 1;
      }
    }
  }
  buf[len] = '\0';
  
  token = tokenize(buf);
  parse_program();
  gen_program(stdout);
  
  free(buf);
  return 0;
}
