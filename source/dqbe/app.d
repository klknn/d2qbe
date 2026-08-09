module dqbe.app;

import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.string;

import dqbe.tokenize;
import dqbe.parse;
import dqbe.codegen;
import dqbe.wasm : emit_wasm_program, set_wasm4_profile;
extern (C) FILE* get_stdin();
extern (C) FILE* get_stdout();
extern (C) FILE* get_stderr();

import dqbe.regalloc : init_regalloc;

extern (C)
int main(int argc, char** argv) {
  fprintf(get_stderr(), "DEBUG_APP_START: dqbe is starting!\n");
  bool target_wasm32 = false;
  bool target_wasm4 = false;

  // Parse command line arguments
  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "-mtriple") == 0 || strcmp(argv[i], "--mtriple") == 0 ||
        strcmp(argv[i], "-target") == 0 || strcmp(argv[i], "--target") == 0) {
      if (i + 1 < argc) {
        char* triple = argv[i + 1];
        i++;
        
        // Parse arch
        if (strstr(triple, "wasm4")) {
          target_wasm32 = true;
          target_wasm4 = true;
        } else if (strstr(triple, "wasm32")) {
          target_wasm32 = true;
        } else if (strstr(triple, "x86_64") || strstr(triple, "amd64")) {
          target_arch = TargetArch.X86_64;
        } else if (strstr(triple, "aarch64") || strstr(triple, "arm64")) {
          target_arch = TargetArch.ARM64;
        } else {
          fprintf(get_stderr(), "Warning: Unknown architecture in triple '%s', defaulting to x86_64\n", triple);
          target_arch = TargetArch.X86_64;
        }
        
        // Parse OS
        if (strstr(triple, "windows") || strstr(triple, "win32") || strstr(triple, "mingw") || strstr(triple, "msvc")) {
          target_os = TARGET_OS_WINDOWS;
          target_apple = false;
        } else if (strstr(triple, "apple") || strstr(triple, "darwin")) {
          target_os = TARGET_OS_SYSV;
          target_apple = true;
        } else {
          target_os = TARGET_OS_SYSV;
          target_apple = false;
        }
      } else {
        fprintf(get_stderr(), "Error: Missing argument for %s\n", argv[i]);
        return 1;
      }
    } else if (strcmp(argv[i], "-t") == 0) {
      if (i + 1 < argc) {
        char* qbe_target = argv[i + 1];
        i++;
        
        if (strcmp(qbe_target, "wasm4") == 0) {
          target_wasm32 = true;
          target_wasm4 = true;
        } else if (strcmp(qbe_target, "wasm") == 0 || strcmp(qbe_target, "wasm32") == 0) {
          target_wasm32 = true;
        } else if (strcmp(qbe_target, "amd64_sysv") == 0) {
          target_arch = TargetArch.X86_64;
          target_os = TARGET_OS_SYSV;
          target_apple = false;
        } else if (strcmp(qbe_target, "amd64_apple") == 0) {
          target_arch = TargetArch.X86_64;
          target_os = TARGET_OS_SYSV;
          target_apple = true;
        } else if (strcmp(qbe_target, "amd64_windows") == 0 || strcmp(qbe_target, "amd64_win") == 0) {
          target_arch = TargetArch.X86_64;
          target_os = TARGET_OS_WINDOWS;
          target_apple = false;
        } else if (strcmp(qbe_target, "arm64") == 0) {
          target_arch = TargetArch.ARM64;
          target_os = TARGET_OS_SYSV;
          target_apple = false;
        } else if (strcmp(qbe_target, "arm64_apple") == 0) {
          target_arch = TargetArch.ARM64;
          target_os = TARGET_OS_SYSV;
          target_apple = true;
        } else if (strcmp(qbe_target, "arm64_windows") == 0 || strcmp(qbe_target, "arm64_win") == 0) {
          target_arch = TargetArch.ARM64;
          target_os = TARGET_OS_WINDOWS;
          target_apple = false;
        } else {
          fprintf(get_stderr(), "Error: Unknown QBE target '%s'\n", qbe_target);
          return 1;
        }
      } else {
        fprintf(get_stderr(), "Error: Missing argument for -t\n");
        return 1;
      }
    } else {
      fprintf(get_stderr(), "Error: Unknown argument '%s'\n", argv[i]);
      return 1;
    }
  }
  if (!target_wasm32) init_regalloc();
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
  int result = 0;
  if (target_wasm32) {
    set_wasm4_profile(target_wasm4);
    if (!emit_wasm_program(get_stdout())) result = 1;
  } else {
    gen_program(get_stdout());
  }
  
  free(buf);
  return result;
}
