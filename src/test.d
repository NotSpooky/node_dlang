pragma(LDC_no_moduleinfo);
import node_api;
import js_native_api;

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

    import std.conv : to;
    status = napi_set_element(env, *toRet, i.to!uint, nv);
    if (status != napi_status.napi_ok) return status;
  }
  return status;
}

template toNapi (F) {
  static if (is (F == double)) {
    alias toNapi = napi_create_double;
  } else static if (is (F == int)) {
    alias toNapi = napi_create_int32;
  } else static if (is (F == long)) {
    alias toNapi = napi_create_int64;
  } else static if (is (F == T[], T)) {
    alias toNapi = arrayToNapi;
  } else {
    static assert (0, `Not implemented: Conversion to JS type for ` ~ F.stringof);
  }
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

auto testoDesu(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value [1] argv;
  auto status = napi_get_cb_info(env, info, &argc, argv.ptr, null, null);

  if (status != napi_status.napi_ok) {
    napi_throw_error(env, null, "Failed to parse arguments");
  }

  int number;
  status = napi_get_value_int32(env, argv[0], &number);
  if (status != napi_status.napi_ok) {
    napi_throw_error(env, null, "Invalid number was passed as argument");
  }
  return [1, 2];
}

napi_value initialize (napi_env env, napi_callback_info info) {
  import core.runtime;
  rt_init();
  return 0.toNapiValue (env);
}

mixin template exportToJs (Functions ...) {
  template ReturnsNapiValue (alias Function) {
    enum ReturnsNapiValue = is (ReturnType!Function == napi_value);
  }
  template WrappedFunctionName (alias Function) {
    enum WrappedFunctionName = `dlangnapi_` ~ Function.mangleof;
  }
  static foreach (Function; Functions) {
    import std.traits;
    // If the function doesn't manually return a napi_value, create a function
    // that casts to napi_value.
    static if (! ReturnsNapiValue!Function) {
      // Create a function that casts the D type to JS one.
      // That will be the function actually added to exports.
      mixin (`napi_value ` ~ WrappedFunctionName!Function
          ~ q{ (napi_env env, napi_callback_info info) {
          return Function (env, info).toNapiValue (env);
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
      status = napi_create_function(env, null, 0, &FunToBind, null, &fn);
      if (status != napi_status.napi_ok) {
        napi_throw_error(env, null, "Unable to wrap native function");
      } else {
        import std.string : toStringz;
        const fnName = Function.mangleof;
        status = napi_set_named_property(env, exports, fnName.toStringz, fn);
        if (status != napi_status.napi_ok) {
          napi_throw_error(env, null, (
            "Unable to populate exports for " ~ fnName).toStringz
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

mixin exportToJs!(initialize, testoDesu);

// enum NODE_GYP_MODULE_NAME = "module";
// extern (C) export auto _module = NAPI_MODULE(NODE_GYP_MODULE_NAME.ptr, &Init);
