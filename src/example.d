import dlang_node;
pragma(LDC_no_moduleinfo);

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

auto rectExample (CanvasRenderingContext2D ex) {
  import std.stdio;
  ex.fillRect (13,24,30,600);
  return 444;
}

mixin exportToJs!(initialize, kumiko, fumiko, callbackExample, rectExample);
