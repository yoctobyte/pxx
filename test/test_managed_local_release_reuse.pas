{ Scope-exit release, proved by ADDRESS REUSE rather than by counting.

  A missing scope-exit release is a LEAK, and a leak prints nothing — which is
  how the dyn-array arm stayed missing on four backends, the static-array arm on
  three, riscv32's COM-interface arm on one, and i386's variant/record arms on
  one (bug-a-scope-exit-release-matrix-has-four-holes-left-on-i386-and-arm32).
  Every test that did catch one of these counted DESTRUCTOR calls, which only
  works for a class; a Variant, a record and a string have no destructor to
  count.

  So this counts nothing and observes the allocator instead: pxx's free list
  hands a released block straight back for the next same-sized request, so a
  routine that allocates one managed local per call returns the SAME address
  every call — unless the local is leaked, in which case each call takes a fresh
  block and the address marches upward. First call vs fortieth is the whole
  assertion, and it needs no destructor, no counter and no heap instrumentation.

  Each routine below allocates a freshly-built (never literal, never interned)
  string so the block cannot be shared, and hands back the payload address.

  Wired into the i386 / arm32 / aarch64 target blocks as an output comparison
  against the x86-64 build, which is where the value lies: the arms differ per
  backend and the native answer is the oracle. }
program test_managed_local_release_reuse;
{$mode objfpc}{$H+}

type
  TRec = record
    s: AnsiString;
    n: Integer;
  end;

var
  i, pass, fail: Integer;
  a1, a2: PtrUInt;

{ A string built at run time: 'payload-X-0123456789abcdef', X varying, so the
  compiler cannot fold it to a literal in the data segment. }
function Uniq(n: Integer): AnsiString;
begin
  Uniq := 'payload-' + Chr(65 + (n mod 26)) + '-0123456789abcdef';
end;

procedure StrRound(n: Integer; var addr: PtrUInt);
var s: AnsiString;
begin
  s := Uniq(n);
  addr := PtrUInt(Pointer(s));
end;

procedure RecRound(n: Integer; var addr: PtrUInt);
var r: TRec;
begin
  r.s := Uniq(n);
  r.n := n;
  addr := PtrUInt(Pointer(r.s));
end;

procedure VarRound(n: Integer; var addr: PtrUInt);
var v: Variant; s: AnsiString;
begin
  s := Uniq(n);
  v := s;
  addr := PtrUInt(Pointer(s));
end;

procedure StaticArrRound(n: Integer; var addr: PtrUInt);
var a: array[0..2] of AnsiString;
begin
  { ONE element only. The free list is LIFO per size bin, so a round that frees
    three blocks and then requests three hands them back in reverse — the
    address would differ every call with nothing leaked at all, and the probe
    would read a correct release as a failure. }
  a[0] := Uniq(n);
  addr := PtrUInt(Pointer(a[0]));
end;

procedure DynArrRound(n: Integer; var addr: PtrUInt);
var a: array of AnsiString;
begin
  SetLength(a, 3);
  a[0] := Uniq(n);
  addr := PtrUInt(Pointer(a[0]));
end;

procedure Chk(const what: AnsiString; reused: Boolean);
begin
  if reused then
  begin
    Inc(pass);
    writeln('ok   ', what);
  end
  else
  begin
    Inc(fail);
    writeln('FAIL ', what, ' — block not reused, so the local leaked');
  end;
end;

begin
  pass := 0; fail := 0;

  StrRound(1, a1);
  for i := 2 to 40 do StrRound(i, a2);
  Chk('ansistring local', a1 = a2);

  RecRound(1, a1);
  for i := 2 to 40 do RecRound(i, a2);
  Chk('record with managed field', a1 = a2);

  VarRound(1, a1);
  for i := 2 to 40 do VarRound(i, a2);
  Chk('variant local', a1 = a2);

  StaticArrRound(1, a1);
  for i := 2 to 40 do StaticArrRound(i, a2);
  Chk('static array of string', a1 = a2);

  DynArrRound(1, a1);
  for i := 2 to 40 do DynArrRound(i, a2);
  Chk('dynamic array of string', a1 = a2);

  writeln('total ok ', pass, ' / ', pass + fail);
end.
