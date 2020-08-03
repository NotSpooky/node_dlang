extern void (_register_NAPI_MODULE_NAME)(void);
#pragma section(".CRT$XCU", read)
__declspec(dllexport, allocate(".CRT$XCU")) void(* _register_NAPI_MODULE_NAME_)(void) = _register_NAPI_MODULE_NAME;