program test_shortstring_parameter_truncates_through_every_call_shape;
{ The SIBLING SWEEP for test_shortstring_value_parameter_truncates.pas.

  That file fixed the `string[N]` value-parameter clamp and asserted it through
  a direct call to a free routine. The capacity lives on the CALLEE'S ROW
  (ProcParamStrCap), and a row is written by whichever path registered that
  signature -- so the clamp is only as wide as the set of registration paths
  that fill the column. Two did not, and neither was reachable from the
  original test:

    - an INTERFACE method has no out-of-line implementation header at all, so
      the class-body path in pasparser_decl.inc is the ONLY registration its
      signature ever gets (row C);
    - a PROCEDURAL TYPE is registered by ParseProcTypeSig, which drops the
      field for the fourth time in one routine -- its own comments already name
      three instances of the same pattern for the RESULT type (the pointee, the
      enum identity, the record id), and this is the param side of it (row D).

  Both printed `len=10` against fpc 3.2.2's 4, while the identical routine
  called DIRECTLY printed 4 -- which is the tell: the defect is in the row that
  answers for that call shape, not in the clamp.

  .expected is fpc 3.2.2's own output.

  EVERY ROW HERE IS A DISTINCT REGISTRATION PATH, which is the whole point of
  the file. A, B and E were already correct when it was written and are the
  regression controls -- a change to how any row is registered must not be able
  to fix one path and quietly break another, and the two that were broken were
  found only by asking which paths existed rather than by a failure report.

  EACH ROW PRINTS ITS OWN TAG, and that is not decoration. Every row's correct
  answer is the same four characters, so an untagged file prints six identical
  lines: a capture whose value is constant across the population cannot say
  WHICH path regressed, and two rows swapping produces no signal at all. The
  tag is what makes the diff name the call shape. }
{$mode objfpc}{$interfaces corba}
type
  String4 = String[4];
  IFoo = interface
    procedure ByVal(tag: AnsiString; st: String4);
  end;
  TT = class(TObject, IFoo)
    procedure ByVal(tag: AnsiString; st: String4);
  end;
  TCb   = procedure(tag: AnsiString; st: String4);
  TMeth = procedure(tag: AnsiString; st: String4) of object;

procedure TT.ByVal(tag: AnsiString; st: String4);
begin
  WriteLn(tag, ': len=', Length(st), ' [', st, ']');
end;

procedure Free4(tag: AnsiString; st: String4);
begin
  WriteLn(tag, ': len=', Length(st), ' [', st, ']');
end;

procedure Outer;
  procedure Nested(tag: AnsiString; st: String4);
  begin
    WriteLn(tag, ': len=', Length(st), ' [', st, ']');
  end;
begin
  Nested('E nested routine', 'literalfar');
end;

var
  o: TT;
  f: IFoo;
  cb: TCb;
  mp: TMeth;
begin
  o := TT.Create;
  f := o;
  cb := @Free4;
  mp := @o.ByVal;

  Free4( 'A direct free routine',  'literalfar');
  o.ByVal('B direct class method',  'literalfar');
  f.ByVal('C interface reference',  'literalfar');
  cb(     'D procedural-type var',  'literalfar');
  Outer;                          { E }
  mp(     'F method pointer',       'literalfar');
end.
