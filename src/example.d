import dlang_node;
pragma(LDC_no_moduleinfo);

import std.demangle;
pragma(msg, demangle (`_D10dlang_node10jsFunctionFPS19js_native_api_types10napi_env__PSQBj12napi_value__PDFZvZEQCh11napi_status`));

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
  `fillStyle`, string
  , `arc`, void function (double x, double y, double r, double sAngle, double eAngle)
  , `beginPath`, void function ()
  , `closePath`, void function ()
  , `moveTo`, void function (double x, double y)
  , `fill`, void function ()
  , `fillRect`, void function (double x, double y, double width, double height)
  , `fillText`, void function (string text, double x, double y)
  , `lineTo`, void function (double x, double y)
  , `stroke`, void function ()
);

// Can use them just receiving an object of that type :D
auto canvasExample (CanvasRenderingContext2D ctx) {
  //ctx.fillStyle = "#FF0000";
  ctx.fillRect(12.5,30,175,70);

  // Draw triangle
  ctx.fillStyle="#A2322E";
  ctx.beginPath();
  ctx.moveTo(12.5,30);
  ctx.lineTo(185,30);
  ctx.lineTo(99,0);
  ctx.closePath();
  ctx.fill();
  //windows
  ctx.fillStyle="#663300";
  ctx.fillRect(25,40,35,50);
  ctx.fillStyle="#0000FF";
  ctx.fillRect(27,42,13,23);
  ctx.fillRect(43,42,13,23);
  ctx.fillRect(43,67,13,21);
  ctx.fillRect(27,67,13,21);

  //door
  ctx.fillStyle = "#754719";
  ctx.fillRect(80,53,30,47);

  //door knob
  ctx.beginPath();
  ctx.fillStyle = "#F2F2F2";
  import std.math : PI;
  ctx.arc(105,75,3,0,2*PI);
  ctx.fill();
  ctx.closePath();

  //Text on the Right
  //ctx.font="20px Veranda";
  ctx.fillText("Hello",130,60);
  //ctx.font="10px Veranda";
  ctx.fillText("Made In",130,75);
  ctx.fillText("Canvas",130,85);
  return 444;
}

auto logExample (Console console) {
  console.log (`Honk honk`);
}

mixin exportToJs!(initialize, kumiko, fumiko, callbackExample, canvasExample, logExample);
