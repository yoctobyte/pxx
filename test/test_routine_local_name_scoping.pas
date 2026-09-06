program test_routine_local_name_scoping;
{ Routine-local declarations are scoped to the routine and shadow outward, in
  EVERY name table that a routine's `type`/`const` section can write to. There
  are five, they were flat, and the rule was implemented in exactly one of them.
  bug-p-routine-local-name-scoping-is-implemented-in-one-of-three-tables

  ONE ROW PER TABLE, because they fail independently and a fix to one moved
  none of the others:
    1-2  UCls    a record TYPE name, sibling routines        (the flat scan)
    3-4  alias   a type ALIAS, nested routine shadows outer  (a different table
                 for what looks like the same declaration)
    5-6  setcon  a set const, SIBLING routines               (no nesting at all)
    7    strcon  a nested routine READING the enclosing const (the over-correct
                 arm: this one was refused, not miscomputed)
    8    Syms    an ordinary local, the control that was always right

  Sizes and membership rather than flags, and no expected value is 0, 1-by-
  default or SizeOf(Integer) — row 5 asks a set for a member the leaked
  constant DOES contain, so a leak answers TRUE and the correct answer is
  FALSE. If the machinery did nothing, no row here still passes. }

procedure R1;                       { UCls: the earlier sibling }
type TRec = packed record p, q, r: Byte; end;
var v: TRec;
begin Writeln(SizeOf(v)); end;      { 3 }

procedure R2;                       { UCls: its own TRec, same spelling }
type TRec = packed record s: Byte; end;
var v: TRec;
begin Writeln(SizeOf(v)); end;      { 1 }

procedure R3;                       { alias + nesting }
type TNum = LongInt;
var w: TNum;

  procedure Inner;
  type TNum = Byte;
  var v: TNum;
  begin Writeln(SizeOf(v)); end;    { 1 — its own }

begin Writeln(SizeOf(w)); Inner; end;   { 4 then 1 }

procedure S1;                       { set const: the earlier sibling }
const S = [1, 2, 3];
var v: set of Byte;
begin v := S; Writeln(3 in v); end; { TRUE }

procedure S2;                       { set const: its own S, same spelling }
const S = [7, 8];
var v: set of Byte;
begin v := S; Writeln(3 in v); end; { FALSE — TRUE means S1's leaked }

procedure C1;                       { string const read from a NESTED routine }
const Greeting = 'from outer';

  procedure Inner;
  begin Writeln(Greeting); end;     { legal Pascal; was `undefined variable` }

begin Inner; end;

procedure V1;                       { the control: ordinary locals were fine }
var n: LongInt;

  procedure Inner;
  var n: Byte;
  begin n := 9; Writeln(n); end;

begin n := 1; Inner; end;

begin
  R1; R2; R3; S1; S2; C1; V1;
end.
