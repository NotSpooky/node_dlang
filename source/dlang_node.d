module dlang_node;
version (LDC) {
  pragma(LDC_no_moduleinfo);
}
public import js_native_api_types : napi_env;
import node_api;
import js_native_api;

import std.conv : to;
import std.string : toStringz;
import std.traits;
debug import std.stdio;

napi_status stringToNapi (napi_env env, string toCast, napi_value * toRet) {
  return napi_create_string_utf8 (env, toCast.ptr, toCast.length, toRet);
}

auto napiIdentity (napi_env _1, napi_value value, napi_value * toRet) {
  *toRet = value;
  return napi_status.napi_ok;
}

alias ExternD (T) = SetFunctionAttributes!(T, "D", functionAttributes!T);
alias ExternC (T) = SetFunctionAttributes!(T, "C", functionAttributes!T);

// If the first argument to the delegate (in other words, R) is a napi_value
// that is used as the context.
// Otherwise the global context is used.
auto jsFunction (R)(napi_env env, napi_value func, R * toRet) {
  alias Params = Parameters!R;
  *toRet = (Params args) {
    static if (args.length > 0 && is (Params [0] == napi_value)) {
      // Use provided context.
      napi_value context = args [0];
      enum firstArgPos = 1;
    } else {
      napi_value context;
      auto status = napi_get_global (env, &context);
      assert (status == napi_status.napi_ok);
      enum firstArgPos = 0;
    }
    napi_value [args.length - firstArgPos] napiArgs;
    static foreach (i, arg; args [firstArgPos..$]) {
      napiArgs [i] = arg.toNapiValue (env);
    }
    napi_value returned;
    status = napi_call_function (
      env
      , context
      , func
      , napiArgs.length
      , napiArgs.ptr
      , &returned
    );
    writeln (`Got status `, status);
    if (status != napi_status.napi_ok) throw new Exception (`Call errored`);
    
    alias RetType = ReturnType!R;
    static if (!is (RetType == void)) {
      return fromNapi!RetType (env, returned);
    }
  };
  return napi_status.napi_ok;
}

auto reference (napi_env env, napi_value obj) {
  napi_ref toRet;
  auto status = napi_create_reference (env, obj, 1, &toRet);
  if (status != napi_status.napi_ok) throw new Exception (`Reference creation failed`);
  return toRet;
}
// Note this might escape values out of scope
auto val (napi_env env, napi_ref reference) {
  napi_value toRet;
  auto status = napi_get_reference_value (env, reference, &toRet);
  if (status != napi_status.napi_ok) throw new Exception (`Could not get value from reference`);
  assert (toRet != null);
  return toRet;
}

// Will assume void ret for now
auto callNapi (Args ...)(napi_env env, napi_value context, napi_value func, Args args) {
  napi_value [args.length] napiArgs;
  static foreach (i, arg; args) {
    napiArgs [i] = arg.toNapiValue (env);
  }
  napi_value returned;
  auto status = napi_call_function (env, context, func, args.length, napiArgs.ptr, &returned);
  debug {
    stderr.writeln (`Call errored, got `, status);
  }
  if (status != napi_status.napi_ok) throw new Exception (`Call errored`);
  return returned;
}

// Get a property.
auto p (RetType = napi_value) (napi_value obj, napi_env env, string propName) {
  napi_value toRet;
  auto key = propName.toNapiValue (env);
  auto status = napi_get_property (env, obj, key, &toRet);
  if (status != napi_status.napi_ok) {
    throw new Exception (`Failed to get property ` ~ propName);
  }
  return toRet;
}

// Example:
// JSobj!(`multByTwo`, int function (int input), `printNum`, void function (int i))
// Creates a struct with methods multByTwo and printNum of the respective types.
struct JSobj (Funs...) {

