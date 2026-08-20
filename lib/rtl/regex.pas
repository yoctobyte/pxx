{ SPDX-License-Identifier: Zlib }
unit regex;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Regular expressions: a pattern compiler plus a backtracking matcher.

  Track B — language-neutral by design. The first consumer is the Nil-Python
  `re` module, which is a thin mapping onto this surface; it is equally callable
  from Pascal.

  Shape: the pattern compiles to a small instruction program (char / any /
  class / split / jump / save / assert) run by a recursive depth-first matcher.
  That is the classic backtracking VM: alternation and the greedy vs non-greedy
  distinction are both just the ORDER of a split's two branches, and a group
  capture is a save instruction that restores its slot when the branch it
  belongs to fails. Patterns are small and subjects are single lines, which is
  what callers actually have, so backtracking beats a subset construction —
  captures and non-greedy semantics come out exact.

  Supported: literals, `.`, character classes with ranges and negation,
  alternation, groups (capturing and `(?:` non-capturing), the quantifiers
  `* + ?` each optionally non-greedy with a trailing `?`, counted repeats in
  brace form (exact, open-ended and bounded), the anchors `^ $`, escape classes `\d \D \w \W \s \S`, `\xNN`,
  `\n \r \t \f \v \0`, replacement templates with `\1`..`\9`, and the
  IGNORECASE / VERBOSE / DOTALL flags.

  Not supported, and reported by Compile as an error rather than silently
  mis-matched: lookaround, backreferences inside a pattern, named groups,
  possessive quantifiers, unicode classes. }

interface

