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
  { InternKey is never called for the "no module" case, so CMarkTokNoModule
    cannot intern the empty string as a path. }
  modId := InternKey(path);
  CMarkTokModuleId(startTok, modId);
end;

procedure CMarkTokModuleId(startTok, modId: Integer);
{ The collapse, shared by the two entry points. `modId` is a KeyStrs[] index, or
  -1 for NO enclosing module -- which is a real answer, not an absence: it means
  "this text belongs to the translation unit itself, not to any pulled-in .c",
  and it is the same -1 CModuleOfTok already returns when no range covers a
  token, so every existing consumer reads it correctly with no change.

  A sentinel was needed because every interned path is a valid id and there was
  previously no way to MARK absence -- only to never mark at all, which is what
  made the attribution sticky
  (bug-a-c-module-attribution-is-sticky-after-a-crtl-impl-pull). }
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

procedure CInsertTokModuleRange(atIdx, startTok: Integer; const path: AnsiString);
{ Insert a module range at a KNOWN POSITION instead of appending it.

  CModuleOfTok scans BACKWARD and takes the first range whose start is <= the
  token, so "later in the array wins". Appending a coarse range that starts
  before finer ones therefore does not get refined by them — it SHADOWS all of
  them. That is what CPullCrtlForPrototypes did: it marked the whole appended
  block `<crtl-prototype-pull>` after CLexAppend had already marked each pulled
  crtl `.c` with its own path, so every module in the block collapsed into one
  and two crtl modules' same-named file-scope statics read as a duplicate
  definition in one translation unit. `fcntl.c` and `unistd.c` both have a
  `static int sysret`, and any program reaching both through the prototype-pull
  path warned about it — including a program whose only crtl reference is
  `printf`. bug-c-static-functions-in-different-crtl-modules-collide

  The caller records CModRangeCount before the lex and passes it here, so the
  coarse range lands ahead of everything that lex produced and the finer marks
  do what the original comment always claimed they did. }
var i, modId: Integer;
begin
  if CModRangeCount >= MAX_DBG_RANGES then Exit;
  if (atIdx < 0) or (atIdx > CModRangeCount) then Exit;
  modId := InternKey(path);
  for i := CModRangeCount downto atIdx + 1 do
  begin
    CModRangeStart[i] := CModRangeStart[i - 1];
    CModRangeId[i] := CModRangeId[i - 1];
  end;
  CModRangeStart[atIdx] := startTok;
  CModRangeId[atIdx] := modId;
  Inc(CModRangeCount);
end;

procedure CMarkTokNoModule(startTok: Integer);
{ Tokens from `startTok` on belong to NO C module -- the include stack has
  returned above the last `.c` it entered. Without this the attribution only
  ever moved forward into a module and never back out, so a `static` after
  `#include <stdio.h>` in a user header read as though it sat inside crtl's
  stdio.c. bug-a-c-module-attribution-is-sticky-after-a-crtl-impl-pull }
begin
  CMarkTokModuleId(startTok, -1);
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

procedure PasMarkTokFile(startTok: Integer; const path: AnsiString);
{ Tokens from `startTok` on come from the Pascal source `path`. CMarkTokModule's
  twin, and deliberately NOT gated on DebugInfo: it exists so a diagnostic can
  say which file it is talking about, which a build without -g needs just as
  much. Same collapse rules — a repeat of the current path is a no-op, and a
  second mark at the same token index overwrites rather than stacks.
  InternKey, not InternStr: these paths must never reach the emitted string
  pool, or a binary's bytes would depend on where its sources sat
  (bug-a-the-compilers-output-depends-on-argv0). }
var pathId: Integer;
begin
  if PasSrcRangeCount >= MAX_DBG_RANGES then Exit;
  pathId := InternKey(path);
  if (PasSrcRangeCount > 0) and (PasSrcRangeId[PasSrcRangeCount - 1] = pathId) then Exit;
  if (PasSrcRangeCount > 0) and (PasSrcRangeStart[PasSrcRangeCount - 1] = startTok) then
  begin
    PasSrcRangeId[PasSrcRangeCount - 1] := pathId;
    Exit;
  end;
  PasSrcRangeStart[PasSrcRangeCount] := startTok;
  PasSrcRangeId[PasSrcRangeCount] := pathId;
  Inc(PasSrcRangeCount);
  if PxxDbgWants('a.srcmap', '*') then
    writeln('PXXDBG a.srcmap PLANT start=', startTok, ' tokcount=', TokCount,
            ' lexing=', Lexing, ' ', path);
end;

