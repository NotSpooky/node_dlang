module node_dlang;

public import js_native_api_types : napi_env, napi_value, napi_callback;
import node_api;
import js_native_api;

import std.conv : to, text;
import std.string : toStringz;
import std.traits;
import std.algorithm;
debug import std.stdio;

import std.variant;
template isVariantN (alias T) {
  enum isVariantN = __traits(isSame, TemplateOf!T, VariantN);
}

auto napiIdentity (napi_env _1, napi_value value, napi_value * toRet) {
  *toRet = value;
  return napi_status.napi_ok;
}

alias ExternD (T) = SetFunctionAttributes!(T, "D", functionAttributes!T);
alias ExternC (T) = SetFunctionAttributes!(T, "C", functionAttributes!T);

auto toNapiValueArray (T ...)(napi_env env, T args) {
  napi_value [args.length] argVals;
  foreach (i, arg; args) {
    // Create a temporary value with the casted data.
    argVals [i] = arg.toNapiValue (env);
  }
  return argVals;
}

auto constructor (RetType, T ...)(napi_env env, napi_value constructorNapi, T args) {
  const asArr = toNapiValueArray (env, args);
  napi_value toRet;
  auto status = napi_new_instance (
    env
    , constructorNapi
    , asArr.length
    , asArr.ptr
    , &toRet
  );
  assert (status == napi_status.napi_ok, `Error calling JS constructror`);
  return fromNapi!RetType (env, toRet);
}

// If the first argument to the delegate (in other words, R) is a napi_value
// that is used as the context.
// Otherwise the global context is used.
auto jsFunction (R)(napi_env env, napi_value func, R * toRet) {
  alias Params = Parameters!R;
  alias RetType = ReturnType!R;
  // Cannot assign toRet here for extern(C) Rs or LDC complains :(
  auto foo = delegate RetType (Params args) {
    static if (args.length > 0 && is (Params [0] == napi_value)) {
      // Use provided context.
      auto status = napi_status.napi_generic_failure;
      napi_value context = args [0];
      enum firstArgPos = 1;
    } else {
      napi_value context;
      auto status = napi_get_global (env, &context);
      assert (status == napi_status.napi_ok);
      enum firstArgPos = 0;
    }
    /+napi_value [args.length - firstArgPos] napiArgs;
    
    foreach (i, arg; args [firstArgPos..$]) {
      napiArgs [i] = arg.toNapiValue (env);
    }+/
    auto napiArgs = toNapiValueArray (env, args [firstArgPos .. $]);
    napi_value returned;
    status = napi_call_function (
      env
      , context
      , func
      , napiArgs.length
      , napiArgs.ptr
      , &returned
    );
    if (status != napi_status.napi_ok) {
      debug stderr.writeln (`Got status `, status);
      throw new Exception (`JS call errored :(`);
    }
    
    static if (!is (RetType == void)) {
      return fromNapi!RetType (env, returned);
    }
  };
  *toRet = cast (R) foo;
  return napi_status.napi_ok;
}

auto getDgPointer (FP)(napi_env env, napi_value func, FP * toRet) {
  static if (is (FP == F*, F)) {
    import std.conv : emplace;
    char [F.sizeof] buf;
    /+
    auto c = emplace!C(buf, 5);
    auto intermediatePtr = new F [1].ptr;
    jsFunction (env, func, intermediatePtr);
    *toRet = intermediatePtr;
    +/
  } else static assert (0);
  return napi_status.napi_ok;
}

auto reference (napi_env env, ref napi_value obj) {
  napi_ref toRet;
  auto status = napi_create_reference (env, obj, 1, &toRet);
  if (status != napi_status.napi_ok) throw new Exception (
    text (`Reference creation failed: `, status)
  );
  return toRet;
}

// Note this might escape values out of scope
auto val (napi_env env, napi_ref reference) {
  napi_value toRet;
  auto status = napi_get_reference_value (env, reference, &toRet);
  if (status != napi_status.napi_ok) throw new Exception (`Could not get value from reference`);
  assert (toRet != null);
  return toRet;
}

class JSException : Exception {
  napi_value jsException;
  this (
    napi_value jsException
    , string message = `JS Exception`
    , string file = __FILE__
    , size_t line = __LINE__
    , Throwable nextInChain = null) {
    this.jsException = jsException;
    super (message, file, line, nextInChain);
  }
}

auto callNapi (Args ...)(napi_env env, napi_value context, napi_value func, Args args) {
  napi_value [args.length] napiArgs;
  static foreach (i, arg; args) {
    napiArgs [i] = arg.toNapiValue (env);
  }
  napi_value returned;
  auto status = napi_call_function (env, context, func, args.length, napiArgs.ptr, &returned);
  if (status == napi_status.napi_pending_exception) {
    napi_value exceptionData;
    debug stderr.writeln (`Got JS exception`);
    napi_get_and_clear_last_exception (env, &exceptionData);
    throw new JSException (exceptionData);
  } else if (status != napi_status.napi_ok) {
    debug stderr.writeln (`Got JS status `, status);
    throw new Exception (text (`Call errored for args `, args));
  }
  return returned;
}

