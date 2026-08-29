{ SPDX-License-Identifier: Zlib }
unit re;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Python's `re` module for the Nil-Python frontend.

  Deliberately named `re` so `import re` needs NO frontend change: NilPy turns
  `import X` into the Pascal unit resolver's `uses X`, and both the qualified
  spelling `re.match(p, s)` and the flat `match(p, s)` then resolve through
  ordinary unit scoping. The engine underneath is language-neutral
  ([[regex]] / lib/rtl/regex.pas); this unit is only the Python shape.

  What Python code gets:

    m = re.match(pat, s)      -> a TMatch, or None (nil) when it does not match,
                                 so `if m:` and `m is None` behave as in Python
    m.group(n)                -> the text of group n, '' when it did not take part
    re.search / re.fullmatch  -> same, with Python's anchoring rules
    re.findall(pat, s)        -> a Python list
    re.sub(pat, repl, s)      -> replacement with \1..\9 templates
    p = re.compile(pat)       -> a TPattern with .match/.search/.fullmatch/
                                 .findall/.sub, and usable as the first argument
                                 to the module-level functions, as CPython allows
    re.I / re.X / re.S        -> the flags (also IGNORECASE / VERBOSE / DOTALL)

  Two documented differences from CPython, both places where the language has no
  equivalent yet rather than places where behaviour was guessed:

  * `findall` on a pattern with two or more groups yields a LIST per match where
    CPython yields a tuple. NilPy has no tuple type; indexing is identical
    (`note[0]`), which is how real code consumes it.
  * `m.end()` is spelled `m.stop(n)`, because `end` is a Pascal keyword. `m.start(n)`
    keeps its name. Both report 0-based Python offsets, and -1 for a group that
    did not participate, exactly as CPython does. }

interface

uses regex, pylib;

const
  { Python's flag spellings. NOTE the single-letter ones are exported into the
    importing scope, as every unit symbol is; a local named I/X/S shadows them,
    which is the common case, but a module-level global by those names would
    collide. }
  I = 1;
  IGNORECASE = 1;
  X = 2;
  VERBOSE = 2;
  S = 4;
  DOTALL = 4;

