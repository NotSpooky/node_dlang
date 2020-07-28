import dlang_node;
extern (C):

auto initialize () {
  import core.runtime;
  rt_init();
  return 0;
}

auto kumiko(int first, long second) {
  return [first, second * 4, 0];
}
auto fumiko () {
  return 6;
}
import std.traits;
alias ExternD(T) = SetFunctionAttributes!(T, "D", functionAttributes!T);

auto callbackExample (ExternD!(void delegate ()) callback) {
  callback ();
  callback ();
  callback ();
  return 0;
}

mixin exportToJs!(initialize, kumiko, fumiko, callbackExample);
