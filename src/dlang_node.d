pragma(LDC_no_moduleinfo);
import node_api;
import js_native_api;

import std.conv : to;
import std.string : toStringz;
import std.traits;

extern (C):
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

alias ExternC(T) = SetFunctionAttributes!(T, "C", functionAttributes!T);
alias ExternD(T) = SetFunctionAttributes!(T, "D", functionAttributes!T);

// Note: env must be alive when calling the function.
auto jsFunction (napi_env env, napi_value func, ExternD!(void delegate ())* toRet) {
  *toRet = () {
    napi_value global;
    napi_status status = napi_get_global(env, &global);
    if (status != napi_status.napi_ok) return;
    immutable argCount = 0;
    napi_value [argCount] args;
    size_t argCountMut = argCount;
    napi_value returned;
    napi_call_function (env, global, func, argCountMut, args.ptr, &returned);
  };
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
  } else {
    static assert (0, `Not implemented: Convertion from JS type for ` ~ T.stringof);
  }
  auto status = cv (env, value, &toRet);
  if (status != napi_status.napi_ok) {
    napi_throw_error (env, null, `Failed to parse ` ~ argName ~ ` to ` ~ T.stringof);
  }
  return toRet;
}

napi_value toNapiValue (F)(
  F toCast, napi_env env
) {
  napi_value toRet;
  auto status = toNapi!F(env, toCast, &toRet);
  if (status != napi_status.napi_ok) {
    napi_throw_error(env, null, "Unable to create return value");
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

  template ReturnsNapiValue (alias Function) {
    enum ReturnsNapiValue = is (ReturnType!Function == napi_value);
  }
  template WrappedFunctionName (alias Function) {
    enum WrappedFunctionName = `dlangnapi_` ~ Function.mangleof;
  }
  static foreach (Function; Functions) {
    // If the function doesn't manually return a napi_value, create a function
    // that casts to napi_value.
    static if (! ReturnsNapiValue!Function) {
      // Create a function that casts the D type to JS one.
      // That will be the function actually added to exports.
      mixin (`napi_value ` ~ WrappedFunctionName!Function
          ~ q{ (napi_env env, napi_callback_info info) {
          return fromJs!Function (env, info).toNapiValue (env);
        }; }
      );
    }
  }
  napi_value exportToJs (napi_env env, napi_value exports) {
    auto addFunction (alias Function)() {
      napi_status status;
      napi_value fn;
      static if (ReturnsNapiValue!Function) {
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