// Get a property.
auto p (RetType = napi_value, S) (napi_value obj, napi_env env, S propName) 
if (isSomeString!S) {
  napi_value toRet;
  auto key = propName.toNapiValue (env);
  auto status = napi_get_property (env, obj, key, &toRet);
  if (status != napi_status.napi_ok) {
    throw new Exception (`Failed to get property ` ~ propName);
  }
  return fromNapi!RetType (env, toRet);
}
// Assign a property.
void p (InType, S) (napi_value obj, napi_env env, S propName, InType newVal)
if (isSomeString!S) {
  auto key = propName.toNapiValue (env);
  auto status = napi_set_property (env, obj, key, newVal.toNapiValue (env));
  if (status != napi_status.napi_ok) {
    throw new Exception (`Failed to set property ` ~ propName.to!string);
  }
}

private {
  struct NapiRefWithId { napi_ref v; }
  struct NapiValWithId { napi_value v; }
}

struct JSVar {
  napi_env env;
  // DMD seems to handle well the difference between napi_ref and napi_value
  // but LDC doesn't, so wrapped the types.
  alias CtxRefT = Algebraic! (NapiRefWithId, NapiValWithId);
  CtxRefT ctxRef;
  this (napi_env env, napi_value nVal) {
    assert (env != null && nVal != null);
    this.env = env;
    napi_valuetype napiType;
    assert (napi_typeof(env, nVal, &napiType) == napi_status.napi_ok);
    if (napiType == napi_valuetype.napi_object) {
      this.ctxRef = NapiRefWithId (reference (env, nVal));
    } else {
      // TODO: Check cases such as functions which might be problematic.
      this.ctxRef = NapiValWithId (nVal);
    }
  }
  this (T) (napi_env env, T val) {
    this (env, val.toNapiValue (env));
  }

  auto constructor (RetType = JSVar, T ...)(T args) {
    return .constructor!RetType (this.env, this.context (), args);
  }

  auto context () {
    return ctxRef.visit! (
      (NapiValWithId v) => v.v
      , (NapiRefWithId r) => val (env, r.v)
    );
  }

  auto toNapiValue (napi_env env) {
    assert (this.context () != null);
    return this.context ();
  }

  auto opIndex (S)(S propName) if (isSomeString!S) {
    return context.p!JSVar (env, propName);
  }

  auto opIndexAssign (T, S)(T toAssign, S propName) if (isSomeString!S) {
    context ().p (env, propName, toAssign);
  }

  template opDispatch (string s) {
    R opDispatch (R = JSVar, T...)(T args) {
      auto ctx = this.context ();
      auto toCallAsNapi = ctx.p (env, s);
      auto asCallable = fromNapi! (R delegate (napi_value, T))(env, toCallAsNapi);
      static if (is (R == void)) {
        asCallable (ctx, args);
      } else {
        return asCallable (ctx, args);
      }
    }
  }

  // Convenience console.log function
  auto jsLog () {
    console (this.env).log (this.context ());
  }

  bool isUndefined () {
    return .isUndefined (this.env, this.context ());
  }

  auto opCast (T) () {
    return fromNapi!T (env, this.context ());
  }

  auto opCall (R = JSVar, T ...) (T args) {
    auto ctx = this.context ();
    auto toCall = fromNapi! (R delegate (napi_value, T)) (env, ctx);
    return toCall (ctx, args);
  }
}

struct Promise {
  @disable this ();
  napi_deferred deferred;
  JSVar promise;
  napi_env env;
  this (napi_env env) {
    this.env = env;
    napi_value napiPromise;
    auto status = napi_create_promise (env, &deferred, &napiPromise);
    promise = JSVar (env, napiPromise);
    assert (status == napi_status.napi_ok);
  }
  void resolve (T)(T toRet) {
    auto status = napi_resolve_deferred (env, deferred, toRet.toNapiValue (env));
    assert (status == napi_status.napi_ok);
  }
  void reject (T)(T toRet) {
    auto status = napi_reject_deferred (env, deferred, toRet.toNapiValue (env));
    assert (status == napi_status.napi_ok);
  }
  napi_value toNapiValue (napi_env env) {
    assert (env == this.env);
    return this.promise.context ();
  }
}

/// Similar to JSObj but doesn't have a reference counter, so cannot be used
/// after the JS call that has the scope where this was created.
/// Template is a struct type that contains fields and function declarations
/// that this struct will attempt to copy in signature but with JS type conversions.
/// Do note that accessing members is done lazily.
alias ScopedJSObj (Template) = JSObj!(Template, false);

struct Named { string name; };
/// Stores a JS value with a reference counter so that JS's GC doesn't collect
/// it whilst it's stored in D.
/// Template is a struct type that contains fields and function declarations
/// that this struct will attempt to copy in signature but with JS type conversions.
/// Do note that accessing members is done lazily.
struct JSObj (Template, bool useRefCount = true) {
  /// Convenience console.log (this) function
  void jsLog () {
    console (this.env).log (this.context);
  }

  void toString (scope void delegate (const (char)[]) sink) {
    if (env is null || this.context is null) {
      sink (`null JSObj`);
    } else {
      // Note: this could generate an error 
      napi_value asStr;
      napi_coerce_to_string (env, this.context, &asStr);
      sink (fromNapi!string (env, asStr));
    }
  }

