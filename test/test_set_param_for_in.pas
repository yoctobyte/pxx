{ `for x in <set>` over a set PARAMETER, all three element kinds and all three
  passing modes.

  The carrier was already captured (ptypesSetEnum, in the parse window) and only
  ever went to ProcParamSetEnumId, which the CALLER reads to check arguments.
  Nothing stamped the parameter's own SYMBOL, and the for-in reader reads the
  symbol -- so a set parameter had SymSetEnumId = -1 and SymSetElemTk = 0 inside
  the body, which is indistinguishable from `no element kind recorded`, and
  every one of these rows refused with
    `for-in: set iteration supports set of <enum>, set of Char or an ordinal
     set constructor`
  -- a message that names three supported cases while describing a set that IS
  all of them. The metadata was there; the reader was reading a different column.

  Found as the FIRST wall of corpus rung 7 (fcl-passrc, pastree.pp:1890,
  `for m in s` over a `const s: TProcTypeModifiers`), reached in 1.06s.

  The LOCAL rows are the control that says this is about parameters and not
  about sets: they passed throughout, so a test that only declared a local set
  would have been green before the fix and is not evidence for it.

  EVERY row here is diffed against fpc 3.2.2 and matches byte for byte, which is
  why the anonymous-set spelling lives in its own file instead: fpc refuses an
  anonymous set type in a parameter list outright ("Type identifier expected"),
  so keeping that row here would have cost this file its oracle for all the
  others. See test_set_param_for_in_anon.pas. }
program test_set_param_for_in;
type
  TM = (mA, mB, mC);
  TMs = set of TM;
  TCs = set of Char;
  TBs = set of Byte;

procedure PEnumConst(const q: TMs);
var m: TM;
begin
  Write('enum const  : ');
  for m in q do Write(Ord(m), ' ');
  WriteLn;
end;

procedure PEnumValue(q: TMs);
var m: TM;
begin
  Write('enum value  : ');
  for m in q do Write(Ord(m), ' ');
  WriteLn;
end;

procedure PEnumVar(var q: TMs);
var m: TM;
begin
  Write('enum var    : ');
  for m in q do Write(Ord(m), ' ');
  WriteLn;
end;

procedure PChars(const q: TCs);
var c: Char;
begin
  Write('char const  : ');
  for c in q do Write(c);
  WriteLn;
end;

procedure PBytes(const q: TBs);
var b: Byte;
begin
  Write('byte const  : ');
  for b in q do Write(b, ' ');
  WriteLn;
end;

{ A set parameter that is NOT the first one: the capture window is per-parameter
  and the allocation loop runs after every type has been parsed, so a column
  captured in the wrong window describes the LAST parameter. This row fails if
  the four values are read at allocation time instead of staged. }
procedure PSecond(n: Integer; const q: TCs; const r: TMs);
var c: Char; m: TM;
begin
  Write('2nd of 3    : ', n, ' ');
  for c in q do Write(c);
  Write(' ');
  for m in r do Write(Ord(m), ' ');
  WriteLn;
end;

var
  gm: TMs;
  lm: TM;
  ls: TMs;
begin
  gm := [mA, mC];
  PEnumConst(gm);
  PEnumValue(gm);
  PEnumVar(gm);
  PChars(['a', 'c']);
  PBytes([1, 3]);
  PSecond(7, ['x', 'z'], [mB, mC]);

  { Controls: the LOCAL shapes, which worked before the fix and must still. }
  ls := [mA, mC];
  Write('local named : ');
  for lm in ls do Write(Ord(lm), ' ');
  WriteLn;
end.
