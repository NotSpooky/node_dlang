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

assert (nativeModule.receiveCallback (() => 5) == 40);

// Example sending weakly typed/potentially absent data.
var received = nativeModule.withVariableTypes ({intStringProp: "Hello"});
assert (received.intStringProp == 7);
assert (received.maybeUint == 5);

nativeModule.withJSObj (console);
