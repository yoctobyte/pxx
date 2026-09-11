{ SPDX-License-Identifier: Zlib }
unit mimic_shutil;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Python's `shutil` — the terminal-size query only, so far.

  `import shutil` RESOLVES here through the NilPy import resolver's `mimic_`
  fallback, so no file in the tree carries the stdlib's name and `--no-shims`
  can turn the substitution into an error. See
  devdocs/dev/python-compat-tiers.md.

  WHY A PASCAL UNIT AND NOT A `mimic_shutil.py`: the answer comes from a real
  ioctl. `lib/rtl/ansiterm.pas` already asks TIOCGWINSZ and hands back the
  window size, so this shim can report the ACTUAL terminal rather than a
  plausible constant. A Python-side shim would have had to invent 80x24 and
  call it a subset. Nothing else in `shutil` needs a syscall, so if the file
  copiers arrive later they can go in a `.py` beside this one — the resolver
  takes whichever exists.

  THE SUBSET, and it is a small one: `get_terminal_size` and the
  `terminal_size` pair it returns. The rest of CPython's `shutil` — `copy`,
  `copytree`, `rmtree`, `move`, `which`, `make_archive`, `disk_usage` — is
  ABSENT and deliberately so: each is a real filesystem operation where a
  half-right implementation silently does the wrong thing to someone's files,
  and nothing in any corpus here calls one. A missing name fails at the call
  site with a message naming the member, which is found in one run.

  WHY THE SINGLE CALLER WOULD HAVE PASSED ANYWAY, AND WHY THAT IS NOT A REASON
  TO SKIP IT: lekkerzeilen's `app.py` wraps this call in `try / except
  Exception` and falls back to 80 columns, so at RUN time a missing
  `get_terminal_size` is invisible. It does not compile, though — a member that
  no unit declares is a compile error, and `try` does not defer name
  resolution. So the status line that would have degraded gracefully instead
  stopped the whole program from building.

  CPYTHON'S PRECEDENCE IS REPRODUCED AND IT IS NOT THE OBVIOUS ONE. The
  environment wins over the real terminal: `COLUMNS`/`LINES`, when set and
  positive, are used as-is and no ioctl happens for that dimension. That is
  what lets a caller override the size of a pipe it is writing into, and it is
  why a test can set COLUMNS and get a deterministic answer. Only a dimension
  the environment did not supply is queried, and only a dimension the query
  could not supply falls back. Each dimension is resolved INDEPENDENTLY, as
  CPython does — `COLUMNS=100` with no `LINES` gives 100 columns and the
  terminal's own row count, not 100x24. }

interface

uses pylib, sysutils, ansiterm;

type
  { CPython returns `os.terminal_size`, a named tuple read as `.columns` and
    `.lines`. A class with those two fields serves the attribute spelling,
    which is how every caller reads it. It is NOT indexable — `size[0]` works
    in CPython and does not work here; no corpus caller writes that, and a
    TPyList would have given indexing while losing the names, which are the
    half that code actually uses. }
  terminal_size = class
  public
    columns: Integer;
    lines: Integer;
    constructor Create(cols, rws: Integer);
  end;

function get_terminal_size: terminal_size; overload;
function get_terminal_size(fallback: TPyList): terminal_size; overload;

implementation

constructor terminal_size.Create(cols, rws: Integer);
begin
  columns := cols;
  lines := rws;
end;

{ One dimension from the environment, or 0 when absent, unset or not a positive
  integer. CPython treats a malformed COLUMNS exactly as an absent one rather
  than raising, which is what StrToIntDef's default expresses here. }
function EnvDim(const name: AnsiString): Integer;
var s: AnsiString;
begin
  s := GetEnvironmentVariable(name);
  if s = '' then
    Result := 0
  else
  begin
    Result := StrToIntDef(s, 0);
    if Result < 0 then
      Result := 0;
  end;
end;

function Resolve(fbCols, fbRows: Integer): terminal_size;
var cols, rows, qc, qr: Integer;
begin
  cols := EnvDim('COLUMNS');
  rows := EnvDim('LINES');
  if (cols <= 0) or (rows <= 0) then
  begin
    qc := 0;
    qr := 0;
    { TerminalSize fills 80x24 even when it fails, so its BOOLEAN is what says
      whether the numbers came from the terminal. Reading the out-parameters
      without it would turn a failed ioctl into a confident 80x24 and the
      caller's own fallback would never be used. }
    if TerminalSize(qc, qr) then
    begin
      if cols <= 0 then
        cols := qc;
      if rows <= 0 then
        rows := qr;
    end;
    if cols <= 0 then
      cols := fbCols;
    if rows <= 0 then
      rows := fbRows;
  end;
  Result := terminal_size.Create(cols, rows);
end;

function get_terminal_size: terminal_size;
begin
  { CPython's own default fallback. }
  Result := Resolve(80, 24);
end;

function get_terminal_size(fallback: TPyList): terminal_size;
var fbCols, fbRows: Integer;
begin
  fbCols := 80;
  fbRows := 24;
  { A `(cols, lines)` tuple arrives as a TPyList — list, tuple and set share
    the representation. A nil or short one keeps CPython's defaults rather than
    failing: this function's whole job is to answer, and its callers are
    status lines. }
  if fallback <> nil then
  begin
    if len(fallback) > 0 then
      fbCols := Integer(fallback.at(0));
    if len(fallback) > 1 then
      fbRows := Integer(fallback.at(1));
  end;
  Result := Resolve(fbCols, fbRows);
end;

end.
