import node_dlang;
import std.stdio;
import std.conv;
extern (C):

// If you want to execute functions when the module is loaded, they must be
// void (napi_env) and added using MainFunction!functionName to the exportToJs
// template mixin
void onStart (napi_env env) {
  writeln (`Loaded D native library`);
}

// Functions that have void return type in get undefined on JS side.
void voidFunction () {}

// Functions that have napi_value return type (which is a type from N-API)
// don't have the return type casted.
// If you want to do operations on napi_values you'll usually need the N-API
// environment. You can get it by adding a napi_env parameter as first parameter.
// In that case, the environment is automatically added, you don't have to send
// an extra arg from JS.
// That means this function is called from JS as `doSomething ()`;
napi_value returnsNapiValue (napi_env env) {
  // If you want to cast a value to napi_value use toNapiValue:
  return toNapiValue (78, env);
}

// Functions that receive napi_value as args, don't cast their input.
int duplicateAnInteger (napi_env env, napi_value toDuplicate) {
  // fromNapi allows you to cast 'napi_value's to D types.
  return fromNapi!int (env, toDuplicate) * 2;
}

// Functions that return types different than napi_value are automatically casted.
int returnsInt () {
  return 900;
}

double returnsDouble () {
  return 30.505;
}

// There's automatic conversion from/to string and wstring (not dstrings).
// However they might have different performance profiles. Probably wstrings are
// faster because JS seems to use UTF-16
wstring concatText (string firstText, wstring secondText) {
  return firstText.to!wstring ~ '\n' ~ secondText;
}

// You can receive callbacks with delegates.
auto receiveCallback (int delegate () getSomeInt) {
  int calledFromJS = getSomeInt ();
  return calledFromJS * 8;
}

// TODO: Send callbacks

// If you need to use NodeJS pseudo globals and aren't using something like
// electron, the easiest way is receiving the function from JS.
napi_value useRequire (napi_value delegate (string path) require) {
  return require ("./example_required.js");
}

struct Console_ {
  void function (napi_value toLog) log;
}

// We use JSObj to declare strongly typed JS objects.
alias Console = JSObj!Console_;

// Note: In practice, you don't need to receive a Console object from a JS parameter
// as you can get it using 'global' instead
long withJSObj (Console console) {
  console.log (console.context ()); // Log itself for this example
  return 600L;
}

import std.typecons : Nullable, nullable;
import std.variant : Algebraic;
struct VariableTypes_ {
  Algebraic!(int, string) intStringProp;
  Nullable!uint maybeUint;
}
alias VariableTypes = JSObj!VariableTypes_;

VariableTypes withVariableTypes (VariableTypes data) {
  // To get from Algebraics, the type must be specified:
  assert (data.intStringProp!string == "Hello");
  // Undefined and nulls from JS become nulls here.
  assert (data.maybeUint.isNull ());
  data.maybeUint = Nullable!uint (5); // Can also use .nullable
  // Algebraics can be set like this
  data.intStringProp = 6;
  // Or this:
  // But this way is more verbose and internally slower.
  data.intStringProp = Algebraic!(int, string) (7);
  return data;
}

// This mixin is needed to register the functions for JS usage
// Functions marked with MainFunction aren't registered, if you need that
// behavior add them both as MainFunction!funName and just funName
mixin exportToJs!(
  MainFunction!onStart
  , returnsNapiValue
  , duplicateAnInteger
  , concatText
  , useRequire
  , returnsInt
  , returnsDouble
  , receiveCallback
  , withJSObj
  , withVariableTypes
);
