echo "Compiling D files with LDC"
ldc example.d src/*.d --lib --singleobj --od=build --of=build/dfiles.o &&
  echo "Compiling and linking with GCC" &&
  gcc src/module.c build/dfiles.o -shared -O3 -I/usr/include/node -o build/module.node -L "usr/lib" -lphobos2-ldc-debug -ldruntime-ldc-debug &&
  echo "Success, moving to target"
  mv ./build/module.node ~/Programming/wasmgame-electron/ --force
