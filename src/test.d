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

auto MyFunction(napi_env env, napi_callback_info info) {
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
  /+
  import core.runtime;
  rt_init();
  +/
  return 0.toNapiValue (env);
}

napi_value testoDesu (napi_env env, napi_callback_info info) {
  return MyFunction(env, info).toNapiValue (env);
}

napi_value module_init(napi_env env, napi_value exports) {
  napi_status status;
  napi_value fn;

  status = napi_create_function(env, null, 0, &testoDesu, null, &fn);
  if (status != napi_status.napi_ok) {
    napi_throw_error(env, null, "Unable to wrap native function");
  }

  status = napi_set_named_property(env, exports, "my_function", fn);
  if (status != napi_status.napi_ok) {
    napi_throw_error(env, null, "Unable to populate exports (my_function)");
  }

  status = napi_create_function(env, null, 0, &initialize, null, &fn);
  if (status != napi_status.napi_ok) {
    napi_throw_error(env, null, "Unable to wrap native function");
  }
  status = napi_set_named_property(env, exports, "initialize", fn);
  if (status != napi_status.napi_ok) {
    napi_throw_error(env, null, "Unable to populate exports (initialize)");
  }
  return exports;
}

// enum NODE_GYP_MODULE_NAME = "module";
// extern (C) export auto _module = NAPI_MODULE(NODE_GYP_MODULE_NAME.ptr, &Init);
