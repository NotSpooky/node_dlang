pragma(LDC_no_moduleinfo);
import node_api;
import js_native_api;

import std.conv : to;
import std.string : toStringz;
import std.traits;
debug import std.stdio;

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

napi_status stringToNapi (napi_env env, string toCast, napi_value * toRet) {
  return napi_create_string_utf8 (env, toCast.ptr, toCast.length, toRet);
}

auto napiIdentity (napi_env _1, napi_value value, napi_value * toRet) {
  *toRet = value;
  return napi_status.napi_ok;
}

alias ExternD(T) = SetFunctionAttributes!(T, "D", functionAttributes!T);

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

struct CanvasRenderingContext2D {
  napi_value delegate (double x, double y, double width, double height) drawRect;
}

struct Reference {
  // Note: Non-object types such as function don't work as expected.
  // I.e. might get the this object instead.
  @disable this ();
  napi_ref reference;
  napi_env env;
  auto this (napi_env env, napi_value obj) {
    this.env = env;
    auto status = napi_create_reference (env, obj, 1, &this.reference);
    if (status != napi_status.napi_ok) throw new Exception (`Reference creation failed`);
  }
  // Note this might escape values out of scope
  auto val () {
    napi_value toRet;
    auto status = napi_get_reference_value (env, this.reference, &toRet);
    if (status != napi_status.napi_ok) throw new Exception (`Could not get value from reference`);
    assert (toRet != null);
    return toRet;
  }
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

auto log (Args ...)(napi_env env, Args args) {
  napi_value global, console, log;
  napi_status status = napi_get_global (env, &global);
  napi_get_named_property (env, global, "console", &console);
  napi_get_named_property (env, console, "log", &log);
  callNapi (env, console, log, args);
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

auto getCanvasCtx2D (napi_env env, napi_value canvasCtx, CanvasRenderingContext2D * toRet) {
  // TODO: Free
  auto canvasCtxRef = Reference (env, canvasCtx);
  napi_value fillRect = canvasCtx.p (env, `fillRect`);
  *toRet = CanvasRenderingContext2D (
    (double x, double y, double width, double height) {
      try {
        napi_value canvasCtx = canvasCtxRef.val (); // Shadows outer.
        return callNapi (env, canvasCtx, fillRect, x, y, width, height);
      } catch (Exception ex) {
        throwInJS (env, ex.msg);
        return napi_value ();
      }
    }
  );
  return napi_status.napi_ok;
}

T fromNapi (T, string argName = ``)(napi_env env, napi_value value) {
  T toRet;
  static if (is (T == double)) {
    alias cv = napi_get_value_double;
  } else static if (is (T == int)) {
    alias cv = napi_get_value_int32;
  } else static if (is (T == long)) {
    alias cv = napi_get_value_int64;
  } else static if (is (T == napi_value)) {
    alias cv = napiIdentity;
  } else static if (is (T == void delegate ())) {
    alias cv = jsFunction;
  } else static if (is (T == CanvasRenderingContext2D)) {
    alias cv = getCanvasCtx2D;
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

template toNapi (T) {
  static if (is (T == double)) {
    alias toNapi = napi_create_double;
  } else static if (is (T == int)) {
    alias toNapi = napi_create_int32;
  } else static if (is (T == long)) {
    alias toNapi = napi_create_int64;
  } else static if (is (T == string)) {
    alias toNapi = stringToNapi;
  } else static if (is (T == A[], A)) {
    alias toNapi = arrayToNapi;
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
  immutable argCount = FunParams.length;
  napi_value [argCount] argVals;
  size_t argCountMut = argCount;
  auto status = napi_get_cb_info(env, info, &argCountMut, argVals.ptr, null, null);
  if (status != napi_status.napi_ok) {
    napi_throw_type_error (
      env
      , null
      , (`Failed to parse arguments for function ` ~ Function.mangleof ~ `, incorrect amount?`).toStringz
    );
  }
  static foreach (i, Param; FunParams) {
    // Create a temporary value with the casted data.
    mixin (`auto param` ~ i.to!string ~ ` = fromNapi!Param (env, argVals [i]);`);
  }
  // Now call Function with each of these casted values.
  import std.range;
  import std.algorithm;
  enum paramCalls = iota (argCount)
    .map!`"param" ~ a.to!string`
    .joiner (`,`)
    .to!string;
  mixin (`return Function (` ~ paramCalls ~ `);`);
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
      if (addFunction!Function () != napi_status.napi_ok) {
        return exports;
      } 
    }
    return exports;
  }
}
