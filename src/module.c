#include <node_api.h>

/*
napi_value exportToJs(napi_env env, napi_value exports);
NAPI_MODULE(NODE_GYP_MODULE_NAME, exportToJs)
*/
extern napi_module _module;

/*
static void _register_NODE_GYP_MODULE_NAME(void) __attribute__((constructor));
static void _register_NODE_GYP_MODULE_NAME(void) {
  napi_module_register(&_module);
}
*/
