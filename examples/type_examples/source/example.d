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

bool invertBool (bool toInvert) { return !toInvert; }

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

auto duplicateArray (int [] toDuplicate) {
  import std.algorithm;
  import std.array;
  return toDuplicate.map!`a * 2`.array;
}

// Note: TypedArrays must keep their data alive on D's side.
auto typedArrayData = [2f, 3f, 5.5f];
auto returnsTypedArray () {
  return TypedArray!float (typedArrayData);
}

// You can receive callbacks with delegates.
auto receivesCallback (int delegate () getSomeInt) {
  int calledFromJS = getSomeInt ();
  return calledFromJS * 8;
}

// Callbacks can be static functions, function pointers or delegates

// Function pointers and static functions don't need any special handling.
int staticFun (int toDup) {
  return toDup * 2;
}
auto returnsCallbackStaticFun () {
  return &staticFun;
}

auto returnsCallbackFP () {
  return function (int foo) { return foo + 3; };
}

// In the delegate case a pointer to the delegate must be returned and it must
// be kept alive while JS uses it.
// Be careful when assigning the delegate in javascript, especially for async
// functions, as not having a D reference to the pointer would allow D's GC to
// collect it.
// Here it's stored globally so that it isn't collected while D is alive. 
extern (D) int delegate () savedDgRef;
auto returnsCallbackDg (int foo) {
  // LDC doesn't implicitly cast this extern (D) delegate to extern (C), so
  // I declared savedDgRef as extern (D).
  savedDgRef = delegate () { return foo * 5; };
  return & savedDgRef;
}

// If you need to use NodeJS pseudo globals and aren't using something like
// electron, the easiest way is receiving the function from JS.
napi_value useRequire (napi_value delegate (string path) require) {
  return require ("./example_required.js");
}

struct SomeJSObj_ {
  int someIntValue;
  int someIntFun ();
}

long withJSObj (SomeJSObj foo) {
  // JSObj also adds convenience functions such as jsLog:
  foo.jsLog ();
  return foo.someIntFun () - foo.someIntValue;
}

struct SubStruct {
  wstring someText;
}
struct EagerlyConverted {
  uint someNum;
  SubStruct subStruct;
}

// Note, as this is eagerly evaluated, it's not recommended to receive structs
// with lots of fields if you are only going to use a few of them.
// In that case it's better to receive a JSObj.
auto withStruct (EagerlyConverted val) {
  return EagerlyConverted (
    (val.someNum / 2)
    , SubStruct (val.subStruct.someText ~ `hey`)
  );
}

// JSObjs and JSVars can be nested inside other JSObjs.
struct Internal_ {
  uint value1;
  JSVar value2;
}
alias Internal = JSObj!Internal_;
struct Nested_ {
  Internal nested;
}
alias Nested = JSObj!Nested_;

uint withNestedJSObj (Nested nestedJSObj) {
  auto internal = nestedJSObj.nested;
  return internal.value1 + cast (uint) internal.value2;
}

// We use JSObj to declare strongly typed JS objects.
alias SomeJSObj = JSObj!SomeJSObj_;

struct WithReassignableFun_ {
  string function () someStringFun;
}
alias WithReassignableFun = JSObj!WithReassignableFun_;

string newFun () { return `world`; }
void reassignFun (WithReassignableFun toEdit) {
  // Do note that function pointers become delegates when using them
  // as they need some internal context for the conversion.
  // That behavior is transparent for the user.
  assert (toEdit.someStringFun () == `Hello`);
  toEdit.someStringFun = &newFun;
}

struct ScopedJSObjEx_ {
  int foo;
}
alias ScopedType = ScopedJSObj!ScopedJSObjEx_;
auto withScopedJSObj (ScopedType val) {
  return val.foo + 2;
}

import std.typecons : Nullable, nullable;
import std.variant : Algebraic;
struct VariantTypes_ {
  Algebraic! (int, string) intStringProp;
  Nullable!uint maybeUint;
}
alias VariantTypes = JSObj!VariantTypes_;

VariantTypes withVariantTypes (VariantTypes data) {
  try {
  // To get from Algebraics, the type must be specified:
  assert (data.intStringProp!string == "Hello");
  // Undefined and nulls from JS become nulls here.
  assert (data.maybeUint.isNull ());
  data.maybeUint = Nullable!uint (5); // Can also use .nullable
  // Algebraics can be set like this
  data.intStringProp = 6;
  // Or this:
  // But this way is more verbose and internally slower.
  data.intStringProp = Algebraic! (int, string) (7);
  return data;
  } catch (Exception ex) {
    writeln (ex);
    return data;
  }
}

auto withJSVar (JSVar weaklyTyped) {
  // Fields are accesed with ["name"] syntax and have D type JSVar too.
  // Functions are called with normal funcall syntax
  assert (cast (int) (weaklyTyped.someOtherFun ()) == 20);
  return weaklyTyped [`someProp`].someFunCall (21);
}

// You can convert objects to/from AAs.
auto usingAAs (int [string] input) {
  string [string] toRet;
  foreach (key, value; input) {
    toRet [value.to!string] = key;
  }
  return toRet;
}

struct SomeJSClass_ {
  int someVal;
  // Constructors are declared with void return type but actually return a
  // JSObj of this struct.
  void constructor (int someVal);
}
alias SomeJSClass = JSObj!SomeJSClass_;

auto withConstructor (SomeJSClass asJSObj, JSVar asJSVar) {
  auto objInstance = asJSObj.constructor (2);
  auto varInstance = asJSVar.constructor (2);
  assert (objInstance.someVal == 2);
  return varInstance;
}

auto makePromise (napi_env env) {
  auto toRet = Promise (env);
  toRet.resolve (200);
  return toRet;
}

immutable dConstVal = 800;

// This mixin is needed to register the functions for JS usage
// Functions marked with MainFunction aren't registered, if you need that
// behavior add them both as MainFunction!funName and just funName
mixin exportToJs!(
  MainFunction!onStart
  , returnsNapiValue
  , invertBool
  , duplicateAnInteger
  , concatText
  , duplicateArray
  , returnsTypedArray
  , useRequire
  , returnsInt
  , returnsDouble
  , receivesCallback
  , returnsCallbackStaticFun
  , returnsCallbackFP
  , returnsCallbackDg
  , withJSObj
  , withStruct
  , withNestedJSObj
  , withScopedJSObj
  , reassignFun
  , withVariantTypes
  , withJSVar
  , usingAAs
  , withConstructor
  , makePromise
  , dConstVal
);
