import core.stdc.stddef;

public import js_native_api_types;
import node_version;
extern (C):

// Building native module against node

alias uint32_t = uint;
struct uv_loop_s; // Forward declaration.
struct napi_async_context__;
struct napi_async_work__;
struct napi_callback_scope__;
struct napi_threadsafe_function__;
struct napi_callback_info__;
alias napi_async_work = napi_async_work__*;
alias napi_async_context = napi_async_context__*;
alias napi_callback_scope = napi_callback_scope__*;
alias napi_threadsafe_function = napi_threadsafe_function__*;
alias napi_async_execute_callback = void function (napi_env env, void* data);
alias napi_async_complete_callback = void function (napi_env env,
                                             napi_status status,
                                             void* data);
alias napi_threadsafe_function_call_js = void function (napi_env env,
                                                 napi_value js_callback,
                                                 void* context,
                                                 void* data);
enum napi_threadsafe_function_release_mode {
  napi_tsfn_release,
  napi_tsfn_abort
}
enum napi_threadsafe_function_call_mode {
  napi_tsfn_nonblocking,
  napi_tsfn_blocking
}
struct napi_node_version {
  uint32_t major;
  uint32_t minor;
  uint32_t patch;
  const char* release;
}

alias napi_addon_register_func = napi_value__* function (
    napi_env env,
    napi_value exports);

struct napi_module
{
    int nm_version;
    uint nm_flags;
    const(char)* nm_filename;
    napi_addon_register_func nm_register_func;
    const(char)* nm_modname;
    void* nm_priv;
    void*[4] reserved;
}

enum NAPI_MODULE_VERSION = 1;

alias NAPI_MODULE_INITIALIZER_X = NAPI_MODULE_INITIALIZER_X_HELPER;

extern (D) string NAPI_MODULE_INITIALIZER_X_HELPER(T0, T1)(auto ref T0 base, auto ref T1 version_)
{
    import std.conv : to;

    return to!string(base) ~ to!string(version_);
}

/+
    int nm_version;
    uint nm_flags;
    const(char)* nm_filename;
    napi_addon_register_func nm_register_func;
    const(char)* nm_modname;
    void* nm_priv;
    void*[4] reserved;

extern (D) auto NAPI_MODULE_X (
  const(char*) modname
  , napi_addon_register_func regfunc
  , void* priv
  , uint flags
) {
  return napi_module (
    NAPI_MODULE_VERSION
    , flags
    , __FILE__
    , regfunc
    , modname
    , priv
  );
  // TODO: NAPI_C_CTOR
  /+
    NAPI_C_CTOR(_register_ ## modname) {                              \
      napi_module_register(&_module);                                 \
    }                                                                 \
  +/
}

extern (D) auto NAPI_MODULE(
  const (char*) modname
  , napi_addon_register_func regfunc
) {
  return NAPI_MODULE_X (modname, regfunc, null, 0);
}

enum NAPI_MODULE_INITIALIZER_BASE = NODE_MODULE_VERSION;

enum NAPI_MODULE_INITIALIZER = NAPI_MODULE_INITIALIZER_X(NAPI_MODULE_INITIALIZER_BASE, NAPI_MODULE_VERSION);

+/
void napi_module_register (napi_module* mod);

void napi_fatal_error (
    const(char)* location,
    size_t location_len,
    const(char)* message,
    size_t message_len);

// Methods for custom handling of async operations
napi_status napi_async_init (
    napi_env env,
    napi_value async_resource,
    napi_value async_resource_name,
    napi_async_context* result);

napi_status napi_async_destroy (napi_env env, napi_async_context async_context);

napi_status napi_make_callback (
    napi_env env,
    napi_async_context async_context,
    napi_value recv,
    napi_value func,
    size_t argc,
    const(napi_value)* argv,
    napi_value* result);

// Methods to provide node::Buffer functionality with napi types
napi_status napi_create_buffer (
    napi_env env,
    size_t length,
    void** data,
    napi_value* result);
napi_status napi_create_external_buffer (
    napi_env env,
    size_t length,
    void* data,
    napi_finalize finalize_cb,
    void* finalize_hint,
    napi_value* result);
napi_status napi_create_buffer_copy (
    napi_env env,
    size_t length,
    const(void)* data,
    void** result_data,
    napi_value* result);
napi_status napi_is_buffer (napi_env env, napi_value value, bool* result);
napi_status napi_get_buffer_info (
    napi_env env,
    napi_value value,
    void** data,
    size_t* length);

// Methods to manage simple async operations
napi_status napi_create_async_work (
    napi_env env,
    napi_value async_resource,
    napi_value async_resource_name,
    napi_async_execute_callback execute,
    napi_async_complete_callback complete,
    void* data,
    napi_async_work* result);
napi_status napi_delete_async_work (napi_env env, napi_async_work work);
napi_status napi_queue_async_work (napi_env env, napi_async_work work);
napi_status napi_cancel_async_work (napi_env env, napi_async_work work);

// version management
napi_status napi_get_node_version (
    napi_env env,
    const(napi_node_version*)* version_);

// Return the current libuv event loop for a given environment
napi_status napi_get_uv_event_loop (napi_env env, uv_loop_s** loop);

// NAPI_VERSION >= 2

napi_status napi_fatal_exception (napi_env env, napi_value err);

napi_status napi_add_env_cleanup_hook (
    napi_env env,
    void function (void* arg) fun,
    void* arg);

napi_status napi_remove_env_cleanup_hook (
    napi_env env,
    void function (void* arg) fun,
    void* arg);

napi_status napi_open_callback_scope (
    napi_env env,
    napi_value resource_object,
    napi_async_context context,
    napi_callback_scope* result);

napi_status napi_close_callback_scope (
    napi_env env,
    napi_callback_scope scope_);

// NAPI_VERSION >= 3

// Calling into JS from other threads
napi_status napi_create_threadsafe_function (
    napi_env env,
    napi_value func,
    napi_value async_resource,
    napi_value async_resource_name,
    size_t max_queue_size,
    size_t initial_thread_count,
    void* thread_finalize_data,
    napi_finalize thread_finalize_cb,
    void* context,
    napi_threadsafe_function_call_js call_js_cb,
    napi_threadsafe_function* result);

napi_status napi_get_threadsafe_function_context (
    napi_threadsafe_function func,
    void** result);

napi_status napi_call_threadsafe_function (
    napi_threadsafe_function func,
    void* data,
    napi_threadsafe_function_call_mode is_blocking);

napi_status napi_acquire_threadsafe_function (napi_threadsafe_function func);

napi_status napi_release_threadsafe_function (
    napi_threadsafe_function func,
    napi_threadsafe_function_release_mode mode);

napi_status napi_unref_threadsafe_function (
    napi_env env,
    napi_threadsafe_function func);

napi_status napi_ref_threadsafe_function (
    napi_env env,
    napi_threadsafe_function func);
// __wasm32__

// NAPI_VERSION >= 4

// SRC_NODE_API_H_
