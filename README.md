# Node dlang
### **Note: This is currently in early state of development, expect breaking changes!**
Package to create native NodeJS modules based on [N-API](https://nodejs.org/api/n-api.html "N-API")
Tested on Linux and Windows with LDC compiler.

[TOCM]

# Requirements
Just a D compiler (only tested on LDC) with the DUB package manager that is usually included with the compiler.
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
dub --compiler=ldc2
```
The resulting `module.node` file can be require'd from JavaScript.

# Code example
## D side
Add at the beginning of your D file:
```d
module your_module_name;
import dlang_node;
pragma(LDC_no_moduleinfo);
extern (C):
// Needed to be able to use D's runtime features such as garbage collector
// Omission can lead to crashes.
void initialize () {
	import core.runtime;
	rt_init();
}
```
Then add your functions as normal D code (note, as they are using extern (C) they won't have mangling):
```d
auto foo(int first, long second) {
	return [first, second * 4, 0];
}
```
At the end of your file use a mixin to do all the magic:
```d
mixin exportToJs!(initialize, foo);
```
Add to exportToJs template args all the functions that you want to be able to use from JavaScript.
## Javascript side
Make sure NodeJS is installed on your system.
Example file:
```javascript
// Use relative paths if you haven't made an NPM package yet
const mymodule = require ('./module.node');
console.log(mymodule.foo(1, 3));
```
Run with
```shell
node example.js
```
