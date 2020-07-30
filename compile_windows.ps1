node-gyp.cmd clean 
C:\tools\ldc2-1.22.0-windows-x64\bin\ldc2.exe example.d src/dlang_node.d src/node_api.d src/js_native_api.d src/js_native_api_types.d .\src\node_version.d -mtriple=x86_64-windows-msvc -lib --of=build/example.lib
Copy-Item -Path windows_binding.gyp -Destination binding.gyp -Force
node-gyp.cmd configure build
Move-Item -Path ./build/Release/module.node -Destination ../node_example -Force
