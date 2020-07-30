import core.stdc.stdint;
import node_api;
public import js_native_api_types;
extern (C):

// This file needs to be compatible with C compilers.
// NOLINT(modernize-deprecated-headers)
// NOLINT(modernize-deprecated-headers)

// Use INT_MAX, this should only be consumed by the pre-processor anyway.
enum NAPI_VERSION_EXPERIMENTAL = 2147483647;

// The baseline version for N-API.
// The NAPI_VERSION controls which version will be used by default when
// compilling a native addon. If the addon developer specifically wants to use
// functions available in a new version of N-API that is not yet ported in all
// LTS versions, they can set NAPI_VERSION knowing that they have specifically
// depended on that version.
enum NAPI_VERSION = 6;

// If you need __declspec(dllimport), either include <node_api.h> instead, or
// define NAPI_EXTERN as __declspec(dllimport) on the compiler's command line.

enum NAPI_AUTO_LENGTH = SIZE_MAX;

napi_status napi_get_last_error_info (
    napi_env env,
    const(napi_extended_error_info*)* result);

// Getters for defined singletons
napi_status napi_get_undefined (napi_env env, napi_value* result);
napi_status napi_get_null (napi_env env, napi_value* result);
napi_status napi_get_global (napi_env env, napi_value* result);
napi_status napi_get_boolean (napi_env env, bool value, napi_value* result);

// Methods to create Primitive types/Objects
napi_status napi_create_object (napi_env env, napi_value* result);
napi_status napi_create_array (napi_env env, napi_value* result);
napi_status napi_create_array_with_length (
    napi_env env,
    size_t length,
    napi_value* result);
napi_status napi_create_double (napi_env env, double value, napi_value* result);
napi_status napi_create_int32 (napi_env env, int value, napi_value* result);
napi_status napi_create_uint32 (napi_env env, uint value, napi_value* result);
napi_status napi_create_int64 (napi_env env, long value, napi_value* result);
napi_status napi_create_string_latin1 (
    napi_env env,
    const(char)* str,
    size_t length,
    napi_value* result);
napi_status napi_create_string_utf8 (
    napi_env env,
    const(char)* str,
    size_t length,
    napi_value* result);
napi_status napi_create_string_utf16 (
    napi_env env,
    const(char16_t)* str,
    size_t length,
    napi_value* result);
napi_status napi_create_symbol (
    napi_env env,
    napi_value description,
    napi_value* result);
napi_status napi_create_function (
    napi_env env,
    const(char)* utf8name,
    size_t length,
    napi_callback cb,
    void* data,
    napi_value* result);
napi_status napi_create_error (
    napi_env env,
    napi_value code,
    napi_value msg,
    napi_value* result);
napi_status napi_create_type_error (
    napi_env env,
    napi_value code,
    napi_value msg,
    napi_value* result);
napi_status napi_create_range_error (
    napi_env env,
    napi_value code,
    napi_value msg,
    napi_value* result);

// Methods to get the native napi_value from Primitive type
napi_status napi_typeof (
    napi_env env,
    napi_value value,
    napi_valuetype* result);
napi_status napi_get_value_double (
    napi_env env,
    napi_value value,
    double* result);
napi_status napi_get_value_int32 (napi_env env, napi_value value, int* result);
napi_status napi_get_value_uint32 (
    napi_env env,
    napi_value value,
    uint* result);
napi_status napi_get_value_int64 (napi_env env, napi_value value, long* result);
napi_status napi_get_value_bool (napi_env env, napi_value value, bool* result);

// Copies LATIN-1 encoded bytes from a string into a buffer.
napi_status napi_get_value_string_latin1 (
    napi_env env,
    napi_value value,
    char* buf,
    size_t bufsize,
    size_t* result);

// Copies UTF-8 encoded bytes from a string into a buffer.
napi_status napi_get_value_string_utf8 (
    napi_env env,
    napi_value value,
    char* buf,
    size_t bufsize,
    size_t* result);

