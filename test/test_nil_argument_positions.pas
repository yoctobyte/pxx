{ `nil` must be accepted everywhere a reference-shaped type is expected, not
  only where the type is spelled `Pointer`. pxx types `nil` as an INT_LIT 0
  tagged tyPointer, so the kind channel let it reach a Pointer, a PChar, a plain
  procvar and a dynamic array -- and refused it for the three that are NOT
  tyPointer: a CLASS, an INTERFACE (a record) and a METHOD POINTER (also a
  record, the 16-byte {Code,Data} layout).

  `P(o: TObject)` refusing `P(nil)` is the everyday half of that and was the
  bigger bug; the ticket was filed about the method-pointer half.

  Three positions, because each is a different mechanism and each was broken in
  its own way (bug-a-nil-is-not-accepted-as-a-method-pointer-argument):

    ARGUMENT      -- overload matching. Fixed by MatchArgNilOk, asked through
                     the single MatchParamCompatible seam rather than at the
                     seven compatible-phase call sites.
    DEFAULT VALUE -- `e: TEv = nil`, the OMITTED call `TakeDef;`. The default
                     node was built as the literal 0 wearing the PARAMETER's
                     kind, so lowering read an aggregate off address 0. Note
                     `TakeDef(nil)` written out was fine throughout -- the two
                     spellings of one call disagreed.
    RECORD CONST  -- `const R: TRec = (n: 4; ev: nil)`. Same shape again: the
                     field init was a literal 0 tagged tyRecord, i.e. an
                     address to copy 16 bytes from. This one segfaulted in
                     startup code BEFORE main, so the record's other fields
                     never initialised either and the failure did not look like
                     it was about `ev` at all.

  Every line below is checked against FPC 3.2.2, which produces this output
  exactly. }
program test_nil_argument_positions;
{$mode objfpc}
type
  TC = class end;
  IFoo = interface ['{c0000000-0000-0000-0000-000000000001}'] procedure Q; end;
  TPlain = procedure(x: Integer);
  TEv = procedure(x: Integer) of object;
  PInt = ^Integer;
  TDyn = array of Integer;
  THost = class
    procedure H(x: Integer);
  end;
  TRec = record n: Integer; ev: TEv; end;

const
  R: TRec = (n: 4; ev: nil);

procedure THost.H(x: Integer); begin writeln('H ', x); end;

{ argument position, one per nil-able shape }
procedure PClass(o: TC);      begin writeln('class'); end;
procedure PIntf(i: IFoo);     begin writeln('intf'); end;
procedure PPlain(p: TPlain);  begin writeln('plain'); end;
procedure PPtr(p: PInt);      begin writeln('ptr'); end;
procedure PPChar(p: PChar);   begin writeln('pchar'); end;
procedure PDyn(d: TDyn);      begin writeln('dyn'); end;

{ the method-pointer argument, and the fact that it really arrives nil }
procedure Take(e: TEv);
begin
  if e = nil then writeln('take nil') else begin e(1); writeln('take set'); end;
end;

{ default-value position: the omitted call and the written one must agree }
procedure TakeDef(e: TEv = nil);
begin
  if e = nil then writeln('def nil') else writeln('def set');
end;

var h: THost; v: TEv;
begin
  PClass(nil); PIntf(nil); PPlain(nil); PPtr(nil); PPChar(nil); PDyn(nil);

  Take(nil);
  h := THost.Create;
  v := @h.H;
  Take(v);

  TakeDef;
  TakeDef(nil);
  TakeDef(v);

  writeln('const n=', R.n);
  if R.ev = nil then writeln('const ev nil') else writeln('const ev set');
end.
