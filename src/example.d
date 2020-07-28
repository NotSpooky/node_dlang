import dlang_node;
extern (C):

auto initialize () {
  import core.runtime;
  rt_init();
  return 0;
}

auto kumiko(int first, long second) {
  return [first, second * 4, 1000];
}

mixin exportToJs!(initialize, kumiko);