// Copies UTF-16 encoded bytes from a string into a buffer.
napi_status napi_get_value_string_utf16 (
    napi_env env,
    napi_value value,
    char16_t* buf,
    size_t bufsize,
    size_t* result);

// Methods to coerce values
// These APIs may execute user scripts
napi_status napi_coerce_to_bool (
    napi_env env,
    napi_value value,
    napi_value* result);
napi_status napi_coerce_to_number (
    napi_env env,
    napi_value value,
    napi_value* result);
napi_status napi_coerce_to_object (
    napi_env env,
    napi_value value,
    napi_value* result);
napi_status napi_coerce_to_string (
    napi_env env,
    napi_value value,
    napi_value* result);

// Methods to work with Objects
napi_status napi_get_prototype (
    napi_env env,
    napi_value object,
    napi_value* result);
napi_status napi_get_property_names (
    napi_env env,
    napi_value object,
    napi_value* result);
napi_status napi_set_property (
    napi_env env,
    napi_value object,
    napi_value key,
    napi_value value);
napi_status napi_has_property (
    napi_env env,
    napi_value object,
    napi_value key,
    bool* result);
napi_status napi_get_property (
    napi_env env,
    napi_value object,
    napi_value key,
    napi_value* result);
napi_status napi_delete_property (
    napi_env env,
    napi_value object,
    napi_value key,
    bool* result);
napi_status napi_has_own_property (
    napi_env env,
    napi_value object,
    napi_value key,
    bool* result);
napi_status napi_set_named_property (
    napi_env env,
    napi_value object,
    const(char)* utf8name,
    napi_value value);
napi_status napi_has_named_property (
    napi_env env,
    napi_value object,
    const(char)* utf8name,
    bool* result);
napi_status napi_get_named_property (
    napi_env env,
    napi_value object,
    const(char)* utf8name,
    napi_value* result);
napi_status napi_set_element (
    napi_env env,
    napi_value object,
    uint index,
    napi_value value);
napi_status napi_has_element (
    napi_env env,
    napi_value object,
    uint index,
    bool* result);
napi_status napi_get_element (
    napi_env env,
    napi_value object,
    uint index,
    napi_value* result);
napi_status napi_delete_element (
    napi_env env,
    napi_value object,
    uint index,
    bool* result);
napi_status napi_define_properties (
    napi_env env,
    napi_value object,
    size_t property_count,
    const(napi_property_descriptor)* properties);

// Methods to work with Arrays
napi_status napi_is_array (napi_env env, napi_value value, bool* result);
napi_status napi_get_array_length (
    napi_env env,
    napi_value value,
    uint* result);

// Methods to compare values
napi_status napi_strict_equals (
    napi_env env,
    napi_value lhs,
    napi_value rhs,
    bool* result);

// Methods to work with Functions
napi_status napi_call_function (
    napi_env env,
    napi_value recv,
    napi_value func,
    size_t argc,
    const(napi_value)* argv,
    napi_value* result);
napi_status napi_new_instance (
    napi_env env,
    napi_value constructor,
    size_t argc,
    const(napi_value)* argv,
    napi_value* result);
napi_status napi_instanceof (
    napi_env env,
    napi_value object,
    napi_value constructor,
    bool* result);

// Methods to work with napi_callbacks

// Gets all callback info in a single call. (Ugly, but faster.)
// [in] NAPI environment handle
// [in] Opaque callback-info handle
// [in-out] Specifies the size of the provided argv array
// and receives the actual count of args.
// [out] Array of values
// [out] Receives the JS 'this' arg for the call
napi_status napi_get_cb_info (
    napi_env env,
    napi_callback_info cbinfo,
    size_t* argc,
    napi_value* argv,
    napi_value* this_arg,
    void** data); // [out] Receives the data pointer for the callback.

napi_status napi_get_new_target (
    napi_env env,
    napi_callback_info cbinfo,
    napi_value* result);
