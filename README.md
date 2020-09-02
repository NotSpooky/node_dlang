![Actions CI](https://github.com/NotSpooky/node_dlang/workflows/Type%20example%20test/badge.svg?branch=master)
![License](https://img.shields.io/badge/license-MIT-9cf)
# Node dlang
### **Note: This is currently in early state of development, expect breaking changes!**
Package to create native NodeJS modules based on [N-API](https://nodejs.org/api/n-api.html "N-API").
Tested on 64 bit Linux and Windows with LDC and DMD compilers.

# Requirements
Just a D compiler and DUB package manager (usually included with the compiler).
JavaScript is not necessary to generate the modules but NodeJS is needed to test the generated file.
# Usage
Create a DUB project with:
```shell
dub init
```
Assuming JSON format, add the following fields to dub.json:
```json
"dependencies": {
	"node_dlang": "*"
},
"configurations": [
	{
		"name": "example_windows",
		"platforms": ["windows"],
		"targetType": "dynamicLibrary",
		"targetPath" : ".",
		"targetName" : "module.node",
		"postGenerateCommands": ["move module.node.dll module.node"]
	}, {
		"name": "example_posix",
		"platforms": ["posix"],
		"targetName" : "module.node",
		"targetType": "dynamicLibrary",
		"postGenerateCommands": ["mv libmodule.node.so module.node"]
	}
]
```

You can check the example folder for a reference dub.json.

Compile with
```shell
dub build
```
The resulting `module.node` file can be require'd from JavaScript.

# Code example
You probably want to check the code at [examples/type\_examples](examples/type_examples).
## D side
Add at the beginning of your D file:
```d
module your_module_name;
import node_dlang;
extern (C): // We need no mangling
```
Then add your functions as normal D code (note: they are using extern (C)):
```d
auto foo (int first, long second) {
	return [first, second * 4, 0];
}

// Functions that you want executed on load must be void (napi_env)
void atStart (napi_env env) {
	import std.stdio;
	writeln ("Hello from D!");
}
```
At the end of your file use a mixin to do all the magic:
```d
// MainFunction is used to execute on load instead of registering to exports.
mixin exportToJs! (foo, MainFunction!atStart);
```
Add to exportToJs template args all the functions that you want to be able to use from JavaScript.
## Javascript side
Make sure NodeJS is installed on your system.

If you used MainFunction you can run your generated module.node directly:
```shell
node module.node
```

You can also require the module from JS.  
Example file:
```javascript
// Use relative paths if you haven't made an NPM package yet
const mymodule = require ('./module.node');
console.log (mymodule.foo (1, 3));
```
Run with
```shell
node example.js
```