  private static auto positions () {
    size_t [] funPositions;
    size_t [] fieldPositions;
    static foreach (i; 0 .. Funs.length / 2) {
      static if (isFunctionPointer!(Funs [1 + i * 2])) {
        funPositions ~= i * 2;
      } else {
        fieldPositions ~= i * 2;
      }
    }
    import std.typecons : tuple;
    return tuple!(`funPositions`, `fieldPositions`) (funPositions, fieldPositions);
  }
  private enum Positions = positions ();
  private enum FunPositions = Positions.funPositions;
  private enum FieldPositions = Positions.fieldPositions;

  napi_env env;
  napi_ref ctxRef = null;

  enum typeMsg = `JSObj template args should be pairs of strings with types`;
  static assert (Funs.length % 2 == 0, typeMsg);

  // Creating a new object
  this (napi_env env) {
    this.env = env;
    auto context = new napi_value ();
    auto status = napi_create_object (env, context);
    assert (status == napi_status.napi_ok);
    ctxRef = reference (env, *context);
  }

  // Assigning from a JS object.
  this (napi_env env, napi_value context) {
    this.env = env;
    // Keep alive. Note this will NEVER be GC'ed
    ctxRef = reference (env, context);
  }
  
  this (ref return scope JSobj!Funs rhs) {
    // writeln (`Copying ` ~ Funs.stringof);
    this.env = rhs.env;
    this.ctxRef = rhs.ctxRef;
    if (ctxRef != null) {
      auto status = napi_reference_ref (env, ctxRef, null);
      //writeln (`> Ref count is `, currentRefCount);
      assert (status == napi_status.napi_ok);
    }
  }
  ~this () {
    // writeln ("Destructing JSobj " ~ Funs.stringof);
    // uint currentRefCount;
    if (ctxRef != null) {
      auto status = napi_reference_unref (env, ctxRef, null);
      assert (
        status == napi_status.napi_ok
        , `Got status when doing unref ` ~ status.to!string
      );
      //writeln (`< Ref count is `, currentRefCount);
    }
  }
  
  auto context () {
    return val (env, this.ctxRef);
  }

  static foreach (i, FunPosition; FunPositions) {
      // Add function that simply uses callNapi.
      mixin (q{
        napi_value } ~ Funs [FunPosition] ~ q{
          (Parameters!(Funs [FunPosition + 1]) args) {
            auto context = val (env, this.ctxRef);
            auto toCall = context.p (env, Funs [FunPosition]);
            return callNapi (env, context, toCall, args);
          }
        }
      );
  }
  static foreach (i, FieldPosition; FieldPositions) {
    // Setter.
    mixin (q{
      void } ~ Funs [FieldPosition] ~ q{ (Funs [FieldPosition + 1] toSet) {
        auto asNapi = toSet.toNapiValue (env);
        auto propName = Funs [FieldPosition].toStringz;
        auto context = val (env, this.ctxRef);
        napi_set_named_property (env, context, propName, asNapi);
      }
    });
    // Getter.
    mixin (q{
      auto } ~ Funs [FieldPosition] ~ q{ () {
        return fromNapi!(Funs [FieldPosition + 1]) (
          env,
          val (env, this.ctxRef).p (env, Funs [FieldPosition])
        );
      }
    });
  }
}

alias Console = JSobj!(
  `log`, void function (string str)
);

auto global (napi_env env, string name) {
  napi_value val;
  auto status = napi_get_global (env, &val);
  assert (status == napi_status.napi_ok);
  return val;
}

auto getJSobj (T)(napi_env env, napi_value ctx, T * toRet) {
  assert (toRet != null);
  *toRet = T (env, ctx);
  return napi_status.napi_ok;
}

