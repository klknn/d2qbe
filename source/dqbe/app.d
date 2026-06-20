module dqbe.app;

import core.stdc.stdio;
import core.stdc.stdlib;

import dqbe.tokenize;
import dqbe.parse;
import dqbe.codegen;
extern (C) FILE* get_stdin();
extern (C) FILE* get_stdout();
extern (C) FILE* get_stderr();

extern (C)
int main(int argc, char** argv) {
  // Read all inputs from stdin
  int capacity = 4 * 1024 * 1024; // 4MB starting capacity
  char* buf = cast(char*) malloc(capacity);
  if (!buf) {
    fprintf(get_stderr(), "Out of memory allocating input buffer\n");
    return 1;
  }
  
  int len = 0;
  while (true) {
    int read_bytes = cast(int) fread(buf + len, 1, 4096, get_stdin());
    if (read_bytes == 0) {
      break;
    }
    len = len + read_bytes;
    if (len + 4096 >= capacity) {
      capacity = capacity * 2;
      buf = cast(char*) realloc(buf, capacity);
      if (!buf) {
        fprintf(get_stderr(), "Out of memory reallocating input buffer\n");
        return 1;
      }
    }
  }
  buf[len] = '\0';
  
  token = tokenize(buf);
  parse_program();
  gen_program(get_stdout());
  
  free(buf);
  return 0;
}
