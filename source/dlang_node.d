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

alias ExternD(T) = SetFunctionAttributes!(T, "D", functionAttributes!T);
alias ExternC(T) = SetFunctionAttributes!(T, "C", functionAttributes!T);

// Note: func must be alive.
auto jsFunction (napi_env env, napi_value func, ExternD!(void delegate ())* toRet) {
  napi_value global;
  napi_status status = napi_get_global(env, &global);
  if (status != napi_status.napi_ok) return status;
  *toRet = () {
    immutable argCount = 0;
    napi_value [argCount] args;
    size_t argCountMut = argCount;
    napi_value returned;
    napi_call_function (env, global, func, argCountMut, args.ptr, &returned);
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
  napi_value context;
  napi_value [FunPositions.length] funs;
  napi_ref ctxRef = null;

  enum typeMsg = `JSObj template args should be pairs of strings with types`;
  static assert (Funs.length % 2 == 0, typeMsg);

  private void fillFuns () {
    static foreach (i, FunPosition; FunPositions) {
      static assert (is (typeof (Funs [FunPosition]) == string), typeMsg);
      funs [i] = context.p (env, Funs [FunPosition]);
    }
  }

  this (napi_env env) {
    this.env = env;
    auto status = napi_create_object (env, &context);
    assert (status == napi_status.napi_ok);
    ctxRef = reference (env, context);
    fillFuns ();
  }
  // Assigning from a JS object.
  this (napi_env env, napi_value context) {
    this.env = env;
    this.context = context;
    // Keep alive. Note this will NEVER be GC'ed
    ctxRef = reference (env, context);
    fillFuns ();
  }
  
  this(ref return scope JSobj!Funs rhs) {
    // writeln (`Copying ` ~ Funs.stringof);
    this.env = rhs.env;
    this.context = rhs.context;
    this.funs = rhs.funs;
    this.ctxRef = rhs.ctxRef;
    if (ctxRef != null) {
      auto status = napi_reference_ref (env, ctxRef, null);
      //writeln (`> Ref count is `, currentRefCount);
      assert (status == napi_status.napi_ok);
    }
  }
  ~this () {
    /+import std.stdio;
    writeln ("Destructing JSobj " ~ Funs.stringof);+/
    uint currentRefCount;
    if (ctxRef != null) {
      auto status = napi_reference_unref (env, ctxRef, null);
      assert (
        status == napi_status.napi_ok
        , `Got status when doing unref ` ~ status.to!string
      );
      //writeln (`< Ref count is `, currentRefCount);
    }
  }
  static foreach (i, FunPosition; FunPositions) {
      // Add function that simply uses callNapi.
      mixin (q{
        napi_value } ~ Funs [FunPosition] ~ q{
          (Parameters!(Funs [FunPosition + 1]) args) {
            return callNapi (env, context, funs [i], args);
          }
        }
      );
  }
  static foreach (i, FieldPosition; FieldPositions) {
    // Setter.
    enum FieldName = Funs [FieldPosition];
    mixin (q{
      void } ~ FieldName ~ q{ (Funs [FieldPosition + 1] toSet) {
        auto asNapi = toSet.toNapiValue (env);
        auto propName = FieldName.toStringz;
        napi_set_named_property (env, this.context, propName, asNapi);
      }
    });
    // Getter.
    mixin (q{
      auto } ~ FieldName ~ q{ () {
        return fromNapi!(Funs [FieldPosition + 1]) (
          env,
          this
            .context
            .p (env, FieldName)
        );
      }
    });
  }
}

alias Console = JSobj!(
  `log`, void function (string str)
);

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
    // TODO: Throw JS exception instead.
    throw new Exception (`Expected string arg`);
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

T fromNapi (T, string argName = ``)(napi_env env, napi_value value) {
  T toRet;
  static if (is (T == double)) {
    alias cv = napi_get_value_double;
  } else static if (is (T == int)) {
    alias cv = napi_get_value_int32;
  } else static if (is (T == uint)) {
    alias cv = napi_get_value_uint32;
  } else static if (is (T == long)) {
    alias cv = napi_get_value_int64;
  } else static if (is (T == ulong)) {
    alias cv = napi_get_value_uint64;
  } else static if (is (T == string)) {
    alias cv = getStr;
  } else static if (is (T == napi_value)) {
    alias cv = napiIdentity;
  } else static if (is (T == void delegate ())) {
    alias cv = jsFunction;
  } else static if (__traits(isSame, TemplateOf!(T), JSobj)) {
    alias cv = getJSobj;
  } else {
    static assert (0, `Not implemented: Convertion from JS type for ` ~ T.stringof);
  }
  auto status = cv (env, value, &toRet);
  if (status != napi_status.napi_ok) {
    napi_throw_error (env, null, `Failed to parse ` ~ argName ~ ` to ` ~ T.stringof);
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

template toNapi (T) {
  static if (is (T == double)) {
    alias toNapi = napi_create_double;
  } else static if (is (T == int)) {
    alias toNapi = napi_create_int32;
  } else static if (is (T == uint)) {
    alias toNapi = napi_create_uint32;
  } else static if (is (T == long)) {
    alias toNapi = napi_create_int64;
  } else static if (is (T == ulong)) {
    alias toNapi = napi_create_uint64;
  } else static if (is (T == string)) {
    alias toNapi = stringToNapi;
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

napi_value toNapiValue (napi_env env) {
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
                  return toNapiValue (env); // Return undefined to JS.
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
        status = napi_set_named_property(env, exports, fnName.toStringz, fn);
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
  
  import core.sys.windows.windows;
  import core.sys.windows.dll;
  extern (C) pragma(crt_constructor) export __gshared void _register_NAPI_MODULE_NAME () {
    import core.runtime;
    Runtime.initialize ();
    napi_module_register (&_module);
  }
}
