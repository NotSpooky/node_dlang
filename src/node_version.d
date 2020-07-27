// Copyright Joyent, Inc. and other Node contributors.
//
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to permit
// persons to whom the Software is furnished to do so, subject to the
// following conditions:
//
// The above copyright notice and this permission notice shall be included
// in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
// OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN
// NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
// DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
// OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
// USE OR OTHER DEALINGS IN THE SOFTWARE.

extern (C):

enum NODE_MAJOR_VERSION = 14;
enum NODE_MINOR_VERSION = 5;
enum NODE_PATCH_VERSION = 0;

enum NODE_VERSION_IS_LTS = 0;
enum NODE_VERSION_LTS_CODENAME = "";

enum NODE_VERSION_IS_RELEASE = 1;

alias NODE_STRINGIFY = NODE_STRINGIFY_HELPER;

extern (D) string NODE_STRINGIFY_HELPER(T)(auto ref T n)
{
    import std.conv : to;

    return to!string(n);
}

enum NODE_RELEASE = "node";

enum NODE_TAG = "";

// NODE_TAG is passed without quotes when rc.exe is run from msbuild

enum NODE_VERSION_STRING = NODE_MAJOR_VERSION
  ~ `.` ~ NODE_MINOR_VERSION
  ~ `.` ~ NODE_PATCH_VERSION
  ~ NODE_TAG;

enum NODE_EXE_VERSION = NODE_VERSION_STRING;

extern (D) auto NODE_VERSION_AT_LEAST(T0, T1, T2)(auto ref T0 major, auto ref T1 minor, auto ref T2 patch)
{
    return (major < NODE_MAJOR_VERSION) || (major == NODE_MAJOR_VERSION && minor < NODE_MINOR_VERSION) || (major == NODE_MAJOR_VERSION && minor == NODE_MINOR_VERSION && patch <= NODE_PATCH_VERSION);
}

/**
 * Node.js will refuse to load modules that weren't compiled against its own
 * module ABI number, exposed as the process.versions.modules property.
 *
 * Node.js will refuse to load modules with a non-matching ABI version. The
 * version number here should be changed whenever an ABI-incompatible API change
 * is made in the C++ side, including in V8 or other dependencies.
 *
 * Node.js will not change the module version during a Major release line
 * We will, at times update the version of V8 shipped in the release line
 * if it can be made ABI compatible with the previous version.
 *
 * The registry of used NODE_MODULE_VERSION numbers is located at
 *   https://github.com/nodejs/node/blob/master/doc/abi_version_registry.json
 * Extenders, embedders and other consumers of Node.js that require ABI
 * version matching should open a pull request to reserve a number in this
 * registry.
 */
enum NODE_MODULE_VERSION = 83;

// The NAPI_VERSION provided by this version of the runtime. This is the version
// which the Node binary being built supports.
enum NAPI_VERSION = 6;

// SRC_NODE_VERSION_H_
