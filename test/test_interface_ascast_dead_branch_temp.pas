{ Regression: an interface `as`-cast temp is a skLocal COM-interface slot that
  EmitManagedLocalCleanup releases at routine scope exit. The temp is allocated
  during IR lowering — AFTER the prologue's managed-local zero-init pass — so when
  the `as`-cast sits in a branch the run does NOT take, the temp slot is never
  stored, yet the scope-exit release still fires: PXXIntfRelease on stale stack
  bytes → heap corruption / SIGSEGV (bug-pascal-interface-finalization-crash). The
  crash was memory-layout-sensitive (it hit at -O0/-O2/-O3 but not -O1), which is
  why it only surfaced with a fuller object graph on the fuzzer. CompileAST now
  nil-inits such temps at the head of the body. `usecast(false)` never runs the
  cast; `poison` first fills the reused stack region with a live interface pointer
  so an unguarded release would dereference garbage. Must print 120. }
program test_interface_ascast_dead_branch_temp;
{$mode objfpc}
type
  IPas0 = interface ['{11111111-0000-0000-0000-000000000001}'] function Ic0(a: longint): longint; end;
  IPas1 = interface ['{11111111-0000-0000-0000-000000000002}'] function Ic1(a: longint): longint; end;
  TIfc = class(TInterfacedObject, IPas0, IPas1)
    fi: longint;
    constructor Create(v: longint);
    function Ic0(a: longint): longint;
    function Ic1(a: longint): longint;
  end;
constructor TIfc.Create(v: longint); begin inherited Create; fi := v; end;
function TIfc.Ic0(a: longint): longint; begin Ic0 := a + fi; end;
function TIfc.Ic1(a: longint): longint; begin Ic1 := 1 + fi + a; end;
var iw0: IPas0; total: int64;
function poison: longint;
var p: array[0..7] of pointer; i: longint;
begin
  for i := 0 to 7 do p[i] := Pointer(iw0);
  if p[3] = nil then poison := 0 else poison := 1;
end;
function usecast(cond: boolean): longint;
var v: longint;
begin
  v := 5;
  if cond then
    v := (iw0 as IPas1).Ic1(v);
  usecast := v;
end;
var i: longint;
begin
  total := 0;
  iw0 := TIfc.Create(7);
  for i := 1 to 20 do
  begin
    total := total + poison;
    total := total + usecast(false);
  end;
  iw0 := nil;
  writeln(total);
end.
