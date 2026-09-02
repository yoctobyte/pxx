{ NEGATIVE: a CONST and a ROUTINE of the same name are ONE identifier, because
  Pascal is case-insensitive, and a call spelled with the routine's casing must
  not silently fold to the const's value.

  It used to. compiler/builtin/pylib.pas declared `PYITER_MAP = 4` beside
  `function pyiter_map(key: Pointer; const v: Variant): TPyIter` -- four such
  pairs -- and `pyiter_map(key, v)` in pyeval.pas answered 4 with the arguments
  thrown away. Silently, on every target. i386 alone objected, and only
  indirectly: it refuses to LOAD a const symbol, so it turned a wrong answer
  into `symbol kind not supported yet (load)` and every program pulling in
  pyeval was unbuildable there, including examples/tk.

  FPC rejects the declaration PAIR ("overloaded identifier isn't a function"),
  so this was never reachable through parity. We keep accepting the pair -- a
  tag constant beside its constructor is a real thing to write -- and refuse the
  CALL, which is a mistake under any reading.
  bug-a-a-const-and-a-routine-of-the-same-name-silently-resolve-to-the-const }
program test_const_shadows_routine_fail;
const
  MY_THING = 4;
function my_thing(a: Integer): Integer;
begin
  my_thing := a * 100;
end;
var r: Integer;
begin
  r := my_thing(7);      { NOT 4, and not 700 either -- this must not compile }
  WriteLn(r);
end.