type
  { A match. Carries its subject so group() can cut text out of it. }
  TMatch = class
    subject: AnsiString;
    m: TReMatch;
    function group(n: Integer): AnsiString;
    function group: AnsiString; overload;      { group() == group(0) }
    function start(n: Integer): Integer;
    function stop(n: Integer): Integer;        { CPython's m.end(n) }
    function &end(n: Integer): Integer;        { CPython's own spelling of it }
    function groupCount: Integer;
  end;

  { A compiled pattern. }
  TPattern = class
    { not named `re`: inside this unit that identifier is the UNIT itself }
    compiled: TRegex;
    pattern: AnsiString;
    function match(const s: AnsiString): TMatch;
    function search(const s: AnsiString): TMatch;
    function fullmatch(const s: AnsiString): TMatch;
    function findall(const s: AnsiString): TPyList;
    function finditer(const s: AnsiString): TPyList;
    function split(const s: AnsiString): TPyList;
    function split(const s: AnsiString; maxsplit: Integer): TPyList; overload;
    function sub(const repl, s: AnsiString): AnsiString;
    function subn(const repl, s: AnsiString): TPyList;
    function subn(const repl, s: AnsiString; count: Integer): TPyList; overload;
    function ok: Boolean;
    function error: AnsiString;
  end;

{ re.compile(pattern[, flags]) }
function compile(const pattern: AnsiString): TPattern;
function compile(const pattern: AnsiString; flags: Integer): TPattern; overload;

{ re.match / re.search / re.fullmatch — the pattern may be a string or an
  already-compiled TPattern, as in CPython. }
function match(const pattern, s: AnsiString): TMatch;
function match(const pattern, s: AnsiString; flags: Integer): TMatch; overload;
function match(p: TPattern; const s: AnsiString): TMatch; overload;

function search(const pattern, s: AnsiString): TMatch;
function search(const pattern, s: AnsiString; flags: Integer): TMatch; overload;
function search(p: TPattern; const s: AnsiString): TMatch; overload;

function fullmatch(const pattern, s: AnsiString): TMatch;
function fullmatch(const pattern, s: AnsiString; flags: Integer): TMatch; overload;
function fullmatch(p: TPattern; const s: AnsiString): TMatch; overload;

{ re.sub(pattern, repl, string[, count]) — count 0 means every match, as in
  CPython (the engine's own -1 also means every match). }
function sub(const pattern, repl, s: AnsiString): AnsiString;
function sub(const pattern, repl, s: AnsiString; count: Integer): AnsiString; overload;
function sub(p: TPattern; const repl, s: AnsiString): AnsiString; overload;

{ re.findall(pattern, string) — a list of strings when the pattern has no group
  or one group, a list of per-match lists when it has more. }
function findall(const pattern, s: AnsiString): TPyList;
function findall(const pattern, s: AnsiString; flags: Integer): TPyList; overload;
function findall(p: TPattern; const s: AnsiString): TPyList; overload;

{ re.escape(string) — quote every character that is special in a pattern. }
{ Every non-overlapping match as a MATCH OBJECT, so .group(n)/.start()/.end()
  are reachable -- findall answers text, this answers matches. CPython hands
  back a lazy callable_iterator; this is a list, which is the same thing to
  `for m in ...` and to list(), and differs only for next() on the iterator. }
function finditer(const pattern, s: AnsiString): TPyList;
function finditer(const pattern, s: AnsiString; flags: Integer): TPyList; overload;
function finditer(p: TPattern; const s: AnsiString): TPyList; overload;

{ Split on each match. A pattern with GROUPS interleaves them into the result,
  and a group that did not participate contributes None -- both of which CPython
  does and neither of which falls out of a plain scan. `maxsplit` follows the
  count convention documented at ReLimit. }
function split(const pattern, s: AnsiString): TPyList;
function split(const pattern, s: AnsiString; maxsplit: Integer): TPyList; overload;
function split(p: TPattern; const s: AnsiString): TPyList; overload;

{ sub(), plus how many replacements were made, as a (string, count) TUPLE. }
function subn(const pattern, repl, s: AnsiString): TPyList;
function subn(const pattern, repl, s: AnsiString; count: Integer): TPyList; overload;
function subn(p: TPattern; const repl, s: AnsiString): TPyList; overload;

function escape(const s: AnsiString): AnsiString;

implementation

const
  RE_FINDALL_MAX = 4096;   { matches collected per findall call }

{ ---- TMatch -------------------------------------------------------------- }

function TMatch.group(n: Integer): AnsiString;
begin
  group := ReGroup(m, subject, n);
end;

function TMatch.group: AnsiString;
begin
  group := ReGroup(m, subject, 0);
end;

{ Python offsets are 0-based, the engine's are 1-based Pascal indices. The
  subtraction also produces CPython's -1 for a group that did not participate,
  which the engine reports as 0. }
function TMatch.start(n: Integer): Integer;
begin
  start := m.starts[n] - 1;
end;

function TMatch.stop(n: Integer): Integer;
begin
  stop := m.stops[n] - 1;
end;

{ CPython spells this `end`, which is a Pascal keyword -- hence `stop` as the
  native name and this &-escaped alias beside it. Working CPython code says
  m.end(), so without this the module is not upward compatible, which is the
  one direction NilPy promises. }
function TMatch.&end(n: Integer): Integer;
begin
  &end := m.stops[n] - 1;
end;

function TMatch.groupCount: Integer;
begin
  groupCount := m.count;
end;

{ Wrap a raw engine result, or return nil for "no match" so that Python's
  `if m:` / `m is None` work without a truthiness shim. }
function MakeMatch(const raw: TReMatch; const s: AnsiString): TMatch;
var r: TMatch;
begin
  if not raw.matched then
  begin
    MakeMatch := nil;
    exit;
  end;
  r := TMatch.Create;
  r.subject := s;
  r.m := raw;
  MakeMatch := r;
end;

{ ---- TPattern ------------------------------------------------------------ }

function TPattern.match(const s: AnsiString): TMatch;
begin
  match := MakeMatch(ReMatch(compiled, s), s);
end;

function TPattern.search(const s: AnsiString): TMatch;
begin
  search := MakeMatch(ReSearch(compiled, s), s);
end;

function TPattern.fullmatch(const s: AnsiString): TMatch;
begin
  fullmatch := MakeMatch(ReFullMatch(compiled, s), s);
end;

function TPattern.sub(const repl, s: AnsiString): AnsiString;
begin
  sub := ReReplace(compiled, s, repl, -1);
end;

function TPattern.ok: Boolean;
begin
  ok := compiled.ok;
end;

function TPattern.error: AnsiString;
begin
  error := compiled.error;
end;

{ CPython's findall: no group -> the whole match; exactly one group -> that
  group; several -> one entry per group. The several case is a tuple there and a
  list here (NilPy has no tuple), indexed the same way. }
function TPattern.findall(const s: AnsiString): TPyList;
var ms: array of TReMatch; n, i, g: Integer; out_: TPyList; row: TPyList;
begin
  SetLength(ms, RE_FINDALL_MAX);
  n := ReFindAll(compiled, s, ms, RE_FINDALL_MAX);
  out_ := TPyList.Create;
  for i := 0 to n - 1 do
  begin
    if compiled.groupCount <= 1 then
      { append_self, not append: Python's list.append returns NONE, so the
        Self-returning form the chaining idiom needs has its own name
        (bug-nilpy-list-mutators-return-self-instead-of-none). }
      out_ := out_.append_self(ReGroup(ms[i], s, 0))
    else if compiled.groupCount = 2 then
      out_ := out_.append_self(ReGroup(ms[i], s, 1))
    else
    begin
      row := TPyList.Create;
      for g := 1 to compiled.groupCount - 1 do
        row := row.append_self(ReGroup(ms[i], s, g));
      out_ := out_.append_self(row);
    end;
  end;
  findall := out_;
end;

{ CPython's count/maxsplit convention is NOT the engine's, and they disagree on
  exactly one input. CPython: 0 means "no limit", a NEGATIVE value means "do
  NOTHING" -- re.sub('a','X','banana',-1) answers 'banana'. ReReplace spells
  "no limit" as -1 and reads EVERY negative that way, so passing a Python count
  straight through turns "replace nothing" into "replace everything". That is a
  wrong VALUE with no error, which is why it is normalised in one place here
  rather than at each call site. }
function ReLimit(n: Integer): Integer;
begin
  if n = 0 then ReLimit := -1          { Python: no limit }
  else if n < 0 then ReLimit := 0      { Python: none at all }
  else ReLimit := n;
end;

function TPattern.finditer(const s: AnsiString): TPyList;
var ms: array of TReMatch; n, i: Integer; out_: TPyList;
begin
  SetLength(ms, RE_FINDALL_MAX);
  n := ReFindAll(compiled, s, ms, RE_FINDALL_MAX);
  out_ := TPyList.Create;
  for i := 0 to n - 1 do
    out_ := out_.append_self(MakeMatch(ms[i], s));
  finditer := out_;
end;

function TPattern.split(const s: AnsiString): TPyList;
begin
  split := split(s, 0);
end;

function TPattern.split(const s: AnsiString; maxsplit: Integer): TPyList;
var ms: array of TReMatch; n, i, g, lim, pos: Integer; out_: TPyList;
begin
  SetLength(ms, RE_FINDALL_MAX);
  n := ReFindAll(compiled, s, ms, RE_FINDALL_MAX);
  lim := ReLimit(maxsplit);
  out_ := TPyList.Create;
  pos := 1;
  for i := 0 to n - 1 do
  begin
    if (lim >= 0) and (i >= lim) then Break;
    out_ := out_.append_self(Copy(s, pos, ms[i].starts[0] - pos));
    { Groups are part of the RESULT, not just of the match: re.split(r'(\d)',
      'a1b') is ['a','1','b']. A group that did not participate is None and not
      '' -- ReGroup cannot tell those apart (it answers '' for both), so the
      start sentinel is read directly. }
    for g := 1 to compiled.groupCount - 1 do
      if ms[i].starts[g] <= 0 then out_ := out_.append_self(pynone)
      else out_ := out_.append_self(ReGroup(ms[i], s, g));
    pos := ms[i].stops[0];
  end;
  { The tail always exists, including when it is empty: splitting '' on ','
    is [''] and not [], and a trailing separator leaves a final ''. }
  out_ := out_.append_self(Copy(s, pos, Length(s) - pos + 1));
  split := out_;
end;

function TPattern.subn(const repl, s: AnsiString): TPyList;
begin
  subn := subn(repl, s, 0);
end;

function TPattern.subn(const repl, s: AnsiString; count: Integer): TPyList;
var ms: array of TReMatch; n, lim: Integer;
begin
  lim := ReLimit(count);
  SetLength(ms, RE_FINDALL_MAX);
  n := ReFindAll(compiled, s, ms, RE_FINDALL_MAX);
  if (lim >= 0) and (n > lim) then n := lim;
  Result := TPyList.Create;
  Result.FKind := PYSEQ_TUPLE;
  Result.append(ReReplace(compiled, s, repl, lim));
  Result.append(Int64(n));
end;

{ ---- module level -------------------------------------------------------- }

function MakePattern(const pattern: AnsiString; flags: Integer): TPattern;
var p: TPattern;
begin
  p := TPattern.Create;
  p.pattern := pattern;
  p.compiled := ReCompile(pattern, flags);
  MakePattern := p;
end;

function compile(const pattern: AnsiString): TPattern;
begin
  compile := MakePattern(pattern, RE_NONE);
end;

function compile(const pattern: AnsiString; flags: Integer): TPattern;
begin
  compile := MakePattern(pattern, flags);
end;

function match(const pattern, s: AnsiString): TMatch;
var p: TPattern;
begin
  p := MakePattern(pattern, RE_NONE);
  match := p.match(s);
end;

function match(const pattern, s: AnsiString; flags: Integer): TMatch;
var p: TPattern;
begin
  p := MakePattern(pattern, flags);
  match := p.match(s);
end;

function match(p: TPattern; const s: AnsiString): TMatch;
begin
  match := p.match(s);
end;

function search(const pattern, s: AnsiString): TMatch;
var p: TPattern;
begin
  p := MakePattern(pattern, RE_NONE);
  search := p.search(s);
end;

function search(const pattern, s: AnsiString; flags: Integer): TMatch;
var p: TPattern;
begin
  p := MakePattern(pattern, flags);
  search := p.search(s);
end;

function search(p: TPattern; const s: AnsiString): TMatch;
begin
  search := p.search(s);
end;

function fullmatch(const pattern, s: AnsiString): TMatch;
var p: TPattern;
begin
  p := MakePattern(pattern, RE_NONE);
  fullmatch := p.fullmatch(s);
end;

function fullmatch(const pattern, s: AnsiString; flags: Integer): TMatch;
var p: TPattern;
begin
  p := MakePattern(pattern, flags);
  fullmatch := p.fullmatch(s);
end;

function fullmatch(p: TPattern; const s: AnsiString): TMatch;
begin
  fullmatch := p.fullmatch(s);
end;

function sub(const pattern, repl, s: AnsiString): AnsiString;
var p: TPattern;
begin
  p := MakePattern(pattern, RE_NONE);
  sub := ReReplace(p.compiled, s, repl, -1);
end;

function sub(const pattern, repl, s: AnsiString; count: Integer): AnsiString;
var p: TPattern; lim: Integer;
begin
  p := MakePattern(pattern, RE_NONE);
  { was `if lim = 0 then lim := -1` -- which handled CPython's 0 but passed a
    NEGATIVE count straight through, where the engine reads it as "every match".
    re.sub('a','X','banana',-1) answered 'bXnXnX'; CPython answers 'banana'. }
  lim := ReLimit(count);
  sub := ReReplace(p.compiled, s, repl, lim);
end;

function sub(p: TPattern; const repl, s: AnsiString): AnsiString;
begin
  sub := ReReplace(p.compiled, s, repl, -1);
end;

function findall(const pattern, s: AnsiString): TPyList;
var p: TPattern;
begin
  p := MakePattern(pattern, RE_NONE);
  findall := p.findall(s);
end;

function findall(const pattern, s: AnsiString; flags: Integer): TPyList;
var p: TPattern;
begin
  p := MakePattern(pattern, flags);
  findall := p.findall(s);
end;

function findall(p: TPattern; const s: AnsiString): TPyList;
begin
  findall := p.findall(s);
end;

function finditer(const pattern, s: AnsiString): TPyList;
begin
  finditer := MakePattern(pattern, RE_NONE).finditer(s);
end;

function finditer(const pattern, s: AnsiString; flags: Integer): TPyList;
begin
  finditer := MakePattern(pattern, flags).finditer(s);
end;

function finditer(p: TPattern; const s: AnsiString): TPyList;
begin
  finditer := p.finditer(s);
end;

function split(const pattern, s: AnsiString): TPyList;
begin
  split := MakePattern(pattern, RE_NONE).split(s, 0);
end;

function split(const pattern, s: AnsiString; maxsplit: Integer): TPyList;
begin
  split := MakePattern(pattern, RE_NONE).split(s, maxsplit);
end;

function split(p: TPattern; const s: AnsiString): TPyList;
begin
  split := p.split(s, 0);
end;

function subn(const pattern, repl, s: AnsiString): TPyList;
begin
  subn := MakePattern(pattern, RE_NONE).subn(repl, s, 0);
end;

function subn(const pattern, repl, s: AnsiString; count: Integer): TPyList;
begin
  subn := MakePattern(pattern, RE_NONE).subn(repl, s, count);
end;

function subn(p: TPattern; const repl, s: AnsiString): TPyList;
begin
  subn := p.subn(repl, s, 0);
end;


function escape(const s: AnsiString): AnsiString;
var i: Integer; c: Char; r: AnsiString;
begin
  r := '';
  for i := 1 to Length(s) do
  begin
    c := s[i];
    if not (((c >= 'a') and (c <= 'z')) or ((c >= 'A') and (c <= 'Z')) or
            ((c >= '0') and (c <= '9')) or (c = '_')) then
      r := r + '\';
    r := r + c;
  end;
  escape := r;
end;

end.
