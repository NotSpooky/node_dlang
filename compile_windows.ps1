C:\tools\ldc2-1.22.0-windows-x64\bin\ldc2.exe example.d src/dlang_node.d src/node_api.d src/js_native_api.d src/js_native_api_types.d .\src\node_version.d -mtriple=x86_64-windows-msvc -lib
mv example.lib build/example.lib
cp windows_binding.gyp binding.gyp
node-gyp.cmd configure build
mv ./build/Release/module.node ..
