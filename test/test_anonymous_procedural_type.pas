{ An ANONYMOUS procedural type — `cb: procedure(l: LongInt)` written inline,
  with no named alias — is ordinary Pascal and FPC takes it. pxx rejected it
  everywhere, because the grammar lived in ParseTypeSection's NAMING path
  instead of in ParseTypeKind.

  The second half of this test is a distinct, pre-existing bug the first one
  uncovered: PreScanSkipRoutineBody read any `procedure`/`function` keyword in a
  routine's local declaration part as a nested routine, so a routine-local
  procedural type (named OR anonymous) made it hunt for a phantom routine's
  `begin`, find the enclosing routine's, and consume the real body.
  bug-a-an-anonymous-procedural-type-is-not-accepted
  bug-a-a-routine-local-procedural-type-eats-the-body }
program test_anonymous_procedural_type;

type
  TC = class
    procedure H(x: Integer);
  end;
  { anonymous procedural types as record fields, including two in one
    declaration and an `of object` one }
  TCallbacks = record
    a, b: procedure(l: LongInt);
    fn: function(x: Integer): Integer;
    m: procedure(x: Integer) of object;
    n: LongInt;
  end;
  TNested = record inner: TCallbacks; tag: LongInt; end;
  { FPC rejects an anonymous procedural type in a PARAMETER list, so the Apply
    row below uses a named one. pxx accepts the inline form there too — the
    dialect's documented laxness, not something to lock in against an oracle
    that cannot express it. }
  TIntFn = function(x: Integer): Integer;

procedure TC.H(x: Integer); begin WriteLn('meth ', x); end;
procedure S1(l: LongInt); begin WriteLn('s1 ', l); end;
procedure S2(l: LongInt); begin WriteLn('s2 ', l); end;
procedure Hi; begin WriteLn('hi'); end;
function Sq(x: Integer): Integer; begin Sq := x * x; end;
function CF(x: Integer): Integer; cdecl; begin CF := x + 100; end;

procedure Apply(g: TIntFn; v: Integer);
begin
  WriteLn('apply ', g(v));
end;

{ routine-local: a NAMED procedural type in a local type section — the shape
  that ate the body — and an anonymous one in the local var section }
procedure Local;
type
  TP = procedure(l: LongInt);
var
  named: TP;
  anon: procedure(l: LongInt);
  bare: procedure;
  f: function(x: Integer): Integer;
begin
  named := @S1; named(1);
  anon := @S2; anon(2);
  bare := @Hi; bare;
  f := @Sq; WriteLn('localfn ', f(4));
end;

{ ...and one level deeper, to prove the recursion into a real nested routine
  still finds its own begin }
procedure Outer;
var n: Integer;
  procedure Inner(k: Integer);
  var cb: procedure(l: LongInt);
  begin
    cb := @S1; cb(k);
  end;
begin
  n := 6; Inner(n);
end;

var
  cbs: TCallbacks;
  nst: TNested;
  c: TC;
  gv: procedure(l: LongInt);
  gc: function(x: Integer): Integer; cdecl;
  fa: array[0..1] of function(x: Integer): Integer;
  i: Integer;
begin
  c := TC.Create;

  gv := @S1; gv(10);
  WriteLn('assigned ', Assigned(gv));
  gv := nil;
  WriteLn('assigned ', Assigned(gv));

  gc := @CF; WriteLn('cdecl ', gc(8));

  cbs.n := 11;
  cbs.a := @S1; cbs.b := @S2; cbs.fn := @Sq; cbs.m := @c.H;
  cbs.a(12); cbs.b(13);
  WriteLn('field ', cbs.fn(5));
  cbs.m(14);
  WriteLn('after ', cbs.n);          { the fields after the procvars still line up }

  nst.tag := 15;
  nst.inner.a := @S1; nst.inner.a(16);
  WriteLn('nested ', nst.tag);

  fa[0] := @Sq; fa[1] := @Sq;
  for i := 0 to 1 do Write(fa[i](i + 2), ' ');
  WriteLn;

  Apply(@Sq, 7);
  Local;
  Outer;

  WriteLn('sizes ', SizeOf(cbs), ' ', SizeOf(nst));
  c.Free;
end.