  alias FieldNames = __traits (allMembers, Template);
  private template nameForCaller (string name) {
    alias nameUDAs = getUDAs! (mixin (`Template.` ~ name), Named);
    static if (nameUDAs.length == 0) {
      alias nameForCaller = name;
    } else {
      static assert (nameUDAs.length == 1, `Cannot have more than one Named UDA`);
      enum nameForCaller = nameUDAs [0].name;
    }
  }
  import std.meta;
  // Equals to FieldNames unless the @named uda is used.
  alias NamesForCaller = staticMap! (nameForCaller, FieldNames);
  private template type (string name) {
    alias type = typeof (mixin (`Template.` ~ name));
  }
  alias FieldTypes = staticMap! (type, FieldNames);
  private static auto positions () {
    size_t [] funPositions;
    size_t [] fieldPositions;
    static foreach (i, Member; FieldNames) {
      // Ignore opAssign, which might be implicitly generated
      static if (Member != `opAssign` && !Member.startsWith (`__`)) {
        static if (mixin (`isFunction! (Template.` ~ Member ~ `)`)) {
          funPositions ~= i;
        } else {
          fieldPositions ~= i;
        }
      }
    }
    import std.typecons : tuple;
    return tuple!(`funPositions`, `fieldPositions`) (funPositions, fieldPositions);
  }

  static assert (NamesForCaller.length == FieldTypes.length);
  // Useful for type checking. 
  enum dlangNodeIsJSObj = true;

  private enum Positions = positions ();
  private enum FunPositions = Positions.funPositions;
  private enum FieldPositions = Positions.fieldPositions;

  napi_env env;
  static if (useRefCount) {
    napi_ref ctxRef = null;
    auto context () {
      return val (env, this.ctxRef);
    }
  } else {
    napi_value context;
  }

  private enum typeMsg = `JSObj template args should be pairs of strings with types`;
  // Creating a new object from D.
  this (napi_env env) {
    this.env = env;
    static if (useRefCount) {
      auto context = napi_value ();
      auto status = napi_create_object (env, &context);
      assert (status == napi_status.napi_ok);
      ctxRef = reference (env, context);
    }
  }

  // Assigning from a JS object.
  this (napi_env env, napi_value context) {
    this.env = env;
    // Keep alive. Note this will NEVER be GC'ed
    static if (useRefCount) {
      ctxRef = reference (env, context);
    } else {
      this.context = context;
    }
  }
  
  // Copy ctor.
  this (ref return scope typeof (this) rhs) {
    this.env = rhs.env;
    static if (useRefCount) {
      this.ctxRef = rhs.ctxRef;
      if (ctxRef != null) {
        auto status = napi_reference_ref (env, ctxRef, null);
        //writeln (`> Ref count is `, currentRefCount);
        assert (status == napi_status.napi_ok);
      }
    } else {
      this.context = rhs.context;
    }
  }
  ~this () {
    // writeln ("Destructing JSobj " ~ exportsAlias.stringof);
    // uint currentRefCount;
    static if (useRefCount) {
      if (ctxRef != null) {
        auto status = napi_reference_unref (env, ctxRef, null);
        assert (
          status == napi_status.napi_ok
          , `Got status when doing unref ` ~ status.to!string
        );
        //writeln (`< Ref count is `, currentRefCount);
      }
    }
  }

  static foreach (i, FunPosition; FunPositions) {
    // Functions called constructor are equivalent to using new in JS.
    static if (FieldNames [FunPosition] == `constructor`) {
      pragma (msg, `Found constructor`);
      static assert (
        is (ReturnType! (FieldTypes [FunPosition]) == void)
        , `Please put void return type on JS constructor declarations, found `
          ~ ReturnType! (FieldTypes [FunPosition]).stringof
      );
      auto constructor (Parameters! (FieldTypes [FunPosition]) args) {
        return .constructor!(typeof (this)) (this.env, this.context (), args);
      }
    } else {
      // Add function that simply uses callNapi.
      mixin (
        q{auto } ~ NamesForCaller [FunPosition] ~ q{ (Parameters! (FieldTypes [FunPosition]) args) {
          alias FunType = FieldTypes [FunPosition];
          alias RetType = ReturnType!(FunType);
            //auto context = val (env, this.ctxRef);
            auto toCall = context
              .p! (RetType delegate (napi_value, Parameters!FunType))
                (env, NamesForCaller [FunPosition]);
            static if (is (RetType == void)) {
              toCall (context, args);
            } else {
              return toCall (context, args);
            }
          }
        }
      );
    }
  }
  static foreach (i, FieldPosition; FieldPositions) {
    // Setter.
    static if (isVariantN! (FieldTypes [FieldPosition])) {
      // Also add implicit conversions :)
      static foreach (PossibleType; TemplateArgsOf!(FieldTypes [FieldPosition])[1..$]) {
        mixin (q{
          void } ~ NamesForCaller [FieldPosition] ~ q{ (PossibleType toSet) {
            enum fieldName = NamesForCaller [FieldPosition];
            auto asNapi = toSet.toNapiValue (env);
            auto propName = fieldName.toStringz;
            //auto context = val (env, this.ctxRef);
            auto status = napi_set_named_property (env, context, propName, asNapi);
            assert (status == napi_status.napi_ok, `Couldn't set property ` ~ fieldName);
          }
        });
      };
    }
    mixin (q{
      void } ~ FieldNames [FieldPosition] ~ q{ (FieldTypes [FieldPosition] toSet) {
        enum fieldName = FieldNames [FieldPosition];
        auto asNapi = toSet.toNapiValue (env);
        auto propName = fieldName.toStringz;
        //auto context = val (env, this.ctxRef);
        auto status = napi_set_named_property (env, context, propName, asNapi);
        assert (status == napi_status.napi_ok, `Couldn't set property ` ~ fieldName);
      }
    });
    // Getter.
    // Pretty similar in both cases, would like to deduplicate it but
    // static foreach is fun.
    static if (isVariantN! (FieldTypes [FieldPosition])) {
      // Getting Algebraics/VariantNs must specify the returned type.
      mixin (q{
        auto } ~ FieldNames [FieldPosition] ~ q{ (Type) () {
          return fromNapi!Type (
            env
            , context.p (env, FieldNames [FieldPosition])
          );
        }
      });
    } else {
      static if (isFunctionPointer! (FieldTypes [FieldPosition])) {
        // Function pointers must become delegates because jsFunction
        // adds a context.
        // They also have a different signature so that two sets of parens
        // aren't needed to call them.
        mixin (q{auto } ~ FieldNames [FieldPosition] ~ q{ (Parameters!(FieldTypes [FieldPosition]) args) {
          import std.functional : toDelegate;
          alias RetType = typeof (FieldTypes [FieldPosition].init.toDelegate);
          return fromNapi!RetType (
            env
            , context.p (env, FieldNames [FieldPosition])
          ) (args);
        }});
      } else {
        // Other types use a direct getter function.
        mixin (q{auto } ~ FieldNames [FieldPosition] ~ q{ () {
          return fromNapi! (FieldTypes [FieldPosition]) (
            env
            , context.p (env, FieldNames [FieldPosition])
          );
        }});
      }
    }
  }
}