auto getStr (napi_env env, napi_value napiVal, string * toRet) {
  // Try with statically allocated buffer for small strings
  char [2048] inBuffer;
  assert (toRet != null);
  size_t readChars = 0;
  auto status = napi_get_value_string_utf8 (
    env
    , napiVal
    , inBuffer.ptr
    , inBuffer.length
    , & readChars
  );
  if (status != napi_status.napi_ok) {
    return status;
  }
  
  if (readChars == inBuffer.length - 1) {
    // String bigger than buffer :( need a dynamic array.
    // Technically this is not needed for the specific case of
    // exactly size inBuffer.length - 1
    // Get string size to allocate an array.
    status = napi_get_value_string_utf8 (
      env
      , napiVal
      , null
      , 0
      , & readChars
    );
    assert (status == napi_status.napi_ok);
    // Try again with bigger size.
    auto buffer = new char [readChars + 1]; // include null terminator
    status = napi_get_value_string_utf8 (
      env
      , napiVal
      , buffer.ptr
      , buffer.length
      , & readChars
    );
    assert (status == napi_status.napi_ok);
    *toRet = buffer.ptr [0..readChars].to!string;
  } else {
    *toRet = inBuffer.ptr [0..readChars].to!string;
  }
  return napi_status.napi_ok;
}

auto getFloat (napi_env env, napi_value napiVal, float * toRet) {
  double intermediate;
  auto status = napi_get_value_double (env, napiVal, &intermediate);
  *toRet = intermediate.to!float;
  return status;
}

template fromNapiB (T) {
  static if (is (T == bool)) {
    alias fromNapiB = napi_get_value_bool;
  } else static if (is (T == double)) {
    alias fromNapiB = napi_get_value_double;
  } else static if (is (T == int)) {
    alias fromNapiB = napi_get_value_int32;
  } else static if (is (T == uint)) {
    alias fromNapiB = napi_get_value_uint32;
  } else static if (is (T == long)) {
    alias fromNapiB = napi_get_value_int64;
  } else static if (is (T == ulong)) {
    alias fromNapiB = napi_get_value_uint64;
  } else static if (is (T == double)) {
    alias fromNapiB = napi_get_value_double;
  } else static if (is (T == float)) {
    alias fromNapiB = getFloat;
  } else static if (is (T == string)) {
    alias fromNapiB = getStr;
  } else static if (is (T == Nullable!A, A)) {
    alias fromNapiB = getNullable!A;
  } else static if (is (T == napi_value)) {
    alias fromNapiB = napiIdentity;
  } else static if (isCallable!T) {
  //} else static if (is (T == R delegate (), R)) {
    alias fromNapiB = jsFunction;
  } else static if (__traits(isSame, TemplateOf!(T), JSobj)) {
    alias fromNapiB = getJSobj;
  } else {
    static assert (0, `Not implemented: Convertion from JS type for ` ~ T.stringof);
  }
}

napi_status getNullable (BaseType) (
  napi_env env
  , napi_value value
  , Nullable!BaseType * toRet
) {
  /+
  auto erroredToJS = () => napi_throw_error (
    env, null, `Failed to parse to ` ~ Nullable!BaseType.stringof
  );
  +/
  BaseType toRetNonNull;
  auto status = fromNapiB!BaseType (env, value, &toRetNonNull);
  if (status != napi_status.napi_ok) {
    /+debug {
      import std.stdio;
      writeln (
        `Got status `, status, ` when trying to convert to `, Nullable!BaseType.stringof
      );
    }+/
    *toRet = Nullable!BaseType ();
  } else {
    *toRet = Nullable!BaseType (toRetNonNull);
  }
  return napi_status.napi_ok;
}

import std.typecons : Nullable;
T fromNapi (T, string argName = ``)(napi_env env, napi_value value) {
  T toRet;
  auto erroredToJS = () => napi_throw_error (
    env, null, `Failed to parse ` ~ argName ~ ` to ` ~ T.stringof
  );
  try {
    auto status = fromNapiB!T (env, value, &toRet);
    if (status != napi_status.napi_ok) {
      erroredToJS ();
    }
  } catch (Exception ex) {
    erroredToJS ();
  }
  return toRet;
}

void throwInJS (napi_env env, string message) {
  napi_throw_error (env, null, message.toStringz);
}

