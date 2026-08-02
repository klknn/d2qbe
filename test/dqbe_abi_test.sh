#!/bin/bash
set -e

DQBE=${DQBE:-./dqbe}
ARCH=$(uname -m)
BIN=tmp_dqbe_abi

if [ "$OS" = "Windows_NT" ]; then
  BIN=tmp_dqbe_abi.exe
fi

case "$ARCH" in
  arm64|aarch64)
    PARAMS="w %a, w %b, w %c, w %d, w %e, w %f, w %g, w %h, w %i"
    ARGS="w 1, w 2, w 3, w 4, w 5, w 6, w 7, w 8, w 9"
    RESULT=9
    ;;
  x86_64|amd64)
    PARAMS="w %a, w %b, w %c, w %d, w %e, w %f, w %g"
    ARGS="w 1, w 2, w 3, w 4, w 5, w 6, w 7"
    RESULT=7
    ;;
  *)
    echo "Skipping dqbe ABI stack-argument test on unsupported host: $ARCH"
    exit 0
    ;;
esac

trap 'rm -f tmp_dqbe_abi.s tmp_dqbe_abi tmp_dqbe_abi.exe' EXIT

{
  printf 'export function w $last(%s) {\n' "$PARAMS"
  printf '@start\n'
  if [ "$RESULT" = 7 ]; then
    printf '  ret %%g\n'
  else
    printf '  ret %%i\n'
  fi
  printf '}\n'
  printf 'export function w $main() {\n'
  printf '@start\n'
  printf '  %%result =w call $last(%s)\n' "$ARGS"
  printf '  ret %%result\n'
  printf '}\n'
} | "$DQBE" > tmp_dqbe_abi.s

cc -o "$BIN" tmp_dqbe_abi.s
set +e
./"$BIN"
ACTUAL=$?
set -e

if [ "$ACTUAL" -ne "$RESULT" ]; then
  echo "FAILED: expected stack-passed argument $RESULT, got $ACTUAL"
  exit 1
fi

{
  printf 'export function w $last_float(s %%a, s %%b, s %%c, s %%d, s %%e, s %%f, s %%g, s %%h, s %%i) {\n'
  printf '@start\n'
  printf '  %%answer =w stosi %%i\n'
  printf '  ret %%answer\n'
  printf '}\n'
  printf 'export function w $main() {\n'
  printf '@start\n'
  printf '  %%a =s copy s_1\n'
  printf '  %%b =s copy s_2\n'
  printf '  %%c =s copy s_3\n'
  printf '  %%d =s copy s_4\n'
  printf '  %%e =s copy s_5\n'
  printf '  %%f =s copy s_6\n'
  printf '  %%g =s copy s_7\n'
  printf '  %%h =s copy s_8\n'
  printf '  %%i =s copy s_9\n'
  printf '  %%result =w call $last_float(s %%a, s %%b, s %%c, s %%d, s %%e, s %%f, s %%g, s %%h, s %%i)\n'
  printf '  ret %%result\n'
  printf '}\n'
} | "$DQBE" > tmp_dqbe_abi.s

cc -o "$BIN" tmp_dqbe_abi.s
set +e
./"$BIN"
ACTUAL=$?
set -e

if [ "$ACTUAL" -ne 9 ]; then
  echo "FAILED: expected stack-passed float argument 9, got $ACTUAL"
  exit 1
fi

echo "PASS: dqbe preserves stack-passed integer and float ABI arguments"