// Convenience console type.
private struct Console_ {
  void log (napi_value);
};
alias Console = JSObj!Console_;
auto console = (napi_env env) => global!Console (env, `console`);
void jsLog (T)(napi_env env, T toLog) {
  console (env).log (toLog.toNapiValue (env));
}
auto global (napi_env env) {
  napi_value val;
  auto status = napi_get_global (env, &val);
  assert (status == napi_status.napi_ok, `Couldn't get global context`);
  return val;
}

auto global (RetType = JSVar)(napi_env env, string name) {
  return fromNapi!RetType (env, global (env).p (env, name));
}

auto getJSobj (T)(napi_env env, napi_value ctx, T * toRet) {
  assert (toRet != null);
  *toRet = T (env, ctx);
  return napi_status.napi_ok;
}

auto getStr (StrType)(napi_env env, napi_value napiVal, StrType * toRet) {
  // Try with statically allocated buffer for small strings
  assert (toRet != null);
  size_t readChars = 0;
  static if (is (StrType == string)) {
    alias CharType = char;
    char [2048] inBuffer;
    alias conversionFunction = napi_get_value_string_utf8;
  } else static if (is (StrType == wstring)) {
    alias CharType = wchar;
    ushort [2048] inBuffer;
    alias conversionFunction = napi_get_value_string_utf16;
  } else static assert (
    false
    , `N-API doesn't provide conversion for UTF-32 (dstrings), use string or wstring instead`
  );
  auto status = conversionFunction (
    env
    , napiVal
    , inBuffer.ptr
    , inBuffer.length
    , & readChars
  );
  if (status != napi_status.napi_ok) {
    return status;
  }
  
  if (readChars == inBuffer.length - 1) {
    // String bigger than buffer :( need a dynamic array.
    // Technically this is not needed for the specific case of
    // exactly size inBuffer.length - 1
    // Get string size to allocate an array.
    status = conversionFunction (
      env
      , napiVal
      , null
      , 0
      , & readChars
    );
    assert (status == napi_status.napi_ok);
    // Try again with bigger size.
    auto buffer = new typeof(inBuffer [0]) [readChars + 1]; // include null terminator
    status = conversionFunction (
      env
      , napiVal
      , buffer.ptr
      , buffer.length
      , & readChars
    );
    assert (status == napi_status.napi_ok);
    *toRet = buffer.ptr [0..readChars].map!(to!CharType).to!StrType;
  } else {
    // Got it on first try
    *toRet = inBuffer.ptr [0..readChars].map!(to!CharType).to!StrType;
  }
  return napi_status.napi_ok;
}

auto getFloat (napi_env env, napi_value napiVal, float * toRet) {
  double intermediate;
  auto status = napi_get_value_double (env, napiVal, &intermediate);
  *toRet = intermediate.to!float;
  return status;
}

void inJSScope (alias fun)(napi_env env) {
  napi_handle_scope jsScope;
  auto status = napi_open_handle_scope (env, &jsScope);
  assert (status == napi_status.napi_ok);
  scope (exit) napi_close_handle_scope (env, jsScope);
  fun ();
}

auto getAA (V)(napi_env env, napi_value napiVal, V [string] * toRet) {
  * toRet = V [string].init;
  napi_value propertyNames;
  auto status = napi_get_property_names (env, napiVal, &propertyNames);
  assert (status == napi_status.napi_ok);
  uint propertyNamesLength;
  status = napi_get_array_length (env, propertyNames, &propertyNamesLength);
  assert (status == napi_status.napi_ok);
  foreach (i; 0 .. propertyNamesLength) {
    inJSScope! (() {
      napi_value keyNapi;
      status = napi_get_element (env, propertyNames, i, &keyNapi);
      assert (status == napi_status.napi_ok);
      napi_value element;
      status = napi_get_property (env, napiVal, keyNapi, &element);
      assert (status == napi_status.napi_ok);
      (* toRet) [fromNapi!string (env, keyNapi)] = fromNapi!V (env, element);
    }) (env);
  }
  return napi_status.napi_ok;
}

auto getJSVar (napi_env env, napi_value napiVal, JSVar * toRet) {
  *toRet = JSVar (env, napiVal);
  return napi_status.napi_ok;
}

