{ ===== dbg_filetable.inc — DWARF -g: the multi-file line table ===============

  Carved out of parser.inc, byte-for-byte, by
  refactor-a-carve-out-plexer-pparser-so-p-owns-its-own-files.

  **Owned by Track A** (language-agnostic core), not by a frontend. Which source
  file a token came from is a debug-info question, not a Pascal one — a C
  translation unit is mapped here too (CMarkTokModule / CModuleOfTok). It lived
  in the Pascal parser's file only because Pascal was the seed.

  Included from compiler.pas at exactly the point it used to occupy, so include
  ORDER is unchanged — that is what makes the carve-out provable by the
  self-host fixedpoint rather than by reading it.

  Note DbgFileId is ALSO forward-declared in compiler.pas itself, before
  lexer.inc, because lexer.inc and clexer.inc call it and this file is included
  after them (regression-fpc-seed-drift-b1976-stale). }

{ ===== DWARF -g: the multi-file line table =====================================
  A source other than the main file joins the line table by INTERNING its path
  (DbgFileId) and MARKING the token index where its tokens start
  (DbgMarkTokFile). Two shapes use it:

    NilPy  an imported module is one contiguous run of appended tokens, so it
           marks once at its start.
    C      the preprocessor inlines every #include, so a header's tokens
           interleave with the main file's — a mark at every boundary, which is
           why ranges are a separate, much larger table than files.

  Sources that are NOT marked keep the line-0 treatment (no rows). The Pascal
  RTL and pylib are appended the same way and are left out on purpose: they
  would swamp the table and nobody wants to single-step pystr_upper. }

{ Intern a path, returning its .debug_line file index. 1 is the main file, so
  interned files start at 2. Repeated paths return the same id — a header
  included twice is one file entry with many ranges. }
function DbgFileId(const path: AnsiString): Integer;
var i: Integer;
begin
  DbgFileId := 1;
  if not DebugInfo then Exit;
  for i := 0 to DbgFileCount - 1 do
    if DbgFileName[i] = path then begin DbgFileId := i + 2; Exit; end;
  if DbgFileCount >= MAX_DBG_FILES then Exit;   { silently stop: -g must not fail a build }
  DbgFileName[DbgFileCount] := path;
  Inc(DbgFileCount);
  DbgFileId := DbgFileCount + 1;
end;

{ From token `startTok` on, tokens come from file `fileId`. Ranges must arrive
  in ascending token order (both callers lex forward). A mark identical to the
  current one is dropped, so a run of boundaries that do not actually change
  file costs nothing. }
function CPathIsCModule(const path: AnsiString): Boolean;
{ A top-level C SOURCE, i.e. `.c` — not a header. See CModRange* in defs.inc. }
var n: Integer;
begin
  n := Length(path);
  CPathIsCModule := (n >= 2) and (path[n] = 'c') and (path[n - 1] = '.');
end;

procedure CMarkTokModule(startTok: Integer; const path: AnsiString);
{ Tokens from `startTok` on belong to the C module `path`. Same collapse rules as
  DbgMarkTokFile: a repeat of the current module is a no-op, and a second mark
  at the same token index overwrites rather than stacks. NOT gated on
  DebugInfo — the duplicate-definition check needs this in every build.
  bug-c-static-functions-in-different-crtl-modules-collide }
var modId: Integer;
begin
  if CModRangeCount >= MAX_DBG_RANGES then Exit;
  { interned HERE, not at the call site: clexer.inc is included before emit.inc,
    where InternKey lives, and the FPC seed build has no declare-anywhere
    laxness (bug-a-fpc-seed-drift-emitasmx64-forward).
    InternKey, NOT InternStr: `path` carries ExeDir for anything resolved out of
    lib/crtl, and InternStr would append it to the EMITTED string pool, making a
    C binary's bytes depend on where the compiler binary sat. Measured: one
    `#include <stdio.h>` program compiled by ./compiler/pascal26 vs by a copy
    outside the repo came out 218207 vs 218095 bytes, the difference being
    './compiler/../lib/crtl/src/*.c' spelled into the output.
    bug-a-the-compilers-output-depends-on-argv0 }
  modId := InternKey(path);
  if (CModRangeCount > 0) and (CModRangeId[CModRangeCount - 1] = modId) then Exit;
  if (CModRangeCount > 0) and (CModRangeStart[CModRangeCount - 1] = startTok) then
  begin
    CModRangeId[CModRangeCount - 1] := modId;
    Exit;
  end;
  CModRangeStart[CModRangeCount] := startTok;
  CModRangeId[CModRangeCount] := modId;
  Inc(CModRangeCount);
end;

function CModuleOfTok(t: Integer): Integer;
{ The C module a token belongs to: the last range starting at or before it, or
  -1 (the main source) when none does. Backward scan, like DbgFileOfTok — the
  token asked about is nearly always in the most recent range. }
var i: Integer;
begin
  CModuleOfTok := -1;
  for i := CModRangeCount - 1 downto 0 do
    if t >= CModRangeStart[i] then
    begin
      CModuleOfTok := CModRangeId[i];
      Exit;
    end;
end;

procedure DbgMarkTokFile(startTok, fileId: Integer);
begin
  if not DebugInfo then Exit;
  if DbgRangeCount >= MAX_DBG_RANGES then Exit;
  if (DbgRangeCount > 0) and (DbgRangeFile[DbgRangeCount - 1] = fileId) then Exit;
  if (DbgRangeCount > 0) and (DbgRangeStart[DbgRangeCount - 1] = startTok) then
  begin
    DbgRangeFile[DbgRangeCount - 1] := fileId;   { same index: overwrite, do not stack }
    Exit;
  end;
  DbgRangeStart[DbgRangeCount] := startTok;
  DbgRangeFile[DbgRangeCount] := fileId;
  Inc(DbgRangeCount);
end;

{ The .debug_line file index for a token: the file of the last range starting at
  or before it, or 1 (the main file) when no range does. Backward scan — the
  token being asked about is nearly always in the most recent range. }
function DbgFileOfTok(t: Integer): Integer;
var i: Integer;
begin
  DbgFileOfTok := 1;
  if not DebugInfo then Exit;
  for i := DbgRangeCount - 1 downto 0 do
    if t >= DbgRangeStart[i] then
    begin
      DbgFileOfTok := DbgRangeFile[i];
      Exit;
    end;
end;

{ TRUE when a token belongs to a source the line table describes — the main
  file, or a marked one. Drives ProcDbgMain, i.e. whether a routine gets a
  DW_TAG_subprogram: an imported `.py` module's defs need one or `break scale`
  finds nothing. }
function DbgTokIsDebuggable(t: Integer): Boolean;
begin
  DbgTokIsDebuggable := (t <= DbgMainTokEnd) or (DbgFileOfTok(t) > 1);
end;
