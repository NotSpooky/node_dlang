echo "Compiling D files with LDC"
ldc --shared example.d ./src/*d --of="$HOME/Programming/wasmgame-electron/module.node"
