cp linux_binding.gyp binding.gyp
ldc src/example.d src/dlang_node.d src/node_api.d src/js_native_api.d src/js_native_api_types.d src/node_version.d --lib -of src/example.a &&
  node-gyp configure build && 
  mv build/Release/module.node ~/Programming/wasmgame-electron/ 