auto getStaticArray (A)(napi_env env, napi_value napiVal, A * toRet) {
  // Copying could be avoided
  auto asDynamicArr = (* toRet) [];
  auto toRetNapi = getArray (env, napiVal, & asDynamicArr);
  foreach (i, val; asDynamicArr) {
    (* toRet) [i] = val;
  }
  return toRetNapi;
}

auto getArray (A)(napi_env env, napi_value napiVal, A [] * toRet) {
  import std.array;
  Appender!(A []) toRetAppender;
  uint arrLength;
  auto status = napi_get_array_length (env, napiVal, &arrLength);
  assert (
    status == napi_status.napi_ok
    , `Error getting array length, maybe object isn't array or N-API errored on`
      ~ ` the call before this one.`
  );
  foreach (i; 0 .. arrLength) {
    inJSScope! (() {
      napi_value toConvert;
      status = napi_get_element (env, napiVal, i, &toConvert);
      assert (status == napi_status.napi_ok, `Couldn't get element from array`);
      toRetAppender ~= fromNapi!A (env, toConvert);
    }) (env);
  }
  *toRet = toRetAppender.data;
  return napi_status.napi_ok;
}

auto getTypedArray (T)(napi_env env, napi_value napiVal, TypedArray!T * toRet) {
  napi_typedarray_type type;
  size_t length;
  void * data;
  napi_value arrayBuffer;
  size_t offset;
  auto status = napi_get_typedarray_info (
    env
    , napiVal
    , & type
    , & length
    , & data
    , & arrayBuffer
    , & offset
  );

  enum expectedType = TypedArray!T.type;
  assert (
    // ubyte accepts both clamped and unclamped arrays.
    expectedType == type || (is (T == ubyte)
      && type == napi_typedarray_type.napi_uint8_clamped_array)
    , `TypedArray type doesn't match (make sure signedness is correct too)`
  );
  toRet.internal = (cast (T *) data) [0 .. length];
  return status;
}

auto getStruct (S)(napi_env env, napi_value napiVal, S * toRet) {
  *toRet = S.init;
  foreach (fieldName; FieldNameTuple!S) {
    alias FieldType = typeof (__traits (getMember, *toRet, fieldName));
    auto napiProp = napiVal.p (env, fieldName);
    __traits (getMember, *toRet, fieldName) = fromNapi!FieldType (env, napiProp);
  }
  return napi_status.napi_ok;
}

template fromNapiB (T) {
  static if (is (T == bool)) {
    alias fromNapiB = napi_get_value_bool;
  } else static if (is (T == double)) {
    alias fromNapiB = napi_get_value_double;
  } else static if (is (T == int)) {
    alias fromNapiB = napi_get_value_int32;
  } else static if (is (T == uint)) {
    alias fromNapiB = napi_get_value_uint32;
  } else static if (is (T == long)) {
    alias fromNapiB = napi_get_value_int64;
  } else static if (is (T == ulong)) {
    alias fromNapiB = napi_get_value_bigint_uint64;
  } else static if (is (T == double)) {
    alias fromNapiB = napi_get_value_double;
  } else static if (is (T == float)) {
    alias fromNapiB = getFloat;
  } else static if (is (T == TypedArray!A, A)) {
    alias fromNapiB = getTypedArray;
  } else static if (is (T == V [string], V)) {
    alias fromNapiB = getAA;
  } else static if (isSomeString!T) {
    alias fromNapiB = getStr;
  } else static if (is (T == Nullable!A, A)) {
    alias fromNapiB = getNullable!A;
  } else static if (is (T == napi_value)) {
    alias fromNapiB = napiIdentity;
  } else static if (isDelegate!T) {
    alias fromNapiB = jsFunction;
  } else static if (is (T == JSVar)) {
    alias fromNapiB = getJSVar;
  } else static if (isStaticArray!T) {
    alias fromNapiB = getStaticArray;
  } else static if (is (T == A[], A)) {
    alias fromNapiB = getArray;
  } else static if (is (T == A*, A) && isDelegate!A) {
    alias fromNapiB = getDgPointer;
  } else static if (isFunctionPointer!T) {
    // Need context to perform JS calls.
    static assert (
      0
      , `Cannot receive function pointers, use delegates instead`
    );
  } else static if (__traits(hasMember, T, `dlangNodeIsJSObj`)) {
    alias fromNapiB = getJSobj;
  } else static if (isVariantN!T) {
    static assert (
      0
      , `Don't use fromNapiB to get a VariantN/Algebraic, get the expected type instead`
    );
  } else static if (__traits(isPOD, T)) {
    alias fromNapiB = getStruct;
  } else {
    static assert (0, `Not implemented: Conversion from JS type for ` ~ T.stringof);
  }
}

napi_status getNullable (BaseType) (
  napi_env env
  , napi_value value
  , Nullable!BaseType * toRet
) {
  auto erroredToJS = () => napi_throw_error (
    env, null, `Failed to parse to ` ~ Nullable!BaseType.stringof
  );
  BaseType toRetNonNull;
  auto status = fromNapiB!BaseType (env, value, &toRetNonNull);
  if (status != napi_status.napi_ok) {
    *toRet = Nullable!BaseType ();
  } else {
    *toRet = Nullable!BaseType (toRetNonNull);
  }
  return napi_status.napi_ok;
}

