{ A COM interface `as`-cast temp created in the MAIN program body must live until
  end-of-main (FPC), so the object is destroyed AFTER the last body statement — not
  early when `a := nil` drops the global var's reference. pxx modelled the main-body
  temp as a plain skGlobal alias (no retain / no release), so the object died at
  `a := nil` and the destructor's output landed before "after nil"
  (bug-pascal-mainbody-ascast-temp-finalization-timing). Now the temp is AddRef'd on
  creation and released at program exit. Expected order: cast=107 / after nil /
  destroy 7. }
program test_interface_mainbody_ascast_temp;
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
begin
  a := TC.Create(7);
  writeln('cast=', (a as IB).GetW);
  a := nil;
  writeln('after nil');
end.
