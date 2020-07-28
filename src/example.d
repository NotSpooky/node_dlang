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

auto callbackExample (ExternD!(void delegate ()) callback) {
  callback ();
  callback ();
  callback ();
}

mixin exportToJs!(initialize, kumiko, fumiko, callbackExample);
