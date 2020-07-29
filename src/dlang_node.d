pragma(LDC_no_moduleinfo);
import node_api;
import js_native_api;

import std.conv : to;
import std.string : toStringz;
import std.traits;

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

template toNapi (T) {
  static if (is (T == double)) {
    alias toNapi = napi_create_double;
  } else static if (is (T == int)) {
    alias toNapi = napi_create_int32;
  } else static if (is (T == long)) {
    alias toNapi = napi_create_int64;
  } else static if (is (T == A[], A)) {
    alias toNapi = arrayToNapi;
  } else {
    static assert (0, `Not implemented: Conversion to JS type for ` ~ T.stringof);
  }
}

auto napiIdentity (napi_env _1, napi_value value, napi_value * toRet) {
  *toRet = value;
  return napi_status.napi_ok;
}

alias ExternD(T) = SetFunctionAttributes!(T, "D", functionAttributes!T);

// Note: env must be alive when calling the function.
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
  napi_status delegate (double x, double y, double width, double height) drawRect;
}

struct Reference {
  @disable this ();
  napi_ref reference;
  napi_env env;
  auto this (napi_env env, napi_value obj) {
    this.env = env;
    auto status = napi_create_reference (env, obj, 1, &reference);
    if (status != napi_status.napi_ok) throw new Exception (`Reference creation failed`);
  }
  // Note this might escape values out of scope
  auto val () {
    napi_value toRet;
    auto status = napi_get_reference_value (env, reference, &toRet);
    if (status != napi_status.napi_ok) throw new Exception (`Could not get value from reference`);
    assert (toRet != null);
    return toRet;
  }
}

auto getCanvasCtx2D (napi_env env, napi_value canvasCtx, CanvasRenderingContext2D * toRet) {
  // TODO: Free
  auto canvasCtxRef = Reference (env, canvasCtx);
  napi_value key;
  string keyS = `fillRect`;
  auto status = napi_create_string_utf8 (env, keyS.ptr, keyS.length, &key);
  if (status != napi_status.napi_ok) return status;
  napi_value fillRect;
  status = napi_get_property (env, canvasCtx, key, &fillRect);
  if (status != napi_status.napi_ok) return status;
  auto fillRectRef = Reference (env, canvasCtx);
  napi_value [4] args;
  args [0] = 10.0.toNapiValue (env);
  args [1] = 20.0.toNapiValue (env);
  args [2] = 30.0.toNapiValue (env);
  args [3] = 40.0.toNapiValue (env);
  *toRet = CanvasRenderingContext2D (
    (double x, double y, double width, double height) {
      napi_value canvasCtx = canvasCtxRef.val (); // Shadows outer.
      napi_value fillRect = fillRectRef.val ();
      napi_value returned;
      return napi_call_function (env, canvasCtx, fillRect, args.length, args.ptr, &returned);
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

napi_value toNapiValue (F)(
  F toCast, napi_env env
) {
  napi_value toRet;
  auto status = toNapi!F(env, toCast, &toRet);
  if (status != napi_status.napi_ok) {
    env.throwInJS (`Unable to create return value`);
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
