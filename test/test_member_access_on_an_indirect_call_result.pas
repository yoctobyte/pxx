program test_member_access_on_an_indirect_call_result;
{ `.field` on the result of a call whose CALLEE IS NOT A LITERAL ROUTINE NAME.

  Member access on a DIRECT call result has worked since
  feature-member-access-on-call-result. Every INDIRECT spelling was broken, and
  in two different ways, which is why they are all here in one program:

    fp(8).c        procedural VARIABLE      parse: expected ')' before '.'
    mp(8).c        method POINTER           parse: expected ')' before '.'
    TF(pv)(8).c    procedural CAST          parse: expected ')' before '.'
    h.fn(8).c      procedural FIELD         parsed, then read OFFSET 0
    arr[0](8).c    procedural ELEMENT       parsed, then read OFFSET 0
    i.M(8).c       INTERFACE method         IR: could not lower (kind 58)
    mc.CM(8).c     virtual CLASS method     IR: could not lower (kind 88)

  THE FIELD IS `.c` AND NEVER `.a`, AND THAT IS THE POINT. Two of these rows
  failed by resolving the record id to REC_NONE and applying the selector at
  offset 0 -- a `.a` row prints the right answer there and certifies the bug as
  fixed. `.c` is k*3, which no offset-0 read can produce.

  The `via a local` rows are the control in the other direction: `r := fp(8)`
  and friends already worked, because the DESTINATION carries the record type
  and nothing has to ask the signature. A fix that broke ordinary aggregate
  returns would fail there and pass everywhere else.

  Oracle: fpc 3.2.2 -Mdelphi -O1, byte-identical output.
  bug-p-member-access-on-a-procedural-variable-call-result-is-rejected }
{$mode delphi}
type
  TR = record a, b, c: Integer; end;
  TF = function(k: Integer): TR;
  TMF = function(k: Integer): TR of object;
  TH = record fn: TF; end;

  IFoo = interface
    ['{11111111-2222-3333-4444-555555555555}']
    function M(k: Integer): TR;
  end;
  TFoo = class(TInterfacedObject, IFoo)
    function M(k: Integer): TR;
  end;
  TB = class
    class function CM(k: Integer): TR; virtual;
  end;
  TBClass = class of TB;

function Plain(k: Integer): TR;
begin Result.a := k; Result.b := k * 2; Result.c := k * 3; end;
function TFoo.M(k: Integer): TR;
begin Result.a := k; Result.b := k * 2; Result.c := k * 3; end;
class function TB.CM(k: Integer): TR;
begin Result.a := k; Result.b := k * 2; Result.c := k * 3; end;

var
  fp: TF; h: TH; arr: array[0..0] of TF; mp: TMF;
  foo: TFoo; ifc: IFoo; mc: TBClass; pv: Pointer; r: TR;
begin
  fp := @Plain; h.fn := @Plain; arr[0] := @Plain; pv := @Plain;
  foo := TFoo.Create; ifc := foo; mc := TB;
  mp := foo.M;

  { the control: the same calls consumed by an ordinary assignment }
  r := fp(8);     Writeln('local  var   ', r.c);
  r := ifc.M(8);  Writeln('local  intf  ', r.c);
  r := mc.CM(8);  Writeln('local  meta  ', r.c);

  { the subject: the same calls consumed by a member access }
  Writeln('direct var   ', fp(8).c);
  Writeln('direct meth  ', mp(8).c);
  Writeln('direct cast  ', TF(pv)(8).c);
  Writeln('direct field ', h.fn(8).c);
  Writeln('direct elem  ', arr[0](8).c);
  Writeln('direct intf  ', ifc.M(8).c);
  Writeln('direct meta  ', mc.CM(8).c);

  { every field, so a result copied at the wrong width shows up }
  Writeln('all fields   ', fp(8).a, ' ', fp(8).b, ' ', fp(8).c);
  { and twice in one expression, so a single-materialisation assumption shows up }
  Writeln('twice        ', fp(8).a + fp(8).b);
end.
