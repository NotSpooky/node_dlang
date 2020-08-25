// When loading is done, functions registered as MainFunction on D side will
// execute automatically.
// In this example, the function onStart will be executed.
const nativeModule = require ('./module.node');
const assert = require('assert');

// napi_values (from N-API library) are automatically converted to JS.
assert (nativeModule.returnsNapiValue () == 78);
assert (nativeModule.duplicateAnInteger (60) == 120);

// Other types are automatically casted:
assert (nativeModule.returnsInt () == 900);

const res = nativeModule.returnsDouble ();
// Not using equals because floating point operations can be lossy.
assert (res > 30.50 && res < 30.51);

assert (nativeModule.concatText("Hello there!", "General kenobi") == "Hello there!\nGeneral kenobi");

// If you want to use pseudo globals such as require, they might not be accesible
// from 'global' in D. So the easiest way usually is to send the function as an
// argument.
assert (nativeModule.useRequire (require) == ":D");

// Sending a callback to D
assert (nativeModule.receivesCallback (() => 5) == 40);

// On JS side, D static functions, delegates and function pointers are handled the same:
var nativeStaticFun = nativeModule.returnsCallbackStaticFun ();
assert (nativeStaticFun (2) == 4);

var nativeFP = nativeModule.returnsCallbackFP ();
assert (nativeFP (5) == 8);

var nativeDg = nativeModule.returnsCallbackDg (4);
assert (nativeDg () == 20);

// Example sending strongly typed data (JSObj):
// Note: On D side this object is also printed.
assert (nativeModule.withJSObj ({ someIntValue: 45, someIntFun: () => 60 }) == 15);

// Example sending algebraic typed (data can be one of several strongly typed options)
// or potentially absent data:
var received = nativeModule.withVariantTypes ({intStringProp: "Hello"});
assert (received.intStringProp == 7);
assert (received.maybeUint == 5);

// Example sending weakly typed (without a signature on the D side) data.
// This can be either achieved with raw N-API napi_vales like some examples above,
// or the more convenient and high level JSVar like here.
var someObj = {
  someProp: {
    someFunCall: (numToDup) => numToDup * 2
  }
};
assert (nativeModule.withJSVar (someObj) == 42);

console.log ('All tests passed!');