const
  RE_MAX_GROUPS = 20;      { group 0 is the whole match }
  RE_MAX_PROG   = 8192;    { instructions per compiled pattern }
  RE_CLASS_WORDS = 8;      { 256 bits of class membership }

  { Compile flags, combined with `or`. }
  RE_NONE       = 0;
  RE_IGNORECASE = 1;       { Python re.I }
  RE_VERBOSE    = 2;       { Python re.X — skip whitespace and # comments }
  RE_DOTALL     = 4;       { Python re.S — `.` also matches newline }

type
  { 256-entry membership bitmap; `negate` flips the verdict. }
  TReClass = record
    words: array[0..RE_CLASS_WORDS - 1] of Integer;
    negate: Boolean;
  end;

  TReInstr = record
    op: Integer;
    ch: Char;        { rChar }
    x, y: Integer;   { branch targets (rSplit/rJmp), slot (rSave), class index }
  end;

  TRegex = record
    prog: array of TReInstr;
    progLen: Integer;
    classes: array of TReClass;
    classCount: Integer;
    groupCount: Integer;   { including group 0 }
    flags: Integer;
    ok: Boolean;
    error: AnsiString;
  end;

  { Capture offsets, 1-based into the subject like every Pascal string index.
    starts[i] = 0 means group i did not participate. stops[i] is one past the
    last character, so the length is stops - starts. }
  TReMatch = record
    matched: Boolean;
    count: Integer;
    starts: array[0..RE_MAX_GROUPS - 1] of Integer;
    stops: array[0..RE_MAX_GROUPS - 1] of Integer;
  end;

{ Compile a pattern. Check `.ok`; on failure `.error` says why and every match
  call reports no match. }
function ReCompile(const pattern: AnsiString; flags: Integer): TRegex;

{ Anchored at the start of the subject (Python re.match). }
function ReMatch(const re: TRegex; const s: AnsiString): TReMatch;

{ Anchored at the start AND required to reach the end (Python re.fullmatch). }
function ReFullMatch(const re: TRegex; const s: AnsiString): TReMatch;

{ First match at or after `from` (1-based). Python re.search. }
function ReSearchFrom(const re: TRegex; const s: AnsiString; from: Integer): TReMatch;
function ReSearch(const re: TRegex; const s: AnsiString): TReMatch;

{ Text of a group, '' when it did not participate. }
function ReGroup(const m: TReMatch; const s: AnsiString; n: Integer): AnsiString;

{ All non-overlapping matches. An empty match advances one character, as Python
  does. Returns how many were written to outMatches. }
function ReFindAll(const re: TRegex; const s: AnsiString;
                   var outMatches: array of TReMatch; maxOut: Integer): Integer;

{ Replace non-overlapping matches. `repl` may contain \1..\9 group references
  and \\ for a literal backslash. count < 0 replaces every match. }
function ReReplace(const re: TRegex; const s, repl: AnsiString;
                   count: Integer): AnsiString;

{ Convenience for one-shot call sites: compile, match anchored, discard. }
function ReQuickMatch(const pattern, s: AnsiString; flags: Integer): Boolean;

implementation

const
  { opcodes }
  rChar   = 1;
  rAny    = 2;
  rClass  = 3;
  rSplit  = 4;   { try x first, then y }
  rJmp    = 5;
  rSave   = 6;   { x = slot index }
  rBOL    = 7;
  rEOL    = 8;
  rMatch  = 9;

  MAX_DEPTH = 40000;  { backtracking guard: reported as no-match, never a crash }

{ ---- character helpers ---------------------------------------------------- }

function ReLowerCh(c: Char): Char;
begin
  if (c >= 'A') and (c <= 'Z') then
    ReLowerCh := Chr(Ord(c) + 32)
  else
    ReLowerCh := c;
end;

function ReIsDigitCh(c: Char): Boolean;
begin
  ReIsDigitCh := (c >= '0') and (c <= '9');
end;

function ReIsSpaceCh(c: Char): Boolean;
begin
  ReIsSpaceCh := (c = ' ') or (c = #9) or (c = #10) or (c = #13) or
                 (c = #11) or (c = #12);
end;

{ ---- class bitmap -------------------------------------------------------- }

procedure ReClassClear(var k: TReClass);
var i: Integer;
begin
  for i := 0 to RE_CLASS_WORDS - 1 do k.words[i] := 0;
  k.negate := False;
end;

function ReBitMask(b: Integer): Integer;
var m, i: Integer;
begin
  m := 1;
  for i := 1 to b do m := m * 2;
  ReBitMask := m;
end;

procedure ReClassAdd(var k: TReClass; c: Char);
begin
  k.words[Ord(c) div 32] := k.words[Ord(c) div 32] or ReBitMask(Ord(c) mod 32);
end;

procedure ReClassAddRange(var k: TReClass; lo, hi: Char);
var i: Integer;
begin
  for i := Ord(lo) to Ord(hi) do ReClassAdd(k, Chr(i));
end;

function ReClassHasRaw(const k: TReClass; c: Char): Boolean;
begin
  ReClassHasRaw := (k.words[Ord(c) div 32] and ReBitMask(Ord(c) mod 32)) <> 0;
end;

function ReClassHas(const k: TReClass; c: Char): Boolean;
var hit: Boolean;
begin
  hit := ReClassHasRaw(k, c);
  if k.negate then hit := not hit;
  ReClassHas := hit;
end;

procedure ReClassUnion(var dst: TReClass; const src: TReClass);
var i: Integer;
begin
  for i := 0 to RE_CLASS_WORDS - 1 do
    dst.words[i] := dst.words[i] or src.words[i];
end;

procedure ReClassInvertBits(var k: TReClass);
var i, j: Integer; ones: TReClass;
begin
  { complement without `not` over Integer (the pinned stable treats it as
    boolean there — same reason bitset.pas avoids it): xor with all-ones }
  ReClassClear(ones);
  for j := 0 to 255 do ReClassAdd(ones, Chr(j));
  for i := 0 to RE_CLASS_WORDS - 1 do
    k.words[i] := k.words[i] xor ones.words[i];
end;

procedure ReClassAddDigits(var k: TReClass);
begin
  ReClassAddRange(k, '0', '9');
end;

procedure ReClassAddSpace(var k: TReClass);
begin
  ReClassAdd(k, ' ');  ReClassAdd(k, #9);  ReClassAdd(k, #10);
  ReClassAdd(k, #13);  ReClassAdd(k, #11); ReClassAdd(k, #12);
end;

procedure ReClassAddWord(var k: TReClass);
begin
  ReClassAddRange(k, 'a', 'z');
  ReClassAddRange(k, 'A', 'Z');
  ReClassAddDigits(k);
  ReClassAdd(k, '_');
end;

{ Under IGNORECASE the subject is folded to lower case before a test, so a
  class holding 'A'..'Z' must also hold the folded letters. }
procedure ReClassFoldCase(var k: TReClass);
var i: Integer;
begin
  for i := Ord('A') to Ord('Z') do
    if ReClassHasRaw(k, Chr(i)) then ReClassAdd(k, Chr(i + 32));
  for i := Ord('a') to Ord('z') do
    if ReClassHasRaw(k, Chr(i)) then ReClassAdd(k, Chr(i - 32));
end;

procedure ReClassAddShorthand(var k: TReClass; shorthand: Char);
var tmp: TReClass;
begin
  ReClassClear(tmp);
  case shorthand of
    'd': ReClassAddDigits(tmp);
    's': ReClassAddSpace(tmp);
    'w': ReClassAddWord(tmp);
    'D': begin ReClassAddDigits(tmp); ReClassInvertBits(tmp); end;
    'S': begin ReClassAddSpace(tmp);  ReClassInvertBits(tmp); end;
    'W': begin ReClassAddWord(tmp);   ReClassInvertBits(tmp); end;
  end;
  ReClassUnion(k, tmp);
end;

{ ---- compile state ------------------------------------------------------- }

type
  TReProg = array of TReInstr;

  TReParser = record
    pat: AnsiString;
    pos: Integer;        { 1-based read cursor }
    len: Integer;
    nextGroup: Integer;
    failed: Boolean;
    err: AnsiString;
  end;

var
  { Unit state so the recursive descent stays plain procedures instead of
    threading two var parameters through every level. Compilation is not
    re-entrant; a compiled TRegex is an independent value. }
  gPar: TReParser;
  gRe: TRegex;

procedure ReFail(const msg: AnsiString);
begin
  if not gPar.failed then
  begin
    gPar.failed := True;
    gPar.err := msg;
  end;
end;

function ReEmit(op: Integer; c: Char; x, y: Integer): Integer;
begin
  if gRe.progLen >= RE_MAX_PROG then
  begin
    ReFail('pattern too large');
    ReEmit := 0;
    exit;
  end;
  gRe.prog[gRe.progLen].op := op;
  gRe.prog[gRe.progLen].ch := c;
  gRe.prog[gRe.progLen].x := x;
  gRe.prog[gRe.progLen].y := y;
  ReEmit := gRe.progLen;
  gRe.progLen := gRe.progLen + 1;
end;

function ReAddClass(const k: TReClass): Integer;
begin
  if gRe.classCount >= Length(gRe.classes) then
    SetLength(gRe.classes, gRe.classCount + 16);
  gRe.classes[gRe.classCount] := k;
  ReAddClass := gRe.classCount;
  gRe.classCount := gRe.classCount + 1;
end;

procedure RePutSplit(at, x, y: Integer);
begin
  gRe.prog[at].op := rSplit;
  gRe.prog[at].ch := #0;
  gRe.prog[at].x := x;
  gRe.prog[at].y := y;
end;

{ Lift a just-parsed region out of the program, truncating it back to where the
  region started. The caller re-emits it where it wants it, which keeps every
  branch target unambiguous: the region is contiguous, so one delta relocates all
  of it, forward and backward targets alike.

  This replaced an insert-a-gap-and-relocate approach, which could not work: a
  target pointing exactly AT the insertion point is ambiguous. A preceding `x?`
  holds a forward skip-target that must keep pointing at the newly inserted
  split, while a `(a+)?` body holds a backward target to the region start that
  must move — one relocation rule cannot serve both, and the bug showed up as
  `[A-G][#b]?(?:maj7|m7)?` silently failing to match `Am7`. }
procedure ReTakeBody(atomStart: Integer; var body: TReProg; var bodyLen: Integer);
var i: Integer;
begin
  bodyLen := gRe.progLen - atomStart;
  SetLength(body, bodyLen);
  for i := 0 to bodyLen - 1 do body[i] := gRe.prog[atomStart + i];
  gRe.progLen := atomStart;
end;

{ Re-emit a lifted body at the current end of the program. `origStart` is where
  it used to live, so internal targets shift by the difference. Returns the
  position it now starts at. }
function ReAppendBody(const body: TReProg; bodyLen, origStart: Integer): Integer;
var i, base, delta: Integer; ins: TReInstr;
begin
  base := gRe.progLen;
  delta := base - origStart;
  for i := 0 to bodyLen - 1 do
  begin
    ins := body[i];
    if (ins.op = rSplit) or (ins.op = rJmp) then
    begin
      ins.x := ins.x + delta;
      if ins.op = rSplit then ins.y := ins.y + delta;
    end;
    ReEmit(ins.op, ins.ch, ins.x, ins.y);
  end;
  ReAppendBody := base;
end;

{ `atom*` — split, body, jump back to the split. }
procedure ReWrapStar(atomStart: Integer; greedy: Boolean);
var body: TReProg; bodyLen, splitPc, bodyBase, afterPc: Integer;
begin
  ReTakeBody(atomStart, body, bodyLen);
  splitPc := ReEmit(rSplit, #0, 0, 0);
  bodyBase := ReAppendBody(body, bodyLen, atomStart);
  ReEmit(rJmp, #0, splitPc, 0);
  afterPc := gRe.progLen;
  if greedy then
    RePutSplit(splitPc, bodyBase, afterPc)
  else
    RePutSplit(splitPc, afterPc, bodyBase);
end;

{ `atom?` — split, body; both branches continue past it. }
procedure ReWrapOptional(atomStart: Integer; greedy: Boolean);
var body: TReProg; bodyLen, splitPc, bodyBase, afterPc: Integer;
begin
  ReTakeBody(atomStart, body, bodyLen);
  splitPc := ReEmit(rSplit, #0, 0, 0);
  bodyBase := ReAppendBody(body, bodyLen, atomStart);
  afterPc := gRe.progLen;
  if greedy then
    RePutSplit(splitPc, bodyBase, afterPc)
  else
    RePutSplit(splitPc, afterPc, bodyBase);
end;

{ `atom+` — body, then a split back to it. Nothing needs moving. }
procedure ReWrapPlus(atomStart: Integer; greedy: Boolean);
var splitPc: Integer;
begin
  splitPc := gRe.progLen;
  if greedy then
    ReEmit(rSplit, #0, atomStart, splitPc + 1)
  else
    ReEmit(rSplit, #0, splitPc + 1, atomStart);
end;

{ ---- recursive descent: alt -> concat -> repeat -> atom ------------------ }

procedure ReParseAlt; forward;

procedure ReSkipVerbose;
var progressed: Boolean;
begin
  if (gRe.flags and RE_VERBOSE) = 0 then exit;
  progressed := True;
  while progressed do
  begin
    progressed := False;
    while (gPar.pos <= gPar.len) and ReIsSpaceCh(gPar.pat[gPar.pos]) do
    begin
      gPar.pos := gPar.pos + 1;
      progressed := True;
    end;
    if (gPar.pos <= gPar.len) and (gPar.pat[gPar.pos] = '#') then
    begin
      while (gPar.pos <= gPar.len) and (gPar.pat[gPar.pos] <> #10) do
        gPar.pos := gPar.pos + 1;
      progressed := True;
    end;
  end;
end;

function RePeek: Char;
begin
  if gPar.pos <= gPar.len then RePeek := gPar.pat[gPar.pos] else RePeek := #0;
end;

function ReAtEnd: Boolean;
begin
  ReAtEnd := gPar.pos > gPar.len;
end;

function ReHexVal(c: Char): Integer;
begin
  if ReIsDigitCh(c) then ReHexVal := Ord(c) - Ord('0')
  else if (c >= 'a') and (c <= 'f') then ReHexVal := Ord(c) - Ord('a') + 10
  else if (c >= 'A') and (c <= 'F') then ReHexVal := Ord(c) - Ord('A') + 10
  else ReHexVal := -1;
end;

{ Reads the escape after a backslash. isChar=False means it stands for a class
  shorthand (\d, \s, ...) named by `shorthand` instead of a single character. }
procedure ReReadEscape(var c: Char; var isChar: Boolean; var shorthand: Char);
var h1, h2: Integer;
begin
  isChar := True;
  shorthand := #0;
  c := #0;
  if ReAtEnd then
  begin
    ReFail('trailing backslash');
    exit;
  end;
  c := gPar.pat[gPar.pos];
  gPar.pos := gPar.pos + 1;
  if (c = 'd') or (c = 'D') or (c = 'w') or (c = 'W') or
     (c = 's') or (c = 'S') then
  begin
    isChar := False;
    shorthand := c;
    exit;
  end;
  if c = 'n' then c := #10
  else if c = 'r' then c := #13
  else if c = 't' then c := #9
  else if c = 'f' then c := #12
  else if c = 'v' then c := #11
  else if c = '0' then c := #0
  else if c = 'x' then
  begin
    if gPar.pos + 1 > gPar.len then
    begin
      ReFail('incomplete \x escape');
      exit;
    end;
    h1 := ReHexVal(gPar.pat[gPar.pos]);
    h2 := ReHexVal(gPar.pat[gPar.pos + 1]);
    if (h1 < 0) or (h2 < 0) then
    begin
      ReFail('bad \x escape');
      exit;
    end;
    c := Chr(h1 * 16 + h2);
    gPar.pos := gPar.pos + 2;
  end
  else if (c >= '1') and (c <= '9') then
    ReFail('backreferences in a pattern are not supported');
  { anything else (\. \* \\ \( ...) is the literal character }
end;

{ Parse a `[...]` body; the '[' is already consumed. Returns the class index. }
function ReParseClass: Integer;
var k: TReClass; c, lo, shorthand: Char; isChar, closed, isRange: Boolean;
begin
  ReClassClear(k);
  closed := False;
  if RePeek = '^' then
  begin
    k.negate := True;
    gPar.pos := gPar.pos + 1;
  end;
  if RePeek = ']' then      { a ']' first thing is a literal, as in Python }
  begin
    ReClassAdd(k, ']');
    gPar.pos := gPar.pos + 1;
  end;
  while (not ReAtEnd) and (not gPar.failed) and (not closed) do
  begin
    c := gPar.pat[gPar.pos];
    if c = ']' then
    begin
      gPar.pos := gPar.pos + 1;
      closed := True;
    end
    else
    begin
      gPar.pos := gPar.pos + 1;
      isChar := True;
      if c = '\' then
        ReReadEscape(c, isChar, shorthand);
      if gPar.failed then break;
      if not isChar then
        ReClassAddShorthand(k, shorthand)
      else
      begin
        lo := c;
        isRange := (RePeek = '-') and (gPar.pos + 1 <= gPar.len) and
                   (gPar.pat[gPar.pos + 1] <> ']');
        if isRange then
        begin
          gPar.pos := gPar.pos + 1;        { the '-' }
          c := gPar.pat[gPar.pos];
          gPar.pos := gPar.pos + 1;
          if c = '\' then
          begin
            ReReadEscape(c, isChar, shorthand);
            if not isChar then ReFail('class shorthand cannot end a range');
          end;
          if not gPar.failed then
          begin
            if Ord(c) < Ord(lo) then
              ReFail('reversed range in character class')
            else
              ReClassAddRange(k, lo, c);
          end;
        end
        else
          ReClassAdd(k, lo);
      end;
    end;
  end;
  if (not closed) and (not gPar.failed) then
    ReFail('unterminated character class');
  if (gRe.flags and RE_IGNORECASE) <> 0 then ReClassFoldCase(k);
  ReParseClass := ReAddClass(k);
end;

procedure ReEmitLiteral(c: Char);
begin
  if (gRe.flags and RE_IGNORECASE) <> 0 then
    ReEmit(rChar, ReLowerCh(c), 0, 0)
  else
    ReEmit(rChar, c, 0, 0);
end;

procedure ReParseAtom;
var classIdx, grp: Integer; c, shorthand: Char; isChar, capturing: Boolean;
    k: TReClass;
begin
  ReSkipVerbose;
  if ReAtEnd then exit;
  c := gPar.pat[gPar.pos];
  if c = '(' then
  begin
    gPar.pos := gPar.pos + 1;
    capturing := True;
    if RePeek = '?' then
    begin
      gPar.pos := gPar.pos + 1;
      if RePeek = ':' then
      begin
        gPar.pos := gPar.pos + 1;
        capturing := False;
      end
      else
      begin
        ReFail('only (?:...) group extensions are supported');
        exit;
      end;
    end;
    if capturing then
    begin
      grp := gPar.nextGroup;
      gPar.nextGroup := gPar.nextGroup + 1;
      if grp >= RE_MAX_GROUPS then
      begin
        ReFail('too many capturing groups');
        exit;
      end;
      ReEmit(rSave, #0, grp * 2, 0);
      ReParseAlt;
      ReEmit(rSave, #0, grp * 2 + 1, 0);
    end
    else
      ReParseAlt;
    if gPar.failed then exit;
    ReSkipVerbose;
    if RePeek <> ')' then
    begin
      ReFail('missing )');
      exit;
    end;
    gPar.pos := gPar.pos + 1;
  end
  else if c = '[' then
  begin
    gPar.pos := gPar.pos + 1;
    classIdx := ReParseClass;
    ReEmit(rClass, #0, classIdx, 0);
  end
  else if c = '.' then
  begin
    gPar.pos := gPar.pos + 1;
    if (gRe.flags and RE_DOTALL) <> 0 then
      ReEmit(rAny, #0, 1, 0)
    else
      ReEmit(rAny, #0, 0, 0);
  end
  else if c = '^' then
  begin
    gPar.pos := gPar.pos + 1;
    ReEmit(rBOL, #0, 0, 0);
  end
  else if c = '$' then
  begin
    gPar.pos := gPar.pos + 1;
    ReEmit(rEOL, #0, 0, 0);
  end
  else if c = '\' then
  begin
    gPar.pos := gPar.pos + 1;
    ReReadEscape(c, isChar, shorthand);
    if gPar.failed then exit;
    if isChar then
      ReEmitLiteral(c)
    else
    begin
      ReClassClear(k);
      ReClassAddShorthand(k, shorthand);
      ReEmit(rClass, #0, ReAddClass(k), 0);
    end;
  end
  else if (c = '*') or (c = '+') or (c = '?') then
    ReFail('quantifier with nothing to repeat')
  else
  begin
    gPar.pos := gPar.pos + 1;
    ReEmitLiteral(c);
  end;
end;

(* A counted quantifier in brace form: {m}, {m,} or {m,n}. Returns False and
   consumes nothing when what follows is not one — a bare open brace is a
   literal, as in Python. *)
function ReReadCount(var minRep, maxRep: Integer): Boolean;
var save, v: Integer; sawComma, sawDigit: Boolean;
begin
  save := gPar.pos;
  ReReadCount := False;
  minRep := 0;
  maxRep := -1;
  gPar.pos := gPar.pos + 1;   { consume the opening brace }
  v := 0;
  sawDigit := False;
  while (not ReAtEnd) and ReIsDigitCh(gPar.pat[gPar.pos]) do
  begin
    v := v * 10 + (Ord(gPar.pat[gPar.pos]) - Ord('0'));
    gPar.pos := gPar.pos + 1;
    sawDigit := True;
  end;
  if not sawDigit then
  begin
    gPar.pos := save;
    exit;
  end;
  minRep := v;
  sawComma := False;
  maxRep := minRep;
  if RePeek = ',' then
  begin
    sawComma := True;
    gPar.pos := gPar.pos + 1;
    v := 0;
    sawDigit := False;
    while (not ReAtEnd) and ReIsDigitCh(gPar.pat[gPar.pos]) do
    begin
      v := v * 10 + (Ord(gPar.pat[gPar.pos]) - Ord('0'));
      gPar.pos := gPar.pos + 1;
      sawDigit := True;
    end;
    if sawDigit then maxRep := v else maxRep := -1;
  end;
  if RePeek <> '}' then
  begin
    gPar.pos := save;
    minRep := 0;
    maxRep := -1;
    exit;
  end;
  gPar.pos := gPar.pos + 1;
  if sawComma and (maxRep >= 0) and (maxRep < minRep) then
  begin
    ReFail('{m,n} with n below m');
    exit;
  end;
  ReReadCount := True;
end;

{ Counted repeat. The body is lifted once and re-emitted as many times as the
  bounds ask for: a bounded 2-to-4 repeat becomes `a a a? a?` (sequential
  optionals, same language and same greedy order as Python's nesting). }
procedure ReRepeatCounted(atomStart, minRep, maxRep: Integer);
var body: TReProg; bodyLen, j, base, copyStart: Integer;
begin
  ReTakeBody(atomStart, body, bodyLen);

  if (minRep = 0) and (maxRep = -1) then
  begin
    base := ReAppendBody(body, bodyLen, atomStart);
    ReWrapStar(base, True);
    exit;
  end;

  for j := 1 to minRep do
    ReAppendBody(body, bodyLen, atomStart);

  if maxRep = -1 then
  begin
    { open-ended tail: one more copy under a star }
    base := ReAppendBody(body, bodyLen, atomStart);
    ReWrapStar(base, True);
    exit;
  end;

  for j := minRep + 1 to maxRep do
  begin
    copyStart := ReAppendBody(body, bodyLen, atomStart);
    ReWrapOptional(copyStart, True);
  end;
end;

procedure ReParseRepeat;
var atomStart, minRep, maxRep: Integer; greedy: Boolean; c: Char;
begin
  ReSkipVerbose;
  atomStart := gRe.progLen;
  ReParseAtom;
  if gPar.failed then exit;
  ReSkipVerbose;
  if ReAtEnd then exit;
  c := RePeek;
  if (c = '*') or (c = '+') or (c = '?') then
  begin
    gPar.pos := gPar.pos + 1;
    greedy := True;
    if RePeek = '?' then
    begin
      gPar.pos := gPar.pos + 1;
      greedy := False;
    end;
    if c = '*' then ReWrapStar(atomStart, greedy)
    else if c = '+' then ReWrapPlus(atomStart, greedy)
    else ReWrapOptional(atomStart, greedy);
  end
  else if c = '{' then
  begin
    if ReReadCount(minRep, maxRep) then
      if not gPar.failed then ReRepeatCounted(atomStart, minRep, maxRep);
  end;
end;

procedure ReParseConcat;
begin
  ReSkipVerbose;
  while (not ReAtEnd) and (not gPar.failed) and
        (RePeek <> '|') and (RePeek <> ')') do
  begin
    ReParseRepeat;
    ReSkipVerbose;
  end;
end;

procedure ReParseAlt;
var altStart, splitPc, jmpPc, leftBase, bodyLen: Integer; body: TReProg;
begin
  altStart := gRe.progLen;
  ReParseConcat;
  if gPar.failed then exit;
  while (RePeek = '|') and (not gPar.failed) do
  begin
    gPar.pos := gPar.pos + 1;
    { split L, R ; L: <what we have> ; jmp end ; R: <next branch> ; end: }
    ReTakeBody(altStart, body, bodyLen);
    splitPc := ReEmit(rSplit, #0, 0, 0);
    leftBase := ReAppendBody(body, bodyLen, altStart);
    jmpPc := ReEmit(rJmp, #0, 0, 0);
    RePutSplit(splitPc, leftBase, gRe.progLen);
    ReSkipVerbose;
    ReParseConcat;
    if gPar.failed then exit;
    gRe.prog[jmpPc].x := gRe.progLen;
  end;
end;

{ ---- matcher ------------------------------------------------------------- }

type
  TReRunner = record
    subj: AnsiString;
    slen: Integer;
    caps: array[0..RE_MAX_GROUPS * 2 - 1] of Integer;
    fold: Boolean;
    needEnd: Boolean;
    depth: Integer;
    overflow: Boolean;
  end;

var
  gRun: TReRunner;

function ReRun(const re: TRegex; pc, sp: Integer): Boolean;
var c: Char; slot, saved: Integer; alive: Boolean;
begin
  ReRun := False;
  gRun.depth := gRun.depth + 1;
  if gRun.depth > MAX_DEPTH then
  begin
    gRun.overflow := True;
    gRun.depth := gRun.depth - 1;
    exit;
  end;
  alive := True;
  while alive do
  begin
    if re.prog[pc].op = rChar then
    begin
      if sp > gRun.slen then alive := False
      else
      begin
        c := gRun.subj[sp];
        if gRun.fold then c := ReLowerCh(c);
        if c <> re.prog[pc].ch then alive := False
        else
        begin
          pc := pc + 1;
          sp := sp + 1;
        end;
      end;
    end
    else if re.prog[pc].op = rAny then
    begin
      if sp > gRun.slen then alive := False
      else if (re.prog[pc].x = 0) and (gRun.subj[sp] = #10) then alive := False
      else
      begin
        pc := pc + 1;
        sp := sp + 1;
      end;
    end
    else if re.prog[pc].op = rClass then
    begin
      if sp > gRun.slen then alive := False
      else
      begin
        c := gRun.subj[sp];
        if gRun.fold then c := ReLowerCh(c);
        if not ReClassHas(re.classes[re.prog[pc].x], c) then alive := False
        else
        begin
          pc := pc + 1;
          sp := sp + 1;
        end;
      end;
    end
    else if re.prog[pc].op = rBOL then
    begin
      if sp <> 1 then alive := False else pc := pc + 1;
    end
    else if re.prog[pc].op = rEOL then
    begin
      if sp <> gRun.slen + 1 then alive := False else pc := pc + 1;
    end
    else if re.prog[pc].op = rSplit then
    begin
      if ReRun(re, re.prog[pc].x, sp) then
      begin
        ReRun := True;
        gRun.depth := gRun.depth - 1;
        exit;
      end;
      if gRun.overflow then alive := False
      else pc := re.prog[pc].y;
    end
    else if re.prog[pc].op = rJmp then
      pc := re.prog[pc].x
    else if re.prog[pc].op = rSave then
    begin
      slot := re.prog[pc].x;
      saved := gRun.caps[slot];
      gRun.caps[slot] := sp;
      if ReRun(re, pc + 1, sp) then
      begin
        ReRun := True;
        gRun.depth := gRun.depth - 1;
        exit;
      end;
      gRun.caps[slot] := saved;   { this branch failed: undo the capture }
      alive := False;
    end
    else if re.prog[pc].op = rMatch then
    begin
      if gRun.needEnd and (sp <> gRun.slen + 1) then alive := False
      else
      begin
        gRun.caps[1] := sp;
        ReRun := True;
        gRun.depth := gRun.depth - 1;
        exit;
      end;
    end
    else
      alive := False;
  end;
  gRun.depth := gRun.depth - 1;
end;

function ReRunAt(const re: TRegex; const s: AnsiString;
                 at: Integer; needEnd: Boolean): TReMatch;
var m: TReMatch; i: Integer;
begin
  m.matched := False;
  m.count := 0;
  for i := 0 to RE_MAX_GROUPS - 1 do
  begin
    m.starts[i] := 0;
    m.stops[i] := 0;
  end;
  if not re.ok then
  begin
    ReRunAt := m;
    exit;
  end;
  gRun.subj := s;
  gRun.slen := Length(s);
  gRun.fold := (re.flags and RE_IGNORECASE) <> 0;
  gRun.needEnd := needEnd;
  gRun.depth := 0;
  gRun.overflow := False;
  for i := 0 to RE_MAX_GROUPS * 2 - 1 do gRun.caps[i] := 0;
  if ReRun(re, 0, at) then
  begin
    m.matched := True;
    m.count := re.groupCount;
    for i := 0 to re.groupCount - 1 do
    begin
      m.starts[i] := gRun.caps[i * 2];
      m.stops[i] := gRun.caps[i * 2 + 1];
    end;
  end;
  ReRunAt := m;
end;

function ReMatch(const re: TRegex; const s: AnsiString): TReMatch;
begin
  ReMatch := ReRunAt(re, s, 1, False);
end;

function ReFullMatch(const re: TRegex; const s: AnsiString): TReMatch;
begin
  ReFullMatch := ReRunAt(re, s, 1, True);
end;

function ReSearchFrom(const re: TRegex; const s: AnsiString; from: Integer): TReMatch;
var i, start: Integer; m: TReMatch; found: Boolean;
begin
  start := from;
  if start < 1 then start := 1;
  found := False;
  m.matched := False;
  m.count := 0;
  i := start;
  while (i <= Length(s) + 1) and (not found) do
  begin
    m := ReRunAt(re, s, i, False);
    if m.matched then found := True else i := i + 1;
  end;
  ReSearchFrom := m;
end;

function ReSearch(const re: TRegex; const s: AnsiString): TReMatch;
begin
  ReSearch := ReSearchFrom(re, s, 1);
end;

function ReGroup(const m: TReMatch; const s: AnsiString; n: Integer): AnsiString;
begin
  ReGroup := '';
  if not m.matched then exit;
  if (n < 0) or (n >= m.count) then exit;
  if m.starts[n] <= 0 then exit;
  if m.stops[n] <= m.starts[n] then exit;
  ReGroup := Copy(s, m.starts[n], m.stops[n] - m.starts[n]);
end;

function ReFindAll(const re: TRegex; const s: AnsiString;
                   var outMatches: array of TReMatch; maxOut: Integer): Integer;
var pos, n: Integer; m: TReMatch; going: Boolean;
begin
  n := 0;
  pos := 1;
  going := True;
  while going and (pos <= Length(s) + 1) and (n < maxOut) do
  begin
    m := ReSearchFrom(re, s, pos);
    if not m.matched then going := False
    else
    begin
      outMatches[n] := m;
      n := n + 1;
      if m.stops[0] > m.starts[0] then pos := m.stops[0]
      else pos := m.starts[0] + 1;   { empty match: advance, as Python does }
    end;
  end;
  ReFindAll := n;
end;

function ReReplace(const re: TRegex; const s, repl: AnsiString;
                   count: Integer): AnsiString;
var res: AnsiString; pos, done, i, g: Integer; m: TReMatch; c: Char;
    going: Boolean;
begin
  res := '';
  pos := 1;
  done := 0;
  going := True;
  while going and (pos <= Length(s) + 1) do
  begin
    if (count >= 0) and (done >= count) then going := False
    else
    begin
      m := ReSearchFrom(re, s, pos);
      if not m.matched then going := False
      else
      begin
        res := res + Copy(s, pos, m.starts[0] - pos);
        i := 1;
        while i <= Length(repl) do
        begin
          c := repl[i];
          if (c = '\') and (i < Length(repl)) then
          begin
            i := i + 1;
            c := repl[i];
            if ReIsDigitCh(c) then
            begin
              g := Ord(c) - Ord('0');
              res := res + ReGroup(m, s, g);
            end
            else
              res := res + c;
          end
          else
            res := res + c;
          i := i + 1;
        end;
        done := done + 1;
        if m.stops[0] > m.starts[0] then pos := m.stops[0]
        else
        begin
          if m.starts[0] <= Length(s) then res := res + s[m.starts[0]];
          pos := m.starts[0] + 1;
        end;
      end;
    end;
  end;
  if pos <= Length(s) then
    res := res + Copy(s, pos, Length(s) - pos + 1);
  ReReplace := res;
end;

function ReCompile(const pattern: AnsiString; flags: Integer): TRegex;
begin
  gRe.progLen := 0;
  gRe.classCount := 0;
  gRe.groupCount := 1;
  gRe.flags := flags;
  gRe.ok := True;
  gRe.error := '';
  SetLength(gRe.prog, RE_MAX_PROG);
  SetLength(gRe.classes, 16);

  gPar.pat := pattern;
  gPar.pos := 1;
  gPar.len := Length(pattern);
  gPar.nextGroup := 1;
  gPar.failed := False;
  gPar.err := '';

  ReEmit(rSave, #0, 0, 0);     { slots 0/1 = the whole match }
  ReParseAlt;
  if (not gPar.failed) and (not ReAtEnd) then
    ReFail('unbalanced ) in pattern');
  ReEmit(rMatch, #0, 0, 0);

  gRe.groupCount := gPar.nextGroup;
  if gPar.failed then
  begin
    gRe.ok := False;
    gRe.error := gPar.err;
  end;
  ReCompile := gRe;
end;

function ReQuickMatch(const pattern, s: AnsiString; flags: Integer): Boolean;
var re: TRegex; m: TReMatch;
begin
  re := ReCompile(pattern, flags);
  if not re.ok then
  begin
    ReQuickMatch := False;
    exit;
  end;
  m := ReMatch(re, s);
  ReQuickMatch := m.matched;
end;

end.
