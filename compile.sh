ldc src/test.d src/node_api.d src/js_native_api.d src/js_native_api_types.d src/node_version.d --output-s -od src/ &&
  node-gyp configure build && 
  mv build/Release/module.node ~/Programming/wasmgame-electron/ 
