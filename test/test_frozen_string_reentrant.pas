{$undef PXX_MANAGED_STRING}
program test_frozen_string_reentrant;
{ Frozen-string function Result must be per-call (reentrant), not a shared global
  (bug-frozen-string-result-global-not-reentrant). Covers the three call paths now
  routed through the hidden caller-destination ABI: direct (incl. recursion),
  virtual, and indirect (proc-pointer). x86-64. }

var ok: Integer;

procedure Chk(n: Integer; cond: Boolean);
begin
  if cond then begin writeln('ok ', n); ok := ok + 1; end else writeln('FAIL ', n);
end;

{ ---- direct recursion: write Result, recurse, return Result unchanged ----
  A shared-global Result would be clobbered by the inner call. }
function Build(n: Integer): string;
var inner: string;
begin
  Build := Chr(Ord('0') + n);
  if n > 0 then inner := Build(n - 1);   { inner overwrites a shared slot }
end;

{ ---- virtual ---- }
type
  TB = class function G(i: Integer): string; virtual; abstract; end;
  TI = class(TB) function G(i: Integer): string; override; end;
function TI.G(i: Integer): string; begin G := 'v' + Chr(Ord('0') + i); end;

{ ---- indirect (proc pointer) ---- }
type TF = function(n: Integer): string;
function Make(n: Integer): string; begin Make := 'p' + Chr(Ord('0') + n); end;

var
  b: TB;
  f: TF;
begin
  ok := 0;

  Chk(1, Build(5) = '5');           { reentrant direct: not clobbered to '0' }

  b := TI.Create;
  Chk(2, b.G(1) = 'v1');            { virtual frozen return }
  Chk(3, b.G(2) = 'v2');            { second virtual call independent }

  f := @Make;
  Chk(4, f(7) = 'p7');             { indirect frozen return }

  writeln('total ok ', ok, ' / 4');
end.
