#include <node_api.h>
extern void (_register_NAPI_MODULE_NAME)(void);
__declspec(dllexport, allocate(".CRT$XCU")) void(* _register_NAPI_MODULE_NAME_)(void) = _register_NAPI_MODULE_NAME;