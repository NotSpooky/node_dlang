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

napi_status stringToNapi (StrType)(napi_env env, StrType toCast, napi_value * toRet) {
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
    , cast (const NapiCharType *) toCast.ptr
    , toCast.length
    , toRet
  );
}

auto napiIdentity (napi_env _1, napi_value value, napi_value * toRet) {
  *toRet = value;
  return napi_status.napi_ok;
}

alias ExternD (T) = SetFunctionAttributes!(T, "D", functionAttributes!T);
alias ExternC (T) = SetFunctionAttributes!(T, "C", functionAttributes!T);


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
    napi_value [args.length - firstArgPos] napiArgs;
    foreach (i, arg; args [firstArgPos..$]) {
      napiArgs [i] = arg.toNapiValue (env);
    }
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

auto reference (napi_env env, napi_value obj) {
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
    , ulong line = cast (ulong) __LINE__
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
auto p (RetType = napi_value) (napi_value obj, napi_env env, string propName) {
  napi_value toRet;
  auto key = propName.toNapiValue (env);
  auto status = napi_get_property (env, obj, key, &toRet);
  if (status != napi_status.napi_ok) {
    throw new Exception (`Failed to get property ` ~ propName);
  }
  return fromNapi!RetType (env, toRet);
}
// Assign a property.
void p (InType) (napi_value obj, napi_env env, string propName, InType newVal) {
  auto key = propName.toNapiValue (env);
  auto status = napi_set_property (env, obj, key, newVal.toNapiValue (env));
  if (status != napi_status.napi_ok) {
    throw new Exception (`Failed to set property ` ~ propName);
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

  auto opIndex (string propName) {
    return context.p!JSVar (env, propName);
  }

  auto opIndexAssign (T)(T toAssign, string propName) {
    context ().p (env, propName, toAssign);
  }

  template opDispatch (string s) {
    R opDispatch (R = JSVar, T...)(T args) {
      auto ctx = this.context ();
      auto toCallAsNapi = ctx.p(env, s);
      auto asCallable = fromNapi! (R delegate (napi_value, T))(env, toCallAsNapi);
      static if (is (R == void)) {
        asCallable (ctx, args);
      } else {
        return asCallable (ctx, args);
      }
    }
  }

  auto jsLog () {
    console (this.env).log (this.context ());
  }

  auto opCast (T) () {
    return fromNapi!T (env, this.context ());
  }
}

/// Similar to JSObj but doesn't have a reference counter, so cannot be used
/// after the JS call that has the scope where this was created.
/// Template is a struct type that contains fields and function declarations
/// that this struct will attempt to copy in signature but with JS type conversions.
/// Do note that accessing members is done lazily.
alias ScopedJSObj (Template) = JSObj!(Template, false);

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

  alias Members = __traits (allMembers, Template);
  alias FieldNames = Members;
  private template type (string name) {
    alias type = typeof (mixin (`Template.` ~ name));
  }
  import std.meta;
  alias FieldTypes = staticMap! (type, Members);
  private static auto positions () {
    size_t [] funPositions;
    size_t [] fieldPositions;
    static foreach (i, Member; Members) {
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

  static assert (FieldNames.length == FieldTypes.length);
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
      auto context = new napi_value ();
      auto status = napi_create_object (env, context);
      assert (status == napi_status.napi_ok);
      ctxRef = reference (env, *context);
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
    // Add function that simply uses callNapi.
    mixin (
      q{auto } ~ FieldNames [FunPosition] ~ q{ (Parameters!(FieldTypes[FunPosition]) args) {
        alias FunType = FieldTypes [FunPosition];
        alias RetType = ReturnType!(FunType);
          //auto context = val (env, this.ctxRef);
          auto toCall = context
            .p! (RetType delegate (napi_value, Parameters!FunType))
              (env, FieldNames [FunPosition]);
          static if (is (RetType == void)) {
            toCall (context, args);
          } else {
            return toCall (context, args);
          }
        }
      }
    );
  }
  static foreach (i, FieldPosition; FieldPositions) {
    // Setter.
    static if (isVariantN! (FieldTypes [FieldPosition])) {
      // Also add implicit conversions :)
      static foreach (PossibleType; TemplateArgsOf!(FieldTypes [FieldPosition])[1..$]) {
        mixin (q{
          void } ~ FieldNames [FieldPosition] ~ q{ (PossibleType toSet) {
            enum fieldName = FieldNames [FieldPosition];
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
auto console = (napi_env env) => fromNapi!Console (env, global (env, `console`));
void jsLog (T)(napi_env env, T toLog) {
  console (env).log (toLog.toNapiValue (env));
}
auto global (napi_env env) {
  napi_value val;
  auto status = napi_get_global (env, &val);
  assert (status == napi_status.napi_ok, `Couldn't get global context`);
  return val;
}
auto global (napi_env env, string name) {
  return global (env).p (env, name);
}
auto global (RetType)(napi_env env, string name) {
  return fromNapi!RetType (env, global (env, name));
}

/// Note: Only available if the module's globals have 'require' which is not usually
/// the case
auto requireJs (RetType = napi_value) (napi_env env, string id) {
  try {
    return fromNapi!(RetType delegate (string)) (env, global (env, `require`)) (id);
  } catch (Exception ex) {
    debug stderr.writeln (
      `Errored on require, probably the globals object doesn't contain require.`
      , "\nConsider sending the loaded module data from JS"
    );
    throw (ex);
  }
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

auto getJSVar (napi_env env, napi_value napiVal, JSVar * toRet) {
  *toRet = JSVar (env, napiVal);
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
    alias fromNapiB = napi_get_value_uint64;
  } else static if (is (T == double)) {
    alias fromNapiB = napi_get_value_double;
  } else static if (is (T == float)) {
    alias fromNapiB = getFloat;
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
  } else static if (__traits(hasMember, T, `dlangNodeIsJSObj`)) {
    alias fromNapiB = getJSobj;
  } else static if (isVariantN!T) {
    static assert (
      0
      , `Don't use fromNapiB to get a VariantN/Algebraic, get the expected type instead`
    );
  } else {
    static assert (0, `Not implemented: Convertion from JS type for ` ~ T.stringof);
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

napi_status arrayToNapi (F)(napi_env env, F[] array, napi_value * toRet) {
  napi_status status = napi_status.napi_generic_failure;
  assert (toRet != null);
  status = napi_create_array_with_length (env, array.length, toRet);
  if (status != napi_status.napi_ok) {
    return status;
  }
  foreach (i, val; array) {
    // Create a napi_value for 'hello'
    auto nv = val.toNapiValue (env);

    status = napi_set_element (env, *toRet, i.to!uint, nv);
    if (status != napi_status.napi_ok) return status;
  }
  return status;
}

napi_status jsObjToNapi (T)(napi_env env, T toConvert, napi_value * toRet) {
  assert (toRet != null);
  assert (env == toConvert.env);
  *toRet =  toConvert.context;
  return napi_status.napi_ok;
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
  return callbackToNapi (env, &fromJsPtr!(Dg), toRet, toCall);
}

napi_status callableToNapi (F)(napi_env env, F toCall, napi_value * toRet) {
  assert (toRet != null);
  static assert (!isDelegate!(F), `Use delegateToNapi instead`);
  return callbackToNapi (env, &fromJsPtr!F, toRet, toCall);
}

napi_status algebraicToNapi (T ...)(napi_env env, VariantN!T toConvert, napi_value * toRet) {
  static assert (T.length > 1);
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
  assert (env == toConvert.env, `JS environments don't match`);
  *toRet = toConvert.context ();
  return napi_status.napi_ok;
}

template toNapi (alias T) {
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
    alias toNapi = napi_create_uint64;
  } else static if (is (T : double)) {
    alias toNapi = napi_create_double;
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
  } else static if (is (T == A[], A)) {
    alias toNapi = arrayToNapi;
  } else static if (__traits(hasMember, T, `dlangNodeIsJSObj`)) {
    alias toNapi = jsObjToNapi;
  } else static if (isVariantN!T) {
    alias toNapi = algebraicToNapi;
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
  return convertNapiSignature!(F, toCall) (env, info, cast (void **) & toCall);
}

extern (C) napi_value withNapiExpectedSignature (alias Function)(
  napi_env env
  , napi_callback_info info
) {
  return convertNapiSignature!(typeof(Function), Function) (env, info, null);
}

template Returns (alias Function, OtherType) {
  import std.traits : ReturnType;
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
  debug import std.stdio;

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
        , &withNapiExpectedSignature!Exportable
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
