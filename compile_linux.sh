ldc src/*.d --lib --singleobj --od=build --of=build/dfiles.o &&
 gcc src/module.c build/dfiles.o -shared -O3 -I/usr/include/node -o build/module.node -L "usr/lib" -lphobos2-ldc-debug -ldruntime-ldc-debug &&
 mv ./build/module.node ~/Programming/wasmgame-electron/ --force