procedure AdjustSrcRanges(atPos, delta: Integer);
{ A token-stream EDIT at `atPos` of `delta` tokens (positive = insert, negative =
  removal) moves every token after it — so it moves the file boundaries too.
  AdjustPass2Spans is the same idea for the body pass's spans, and this is its
  twin for the token->file map; both are called from InsertTokens/RemoveTokens
  and from the nested-routine lift's hand-rolled shift.

  Without it the map silently rots: the nested-routine lift removes a body from
  the middle of the stream, every later token slides down, and every range
  boundary above the edit now names the WRONG FILE for the tokens under it. The
  visible symptom is a diagnostic whose `in:` line names a 707-line file for an
  error on line 2074 — the LINE right (it rides on the token), the FILE wrong.
  Measured with PXXDBG=a.srcmap, which prints the table and the token index the
  diagnostic asked about.
  bug-a-a-diagnostic-in-a-used-unit-names-the-wrong-source-file

  Both tables move, for the same reason: DbgRange* is the DWARF line table's
  copy of the identical question, so a drifted range there puts a routine's
  line numbers in a different file's name under -g. }
var i: Integer;
begin
  for i := 0 to PasSrcRangeCount - 1 do
    if PasSrcRangeStart[i] >= atPos then
      PasSrcRangeStart[i] := PasSrcRangeStart[i] + delta;
  for i := 0 to DbgRangeCount - 1 do
    if DbgRangeStart[i] >= atPos then
      DbgRangeStart[i] := DbgRangeStart[i] + delta;
end;

{ A token-stream SPLICE pastes tokens that came from ANOTHER FILE into the
  middle of this one — the generic specialization body is the case, and it is a
  big one: rtl-generics' Generics.Defaults pastes tens of thousands of tokens.

  AdjustSrcRanges keeps the boundaries around such an edit correct, but it
  cannot make the pasted REGION right, because the range table is positional and
  the paste's provenance is not its neighbours'. The tokens keep the template's
  `.Line` (it rides on the token) and inherited the destination file (it rides on
  the index), so a diagnostic inside a specialized body reported the right LINE
  against the WRONG FILE — `in:` naming the program for an error on line 892 of
  fgl.pp, or naming nothing at all when the destination was the main file and the
  `in:` line is suppressed. Line and file came from two different places; this is
  what makes them come from one.

  Two entries: the pasted region belongs to `srcKeyId`, and the token just past
  it resumes whatever covered the splice point. Inserted IN ORDER, because
  PasSrcOfTok scans backwards and assumes the table is sorted by start — a plain
  append would be invisible to every lookup below it.
  bug-p-a-diagnostic-in-a-used-unit-names-the-wrong-source-file }
procedure PasInsertSrcRangeAt(startTok, keyId: Integer);
var i, j: Integer;
begin
  if PasSrcRangeCount >= MAX_DBG_RANGES then Exit;
  i := PasSrcRangeCount;
  while (i > 0) and (PasSrcRangeStart[i - 1] > startTok) do
  begin
    PasSrcRangeStart[i] := PasSrcRangeStart[i - 1];
    PasSrcRangeId[i] := PasSrcRangeId[i - 1];
    Dec(i);
  end;
  { An entry already starting exactly here is REPLACED, not stacked -- the same
    rule PasMarkTokFile uses, and it keeps a repeated splice at one point from
    growing the table without bound. }
  if (i > 0) and (PasSrcRangeStart[i - 1] = startTok) then
  begin
    for j := i to PasSrcRangeCount - 1 do
    begin
      PasSrcRangeStart[j] := PasSrcRangeStart[j + 1];
      PasSrcRangeId[j] := PasSrcRangeId[j + 1];
    end;
    PasSrcRangeId[i - 1] := keyId;
    Exit;
  end;
  PasSrcRangeStart[i] := startTok;
  PasSrcRangeId[i] := keyId;
  Inc(PasSrcRangeCount);
end;

procedure PasSpliceTokFile(startTok, count, srcKeyId: Integer);
var destKeyId, i: Integer;
begin
  if (count <= 0) or (srcKeyId < 0) then Exit;
  destKeyId := -1;
  for i := PasSrcRangeCount - 1 downto 0 do
    if startTok >= PasSrcRangeStart[i] then
    begin
      destKeyId := PasSrcRangeId[i];
      Break;
    end;
  if destKeyId = srcKeyId then Exit;   { pasted into its own file: nothing moved }
  { the resume entry FIRST: planting the region entry first would make the
    backward scan for destKeyId above see the region we are about to add }
  if destKeyId >= 0 then PasInsertSrcRangeAt(startTok + count, destKeyId);
  PasInsertSrcRangeAt(startTok, srcKeyId);
  if PxxDbgWants('a.srcmap', '*') then
    writeln('PXXDBG a.srcmap SPLICE start=', startTok, ' count=', count,
            ' src=', KeyStrs[srcKeyId], ' resumes=', destKeyId);
end;

function PasSrcOfTok(t: Integer): AnsiString;
{ The Pascal source a token came from, or '' when no range covers it (the main
  file before its first marker, and every token of a frontend that plants no
  marks). Backward scan, like CModuleOfTok. }
var i: Integer;
begin
  PasSrcOfTok := '';
  for i := PasSrcRangeCount - 1 downto 0 do
    if t >= PasSrcRangeStart[i] then
    begin
      PasSrcOfTok := KeyStrs[PasSrcRangeId[i]];
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