import std.typecons : Nullable;
/// Gets a D typed value from a napi_value
T fromNapi (T, string argName = ``)(napi_env env, napi_value value) {
  T toRet;
  auto erroredToJS = () => napi_throw_error (
    env, null, `Failed to parse ` ~ argName ~ ` to ` ~ T.stringof
  );
  try {
    auto status = fromNapiB!T (env, value, &toRet);
    if (status != napi_status.napi_ok) {
      erroredToJS ();
    }
  } catch (Exception ex) {
    erroredToJS ();
  }
  return toRet;
}

void throwInJS (napi_env env, string message) {
  napi_throw_error (env, null, message.toStringz);
}

napi_status boolToNapi (napi_env env, bool toConvert, napi_value * toRet) {
  return napi_get_boolean (env, toConvert, toRet);
}

// O(n) operation. Use BufferArrays to avoid element-by-element JS object 
// creation.
napi_status arrayToNapi (F)(napi_env env, F[] array, napi_value * toRet) {
  assert (toRet != null);
  auto status = napi_create_array_with_length (env, array.length, toRet);
  assert (status == napi_status.napi_ok);
  foreach (i, val; array) {
    inJSScope! (() {
      auto nv = val.toNapiValue (env);
      status = napi_set_element (env, *toRet, i.to!uint, nv);
      assert (status == napi_status.napi_ok);
    }) (env);
  }
  return status;
}

/// Note: No conversion implemented for Uint8ClampedArray.
struct TypedArray (Element) {
  /// Constructor that uses the provided internal array.
  this (Element [] internal) {
    this.internal = internal;
  }
  /// Constructor that allocates on JS mem.
  this (napi_env env, uint length) {
    auto buffer = global (env, `Uint8Array`).constructor (length);
    this = cast (TypedArray!Element) buffer;
  }
  Element [] internal;
  alias internal this;
  static if (is (Element == byte)) {
    enum type = napi_typedarray_type.napi_int8_array;
  } else static if (is (Element == ubyte)) {
    enum type = napi_typedarray_type.napi_uint8_array;
  } else static if (is (Element == short)) {
    enum type = napi_typedarray_type.napi_int16_array;
  } else static if (is (Element == ushort)) {
    enum type = napi_typedarray_type.napi_uint16_array;
  } else static if (is (Element == int)) {
    enum type = napi_typedarray_type.napi_int32_array;
  } else static if (is (Element == uint)) {
    enum type = napi_typedarray_type.napi_uint32_array;
  } else static if (is (Element == float)) {
    enum type = napi_typedarray_type.napi_float32_array;
  } else static if (is (Element == double)) {
    enum type = napi_typedarray_type.napi_float64_array;
  } else static if (is (Element == long)) {
    enum type = napi_typedarray_type.napi_bigint64_array;
  } else static if (is (Element == ulong)) {
    enum type = napi_typedarray_type.napi_biguint64_array;
  } else {
    static assert (0, `Cannot make TypedArray of ` ~ Element.stringof);
  }
}

private size_t tArrLastId = 0;

import core.memory : GC;
private extern (C) void onTypedArrayFinalize (
  napi_env env
  , void * finalizeData
  , void * hint
) {
  GC.removeRoot (finalizeData);
}

/// Note: The array data must be kept alive in D.
napi_status typedArrayToNapi (T)(
  napi_env env
  , ref TypedArray!T array
  , napi_value * toRet
) {
  napi_value arrayBuffer;
  napi_finalize finalizeCb;
  auto arrPtr = array.internal.ptr;
  // Keep it alive on D side;
  GC.addRoot (arrPtr);
  // Also ensure that a moving collector does not relocate the object.
  GC.setAttr (arrPtr, GC.BlkAttr.NO_MOVE);

  auto status = napi_create_external_arraybuffer (
    env
    , arrPtr
    , T.sizeof * array.internal.length
    , & onTypedArrayFinalize
    , null
    , & arrayBuffer
  );
  assert (status == napi_status.napi_ok);

  return napi_create_typedarray (
    env
    , TypedArray!T.type
    , array.internal.length
    , arrayBuffer
    , 0
    , toRet
  );
}

napi_status aaToNapi (V)(napi_env env, V [string] toConvert, napi_value * toRet) {
  assert (toRet != null);
  auto status = napi_create_object (env, toRet);
  assert (status == napi_status.napi_ok);
  foreach (key, value; toConvert) {
    inJSScope! (() {
      status = napi_set_named_property (env, *toRet, key.toStringz, value.toNapiValue (env));
      assert (status == napi_status.napi_ok);
    }) (env);
  }
  return napi_status.napi_ok;
}

napi_status stringToNapi (StrType)(napi_env env, StrType toConvert, napi_value * toRet) {
  assert (toRet != null);
  static if (is (StrType == string)){
    alias NapiCharType = char;
    alias conversionFunction = napi_create_string_utf8;
  } else static if (is (StrType == wstring)) {
    alias NapiCharType = ushort;
    alias conversionFunction = napi_create_string_utf16;
  } else static assert (
    false
    , `Cannot convert UTF32 strings (dstrings) to JS. Please use strings or wstrings instead`
  );
  return conversionFunction (
    env
    , cast (const NapiCharType *) toConvert.ptr
    , toConvert.length
    , toRet
  );
}

napi_status nullableToNapi (T) (napi_env env, Nullable!T toConvert, napi_value * toRet) {
  assert (toRet != null);
  if (toConvert.isNull ()) {
    return napi_get_null (env, toRet);
  } else {
    return toNapi!T (env, toConvert.get (), toRet);
  }
}

napi_status callbackToNapi (F)(
  napi_env env
  , napi_callback toConvert
  , napi_value * toRet
  , F * fPointer
) {
  assert (toRet != null);
  return napi_create_function (env, null, 0, toConvert, fPointer, toRet);
}