napi_status arrayToNapi (F)(napi_env env, F[] array, napi_value * toRet) {
  napi_status status = napi_status.napi_generic_failure;
  assert (toRet != null);
  status = napi_create_array_with_length (env, array.length, toRet);
  if (status != napi_status.napi_ok) {
    return status;
  }
  foreach (i, val; array) {
    // Create a napi_value for 'hello'
    auto nv = val.toNapiValue(env);

    status = napi_set_element(env, *toRet, i.to!uint, nv);
    if (status != napi_status.napi_ok) return status;
  }
  return status;
}

napi_status jsObjToNapi (T ...)(napi_env env, JSobj!T toConvert, napi_value * toRet) {
  assert (toRet != null);
  assert (env == toConvert.env);
  *toRet =  toConvert.context;
  return napi_status.napi_ok;
}

auto nullableToNapi (T) (napi_env env, Nullable!T toConvert, napi_value * toRet) {
  if (toConvert.isNull ()) {
    return napi_get_null (env, toRet);
  } else {
    return toNapi!T (env, toConvert.get (), toRet);
  }
}

template toNapi (T) {
  static if (is (T == bool)) {
    alias toNapi = napi_create_bool;
  } static if (is (T == double)) {
    alias toNapi = napi_create_double;
  } else static if (is (T == int)) {
    alias toNapi = napi_create_int32;
  } else static if (is (T == uint)) {
    alias toNapi = napi_create_uint32;
  } else static if (is (T == long)) {
    alias toNapi = napi_create_int64;
  } else static if (is (T == ulong)) {
    alias toNapi = napi_create_uint64;
  } else static if (is (T : double)) {
    alias toNapi = napi_create_double;
  } else static if (is (T == string)) {
    alias toNapi = stringToNapi;
  } else static if (is (T == napi_value)) {
    alias toNapi = napiIdentity;
  } else static if (is (T == Nullable!A, A)) {
    alias toNapi = nullableToNapi!A;
  } else static if (is (T == A[], A)) {
    alias toNapi = arrayToNapi;
  } else static if (__traits(isSame, TemplateOf!T, JSobj)) {
    alias toNapi = jsObjToNapi;
  } else {
    static assert (0, `Not implemented: Conversion to JS type for ` ~ T.stringof);
  }
}

napi_value toNapiValue (F)(
  F toCast, napi_env env
) {
  napi_value toRet;
  auto status = toNapi!F(env, toCast, &toRet);
  if (status != napi_status.napi_ok) {
    env.throwInJS (`Unable to create JS value for: ` ~ toCast.to!string);
  }
  return toRet;
}

napi_value undefined (napi_env env) {
  napi_value toRet;
  if (napi_get_undefined (env, &toRet) != napi_status.napi_ok) {
    env.throwInJS (`Unable to return void (undefined in JS)`);
  }
  return toRet;
}

auto fromJs (alias Function) (napi_env env, napi_callback_info info) {
  alias FunParams = Parameters!Function;
  static if (FunParams.length > 0 && is (FunParams [0] == napi_env)) {
    immutable argCount = FunParams.length - 1;
    // First parameter is the env, which is from the 'env' param in fromJs.
    // Thus it isn't stored as an napi_value.
    enum envParam = `env, `;
    enum firstValParam = 1;
  } else {
    immutable argCount = FunParams.length;
    enum envParam = ``;
    enum firstValParam = 0;
  }
  napi_value [argCount] argVals;
  size_t argCountMut = argCount;
  auto status = napi_get_cb_info (env, info, &argCountMut, argVals.ptr, null, null);
  if (status != napi_status.napi_ok) {
    napi_throw_type_error (
      env
      , null
      , (`Failed to parse arguments for function ` ~ Function.mangleof ~ `, incorrect amount?`).toStringz
    );
  }
  static foreach (i, Param; FunParams [firstValParam .. $]) {
    // Create a temporary value with the casted data.
    mixin (`auto param` ~ i.to!string ~ ` = fromNapi!Param (env, argVals [i]);`);
  }
  // Now call Function with each of these casted values.
  import std.range;
  import std.algorithm;
  enum paramCalls = envParam ~ iota (argCount)
    .map!`"param" ~ a.to!string`
    .joiner (`,`)
    .to!string;
  mixin (`return Function (` ~ paramCalls ~ `);`);
}