napi_status napi_define_class (
    napi_env env,
    const(char)* utf8name,
    size_t length,
    napi_callback constructor,
    void* data,
    size_t property_count,
    const(napi_property_descriptor)* properties,
    napi_value* result);

// Methods to work with external data objects
napi_status napi_wrap (
    napi_env env,
    napi_value js_object,
    void* native_object,
    napi_finalize finalize_cb,
    void* finalize_hint,
    napi_ref* result);
napi_status napi_unwrap (napi_env env, napi_value js_object, void** result);
napi_status napi_remove_wrap (
    napi_env env,
    napi_value js_object,
    void** result);
napi_status napi_create_external (
    napi_env env,
    void* data,
    napi_finalize finalize_cb,
    void* finalize_hint,
    napi_value* result);
napi_status napi_get_value_external (
    napi_env env,
    napi_value value,
    void** result);

// Methods to control object lifespan

// Set initial_refcount to 0 for a weak reference, >0 for a strong reference.
napi_status napi_create_reference (
    napi_env env,
    napi_value value,
    uint initial_refcount,
    napi_ref* result);

// Deletes a reference. The referenced value is released, and may
// be GC'd unless there are other references to it.
napi_status napi_delete_reference (napi_env env, napi_ref ref_);

// Increments the reference count, optionally returning the resulting count.
// After this call the  reference will be a strong reference because its
// refcount is >0, and the referenced object is effectively "pinned".
// Calling this when the refcount is 0 and the object is unavailable
// results in an error.
napi_status napi_reference_ref (napi_env env, napi_ref ref_, uint* result);

// Decrements the reference count, optionally returning the resulting count.
// If the result is 0 the reference is now weak and the object may be GC'd
// at any time if there are no other references. Calling this when the
// refcount is already 0 results in an error.
napi_status napi_reference_unref (napi_env env, napi_ref ref_, uint* result);

// Attempts to get a referenced value. If the reference is weak,
// the value might no longer be available, in that case the call
// is still successful but the result is NULL.
napi_status napi_get_reference_value (
    napi_env env,
    napi_ref ref_,
    napi_value* result);

napi_status napi_open_handle_scope (napi_env env, napi_handle_scope* result);
napi_status napi_close_handle_scope (napi_env env, napi_handle_scope scope_);
napi_status napi_open_escapable_handle_scope (
    napi_env env,
    napi_escapable_handle_scope* result);
napi_status napi_close_escapable_handle_scope (
    napi_env env,
    napi_escapable_handle_scope scope_);

napi_status napi_escape_handle (
    napi_env env,
    napi_escapable_handle_scope scope_,
    napi_value escapee,
    napi_value* result);

// Methods to support error handling
napi_status napi_throw (napi_env env, napi_value error);
napi_status napi_throw_error (
    napi_env env,
    const(char)* code,
    const(char)* msg);
napi_status napi_throw_type_error (
    napi_env env,
    const(char)* code,
    const(char)* msg);
napi_status napi_throw_range_error (
    napi_env env,
    const(char)* code,
    const(char)* msg);
napi_status napi_is_error (napi_env env, napi_value value, bool* result);

// Methods to support catching exceptions
napi_status napi_is_exception_pending (napi_env env, bool* result);
napi_status napi_get_and_clear_last_exception (
    napi_env env,
    napi_value* result);

// Methods to work with array buffers and typed arrays
napi_status napi_is_arraybuffer (napi_env env, napi_value value, bool* result);
napi_status napi_create_arraybuffer (
    napi_env env,
    size_t byte_length,
    void** data,
    napi_value* result);
napi_status napi_create_external_arraybuffer (
    napi_env env,
    void* external_data,
    size_t byte_length,
    napi_finalize finalize_cb,
    void* finalize_hint,
    napi_value* result);
napi_status napi_get_arraybuffer_info (
    napi_env env,
    napi_value arraybuffer,
    void** data,
    size_t* byte_length);
