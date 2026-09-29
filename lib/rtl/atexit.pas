{ SPDX-License-Identifier: Zlib }
unit atexit;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Python's `atexit` for the Nil-Python frontend.

  Named `atexit` so `import atexit` needs no frontend change (NilPy turns
  `import X` into the unit resolver's `uses X`, like lib/rtl/re.pas).

  `atexit.register(fn)` records a callable to run when the program ends, and
  CPython runs them LAST-REGISTERED FIRST. That maps exactly onto a unit's
  FINALIZATION section, which pxx already runs at exit in reverse initialisation
  order — so the handlers live here and the exit chain carries them.

  Differences from CPython, both deliberate:
  - `register` takes no arguments to forward (`register(fn, *args)`); the
    handlers real programs write are closures over what they need, which is what
    songformatter's `del_tmp_file` does.
  - an exception escaping a handler is not caught and re-raised as CPython's
    is — it propagates, which is the honest behaviour until NilPy's exception
    surface is settled in this position.
  `unregister` is here because it is trivial once the list exists. }

interface

uses pylib, pyeval;

{ Record a callable to run at exit. Returns the callable, as CPython's does, so
  `@atexit.register` reads naturally when decorators arrive. }
function register(const fn: Variant): Variant;
{ Remove a previously registered callable (matched by value). }
procedure unregister(const fn: Variant);

implementation

const
  MAX_ATEXIT = 64;

var
  gFns: array[0..MAX_ATEXIT - 1] of Variant;
  gCount: Integer;

function register(const fn: Variant): Variant;
begin
  if gCount >= MAX_ATEXIT then
  begin
    WriteLn('atexit: more than ', MAX_ATEXIT, ' handlers registered');
    Halt(1);
  end;
  gFns[gCount] := fn;
  gCount := gCount + 1;
  Result := fn;
end;

{ Is `a` the callable `b` names? CPython's unregister compares with ==. A def
  or a bound method is a {code, receiver} PAIR (pycallback_is), and every
  mention of the name boxes a NEW pair, so its identity is the pair's contents:
  matching the payload let `unregister(f)` miss the `register(f)` it undoes.
  A lambda or a closure is one heap object per value, so it matches by object. }
function SameCallable(const a, b: Variant): Boolean;
begin
  if pycallback_is(a) and pycallback_is(b) then
    SameCallable := (pybound_code(a) = pybound_code(b)) and
                    (pybound_recv(a) = pybound_recv(b))
  else
    SameCallable := PPyVarRec(@a)^.Payload = PPyVarRec(@b)^.Payload;
end;

procedure unregister(const fn: Variant);
var i, j: Integer;
begin
  i := 0;
  while i < gCount do
  begin
    if SameCallable(gFns[i], fn) then
    begin
      for j := i to gCount - 2 do gFns[j] := gFns[j + 1];
      gCount := gCount - 1;
    end
    else
      i := i + 1;
  end;
end;

initialization
  gCount := 0;

finalization
  { LAST registered runs FIRST, as CPython documents. }
  while gCount > 0 do
  begin
    gCount := gCount - 1;
    pycall_value(gFns[gCount], pynone, False);
  end;

end.
