#include <node_api.h>

napi_value module_init(napi_env env, napi_value exports);
napi_value Init(napi_env env, napi_value exports) {
  return module_init (env, exports);
}

NAPI_MODULE(NODE_GYP_MODULE_NAME, Init)
