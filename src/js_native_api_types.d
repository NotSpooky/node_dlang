extern (C):

// This file needs to be compatible with C compilers.
// This is a public include file, and these includes have essentially
// became part of it's API.
// NOLINT(modernize-deprecated-headers)
// NOLINT(modernize-deprecated-headers)

alias char16_t = ushort;

// JSVM API types are all opaque pointers for ABI stability
// typedef undefined structs instead of void* for compile time type safety
struct napi_env__;
alias napi_env = napi_env__*;
struct napi_value__;
alias napi_value = napi_value__*;
struct napi_ref__;
alias napi_ref = napi_ref__*;
struct napi_handle_scope__;
alias napi_handle_scope = napi_handle_scope__*;
struct napi_escapable_handle_scope__;
alias napi_escapable_handle_scope = napi_escapable_handle_scope__*;
struct napi_callback_info__;
alias napi_callback_info = napi_callback_info__*;
struct napi_deferred__;
alias napi_deferred = napi_deferred__*;

enum napi_property_attributes
{
    napi_default = 0,
    napi_writable = 1 << 0,
    napi_enumerable = 1 << 1,
    napi_configurable = 1 << 2,

    // Used with napi_define_class to distinguish static properties
    // from instance properties. Ignored by napi_define_properties.
    napi_static = 1 << 10
}

enum napi_valuetype
{
    // ES6 types (corresponds to typeof)
    napi_undefined = 0,
    napi_null = 1,
    napi_boolean = 2,
    napi_number = 3,
    napi_string = 4,
    napi_symbol = 5,
    napi_object = 6,
    napi_function = 7,
    napi_external = 8,
    napi_bigint = 9
}

enum napi_typedarray_type
{
    napi_int8_array = 0,
    napi_uint8_array = 1,
    napi_uint8_clamped_array = 2,
    napi_int16_array = 3,
    napi_uint16_array = 4,
    napi_int32_array = 5,
    napi_uint32_array = 6,
    napi_float32_array = 7,
    napi_float64_array = 8,
    napi_bigint64_array = 9,
    napi_biguint64_array = 10
}

enum napi_status
{
    napi_ok = 0,
    napi_invalid_arg = 1,
    napi_object_expected = 2,
    napi_string_expected = 3,
    napi_name_expected = 4,
    napi_function_expected = 5,
    napi_number_expected = 6,
    napi_boolean_expected = 7,
    napi_array_expected = 8,
    napi_generic_failure = 9,
    napi_pending_exception = 10,
    napi_cancelled = 11,
    napi_escape_called_twice = 12,
    napi_handle_scope_mismatch = 13,
    napi_callback_scope_mismatch = 14,
    napi_queue_full = 15,
    napi_closing = 16,
    napi_bigint_expected = 17,
    napi_date_expected = 18,
    napi_arraybuffer_expected = 19,
    napi_detachable_arraybuffer_expected = 20,
    napi_would_deadlock = 21 // unused
}

// Note: when adding a new enum value to `napi_status`, please also update
//   * `const int last_status` in the definition of `napi_get_last_error_info()'
//     in file js_native_api_v8.cc.
//   * `const char* error_messages[]` in file js_native_api_v8.cc with a brief
//     message explaining the error.
//   * the definition of `napi_status` in doc/api/n-api.md to reflect the newly
//     added value(s).

alias napi_callback = napi_value__* function (
    napi_env env,
    napi_callback_info info);
alias napi_finalize = void function (
    napi_env env,
    void* finalize_data,
    void* finalize_hint);

struct napi_property_descriptor
{
    // One of utf8name or name should be NULL.
    const(char)* utf8name;
    napi_value name;

    napi_callback method;
    napi_callback getter;
    napi_callback setter;
    napi_value value;

    napi_property_attributes attributes;
    void* data;
}

struct napi_extended_error_info
{
    const(char)* error_message;
    void* engine_reserved;
    uint engine_error_code;
    napi_status error_code;
}

// NAPI_VERSION >= 6

// SRC_JS_NATIVE_API_TYPES_H_