napi_status delegateToNapi (Dg)(napi_env env, Dg * toCall, napi_value * toRet) {
  assert (toRet != null);
  static assert (isDelegate!(Dg));
  return callbackToNapi (env, &fromJsPtr! (Dg), toRet, toCall);
}

napi_status callableToNapi (F)(napi_env env, F toCall, napi_value * toRet) {
  assert (toRet != null);
  static assert (!isDelegate!(F), `Use delegateToNapi instead`);
  return callbackToNapi (env, &fromJsPtr!F, toRet, toCall);
}

napi_status jsObjToNapi (T)(napi_env env, T toConvert, napi_value * toRet) {
  assert (toRet != null);
  assert (env == toConvert.env);
  *toRet =  toConvert.context;
  return napi_status.napi_ok;
}

napi_status algebraicToNapi (T ...)(napi_env env, VariantN!T toConvert, napi_value * toRet) {
  static assert (T.length > 1);
  assert (toRet != null);
  foreach (possibleType; T [1..$]) {
    auto valueTried = toConvert.peek!possibleType;
    if (valueTried != null) {
      *toRet = toNapiValue (*valueTried, env);
      return napi_status.napi_ok;
    }
  }
  assert (0, `Could not get value from Algebraic/VariantN`);
}

napi_status jsVarToNapi (napi_env env, JSVar toConvert, napi_value * toRet) {
  assert (toRet != null);
  assert (env == toConvert.env, `JS environments don't match`);
  *toRet = toConvert.context ();
  return napi_status.napi_ok;
}

napi_status tupleToNapi (T)(napi_env env, const auto ref T toConvert, napi_value * toRet) {
  assert (toRet != null);
  napi_create_object (env, toRet);
  foreach (i, field; toConvert.expand) {
    (*toRet).p (env, toConvert.fieldNames [i], field);
  }
  return napi_status.napi_ok;
}

napi_status structToNapi (S)(napi_env env, const auto ref S toConvert, napi_value * toRet) {
  assert (toRet != null);
  napi_create_object (env, toRet);
  foreach (fieldName; FieldNameTuple!S) {
    (*toRet).p (env, fieldName, __traits (getMember, toConvert, fieldName));
  }
  return napi_status.napi_ok;
}

template toNapi (alias T) {
  import std.typecons : Tuple;
  static if (is (T == bool)) {
    alias toNapi = boolToNapi;
  } static if (is (T == double)) {
    alias toNapi = napi_create_double;
  } else static if (is (T == int)) {
    alias toNapi = napi_create_int32;
  } else static if (is (T == uint)) {
    alias toNapi = napi_create_uint32;
  } else static if (is (T == long)) {
    alias toNapi = napi_create_int64;
  } else static if (is (T == ulong)) {
    alias toNapi = napi_create_bigint_uint64;
  } else static if (is (T : double)) {
    alias toNapi = napi_create_double;
  } else static if (is (T == V [string], V)) {
    alias toNapi = aaToNapi;
  } else static if (isSomeString!T) {
    alias toNapi = stringToNapi;
  } else static if (is (T == Nullable!A, A)) {
    alias toNapi = nullableToNapi!A;
  } else static if (is (T == napi_value)) {
    alias toNapi = napiIdentity;
  } else static if (is (T == Dg*, Dg)) {
    static if (isDelegate!Dg) {
      alias toNapi = delegateToNapi;
    } else static if (isFunctionPointer!T){
      alias toNapi = callableToNapi;
    } else {
      static assert (0, `Not implemented: Conversion to JS type for ` ~ T.stringof);
    }
  } else static if (isDelegate!T) {
    static assert (
      0
      , `Delegates must be sent as pointers to the delegate because of memory management`
    );
  } else static if (is (ExternC!T == napi_callback)) {
    static if (!is (T == ExternC!T)) {
      static assert (0, `Please use extern (C) for napi callbacks`);
    }
    alias toNapi = callbackToNapi;
  } else static if (is (T == TypedArray!A, A)) {
    alias toNapi = typedArrayToNapi;
  } else static if (isStaticArray!T) {
    alias toNapi = arrayToNapi;
  } else static if (is (T == A[], A)) {
    alias toNapi = arrayToNapi;
  } else static if (__traits(hasMember, T, `dlangNodeIsJSObj`)) {
    alias toNapi = jsObjToNapi;
  } else static if (isVariantN!T) {
    alias toNapi = algebraicToNapi;
  } else static if (__traits (isSame, TemplateOf!T, Tuple)) {
    alias toNapi = tupleToNapi;
  } else static if (__traits (isPOD, T)) {
    alias toNapi = structToNapi;
  } else {
    static assert (0, `Not implemented: Conversion to JS type for ` ~ T.stringof);
  }
}

napi_value toNapiValue (F)(
  F toCast, napi_env env
) {
  napi_value toRet;
  auto status = toNapi!F (env, toCast, &toRet);
  if (status != napi_status.napi_ok) {
    env.throwInJS (`Unable to create JS value for: ` ~ toCast.to!string);
  }
  return toRet;
}

napi_value undefined (napi_env env) {
  napi_value toRet;
  if (napi_get_undefined (env, &toRet) != napi_status.napi_ok) {
    env.throwInJS (`Unable to return void (undefined in JS)`);
  }
  return toRet;
}

