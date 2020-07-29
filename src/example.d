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

// Dechare methods of an object like this.
alias CanvasRenderingContext2D = JSobj!(
  `beginPath`, void function ()
  , `moveTo`, void function (double x, double y)
  , `stroke`, void function ()
  , `fill`, void function ()
  , `lineTo`, void function (double x, double y)
  , `fillRect`, void function (double x, double y, double width, double height)
);

// Can use them just receiving an object of that type :D
auto canvasExample (CanvasRenderingContext2D ctx) {
  with (ctx) {
    beginPath ();
    moveTo (5, 10);
    lineTo (300, 150);
    stroke (); 
  }
  return 444;
}

auto logExample (Console console) {
  console.log (`Honk honk`);
}

mixin exportToJs!(initialize, kumiko, fumiko, callbackExample, canvasExample, logExample);
