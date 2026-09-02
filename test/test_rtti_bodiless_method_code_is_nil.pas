{ A METHOD WITH NO BODY MUST REFLECT AS nil, NOT AS ONE BYTE BELOW THE ENTRY
  POINT.

  Every writer resolved a VMT/RTTI method slot as `entry + Procs[p].BodyAddr',
  and a routine with no body has BodyAddr = -1. The slot therefore held
  `entry - 1': an address inside the image, plausible, and jumped to the first
  time anything called through it. typinfo's GetMethodAddr documents nil as its
  only "no address" answer, so a caller that checks for nil was handed a live
  pointer to nothing.

  Two populations have no body, both by declaration and both entirely normal:
  an ABSTRACT method (below) and an INTERFACE method (IInterface.QueryInterface
  and its two siblings -- the object-side half of this is asserted by the
  test_emit_obj `.rela.data' rows in the Makefile, because an interface's RTTI
  blob is not reachable from user code: it is deliberately absent from the class
  registry, measured, so GetClass('IInterface') answers nil).

  AIMED, and measured rather than predicted: the pre-fix compiler prints
  `Abs1 code nil=FALSE' and `GetMethodAddr Abs1 nil=FALSE' where this expects
  TRUE. The address it held was 4194535 in a build whose entry point was
  4194536 -- the two rows here say nil, and the arithmetic behind the wrong
  value is asserted where it can be seen directly, on the OBJECT, by the
  test_emit_obj `.rela.data' rows in the Makefile: they read `.text - 1'.

  THE CONTROL IS ROW 1 AND THE LAST TWO, and it is the point of them: a fix
  that nils every method slot passes the Abs1 rows and fails these. Real1 must
  still reflect a non-nil address AND still run when called through it. }
program test_rtti_bodiless_method_code_is_nil;

uses typinfo;

type
  TBase = class
    procedure Real1; virtual;
    procedure Abs1; virtual; abstract;
  end;
  TDer = class(TBase)
    procedure Abs1; override;
  end;
  TVoidFn = procedure(self: Pointer);

var
  ran: Integer;

procedure TBase.Real1; begin ran := ran + 7; end;
procedure TDer.Abs1;  begin ran := ran + 100; end;

var
  d: TDer;
  cls, par: PClassRTTI;
  mi: PMethInfo;
  fn: TVoidFn;

begin
  ran := 0;
  d := TDer.Create;
  cls := GetInstanceRTTI(d);
  if cls = nil then begin writeln('FAIL: no rtti'); halt(1); end;
  par := PClassRTTI(cls^.ParentRTTI);
  if par = nil then begin writeln('FAIL: no parent rtti'); halt(1); end;

  mi := GetMethInfoByName(par, 'Real1');
  if mi = nil then begin writeln('FAIL: Real1 not reflected'); halt(1); end;
  writeln('Real1 code nil=', mi^.Code = nil);

  mi := GetMethInfoByName(par, 'Abs1');
  if mi = nil then begin writeln('FAIL: Abs1 not reflected'); halt(1); end;
  writeln('Abs1 code nil=', mi^.Code = nil);

  writeln('GetMethodAddr Abs1 nil=', GetMethodAddr(par, 'Abs1') = nil);

  { the control, called through the reflected pointer }
  fn := TVoidFn(GetMethodAddr(par, 'Real1'));
  if fn = nil then begin writeln('FAIL: Real1 addr is nil'); halt(1); end;
  fn(Pointer(d));
  writeln('Real1 called, ran=', ran);
  writeln('DONE');
end.
