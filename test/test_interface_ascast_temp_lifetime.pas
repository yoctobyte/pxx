{ Regression: a COM interface `as`-cast inside a routine creates an owning
  interface temp (QueryInterface AddRefs it), which must live until the routine's
  scope exit — NOT be released early. pxx used to release the skLocal as-cast
  temp at routine end WITHOUT a matching AddRef, so the temp under-refcounted the
  object: the destructor ran when the routine returned (while the global `a` still
  held the only intended reference), and the later `a := nil` double-dropped it →
  use-after-free / SIGSEGV with a fuller object graph
  (bug-pascal-interface-finalization-crash). FPC keeps the object alive across the
  call; `a.GetV` after P must still read 7. }
program test_interface_ascast_temp_lifetime;
{$mode objfpc}
type
  IA = interface ['{a0000000-0000-0000-0000-000000000001}'] function GetV: longint; end;
  IB = interface ['{b0000000-0000-0000-0000-000000000002}'] function GetW: longint; end;
  TC = class(TInterfacedObject, IA, IB)
    fi: longint;
    constructor Create(v: longint);
    destructor Destroy; override;
    function GetV: longint;
    function GetW: longint;
  end;
constructor TC.Create(v: longint); begin inherited Create; fi := v; end;
destructor TC.Destroy; begin writeln('destroy ', fi); inherited Destroy; end;
function TC.GetV: longint; begin GetV := fi; end;
function TC.GetW: longint; begin GetW := fi + 100; end;
var a: IA;
procedure P;
begin
  writeln('in P w=', (a as IB).GetW);
end;
begin
  a := TC.Create(7);
  P;
  writeln('alive v=', a.GetV);
  a := nil;
  writeln('done');
end.