bool isUndefined (napi_env env, napi_value val) {
  napi_valuetype valueType;
  assert (napi_typeof (env, val, &valueType) == napi_status.napi_ok);
  return valueType == napi_valuetype.napi_undefined;
}

private auto convertNapiSignature (F, alias toFinish)(
  napi_env env
  , napi_callback_info info
  , void ** delegateDataPtr = null
) {
  alias FunParams = Parameters!F;
  static if (FunParams.length > 0 && is (FunParams [0] == napi_env)) {
    immutable argCount = FunParams.length - 1;
    // First parameter is the env, which is from the 'env' param in withNapiExpectedSignature.
    // Thus it isn't stored as an napi_value.
    enum envParam = `env, `;
    enum firstValParam = 1;
  } else {
    immutable argCount = FunParams.length;
    enum envParam = ``;
    enum firstValParam = 0;
  }
  napi_value [argCount] argVals;
  size_t argCountMut = argCount;
  auto status = napi_get_cb_info (
    env
    , info
    , &argCountMut
    , argVals.ptr
    , null
    , delegateDataPtr
  );
  if (status != napi_status.napi_ok) {
    napi_throw_type_error (
      env
      , null
      , (`Failed to parse arguments for function ` ~ F.mangleof ~ `, incorrect amount?`)
        .toStringz
    );
  }
  static foreach (i, Param; FunParams [firstValParam .. $]) {
    // Create a temporary value with the casted data.
    mixin (`auto param` ~ i.to!string ~ ` = fromNapi!Param (env, argVals [i]);`);
  }
  // Now call Function with each of these casted values.
  import std.range;
  enum paramCalls = envParam ~ iota (argCount)
    .map!`"param" ~ a.to!string`
    .joiner (`,`)
    .to!string;
  static if (isDelegate!toFinish) {
    assert (delegateDataPtr != null);
    auto tmp = cast (F**) delegateDataPtr;
    toFinish = **tmp;
  }
  enum toMix = q{toFinish (} ~ paramCalls ~ q{)};
  enum retsVoid = Returns! (F, void);
  static if (retsVoid) {
    mixin (toMix ~ `;`);
    return undefined (env);
  } else {
    mixin (q{return } ~ toMix ~ q{.toNapiValue (env);});
  }
}

extern (C) napi_value fromJsPtr (F)(napi_env env, napi_callback_info info) {
  // It's a function pointer type, so must allocate it.
  F toCall;
  return convertNapiSignature! (F, toCall) (env, info, cast (void **) & toCall);
}

extern (C) napi_value withNapiExpectedSignature (alias Function)(
  napi_env env
  , napi_callback_info info
) {
  return convertNapiSignature!(typeof(Function), Function) (env, info, null);
}

template Returns (alias Function, OtherType) {
  enum Returns = is (ReturnType!Function == OtherType);
}

extern (C) alias void func (napi_env);
template MainFunction (alias Function) {
  alias ToCall = Function;
  static assert (
    is (ExternC! (typeof (Function)) == func)
    , `MainFunction must be instantiated with a void function (napi_env)`
  );
}

bool isMainFunction (alias Function) () if (isCallable!Function) {
  return false;
}
import std.meta;
bool isMainFunction (alias Function) () if (!isCallable!Function) {
  static if (__traits (compiles, TemplateOf!(Function))) {
    return __traits (isSame, TemplateOf!(Function), MainFunction);
  } else {
    return false;
  }
}

mixin template exportToJs (Exportables ...) {
  import node_api;
  import js_native_api;
  import std.string : toStringz;
  import std.traits;

  extern (C) napi_value exportToJs (napi_env env, napi_value exports) {
    import core.runtime;
    Runtime.initialize ();
    auto addExportable (alias Exportable)() {
      napi_status status;
      napi_value fn;
      status = napi_create_function (
        env
        , null
        , 0
        , & withNapiExpectedSignature!Exportable
        , null
        , &fn
      );
      if (status != napi_status.napi_ok) {
        napi_throw_error (env, null, "Was not able to wrap native function");
      } else {
        const fnName = Exportable.mangleof;
        status = napi_set_named_property (env, exports, fnName.toStringz, fn);
        if (status != napi_status.napi_ok) {
          napi_throw_error (
            env
            , null
            , ("Unable to populate exports for " ~ fnName).toStringz
          );
        }
      }
      return status;
    }
    static foreach (i, alias Exportable; Exportables) {
      static if (isCallable!Exportable) {
        if (addExportable!Exportable () != napi_status.napi_ok) {
          debug stderr.writeln (`Error registering function to JS`);
          return exports;
        } 
      } else static if (isMainFunction!Exportable ()) {
        // Just call it here (on module load).
        Exportable.ToCall (env);
      } else {
        const fieldName = (Exportables [i]).stringof.toStringz;
        // It's a field.
        // pragma (msg, `Got field ` ~ Exportable.stringof);
        auto toExp = Exportable.toNapiValue (env);
        auto status = napi_set_named_property (env, exports, fieldName, toExp);
      }
    }
    return exports;
  }

  // From the C macros that register the module.

  extern (C) static __gshared napi_module _module = {
    1  // nm_version
    , 0 // nm_flags
    , __FILE__.ptr
    , &.exportToJs
    , "NODE_GYP_MODULE_NAME"
    , null
  };
  
  version (Windows) { version (DigitalMars) {
    void main () {} // Dunno why it's needed but whatever
  }}

  extern (C) pragma (crt_constructor) export __gshared void _register_NAPI_MODULE_NAME () {
    napi_module_register (&_module);
  }
}