napi_status napi_is_typedarray (napi_env env, napi_value value, bool* result);
napi_status napi_create_typedarray (
    napi_env env,
    napi_typedarray_type type,
    size_t length,
    napi_value arraybuffer,
    size_t byte_offset,
    napi_value* result);
napi_status napi_get_typedarray_info (
    napi_env env,
    napi_value typedarray,
    napi_typedarray_type* type,
    size_t* length,
    void** data,
    napi_value* arraybuffer,
    size_t* byte_offset);

napi_status napi_create_dataview (
    napi_env env,
    size_t length,
    napi_value arraybuffer,
    size_t byte_offset,
    napi_value* result);
napi_status napi_is_dataview (napi_env env, napi_value value, bool* result);
napi_status napi_get_dataview_info (
    napi_env env,
    napi_value dataview,
    size_t* bytelength,
    void** data,
    napi_value* arraybuffer,
    size_t* byte_offset);

// version management
napi_status napi_get_version (napi_env env, uint* result);

// Promises
napi_status napi_create_promise (
    napi_env env,
    napi_deferred* deferred,
    napi_value* promise);
napi_status napi_resolve_deferred (
    napi_env env,
    napi_deferred deferred,
    napi_value resolution);
napi_status napi_reject_deferred (
    napi_env env,
    napi_deferred deferred,
    napi_value rejection);
napi_status napi_is_promise (napi_env env, napi_value value, bool* is_promise);

// Running a script
napi_status napi_run_script (
    napi_env env,
    napi_value script,
    napi_value* result);

// Memory management
napi_status napi_adjust_external_memory (
    napi_env env,
    long change_in_bytes,
    long* adjusted_value);

// Dates
napi_status napi_create_date (napi_env env, double time, napi_value* result);

napi_status napi_is_date (napi_env env, napi_value value, bool* is_date);

napi_status napi_get_date_value (
    napi_env env,
    napi_value value,
    double* result);

// Add finalizer for pointer
napi_status napi_add_finalizer (
    napi_env env,
    napi_value js_object,
    void* native_object,
    napi_finalize finalize_cb,
    void* finalize_hint,
    napi_ref* result);

// NAPI_VERSION >= 5

// BigInt
napi_status napi_create_bigint_int64 (
    napi_env env,
    long value,
    napi_value* result);
napi_status napi_create_bigint_uint64 (
    napi_env env,
    ulong value,
    napi_value* result);
napi_status napi_create_bigint_words (
    napi_env env,
    int sign_bit,
    size_t word_count,
    const(ulong)* words,
    napi_value* result);
napi_status napi_get_value_bigint_int64 (
    napi_env env,
    napi_value value,
    long* result,
    bool* lossless);
napi_status napi_get_value_bigint_uint64 (
    napi_env env,
    napi_value value,
    ulong* result,
    bool* lossless);
napi_status napi_get_value_bigint_words (
    napi_env env,
    napi_value value,
    int* sign_bit,
    size_t* word_count,
    ulong* words);

enum napi_key_collection_mode {
  napi_key_include_prototypes,
  napi_key_own_only
}

enum napi_key_filter {
  napi_key_all_properties = 0,
  napi_key_writable = 1,
  napi_key_enumerable = 1 << 1,
  napi_key_configurable = 1 << 2,
  napi_key_skip_strings = 1 << 3,
  napi_key_skip_symbols = 1 << 4
}
enum napi_key_conversion {
  napi_key_keep_numbers,
  napi_key_numbers_to_strings
}

// Object
napi_status napi_get_all_property_names (
    napi_env env,
    napi_value object,
    napi_key_collection_mode key_mode,
    napi_key_filter key_filter,
    napi_key_conversion key_conversion,
    napi_value* result);

// Instance data
napi_status napi_set_instance_data (
    napi_env env,
    void* data,
    napi_finalize finalize_cb,
    void* finalize_hint);

napi_status napi_get_instance_data (napi_env env, void** data);
// NAPI_VERSION >= 6

// ArrayBuffer detaching

// NAPI_EXPERIMENTAL

// SRC_JS_NATIVE_API_H_
