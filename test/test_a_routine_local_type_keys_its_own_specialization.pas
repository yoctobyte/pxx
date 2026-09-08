program test_a_routine_local_type_keys_its_own_specialization;
{ A specialization's concrete argument is a TYPE, not the string that names it.
  Two routines that each declare `type TRec = ...` declare two types, and
  `specialize TBox<TRec>` in each is two specializations -- the already-declared
  shortcut compared the SPELLINGS and read the second as a re-statement of the
  first, so the inner declaration became the outer one.
  bug-p-a-specializations-concrete-argument-is-keyed-by-its-spelling-so-two-scopes-types-collide

  ROW 1 IS THE ONE UNDER TEST AND IT NEEDS THE SAME NAME IN BOTH SCOPES.
  Measured first with DISTINCT type names (`TRec` outer, `TRec2` inner) and it
  PASSED, which would have read as the defect being closed. Rows 2 and 3 are
  that measurement kept as controls: they vary the two names independently, so
  the row that fails names WHICH name the key was standing on.

    1  nest-same   nested routine, same type name AND same alias name  <- the bug
    2  nest-type   nested routine, own type name differs               (passed before)
    3  nest-alias  nested routine, own alias name differs              (passed before)
    4  sib-shared  two SIBLING routines over ONE GLOBAL TRec           (the no-op arm)
    5  inherit     a nested routine USING the enclosing routine's one  (the control
                   for the scope filter: it must still reach outward)

  Row 4 is the opposite direction and it is why the fix is not just "compare
  more strictly". Both routines name the SAME global type, so both must keep
  getting ONE specialization -- and the row that catches a wrong answer here is
  a COMPILE ERROR, not a size: the shortcut consumed the second declaration
  against a class scoped to the first routine, and `var b: TBoxRec` answered
  `unknown type`. Two record types over-minted in two routines are not
  observable from Pascal at all, so this row asserts that the declaration
  RESOLVES; it cannot see an over-mint and does not claim to.

  No row can pass by nothing happening: every nested type is 1 byte and every
  enclosing one is 3, so a collapse prints the enclosing size -- 3 where 1 is
  correct -- and neither value is a default, a zero, or SizeOf(Integer). }

type
  generic TBox<T> = record f: T; end;
  TGlobalRec = packed record g, h, i: Byte; end;   { row 4's shared argument }

{ ---- 1: nested routine, SAME type name and SAME alias name ---- }
procedure NestSame;
type
  TRec = packed record p, q, r: Byte; end;
  TBoxRec = specialize TBox<TRec>;
var ob: TBoxRec;

  procedure Inner;
  type
    TRec = packed record s: Byte; end;
    TBoxRec = specialize TBox<TRec>;
  var ib: TBoxRec;
  begin
    ib.f.s := 1;
    Writeln('nest-same inner ', SizeOf(ib.f));      { 1 }
  end;

begin
  Inner;
  ob.f.p := 1;
  Writeln('nest-same outer ', SizeOf(ob.f));        { 3 }
end;

{ ---- 2: the inner TYPE name differs, the alias name does not ---- }
procedure NestType;
type
  TRec = packed record p, q, r: Byte; end;
  TBoxRec = specialize TBox<TRec>;
var ob: TBoxRec;

  procedure Inner;
  type
    TRec2 = packed record s: Byte; end;
    TBoxRec = specialize TBox<TRec2>;
  var ib: TBoxRec;
  begin
    ib.f.s := 1;
    Writeln('nest-type inner ', SizeOf(ib.f));      { 1 }
  end;

begin
  Inner;
  ob.f.p := 1;
  Writeln('nest-type outer ', SizeOf(ob.f));        { 3 }
end;

{ ---- 3: the inner ALIAS name differs, the type name does not ---- }
procedure NestAlias;
type
  TRec = packed record p, q, r: Byte; end;
  TBoxRec = specialize TBox<TRec>;
var ob: TBoxRec;

  procedure Inner;
  type
    TRec = packed record s: Byte; end;
    TBoxRec2 = specialize TBox<TRec>;
  var ib: TBoxRec2;
  begin
    ib.f.s := 1;
    Writeln('nest-alias inner ', SizeOf(ib.f));     { 1 }
  end;

begin
  Inner;
  ob.f.p := 1;
  Writeln('nest-alias outer ', SizeOf(ob.f));       { 3 }
end;

{ ---- 4: two SIBLING routines, one GLOBAL argument type ---- }
procedure SibA;
type TBoxRec = specialize TBox<TGlobalRec>;
var b: TBoxRec;
begin b.f.g := 1; Writeln('sib-shared A ', SizeOf(b.f)); end;   { 3 }

procedure SibB;
type TBoxRec = specialize TBox<TGlobalRec>;
var b: TBoxRec;
begin b.f.h := 2; Writeln('sib-shared B ', SizeOf(b.f)); end;   { 3 }

{ ---- 5: a nested routine USING the enclosing routine's specialization ---- }
procedure Inherit;
type
  TRec = packed record p, q, r: Byte; end;
  TBoxRec = specialize TBox<TRec>;

  procedure Inner;
  var ib: TBoxRec;                                  { the ENCLOSING one }
  begin
    ib.f.q := 1;
    Writeln('inherit inner ', SizeOf(ib.f));        { 3 }
  end;

begin
  Inner;
end;

begin
  NestSame;
  NestType;
  NestAlias;
  SibA;
  SibB;
  Inherit;
end.