extern (C) alias void func (napi_env);
template MainFunction (alias Function) {
  alias ToCall = Function;
  //pragma (msg, ExternD!(typeof (Function)).stringof);
  static assert (
    is (ExternC! (typeof (Function)) == func)
    , `MainFunction must be instantiated with a void function (napi_env)`
  );
}

bool isMainFunction (alias Function) () if (isCallable!Function) {
  return false;
}
import std.meta;
bool isMainFunction (alias Function) () if (!isCallable!Function) {
  assert (__traits (isSame, TemplateOf!(Function), MainFunction));
  return true;
}

mixin template exportToJs (Functions ...) {
  import node_api;
  import js_native_api;
  import std.string : toStringz;

  template Returns (alias Function, OtherType) {
    import std.traits : ReturnType;
    enum Returns = is (ReturnType!Function == OtherType);
  }
  template WrappedFunctionName (alias Function) {
    enum WrappedFunctionName = `dlangnapi_` ~ Function.mangleof;
  }
  static foreach (Function; Functions) {
    static if (! (isMainFunction!Function ())) {
      // If the function doesn't manually return a napi_value, create a function
      // that casts to napi_value.
      static if (! Returns! (Function, napi_value)) {
        // Create a function that casts the D type to JS one.
        // That will be the function actually added to exports.

        mixin (`extern (C) napi_value ` ~ WrappedFunctionName!Function
            ~ `(napi_env env, napi_callback_info info) {`
          ~ (Returns! (Function, void) // Check whether function returns or not.
              // This version returns a napi_value with undefined.
              ? q{
                  fromJs!Function (env, info);
                  return undefined (env);
                }
              // This version casts the returned D value to an napi_value
              : q{
                  return fromJs!Function (env, info).toNapiValue (env);
                }
            )
          ~ `}`
        );
      }
    }
  }
  extern (C) napi_value exportToJs (napi_env env, napi_value exports) {
    import core.runtime;
    Runtime.initialize ();
    auto addFunction (alias Function)() {
      napi_status status;
      napi_value fn;
      static if (Returns! (Function, napi_value)) {
        alias FunToBind = Function;
      } else {
        // Use wrapper made above whose function returns a napi_value
        mixin (`alias FunToBind = ` ~ WrappedFunctionName!Function ~ `;`);
      }
      status = napi_create_function (env, null, 0, &FunToBind, null, &fn);
      if (status != napi_status.napi_ok) {
        napi_throw_error(env, null, "Unable to wrap native function");
      } else {
        const fnName = Function.mangleof;
        status = napi_set_named_property (env, exports, fnName.toStringz, fn);
        if (status != napi_status.napi_ok) {
          napi_throw_error (
            env
            , null
            , ("Unable to populate exports for " ~ fnName).toStringz
          );
        }
      }
      return status;
    }
    static foreach (Function; Functions) {
      static if (isMainFunction!Function ()) {
        // Just call it.
        Function.ToCall (env);
      } else {
        if (addFunction!Function () != napi_status.napi_ok) {
          return exports;
        } 
      }
    }
    return exports;
  }

  // From the C macros that register the module.

  extern (C) static __gshared napi_module _module = {
    1  // nm_version
    , 0 // nm_flags
    , __FILE__.ptr
    , &.exportToJs
    , "NODE_GYP_MODULE_NAME"
    , null
  };
  
  version (Windows) { version (DigitalMars) {
    void main () {} // Dunno why it's needed but whatever
  }}

  extern (C) pragma(crt_constructor) export __gshared void _register_NAPI_MODULE_NAME () {
    napi_module_register (&_module);
  }
}
