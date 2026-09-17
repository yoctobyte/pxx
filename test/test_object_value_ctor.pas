{ An old-style `object` may declare a CONSTRUCTOR and a DESTRUCTOR.
  They are plain methods: pxx hard-errors on both routes to a VMT -- an
  ancestor and a `virtual`/`dynamic`/`override`/`abstract` directive -- so every
  `object` that compiles at all is VMT-less, and on a VMT-less object there is
  nothing for a constructor to set. fpc agrees; this file compiles and prints
  the same bytes under both.

  THE PARAMETERLESS CONSTRUCTOR IS THE ROW THAT MATTERS, and it is deliberately
  NOT last: `Init` takes parameters, `Reset` takes none, and `Reset` is declared
  and called BETWEEN two parameterful members, because the Delphi RECORD rule
  ("at least one parameter without a default value") applied to objects would
  refuse exactly it -- and FPC's own versioncmp.pas:35 writes that shape
  (`constructor invalidate;`). A fixture with the parameterless row last would
  pass on a compiler that stopped at the first member it disliked.

  The DESTRUCTOR is likewise not a `Dispose` partner here: it is called directly
  as `v.Done`, which is the only form pxx implements. The extended
  `New(p, Init)` / `Dispose(p, Done)` forms go through the VMT in fpc and are
  refused by name -- see test_object_value_ctor_fail.pas.
  feature-p-legacy-value-object-types }
program test_object_value_ctor;

type
  TVer = object
   private
    fstr: string;
    fnum: Cardinal;
   public
    constructor Init(const s: string; maj, min: Byte);
    constructor Reset;
    function Num: Cardinal;
    function Str: string;
    destructor Done;
  end;

constructor TVer.Init(const s: string; maj, min: Byte);
begin
  fstr := s;
  fnum := Cardinal(maj) * 256 + min;
end;

constructor TVer.Reset;
begin
  fstr := '<none>';
  fnum := 0;
end;

function TVer.Num: Cardinal;
begin
  Num := fnum;
end;

function TVer.Str: string;
begin
  Str := fstr;
end;

destructor TVer.Done;
begin
  fstr := '';
  fnum := 999;
end;

var
  a, b: TVer;
begin
  a.Init('3.2.2', 3, 2);
  WriteLn('a.str=', a.Str, ' a.num=', a.Num);

  b.Reset;
  WriteLn('b.str=', b.Str, ' b.num=', b.Num);

  { a value object is a VALUE: assignment copies, and the copy is independent }
  b := a;
  b.Init('9.9.9', 9, 9);
  WriteLn('after copy+init  a.num=', a.Num, ' b.num=', b.Num);

  a.Done;
  WriteLn('after done       a.str=[', a.Str, '] a.num=', a.Num);
  b.Done;
  WriteLn('after done       b.num=', b.Num);
end.
