{ An implicit-conversion operator applies to any source ASSIGNMENT-COMPATIBLE
  with its parameter, not only to one whose type kind matches exactly.

  It used to match exactly, so `c := 10` against
  `operator := (const s: Int64): TCe` answered *cannot assign Integer to
  record* while `c := someInt64` worked — the acceptance matrix was the
  diagonal and nothing else. That fails on the first line most users write:
  giving a record value semantics against builtins is what `operator :=` is
  FOR, and an integer literal is the commonest thing anyone assigns to one.

  Widening the SOURCE alone would be unsound — the overload table is keyed on
  the source, so two conversions to different records would answer each other's
  assignments. The DESTINATION disambiguates, and it costs no new column: it is
  the operator proc's own return type. The TA/TB block below is that case.

  Ranks are FPC's, measured: exact kind, else same SIGNEDNESS, else any
  integer, else (last) a float parameter. A Byte prefers the unsigned
  parameter even though the signed one would hold it. A float source reaches
  only a float parameter — FPC has no implicit float-to-integer, and neither
  has this.

  FPC's own constexp.pas declares exactly the QWord/Int64 pair in the second
  block and then assigns plain integer constants throughout, which is the
  corpus case this was opened for.
  bug-p-an-implicit-conversion-operator-needs-an-exact-type-kind-match }
program test_implicit_conversion_operator_widens_source;

type
  TFromInt   = record v: Int64; end;
  TFromI64   = record v: Int64; end;
  TFromQWord = record v: Int64; end;
  TFromDbl   = record v: Double; end;
  TFromByte  = record v: Int64; end;

  { the ambiguity guard: two conversions, two destinations, overlapping sources }
  TA = record v: Int64; end;
  TB = record v: Int64; end;

  { constexp.pas's pair: two conversions, ONE destination }
  TCe = record v: Int64; tag: Integer; end;

operator := (const u: Integer): TFromInt;   begin Result.v := u;        end;
operator := (const u: Int64):   TFromI64;   begin Result.v := u;        end;
operator := (const u: QWord):   TFromQWord; begin Result.v := Int64(u); end;
operator := (const u: Double):  TFromDbl;   begin Result.v := u;        end;
operator := (const u: Byte):    TFromByte;  begin Result.v := u;        end;

operator := (const a: Int64):   TA; begin Result.v := a * 10;  end;
operator := (const b: Integer): TB; begin Result.v := b * 100; end;

operator := (const u: QWord): TCe; begin Result.v := Int64(u); Result.tag := 1; end;
operator := (const s: Int64): TCe; begin Result.v := s;        Result.tag := 2; end;

var
  ai: TFromInt; a64: TFromI64; aq: TFromQWord; ad: TFromDbl; ab: TFromByte;
  va: TA; vb: TB; c: TCe;
  ni: Integer; n64: Int64; nq: QWord; nd: Double; nb: Byte;
begin
  ni := 1; n64 := 2; nq := 3; nd := 4.5; nb := 5;

  { every integer source reaches every integer-parameter operator }
  ai := 10;   a64 := 10;   aq := 10;   ab := 10;
  writeln(ai.v, ' ', a64.v, ' ', aq.v, ' ', ab.v);
  ai := ni;   a64 := ni;   aq := ni;   ab := ni;
  writeln(ai.v, ' ', a64.v, ' ', aq.v, ' ', ab.v);
  ai := n64;  a64 := n64;  aq := n64;  ab := n64;
  writeln(ai.v, ' ', a64.v, ' ', aq.v, ' ', ab.v);
  ai := nq;   a64 := nq;   aq := nq;   ab := nq;
  writeln(ai.v, ' ', a64.v, ' ', aq.v, ' ', ab.v);
  ai := nb;   a64 := nb;   aq := nb;   ab := nb;
  writeln(ai.v, ' ', a64.v, ' ', aq.v, ' ', ab.v);

  { an integer reaches a FLOAT parameter too, and a float reaches only that one }
  ad := 10;  writeln(ad.v:0:1);
  ad := ni;  writeln(ad.v:0:1);
  ad := nd;  writeln(ad.v:0:1);

  { two destinations, overlapping sources: each picks its own }
  va := 10;  vb := 10;  writeln(va.v, ' ', vb.v);
  va := ni;  vb := ni;  writeln(va.v, ' ', vb.v);
  va := n64;             writeln(va.v);

  { one destination, two sources: the rank order is what picks }
  c := 10;   writeln('lit   ', c.tag);
  c := ni;   writeln('int   ', c.tag);
  c := nb;   writeln('byte  ', c.tag);
  c := nq;   writeln('qword ', c.tag);
  c := n64;  writeln('int64 ', c.tag);
end.
