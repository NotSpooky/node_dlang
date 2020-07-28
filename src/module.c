#include <node_api.h>

napi_value exportToJs(napi_env env, napi_value exports);
napi_value Init(napi_env env, napi_value exports) {
  return exportToJs (env, exports);
}

NAPI_MODULE(NODE_GYP_MODULE_NAME, Init)
