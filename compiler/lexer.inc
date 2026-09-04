{ SPDX-License-Identifier: MPL-2.0 }

{ ===== Error ===== }

procedure WriteTokenContext; forward;   { body sits after GetTokenStrFromRaw, which it uses }

procedure WriteDiagSourceFile; forward;   { body sits after PasSrcOfTok is reachable; see below }

procedure LexOne(var tokStart: Integer); forward;   { body is in paslexer.inc, which is
  included right after this file. LexAppend below is SHARED -- pylexer.inc, symtab.inc and
  pasparser_proc.inc all call it -- so it could not follow the Pascal lexer out, and it is
  the one routine here that calls into it. This forward is the whole cost of the split. }

{ ===== The error routines: TWO axes, TWO helpers, four entry points =====

  The axes are independent, which is why there are four names and not one:

    WHERE THE LINE COMES FROM   the current token (the parser is there) vs an
                                AST node's recorded line (an IR-lowering check
                                runs long after the parser reached EOF, so
                                CurTok.Line and the `near:` window would both
                                point at the end of the program and actively
                                mislead)
    WHAT HAPPENS AFTERWARDS     halt, or count and return

  Everything else -- the wording, the optional `(ident)` suffix, clearing
  ErrorIdent, the `in:` line, the `near:` window, the MAX_REPORTED_ERRORS cap --
  is shared, and is shared HERE rather than copied into each of the four.

  It was copied into each of the four. ErrorPrint's comment claimed to be "the
  one place a diagnostic is formatted" while ErrorAt and then ErrorAtRecover
  each carried their own copy of the ident-parens logic, and the cap was written
  out twice. Three copies of one five-line rule is the shape
  devdocs/dev/normalise-dont-special-case.md names, and the third copy arrived
  the moment a fourth entry point was needed -- which is the argument for
  deleting the pattern rather than auditing it.
  feature-a-error-does-not-halt-so-a-parse-can-be-speculative }

procedure ErrorPrintAt(line: Integer; const msg: AnsiString; withContext: Boolean);
{ THE one place a diagnostic is worded. `withContext` is False for a check that
  runs after the parse: the `in:` path and the `near:` window are both read off
  the LEXER's current position, which by then is EOF. }
begin
  { ErrorIdent names the symbol the diagnostic is about; when there is none, the
    old unconditional parens printed a bare "()" that reads like an empty format
    slot (bug-overload-mismatch-dumps-internals-to-stdout). }
  if ErrorIdent <> '' then
    writeln('pascal26:', line, ': error: ', msg, ' (', ErrorIdent, ')')
  else
    writeln('pascal26:', line, ': error: ', msg);
  if withContext then
  begin
    WriteDiagSourceFile;
    WriteTokenContext;
  end;
  { cleared, because a RECOVERED diagnostic is followed by more of them: a stale
    ident would be re-printed beside the next message, naming the wrong symbol. }
  ErrorIdent := '';
end;

procedure ErrorPrint(const msg: AnsiString);
{ The parser-position form of the above, kept as its own name because that is
  what the ~600 Error() sites read as. }
begin
  ErrorPrintAt(CurTok.Line, msg, True);
end;

procedure CountRecoveredError;
{ The tail every recovering diagnostic shares: count it, and stop once the file
  is producing noise rather than information. Past a handful of errors a
  cascading file is not telling the user anything more. }
begin
  Inc(ErrCount);
  if ErrCount >= MAX_REPORTED_ERRORS then
  begin
    writeln('pascal26: too many errors, stopping');
    Halt(1);
  end;
end;

procedure Error(const msg: AnsiString);
begin
  ErrorPrint(msg);
  Halt(1);
end;

procedure ErrorRecover(const msg: AnsiString);
{ A diagnostic the caller can CARRY ON past: it is reported and counted, and the
  parse continues so the next independent mistake in the file is found too. The
  caller owes the parse a well-formed stand-in for whatever failed (see
  PoisonSym in pasparser_lval.inc) -- returning here with a -1 symbol index or
  an unset Result node just moves the crash.

  Only ever a SEMANTIC failure over a well-formed token stream (a name that does
  not resolve). A syntax error still halts: past one, the parser's position is
  no longer meaningful and every later message is noise.

  ErrCount is checked once, after the parse, and no output is written when it is
  nonzero -- so nothing downstream ever sees a poisoned symbol. }
begin
  ErrorPrint(msg);
  CountRecoveredError;
end;

procedure ErrorAt(line: Integer; const msg: AnsiString);
{ Fatal error for a site the CURRENT TOKEN is nowhere near -- an IR-lowering
  check. See the `withContext` note on ErrorPrintAt. }
begin
  ErrorPrintAt(line, msg, False);
  Halt(1);
end;

procedure ErrorNoPos(const msg: AnsiString);
{ A WHOLE-PROGRAM diagnostic: one that is true of the output as a unit and has
  no source position at all. Every check in `elfwriter.inc` is one of these,
  because the writer runs after the parse has finished.

  Plain `Error` was wrong for them in a way that reads as CORRECT, which is why
  it survived: `ErrorPrint` passes withContext=True, so the `in:` path and the
  `near:` window are read off the LEXER's position -- and at that point the
  lexer is standing wherever it stopped, which is inside the last builtin unit
  it parsed. So `--emit-obj` on a plain program refused with

    pascal26:2: error: --emit-obj: this object would define no linkable symbol...
      in: ./compiler/builtin/builtinheap.pas
      near: ( 'hi' ) ; end . >>> unit builtinheap ;

  The MESSAGE is right and its COORDINATES are not, which is the expensive
  combination: it names a real file the user never wrote, and a `near:` window
  splicing their tokens onto a builtin's. Two agents read it as "the frontend
  cannot parse this" and one spent a probe on it before checking.

  `line` is 1 rather than absent because the first line is a PARSED INTERFACE --
  garin's builder.pas keys jump-to-error off the number between the first two
  colons (see WriteDiagSourceFile below), so dropping it would make these
  invisible to the IDE. 1 opens the user's main file at the top, which is the
  right place to stand for a diagnostic about the program as a whole. }
begin
  ErrorPrintAt(1, msg, False);
  Halt(1);
end;

procedure ErrorAtRecover(line: Integer; const msg: AnsiString);
{ ErrorAt's recovering twin, and ErrorRecover's out-of-position twin: same
  contract as ErrorRecover -- a SEMANTIC failure whose caller leaves something
  well-formed behind -- reported against an AST node's line because the lowering
  is past the parser's position. }
begin
  ErrorPrintAt(line, msg, False);
  CountRecoveredError;
end;

{ `  in: <path>` under a diagnostic whose token did NOT come from the main
  source — an included .inc, or a `uses`d unit. Silent for the main file, whose
  name the user just typed.

  A SEPARATE LINE, and the `pascal26:<line>:` prefix above is left exactly as it
  was, deliberately. That first line is a parsed interface: apps/ide/garin's
  builder.pas keys off "a number between the first two colons" to drive
  jump-to-error, so folding the path in as `pascal26:<path>:<line>:` would make
  every diagnostic in an include invisible to the IDE — trading one broken half
  of "where" for another. An extra context line is additive, in the same shape
  as the `near:` window that follows it, and anything that does not understand
  it ignores it.
  bug-a-a-parse-error-in-a-used-unit-reports-a-line-in-no-file }
procedure WriteDiagSourceFile;
var path, cpath: AnsiString; t, dbgI, cmod: Integer;
begin
  if Lexing then t := TokCount
  else if TokPos > 0 then t := TokPos - 1
  else t := 0;
  path := PasSrcOfTok(t);
  { PXXDBG=a.srcmap — the token->file range table, plus the token index this
    diagnostic actually asked about. `in:` has been seen naming a 707-line file
    for an error on line 2074, and there is no way to tell from the outside
    whether the RANGES are wrong or the token INDEX is: this prints both.
    bug-a-a-diagnostic-in-a-used-unit-names-the-wrong-source-file }
  if PxxDbgWants('a.srcmap', '*') then
  begin
    writeln('PXXDBG a.srcmap tok=', t, ' srcline=', Tokens[t].Line,
            ' lexing=', Lexing, ' tokcount=', TokCount, ' -> ', path);
    for dbgI := 0 to PasSrcRangeCount - 1 do
      writeln('PXXDBG a.srcmap   [', dbgI, '] start=', PasSrcRangeStart[dbgI],
              ' lines ', Tokens[PasSrcRangeStart[dbgI] - 1].Line, '|',
              Tokens[PasSrcRangeStart[dbgI]].Line, ' ',
              Tokens[PasSrcRangeStart[dbgI] + 1].Line, ' ',
              Tokens[PasSrcRangeStart[dbgI] + 2].Line, '  ',
              GetTokenStr(PasSrcRangeStart[dbgI]), ' ',
              GetTokenStr(PasSrcRangeStart[dbgI] + 1), ' ',
              GetTokenStr(PasSrcRangeStart[dbgI] + 2),
              '  ', KeyStrs[PasSrcRangeId[dbgI]]);
  end;
  { PXXDBG=c.srcmap — the C twin of the probe above. The C answer is reached only
    where the Pascal one is EMPTY, so it is invisible to every Pascal diagnostic
    and to every C diagnostic the Pascal table happens to answer; there is no
    output to be suspicious of when it is wrong. Print what it saw. }
  if PxxDbgWants('c.srcmap', '*') then
  begin
    writeln('PXXDBG c.srcmap tok=', t, ' paspath="', path, '" cmod=', CModuleOfTok(t),
            ' dbgsrc=', DbgSrcName);
    for dbgI := 0 to CModRangeCount - 1 do
      writeln('PXXDBG c.srcmap   [', dbgI, '] start=', CModRangeStart[dbgI],
              '  ', KeyStrs[CModRangeId[dbgI]]);
  end;
  if (path <> '') and (path <> DbgSrcName) then writeln('  in: ', path)
  { The C fallback, and it is an APPENDED arm on purpose: it fires only where
    `path` is EMPTY, i.e. where the Pascal range table has no answer at all, so
    every state that printed something before still prints exactly that, and
    every state that deliberately stayed silent BECAUSE the path was the main
    source still does. Restructuring the condition instead would be invisible to
    every Pascal test, because a test with an answer never reaches this arm.

    CModRange* is populated in every build, not just under -g, so this works
    without debug info. What it names is the C MODULE: a file-scope static in a
    header is attributed to the `.c` that included it (see CMarkTokModule), so an
    error inside an INCLUDED HEADER still prints nothing here when that header
    came from the main source. Naming the header needs an ungated per-token
    source table for C -- PasMarkTokFile's twin -- which is Track A ground:
    bug-a-c-diagnostics-cannot-name-a-header-only-the-module-that-included-it. }
  else if path = '' then
  begin
    cmod := CModuleOfTok(t);
    if cmod >= 0 then
    begin
      cpath := KeyStrs[cmod];
      { the main `.c` stays silent, exactly as the main `.pas` does above -- the
        user typed that name. `<crtl-prototype-pull>` is a synthetic marker, not
        a file, and must never be printed as one -- that arm is DEFENSIVE and
        unreached by anything I could construct: the real `.c` markers inside the
        pulled block refine the synthetic one immediately, so an error there
        reports cmod = -1 (measured, PXXDBG=c.srcmap). It stays because the
        window between the block's start and its first real marker is the crtl
        headers' own prototypes, which is reachable in principle. }
      if (cpath <> '') and (cpath <> DbgSrcName) and (cpath[1] <> '<') then
        writeln('  in: ', cpath);
    end;
  end;
end;

procedure EnsureTokCapacity(need: Integer);
{ Grow the token parallel arrays so index `need-1` is in bounds. Called after every
  Inc(TokCount) append (across all frontend lexers) and once at startup, so the
  invariant TokCapacity > TokCount holds before every write. Doubling from 65536;
  capacity never shrinks across a per-source TokCount reset. ALL 12 token arrays grow
  in lockstep — a missed one is a silent out-of-bounds. See
  feature-dynamic-compiler-tables. }
var n: Integer;
begin
  if need <= TokCapacity then Exit;
  if TokCapacity = 0 then n := 65536 else n := TokCapacity;
  while n < need do n := n * 2;
  SetLength(Tokens, n);          SetLength(TokPackRecords, n);  SetLength(TokQChecks, n);
  SetLength(TokAssertions, n);
  SetLength(TokRChecks, n);      SetLength(TokIChecks, n);      SetLength(TokScopedEnums, n);
  SetLength(TokNChecks, n);
  SetLength(TokSrcOff, n);       SetLength(TokSrcLen, n);
  SetLength(CAttrFlags, n);      SetLength(CAttrAlignValues, n);
  TokCapacity := n;
end;

procedure ShiftTokParallel(atPos, delta: Integer);
{ Move the ELEVEN token-parallel arrays to match a shift of Tokens[] by `delta` at
  `atPos` -- positive for an insert, negative for a remove. Call it with the OLD
  TokCount still in place, which is what both splice sites do.

  ALL ELEVEN ARE POSITIONAL, checked one at a time rather than assumed: defs.inc
  documents every one of them as state "at this token" -- the seven directive
  states ({$PACKRECORDS}, {$Q}, {$R}, {$I}, {$N}, {$SCOPEDENUMS}, {$ASSERTIONS}), the two
  source-spelling channels and the two C attribute slots. Not one is a side
  table keyed by anything but the token index, so a splice moves all of them or
  desynchronises all of them.

  IT MOVED EXACTLY ONE OF ELEVEN. InsertTokens and RemoveTokens shifted
  Tokens[] and nothing else, so the FIRST splice of a compile desynchronised the
  other ten and they stayed that way for the rest of it. The loud symptom was
  the `near:` window printing the text that used to live at those indices --
  on a generic specialization it printed un-substituted `T`, which cannot occur
  in a substituted body, so the output convicted itself without reading any
  code. The directive states are the quiet half and nobody had looked: a {$R+}
  region's boundary moves by the splice width, and range checking silently
  starts or stops at the wrong token.

  EnsureTokCapacity above already says "ALL 12 token arrays grow in lockstep --
  a missed one is a silent out-of-bounds". This is the same list and the same
  hazard one operation over, which is why the two now sit together: a new
  parallel array must be added to BOTH, and separating them is what let one
  list run ahead of the other.
  bug-a-the-near-context-window-is-stale-after-a-token-splice }
var i, src: Integer;
begin
  if delta > 0 then
  begin
    for i := TokCount - 1 downto atPos do
    begin
      TokPackRecords[i + delta] := TokPackRecords[i];
      TokQChecks[i + delta]     := TokQChecks[i];
      TokAssertions[i + delta]  := TokAssertions[i];
      TokRChecks[i + delta]     := TokRChecks[i];
      TokIChecks[i + delta]     := TokIChecks[i];
      TokNChecks[i + delta]     := TokNChecks[i];
      TokScopedEnums[i + delta] := TokScopedEnums[i];
      TokSrcOff[i + delta]      := TokSrcOff[i];
      TokSrcLen[i + delta]      := TokSrcLen[i];
      CAttrFlags[i + delta]     := CAttrFlags[i];
      CAttrAlignValues[i + delta] := CAttrAlignValues[i];
    end;
    { THE GAP, and the two halves of it are filled DIFFERENTLY on purpose.

      Directive state is LEXICALLY CONTINUOUS, so a spliced token inherits the
      state in effect immediately before it -- the token at atPos-1, or the one
      it displaced when it is being inserted at the very front. Leaving the gap
      as whatever those slots happened to hold is how a {$R+} region acquires a
      hole the source never wrote.

      The SPELLING channels are zeroed instead. For a SYNTHESIZED token that is
      the correct answer and not a default: WriteTokenContext falls back to the
      raw token's own SOffset/SLen when TokSrcLen is 0, and there is no source
      range to point at because the token was never in the file. Copying a
      neighbour's spelling here would reproduce the very bug this procedure
      fixes, one token over. Same for the C attribute slots: a synthesized
      token carries no attribute.

      IT IS NOT THE RIGHT ANSWER FOR EVERY CALLER, AND THAT WAS MEASURED HERE
      RATHER THAN REASONED. A generic specialization splices tokens that are
      VERBATIM COPIES of template tokens, each with a real source range, so
      zeroing lost it and the window inside a specialized body printed its
      identifiers with its punctuation blanked -- the same defect
      TokSrcOff/TokSrcLen exist to fix, one scope down. A caller that HAS real
      spans cannot say so through this procedure, so it does not try to: the
      specializer overwrites these two slots itself, right after this shift,
      carrying the span for verbatim copies and leaving the zero for
      substituted ones (95c98db70). Any future caller splicing real tokens owes
      the same overwrite; a caller splicing synthesized ones owes nothing. }
    src := atPos - 1;
    if src < 0 then src := atPos + delta;
    if (src >= 0) and (src < TokCount + delta) then
      for i := atPos to atPos + delta - 1 do
      begin
        TokPackRecords[i] := TokPackRecords[src];
        TokQChecks[i]     := TokQChecks[src];
        TokAssertions[i]  := TokAssertions[src];
        TokRChecks[i]     := TokRChecks[src];
        TokIChecks[i]     := TokIChecks[src];
        TokNChecks[i]     := TokNChecks[src];
        TokScopedEnums[i] := TokScopedEnums[src];
        TokSrcOff[i]      := 0;
        TokSrcLen[i]      := 0;
        CAttrFlags[i]     := 0;
        CAttrAlignValues[i] := 0;
      end;
  end
  else if delta < 0 then
    for i := atPos to TokCount + delta - 1 do
    begin
      TokPackRecords[i] := TokPackRecords[i - delta];
      TokQChecks[i]     := TokQChecks[i - delta];
      TokAssertions[i]  := TokAssertions[i - delta];
      TokRChecks[i]     := TokRChecks[i - delta];
      TokIChecks[i]     := TokIChecks[i - delta];
      TokNChecks[i]     := TokNChecks[i - delta];
      TokScopedEnums[i] := TokScopedEnums[i - delta];
      TokSrcOff[i]      := TokSrcOff[i - delta];
      TokSrcLen[i]      := TokSrcLen[i - delta];
      CAttrFlags[i]     := CAttrFlags[i - delta];
      CAttrAlignValues[i] := CAttrAlignValues[i - delta];
    end;
end;

procedure RecordTokSpan(idx, startPos, endPos: Integer);
{ Record token `idx`'s SOURCE SPELLING -- Source[startPos..endPos-1] -- into
  TokSrcOff/TokSrcLen. THE one implementation, called by every frontend's lexer.

  Shared deliberately, and it is the one thing in this feature that is shared.
  The bug being fixed exists because eleven lexers hand-copied the same "which
  tokens keep their text" if/else and the copies could not be fixed in one
  place; writing this out per lexer would rebuild that exact situation while
  claiming to repair it. What must stay per-language is the DECISION of where a
  token starts and ends -- that is the lexer's own business, and the reason
  `devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md` says to duplicate
  parsers and share substrate. This is substrate.

  Shares the bytes already written for the token's SVal when the two are the
  same text, which for an identifier they almost always are. Copying both
  unconditionally took the char pool from 38% to 86% of a FIXED cap on
  compiler.pas; sharing puts it at 51%. Measure with PXXDBG=a.tokpool:*, never
  by counting source bytes -- that proxy has now been wrong twice, in opposite
  directions.
  bug-a-the-token-pool-stores-text-only-for-identifiers-and-strings }
var n, i: Integer; reuse: Boolean;
begin
  n := endPos - startPos;
  if n < 0 then n := 0;
  if startPos + n - 1 > Length(Source) then n := Length(Source) - startPos + 1;
  if n <= 0 then Exit;
  reuse := (Tokens[idx].SLen = n);
  if reuse then
  begin
    i := 1;
    while i <= n do
    begin
      if TokChars[Tokens[idx].SOffset + i - 1] <> Source[startPos + i - 1] then
      begin
        reuse := False;
        i := n;
      end;
      Inc(i);
    end;
  end;
  if reuse then
  begin
    TokSrcOff[idx] := Tokens[idx].SOffset;
    TokSrcLen[idx] := n;
    Exit;
  end;
  if TokCharLen + n > STRING_CAP then Error('token char pool overflow');
  TokSrcOff[idx] := TokCharLen;
  TokSrcLen[idx] := n;
  i := 1;
  while i <= n do
  begin
    TokChars[TokCharLen] := Source[startPos + i - 1];
    Inc(TokCharLen);
    Inc(i);
  end;
end;

procedure TokPoolReport;
{ PXXDBG=a.tokpool — what the token char pool actually holds, against its cap.
  STRING_CAP is FIXED and overflowing it is a hard Error, so anyone sizing a
  change against it needs the real number rather than a proxy for it. Sizing the
  source-spelling channel from SOURCE bytes gave 7.52 MB (94% of cap) and would
  have killed the feature; sizing it as an ADDITION gave 40% and would have
  waved through something that measured 86%. The quantity is TOKEN bytes, this
  repo is ~68% comment bytes, and only the compiler can count them.

  Deliberately NOT in a lexer: it must read the same number for every frontend,
  and the frontend whose headroom is actually in question is C, whose largest
  real input (sqlite's 257k-line amalgamation) is the file that broke a fixed
  table cap once already.
  bug-a-the-token-pool-stores-text-only-for-identifiers-and-strings }
var i, spell: Integer;
begin
  if not PxxDbgWants('a.tokpool', '*') then Exit;
  spell := 0;
  for i := 0 to TokCount - 1 do spell := spell + TokSrcLen[i];
  writeln('PXXDBG a.tokpool bytes=', TokCharLen, ' cap=', STRING_CAP,
          ' pct=', (TokCharLen * 100) div STRING_CAP,
          ' tokens=', TokCount, ' spellings=', spell,
          ' other=', TokCharLen - spell);
end;

{ Non-fatal diagnostic for accepted-but-suspect constructs (a case-insensitive
  C-import match, a narrowing, an ignored attribute). Prints
  `pascal26:<line>: warning: ...` to stdout, in the same shape as Error, and
  keeps compiling. With -Werror (WarnAsError) it is promoted to a fatal Error.
  Use WarnAt when the current token is not at the offending site. }
procedure WarnAt(line: Integer; const msg: AnsiString);
begin
  Inc(WarnCount);
  if WarnAsError then
  begin
    writeln('pascal26:', line, ': error: ', msg, ' (warning promoted by -Werror)');
    Halt(1);
  end;
  writeln('pascal26:', line, ': warning: ', msg);
end;

procedure Warn(const msg: AnsiString);
begin
  WarnAt(CurTok.Line, msg);
end;

{ Oversized stack-frame warning. Built with writeln (not Warn) so the byte
  counts format without an int->string helper, matching Error's inline style.
  -Werror promotes it. See feature-warn-oversized-stack-frame. }
procedure WarnStackFrame(line: Integer; const routine: AnsiString; frameBytes, limit: Integer);
begin
  Inc(WarnCount);
  if WarnAsError then
  begin
    writeln('pascal26:', line, ': error: routine ''', routine, ''' uses ', frameBytes,
            ' bytes of stack frame (> ', limit, ') (warning promoted by -Werror)');
    Halt(1);
  end;
  writeln('pascal26:', line, ': warning: routine ''', routine, ''' uses ', frameBytes,
          ' bytes of stack frame (> ', limit, '); large frames risk stack overflow',
          ' — move big buffers to the heap (GetMem) or a global');
end;

{ A C name resolved through FindProc, which spans the C and PASCAL namespaces
  case-insensitively, and landed on a Pascal routine of a DIFFERENT arity. The
  cross-namespace bind itself is deliberate (lua's <math.h> sqrt/sin/cos bind to
  the RTL's Pascal routines), but nothing checked that the two agree, and when
  they do not the call compiles and crashes somewhere else entirely:
  `time(NULL)` bound to sysutils' parameterless `Time` and faulted inside it
  (bug-c-unit-crashes-when-sysutils-is-used), and the same shape made exp(x)
  return e^(previous result) because the argument never arrived (b377).
  bug-cfront-silent-bind-to-pascal-proc-of-different-arity. }
procedure WarnCrossBindArity(line: Integer; const cname, pname: AnsiString;
                             pcount, nargs: Integer);
begin
  Inc(WarnCount);
  if WarnAsError then
  begin
    writeln('pascal26:', line, ': error: C declaration of ''', cname,
            ''' does not match the Pascal routine ''', pname, ''' which takes ',
            pcount, ' parameter(s), not ', nargs,
            ' (warning promoted by -Werror)');
    Halt(1);
  end;
  writeln('pascal26:', line, ': warning: C declaration of ''', cname,
          ''' does not match the Pascal routine ''', pname, ''' which takes ',
          pcount, ' parameter(s), not ', nargs,
          ' — binding to the C declaration, not the Pascal routine');
end;

{ The arity check's sibling: same parameter COUNT, but a parameter (or the
  result) disagrees on whether it is a FLOAT. That class decides the register
  file — XMM vs general-purpose on x86-64, and the whole marshalling path — so a
  disagreement there cannot produce a right answer, unlike int-vs-pointer, which
  share the GP path and are interchanged harmlessly all over the corpora. This
  is the shape that made `exp(x)` return e^(previous result) in b377.
  bug-cfront-silent-bind-to-pascal-proc-of-different-arity, rung 3. }
procedure WarnCrossBindType(line: Integer; const cname, pname, what: AnsiString);
begin
  Inc(WarnCount);
  if WarnAsError then
  begin
    writeln('pascal26:', line, ': error: C declaration of ''', cname,
            ''' disagrees with the Pascal routine ''', pname, ''' on ', what,
            ' (float vs non-float; warning promoted by -Werror)');
    Halt(1);
  end;
  writeln('pascal26:', line, ': warning: C declaration of ''', cname,
          ''' disagrees with the Pascal routine ''', pname, ''' on ', what,
          ' (float vs non-float) — binding to the C declaration');
end;

{ --auto-locals / {$IMPLICITVARS ON}: an assignment to an undeclared name just
  created an implicit routine-local. Warn so the sloppy-mode inference is
  visible (a typo'd name silently becomes a new variable otherwise). }
procedure WarnImplicitVar(line: Integer; const name: AnsiString);
begin
  Inc(WarnCount);
  if WarnAsError then
  begin
    writeln('pascal26:', line, ': error: implicit variable ''', name,
            ''' (warning promoted by -Werror)');
    Halt(1);
  end;
  writeln('pascal26:', line, ': warning: implicit variable ''', name,
          ''' created by --auto-locals (undeclared; type inferred from first assignment)');
end;

{ ===== Lexer ===== }

function Keyword(const s0: AnsiString): TTokenKind;
var s: AnsiString; ki: Integer;
begin
  Result := tkIdent;
  { Pascal keywords are case-insensitive in user code (only the compiler's own
    source is {$CASESENSITIVE ON}). The table below historically hard-coded
    lowercase (plus ad-hoc Capital variants for some), so mixed/upper-case forms
    like `Then`, `Type`, `Mod`, `Case`, `ARRAY` fell through to identifiers.
    Lowercase the token once here (user mode only) so every entry matches any
    case; the redundant Capital-variant entries become harmless. CaseSensitive
    mode (the self-build) keeps the exact spelling, so self-host stays
    byte-identical. }
  s := s0;
  if not CaseSensitiveMode then
    for ki := 1 to Length(s) do
      if (s[ki] >= 'A') and (s[ki] <= 'Z') then
        s[ki] := Chr(Ord(s[ki]) + 32);
  if Length(s) = 2 then
  begin
    if (s[1]='i') and (s[2]='f') then Result := tkIf;
    if (s[1]='i') and (s[2]='n') then Result := tkIn;
    if (s[1]='I') and (s[2]='n') then Result := tkIn;
    if (s[1]='d') and (s[2]='o') then Result := tkDo;
    if (s[1]='t') and (s[2]='o') then Result := tkTo;
    if (s[1]='o') and (s[2]='f') then Result := tkOf;
    if (s[1]='o') and (s[2]='r') then Result := tkOr;
    if (s[1]='o') and (s[2]='n') then Result := tkOn;
    if (s[1]='O') and (s[2]='n') then Result := tkOn;
  end
  else if Length(s) = 3 then
  begin
    if (s[1]='a') and (s[2]='s') and (s[3]='m') then Result := tkAsm;
    if (s[1]='A') and (s[2]='s') and (s[3]='m') then Result := tkAsm;
    if (s[1]='A') and (s[2]='S') and (s[3]='M') then Result := tkAsm;
    if (s[1]='e') and (s[2]='n') and (s[3]='d') then Result := tkEnd;
    if (s[1]='v') and (s[2]='a') and (s[3]='r') then Result := tkVar;
    if (s[1]='f') and (s[2]='o') and (s[3]='r') then Result := tkFor;
    if (s[1]='a') and (s[2]='n') and (s[3]='d') then Result := tkAnd;
    if ((s[1]='x') or (s[1]='X')) and ((s[2]='o') or (s[2]='O')) and ((s[3]='r') or (s[3]='R')) then Result := tkXor;
    if (s[1]='n') and (s[2]='o') and (s[3]='t') then Result := tkNot;
    if (s[1]='d') and (s[2]='i') and (s[3]='v') then Result := tkDiv;
    if (s[1]='m') and (s[2]='o') and (s[3]='d') then Result := tkMod;
    if (s[1]='s') and (s[2]='h') and (s[3]='l') then Result := tkShl;
    if (s[1]='S') and (s[2]='h') and (s[3]='l') then Result := tkShl;
    { 'ord'/'chr'/'low' (and 'high'/'length' below) are soft keywords: they lex
      as plain tkIdent and ParseFactor dispatches on the name, so they are
      legal identifiers like in FPC (bug-hard-keyword-intrinsics-block-
      identifier-use). Their tk enum members survive only as -Ord(tkXxx)
      intrinsic CALL ids. }
    if (s[1]='t') and (s[2]='r') and (s[3]='y') then Result := tkTry;
    if (s[1]='T') and (s[2]='r') and (s[3]='y') then Result := tkTry;
    if (s[1]='n') and (s[2]='i') and (s[3]='l') then Result := tkNil;
    if (s[1]='N') and (s[2]='i') and (s[3]='l') then Result := tkNil;
  end
  else if Length(s) = 4 then
  begin
    if (s[1]='w') and (s[2]='i') and (s[3]='t') and (s[4]='h') then Result := tkWith;
    if (s[1]='W') and (s[2]='i') and (s[3]='t') and (s[4]='h') then Result := tkWith;
    if (s[1]='W') and (s[2]='I') and (s[3]='T') and (s[4]='H') then Result := tkWith;
    if (s[1]='t') and (s[2]='y') and (s[3]='p') and (s[4]='e') then Result := tkType;
    if (s[1]='u') and (s[2]='s') and (s[3]='e') and (s[4]='s') then Result := tkUses;
    if (s[1]='u') and (s[2]='n') and (s[3]='i') and (s[4]='t') then Result := tkUnit;
    if (s[1]='t') and (s[2]='h') and (s[3]='e') and (s[4]='n') then Result := tkThen;
    if (s[1]='e') and (s[2]='l') and (s[3]='s') and (s[4]='e') then Result := tkElse;
    if (s[1]='c') and (s[2]='a') and (s[3]='s') and (s[4]='e') then Result := tkCase;
    if (s[1]='t') and (s[2]='r') and (s[3]='u') and (s[4]='e') then Result := tkTrue;
    if (s[1]='T') and (s[2]='r') and (s[3]='u') and (s[4]='e') then Result := tkTrue;
    if CaseEqual(s, 'read') then Result := tkRead;
    if (s[1]='c') and (s[2]='h') and (s[3]='a') and (s[4]='r') then Result := tkChar_T;
    if (s[1]='C') and (s[2]='h') and (s[3]='a') and (s[4]='r') then Result := tkChar_T;
    if (s[1]='r') and (s[2]='e') and (s[3]='a') and (s[4]='l') then Result := tkReal_T;
    if (s[1]='R') and (s[2]='e') and (s[3]='a') and (s[4]='l') then Result := tkReal_T;
    if (s[1]='b') and (s[2]='y') and (s[3]='t') and (s[4]='e') then Result := tkInteger_T;
    if (s[1]='B') and (s[2]='y') and (s[3]='t') and (s[4]='e') then Result := tkInteger_T;
  end
  else if Length(s) = 5 then
  begin
    if (s[1]='b') and (s[2]='e') and (s[3]='g') and (s[4]='i') and (s[5]='n') then Result := tkBegin;
    if (s[1]='c') and (s[2]='o') and (s[3]='n') and (s[4]='s') and (s[5]='t') then Result := tkConst;
    if (s[1]='w') and (s[2]='h') and (s[3]='i') and (s[4]='l') and (s[5]='e') then Result := tkWhile;
    if (s[1]='u') and (s[2]='n') and (s[3]='t') and (s[4]='i') and (s[5]='l') then Result := tkUntil;
    if (s = 'array') or ((not CaseSensitiveMode) and CaseEqual(s, 'array')) then Result := tkArray;
    if (s[1]='f') and (s[2]='a') and (s[3]='l') and (s[4]='s') and (s[5]='e') then Result := tkFalse;
    if (s[1]='F') and (s[2]='a') and (s[3]='l') and (s[4]='s') and (s[5]='e') then Result := tkFalse;
    if CaseEqual(s, 'write') then Result := tkwrite;
    if (s[1]='c') and (s[2]='l') and (s[3]='a') and (s[4]='s') and (s[5]='s') then Result := tkClass;
    if (s[1]='C') and (s[2]='l') and (s[3]='a') and (s[4]='s') and (s[5]='s') then Result := tkClass;
    if (s[1]='r') and (s[2]='a') and (s[3]='i') and (s[4]='s') and (s[5]='e') then Result := tkRaise;
    if (s[1]='R') and (s[2]='a') and (s[3]='i') and (s[4]='s') and (s[5]='e') then Result := tkRaise;
  end
  else if Length(s) = 6 then
  begin
    if (s[1]='d') and (s[2]='o') and (s[3]='w') and (s[4]='n') and (s[5]='t') and (s[6]='o') then Result := tkDownto;
    if (s[1]='r') and (s[2]='e') and (s[3]='p') and (s[4]='e') and (s[5]='a') and (s[6]='t') then Result := tkRepeat;
    if (s[1]='p') and (s[2]='a') and (s[3]='c') and (s[4]='k') and (s[5]='e') and (s[6]='d') then Result := tkPacked;
    if (s[1]='P') and (s[2]='a') and (s[3]='c') and (s[4]='k') and (s[5]='e') and (s[6]='d') then Result := tkPacked;
    if (s[1]='r') and (s[2]='e') and (s[3]='c') and (s[4]='o') and (s[5]='r') and (s[6]='d') then Result := tkRecord;
    if CaseEqual(s, 'readln') then Result := tkReadln;
    { 'length' deliberately NOT a keyword token: it lexes as a plain tkIdent and
      ParseFactor dispatches on the name (soft keyword), so `var length: ...`
      is a legal identifier like in FPC. Pilot conversion for
      bug-hard-keyword-intrinsics-block-identifier-use; likewise inc/dec/halt/
      exit/break/continue/getmem/freemem, dispatched in ParseStatementAST (and
      GetMem's function form in ParseFactor). The tk enum members survive only
      as -Ord(tkXxx) intrinsic CALL ids and AN node selectors. }
    if (s[1]='a') and (s[2]='r') and (s[3]='g') and (s[4]='s') and (s[5]='t') and (s[6]='r') then Result := tkArgStr;
    if (s[1]='A') and (s[2]='r') and (s[3]='g') and (s[4]='S') and (s[5]='t') and (s[6]='r') then Result := tkArgStr;
    if (s[1]='s') and (s[2]='t') and (s[3]='r') and (s[4]='i') and (s[5]='n') and (s[6]='g') then Result := tkString_T;
    if (s[1]='S') and (s[2]='t') and (s[3]='r') and (s[4]='i') and (s[5]='n') and (s[6]='g') then Result := tkString_T;
    if (s[1]='e') and (s[2]='x') and (s[3]='c') and (s[4]='e') and (s[5]='p') and (s[6]='t') then Result := tkExcept;
    if (s[1]='E') and (s[2]='x') and (s[3]='c') and (s[4]='e') and (s[5]='p') and (s[6]='t') then Result := tkExcept;
    if (s[1]='s') and (s[2]='i') and (s[3]='n') and (s[4]='g') and (s[5]='l') and (s[6]='e') then Result := tkSingle_T;
    if (s[1]='S') and (s[2]='i') and (s[3]='n') and (s[4]='g') and (s[5]='l') and (s[6]='e') then Result := tkSingle_T;
    if (s[1]='d') and (s[2]='o') and (s[3]='u') and (s[4]='b') and (s[5]='l') and (s[6]='e') then Result := tkDouble_T;
    if (s[1]='D') and (s[2]='o') and (s[3]='u') and (s[4]='b') and (s[5]='l') and (s[6]='e') then Result := tkDouble_T;
  end
  else if Length(s) = 7 then
  begin
    if (s[1]='d') and (s[2]='e') and (s[3]='f') and (s[4]='a') and (s[5]='u') and (s[6]='l') and (s[7]='t') then Result := tkDefault;
    if (s[1]='D') and (s[2]='e') and (s[3]='f') and (s[4]='a') and (s[5]='u') and (s[6]='l') and (s[7]='t') then Result := tkDefault;
    if (s[1]='p') and (s[2]='r') and (s[3]='o') and (s[4]='g') and (s[5]='r') and (s[6]='a') and (s[7]='m') then Result := tkProgram;
    if (s[1]='f') and (s[2]='o') and (s[3]='r') and (s[4]='w') and (s[5]='a') and (s[6]='r') and (s[7]='d') then Result := tkForward;
    if CaseEqual(s, 'writeln') then Result := tkwriteln;
    if (s[1]='s') and (s[2]='y') and (s[3]='s') and (s[4]='o') and (s[5]='p') and (s[6]='e') and (s[7]='n') then Result := tkSysOpen;
    if (s[1]='S') and (s[2]='y') and (s[3]='s') and (s[4]='O') and (s[5]='p') and (s[6]='e') and (s[7]='n') then Result := tkSysOpen;
    if (s[1]='s') and (s[2]='y') and (s[3]='s') and (s[4]='r') and (s[5]='e') and (s[6]='a') and (s[7]='d') then Result := tkSysRead;
    if (s[1]='S') and (s[2]='y') and (s[3]='s') and (s[4]='R') and (s[5]='e') and (s[6]='a') and (s[7]='d') then Result := tkSysRead;
    if (s[1]='i') and (s[2]='n') and (s[3]='t') and (s[4]='e') and (s[5]='g') and (s[6]='e') and (s[7]='r') then Result := tkInteger_T;
    if (s[1]='I') and (s[2]='n') and (s[3]='t') and (s[4]='e') and (s[5]='g') and (s[6]='e') and (s[7]='r') then Result := tkInteger_T;
    if (s[1]='b') and (s[2]='o') and (s[3]='o') and (s[4]='l') and (s[5]='e') and (s[6]='a') and (s[7]='n') then Result := tkBoolean_T;
    if (s[1]='B') and (s[2]='o') and (s[3]='o') and (s[4]='l') and (s[5]='e') and (s[6]='a') and (s[7]='n') then Result := tkBoolean_T;
    if (s[1]='f') and (s[2]='i') and (s[3]='n') and (s[4]='a') and (s[5]='l') and (s[6]='l') and (s[7]='y') then Result := tkFinally;
    if (s[1]='F') and (s[2]='i') and (s[3]='n') and (s[4]='a') and (s[5]='l') and (s[6]='l') and (s[7]='y') then Result := tkFinally;
  end
  else if Length(s) = 8 then
  begin
    if (s[1]='o') and (s[2]='v') and (s[3]='e') and (s[4]='r') and (s[5]='l') and (s[6]='o') and (s[7]='a') and (s[8]='d') then Result := tkOverload;
    if (s[1]='O') and (s[2]='v') and (s[3]='e') and (s[4]='r') and (s[5]='l') and (s[6]='o') and (s[7]='a') and (s[8]='d') then Result := tkOverload;
    if (s[1]='f') and (s[2]='u') and (s[3]='n') and (s[4]='c') and (s[5]='t') and (s[6]='i') and (s[7]='o') and (s[8]='n') then Result := tkFunction;
    if (s[1]='s') and (s[2]='y') and (s[3]='s') and (s[4]='w') and (s[5]='r') and (s[6]='i') and (s[7]='t') and (s[8]='e') then Result := tkSyswrite;
    if (s[1]='S') and (s[2]='y') and (s[3]='s') and (s[4]='W') and (s[5]='r') and (s[6]='i') and (s[7]='t') and (s[8]='e') then Result := tkSyswrite;
    if (s[1]='s') and (s[2]='y') and (s[3]='s') and (s[4]='c') and (s[5]='l') and (s[6]='o') and (s[7]='s') and (s[8]='e') then Result := tkSysClose;
    if (s[1]='S') and (s[2]='y') and (s[3]='s') and (s[4]='C') and (s[5]='l') and (s[6]='o') and (s[7]='s') and (s[8]='e') then Result := tkSysClose;
    if (s[1]='a') and (s[2]='r') and (s[3]='g') and (s[4]='c') and (s[5]='o') and (s[6]='u') and (s[7]='n') and (s[8]='t') then Result := tkArgCount;
    if (s[1]='p') and (s[2]='a') and (s[3]='r') and (s[4]='a') and (s[5]='m') and (s[6]='s') and (s[7]='t') and (s[8]='r') then Result := tkArgStr;
    if (s[1]='A') and (s[2]='r') and (s[3]='g') and (s[4]='C') and (s[5]='o') and (s[6]='u') and (s[7]='n') and (s[8]='t') then Result := tkArgCount;
    if (s[1]='P') and (s[2]='a') and (s[3]='r') and (s[4]='a') and (s[5]='m') and (s[6]='S') and (s[7]='t') and (s[8]='r') then Result := tkArgStr;
    if (s[1]='l') and (s[2]='o') and (s[3]='n') and (s[4]='g') and (s[5]='w') and (s[6]='o') and (s[7]='r') and (s[8]='d') then Result := tkLongWord_T;
    if (s[1]='L') and (s[2]='o') and (s[3]='n') and (s[4]='g') and (s[5]='W') and (s[6]='o') and (s[7]='r') and (s[8]='d') then Result := tkLongWord_T;
    if (s[1]='e') and (s[2]='x') and (s[3]='t') and (s[4]='e') and (s[5]='n') and (s[6]='d') and (s[7]='e') and (s[8]='d') then Result := tkExtended_T;
    if (s[1]='E') and (s[2]='x') and (s[3]='t') and (s[4]='e') and (s[5]='n') and (s[6]='d') and (s[7]='e') and (s[8]='d') then Result := tkExtended_T;
    if (s[1]='p') and (s[2]='r') and (s[3]='o') and (s[4]='p') and (s[5]='e') and (s[6]='r') and (s[7]='t') and (s[8]='y') then Result := tkProperty;
    if (s[1]='P') and (s[2]='r') and (s[3]='o') and (s[4]='p') and (s[5]='e') and (s[6]='r') and (s[7]='t') and (s[8]='y') then Result := tkProperty;
    if (s[1]='P') and (s[2]='R') and (s[3]='O') and (s[4]='P') and (s[5]='E') and (s[6]='R') and (s[7]='T') and (s[8]='Y') then Result := tkProperty;
  end
  else if Length(s) = 9 then
  begin
    if (s[1]='p') and (s[2]='r') and (s[3]='o') and (s[4]='c') and (s[5]='e') and (s[6]='d') and (s[7]='u') and (s[8]='r') and (s[9]='e') then Result := tkProcedure;
    if (s[1]='s') and (s[2]='y') and (s[3]='s') and (s[4]='f') and (s[5]='c') and (s[6]='h') and (s[7]='m') and (s[8]='o') and (s[9]='d') then Result := tkSysFchmod;
    if (s[1]='S') and (s[2]='y') and (s[3]='s') and (s[4]='F') and (s[5]='c') and (s[6]='h') and (s[7]='m') and (s[8]='o') and (s[9]='d') then Result := tkSysFchmod;
  end
  else if Length(s) = 10 then
  begin
    if (s[1]='p') and (s[2]='a') and (s[3]='r') and (s[4]='a') and (s[5]='m') and (s[6]='c') and (s[7]='o') and (s[8]='u') and (s[9]='n') and (s[10]='t') then Result := tkArgCount;
    if (s[1]='P') and (s[2]='a') and (s[3]='r') and (s[4]='a') and (s[5]='m') and (s[6]='C') and (s[7]='o') and (s[8]='u') and (s[9]='n') and (s[10]='t') then Result := tkArgCount;
  end;
  { `forward` is a DIRECTIVE, not a reserved word — FPC lets it be an ordinary
    identifier (e.g. `procedure Forward(...)`). The case-insensitive table above
    would otherwise reserve every casing of it. Keep only the exact lowercase
    spelling as the directive; any other casing (only possible when lowercasing
    changed the token, i.e. s0 had an uppercase letter) stays an identifier. }
  if (Result = tkForward) and (s0 <> s) then Result := tkIdent;
end;
{$ifdef FPC}
procedure AppendChar(var dst: AnsiString; c: Char);
begin
  dst := dst + c;
end;

procedure AppendString(var dst: AnsiString; const src: AnsiString);
begin
  dst := dst + src;
end;

procedure AppendRange(var dst: AnsiString; const src: AnsiString; first, last: Integer);
var oldLen, count, i: Integer;
begin
  if last < first then Exit;
  count := last - first + 1;
  oldLen := Length(dst);
  SetLength(dst, oldLen + count);
  for i := 0 to count - 1 do
    dst[oldLen + i + 1] := src[first + i];
end;
{$else}
procedure AppendChar(var dst: AnsiString; c: Char);
var len: Integer;
begin
  len := Length(dst);
  SetLength(dst, len + 1);
  dst[len + 1] := c;
end;

procedure AppendString(var dst: AnsiString; const src: AnsiString);
var oldLen, i: Integer;
begin
  oldLen := Length(dst);
  SetLength(dst, oldLen + Length(src));
  for i := 1 to Length(src) do
    dst[oldLen + i] := src[i];
end;

procedure AppendRange(var dst: AnsiString; const src: AnsiString; first, last: Integer);
var oldLen, count, i: Integer;
begin
  if last < first then Exit;
  count := last - first + 1;
  oldLen := Length(dst);
  SetLength(dst, oldLen + count);
  for i := 0 to count - 1 do
    dst[oldLen + i + 1] := src[first + i];
end;
{$endif}

{ Token text from the TokChars pool (off, len). Defined here in lexer.inc —
  before its lexer.inc diagnostic use and the pasparser_* uses — so FPC's
  declaration-before-use is satisfied (the pxx self-host prescan is order-
  agnostic, so it built either way). Moved up from the old pasparser_*.inc. }
function GetTokenStrFromRaw(off, len: Integer): AnsiString;
var s: AnsiString; i: Integer;
begin
  { TokChars[off..off+len-1] is contiguous — materialise in one SetLength + fill.
    The old char-at-a-time AppendChar reallocated per char (O(n^2) for the token),
    and this builds every identifier/keyword/string token. Same result string. }
  SetLength(s, len);
  for i := 0 to len - 1 do
    s[i + 1] := TokChars[off + i];
  Result := s;
end;

procedure WriteTokenContext;
{ The source words around the current token, with `>>>` marking exactly where we
  tripped. Expect() has printed this for years and it is the difference between a
  findable error and an unfindable one — a bare line number does NOT track across
  {$i} includes, so "line 19" can be a comment in one file and a directive in
  another. Every Error gets it now, not just the token-mismatch path.

  Token text lives in the TokChars pool; the raw token's SOffset indexes it. }
var ctx: AnsiString; ei: Integer;
begin
  if (TokPos < 1) or (TokPos > TokCount) then Exit;
  ctx := '';
  for ei := TokPos - 6 to TokPos + 2 do
    if (ei >= 1) and (ei <= TokCount) then
    begin
      if ei = TokPos then ctx := ctx + '>>> ';
      { TokSrcOff/TokSrcLen -- the token's SOURCE SPELLING, not SOffset/SLen.
        The latter holds text only for identifiers and strings, so this window
        used to print a line's identifiers and silently drop its syntax:
        `x := (1 ;` rendered as `begin x    >>>  end`, losing ':=', '(', '1'
        and ';' -- precisely the characters a syntax error is about. Falls back
        to SOffset/SLen for the frontends whose lexers do not fill the new
        channel yet (TokSrcLen is 0 there), so their output is unchanged rather
        than blank. }
      if TokSrcLen[ei-1] > 0 then
        ctx := ctx + GetTokenStrFromRaw(TokSrcOff[ei-1], TokSrcLen[ei-1]) + ' '
      else
        ctx := ctx + GetTokenStrFromRaw(Tokens[ei-1].SOffset, Tokens[ei-1].SLen) + ' ';
    end;
  writeln('  near: ', ctx);
end;


function StrToDoubleBits(const s: AnsiString): Int64;
{ A float literal's bits, correctly rounded — the nearest double to the decimal
  text, every time.

  What it replaced was a rational N/D scaler that stayed inside Int64 by halving
  with round-to-odd — which composes safely for ONE final rounding of an
  exactly-known value, but not for a chain that introduces error at every step,
  and the chain is the whole algorithm here. At 1e-292 scale that
  chain is ~300 steps against ~7 guard bits, and 23 of 490 sampled literals came
  out 1 ULP off — silently, since the error survives every comparison against a
  nearby value and shows up only in a round trip
  (bug-a-float-literal-lexer-is-not-correctly-rounded).

  ExDecStrToDouble accepts leading/trailing spaces, a sign, a point and an
  exponent — a superset of what the lexers hand it, since they have already
  matched the number's shape. `def` is unreachable for that reason. }
var d: Double;
begin
  d := ExDecStrToDouble(s, 0.0);
  Result := ExDecDoubleToBits(d);
end;

{ ===== The Pascal directive, conditional and lexing machinery lived HERE =====
  Moved to paslexer.inc 2026-09-04, which is included immediately after this
  file, so it still occupies this offset. DecDigitsExceed below did NOT go with
  it: pylexer.inc, ir.inc and pasparser_expr.inc call it and nothing about it is
  Pascal. It is why "everything between these two routines" was the wrong cut. }

{ Is the decimal digit string `d` numerically greater than `limit` (also a
  decimal digit string)? Compared as TEXT so the check itself can never
  overflow the type it is guarding. }
function DecDigitsExceed(const d, limit: AnsiString): Boolean;
var a: AnsiString;
    i: Integer;
begin
  a := d;
  while (Length(a) > 1) and (a[1] = '0') do a := Copy(a, 2, Length(a) - 1);
  if Length(a) <> Length(limit) then
  begin
    DecDigitsExceed := Length(a) > Length(limit);
    Exit;
  end;
  for i := 1 to Length(a) do
    if a[i] <> limit[i] then
    begin
      DecDigitsExceed := a[i] > limit[i];
      Exit;
    end;
  DecDigitsExceed := False;
end;

function LexAppend(const srcText: AnsiString): Integer;
var
  savedSrcPos, savedSrcLine: Integer;
  len, i, unitStart, tokStart: Integer;
  savedMarkDbg, savedLexing: Boolean;
  sval: AnsiString;
begin
  SavedLexSource := Source;
  savedSrcPos := SrcPos;
  savedSrcLine := SrcLine;
  { A `uses`d unit stays OUT of the DWARF line table — see PasLexLineMarker.
    Saved and restored rather than set to a constant: this runs re-entrantly
    (a unit's own `uses` loads another unit mid-lex). }
  savedMarkDbg := LexMarkDbgLines;
  savedLexing := Lexing;
  LexMarkDbgLines := False;
  Lexing := True;

  Source := srcText;
  SrcPos := 1;
  SrcLine := 1;

  if (MainProgramTokCount = TOK_UNBOUNDED) and (TokCount > 0) and (Tokens[TokCount-1].Kind = tkEOF) then
  begin
    Dec(TokCount);
    unitStart := TokCount;
  end
  else
    unitStart := TokCount;

  repeat
    LexOne(tokStart);
    EnsureTokCapacity(TokCount + 1);
    Tokens[TokCount].Kind    := CurTok.Kind;
    Tokens[TokCount].IVal    := CurTok.IVal;
    Tokens[TokCount].Line    := CurTok.Line;
    TokPackRecords[TokCount] := PackRecordsVal;
    TokScopedEnums[TokCount] := ScopedEnumsVal;
    TokQChecks[TokCount] := QChecksVal;
    TokAssertions[TokCount] := AssertionsVal;
    TokRChecks[TokCount] := RChecksVal;
    TokNChecks[TokCount] := Byte(NChecksVal);
    TokIChecks[TokCount] := IChecksVal;
    sval := CurTok.SVal;
    len  := Length(sval);
    if TokCharLen + len > STRING_CAP then Error('token char pool overflow');
    Tokens[TokCount].SOffset := TokCharLen;
    Tokens[TokCount].SLen    := len;
    i := 1;
    while i <= len do
    begin
      TokChars[TokCharLen] := sval[i];
      Inc(TokCharLen);
      Inc(i);
    end;
    { and the SOURCE SPELLING, in its own channel — see TokSrcOff/TokSrcLen in
      defs.inc for why it cannot share SOffset/SLen. }
    RecordTokSpan(TokCount, tokStart, SrcPos);
    Inc(TokCount); EnsureTokCapacity(TokCount+1);
  until CurTok.Kind = tkEOF;

  Source := SavedLexSource;
  SrcPos := savedSrcPos;
  SrcLine := savedSrcLine;
  LexMarkDbgLines := savedMarkDbg;
  Lexing := savedLexing;
  Result := unitStart;
end;

{ Keep the body pass's recorded token indices in sync with a token-stream edit at
  `atPos` of `delta` tokens (positive = insert, negative = removal). Only the still-
  pending DeclItem spans and the body-begin marker matter; entries before the edit
  are unaffected. No-op unless the body pass is active, so the nested-routine-free
  self-build is byte-identical. }
procedure AdjustPass2Spans(atPos, delta: Integer);
var k: Integer;
begin
  if not Pass2Active then Exit;
  for k := 0 to DeclItemCount - 1 do
  begin
    if DeclItemStart[k] >= atPos then DeclItemStart[k] := DeclItemStart[k] + delta;
    if DeclItemEnd[k]   >= atPos then DeclItemEnd[k]   := DeclItemEnd[k]   + delta;
  end;
  if Pass2BodyTok >= atPos then Pass2BodyTok := Pass2BodyTok + delta;
end;

procedure InsertTokens(insertPos: Integer; const srcTokens: array of TRawToken; count: Integer);
var i: Integer;
begin
  EnsureTokCapacity(TokCount + count + 1);
  { Shift right }
  for i := TokCount - 1 downto insertPos do
    Tokens[i + count] := Tokens[i];
  { Copy }
  ShiftTokParallel(insertPos, count);
  for i := 0 to count - 1 do
    Tokens[insertPos + i] := srcTokens[i];
  Inc(TokCount, count);
  AdjustPass2Spans(insertPos, count);
  AdjustSrcRanges(insertPos, count);
end;

{ Remove `count` tokens starting at atPos (mirror of InsertTokens). Used by
  the mode-Delphi generics desugar to excise `<...>` groups it rewrote. }
procedure RemoveTokens(atPos, count: Integer);
var i: Integer;
begin
  ShiftTokParallel(atPos, -count);
  for i := atPos to TokCount - count - 1 do
    Tokens[i] := Tokens[i + count];
  Dec(TokCount, count);
  AdjustPass2Spans(atPos, -count);
  AdjustSrcRanges(atPos, -count);
end;

procedure Next;
var i, off, len, j: Integer;
begin
  if TokPos >= TokCount then begin CurTok.Kind := tkEOF; Exit; end;
  CurTok.Kind := Tokens[TokPos].Kind;
  CurTok.IVal := Tokens[TokPos].IVal;
  CurTok.Line := Tokens[TokPos].Line;
  off := Tokens[TokPos].SOffset;
  len := Tokens[TokPos].SLen;
  { TokChars[off..off+len-1] is contiguous — one SetLength + fill instead of
    per-char AppendChar realloc. Runs for every token the parser consumes. }
  SetLength(CurTok.SVal, len);
  i := 0;
  while i < len do
  begin
    j := off + i;
    CurTok.SVal[i + 1] := TokChars[j];
    Inc(i);
  end;
  Inc(TokPos);
end;

function Eat(k: TTokenKind): Boolean;
begin Result := CurTok.Kind = k; if Result then Next; end;

procedure Expect(k: TTokenKind; const name: AnsiString);
{ ONE diagnostic, on the path every other diagnostic already uses. This used to
  writeln a raw dump -- `Expected: <close-brace>, but got:  (Kind: 57,
  Line: 2)` -- and THEN
  call Error, so a failed Expect printed two lines: an unprefixed one carrying
  the information and a prefixed one carrying none. Anything keying on `error:`
  (a build script, a test recipe, a harness classifying a run) saw only the half
  that does not say what was expected. Error already prints the `pascal26:<line>:
  error:` prefix, the `in:` path for an include or a used unit, and the `near:`
  window -- the raw line was a second output path that skipped the first one.

  The offending token is named only when the lexer actually HAS its text. It
  stores text for tkIdent and tkString and nothing else, so a keyword, an
  operator or a number has none -- which is why the old line's `but got: ` came
  out empty in precisely the cases where a reader could not identify the token
  themselves. An omitted clause says "not recorded"; an empty one reads as
  "nothing there". Recovering the missing spellings (and with them every `near:`
  window in the compiler) is
  bug-a-the-token-pool-stores-text-only-for-identifiers-and-strings.

  Do NOT answer that by mapping the kind to a spelling: kinds are shared across
  frontends and their words are not. `Expect(tkEnd, <close-brace>)` in cparser.inc
  against `Expect(tkEnd, 'end')` in pasparser_stmt.inc is one kind, two spellings,
  so a table would confidently print the other language's keyword. That is what
  the `name` parameter is for -- only the caller knows the language.

  The ordinal moves behind PXXDBG=a.expect. It is meaningful only against
  TTokenKind's declaration order and it shifts whenever a token is added, so it
  is a debugging aid and never a user-facing one.
  bug-a-a-failed-expect-prints-a-raw-dump-with-no-error-prefix-and-no-source-path }
var spell: AnsiString;
begin
  if CurTok.Kind <> k then
  begin
    if PxxDbgWants('a.expect', '*') then
      writeln('PXXDBG a.expect want=', Ord(k), ' got=', Ord(CurTok.Kind),
              ' line=', CurTok.Line);
    { The token's SOURCE SPELLING where the lexer records one (TokSrcOff/
      TokSrcLen), else its SVal. That order matters: SVal is a NAME or a decoded
      VALUE, and it is empty for exactly the tokens a reader cannot identify --
      keywords and punctuation. The spelling is what was typed, so `;` and `end`
      can finally be named instead of omitted. }
    spell := CurTok.SVal;
    if (TokPos >= 1) and (TokPos <= TokCount) and (TokSrcLen[TokPos - 1] > 0) then
      spell := GetTokenStrFromRaw(TokSrcOff[TokPos - 1], TokSrcLen[TokPos - 1]);
    if spell <> '' then
      Error('expected ''' + name + ''' before ''' + spell + '''')
    else
      Error('expected ''' + name + '''');
  end;
  Next;
end;

{ THE PASCAL SEARCH PATHS -- `-Fu` unit roots and `-Fi` include roots.

  Here rather than in cpreproc.inc, where they used to live: they are generic,
  compiler.pas calls them straight from ordinary option handling, and a build
  with the C frontend omitted must still resolve its own units. Their old home
  made `-Fu` depend on the C preprocessor, which is the kind of dependency that
  is invisible until something tries to remove a component
  (refactor-a-search-path-helpers-live-in-the-c-preprocessor). }
procedure AddPasUnitDir(const dir: AnsiString);
var s: AnsiString; j: Integer;
begin
  s := '';
  for j := 1 to Length(dir) do AppendChar(s, dir[j]);
  if (Length(s) > 0) and (s[Length(s)] <> '/') then AppendChar(s, '/');
  for j := 0 to PasUnitDirCount - 1 do
    if PasUnitDirs[j] = s then Exit;
  if PasUnitDirCount >= MAX_PAS_UNIT_DIRS then Error('too many -Fu/-I unit directories');
  PasUnitDirs[PasUnitDirCount] := s;
  Inc(PasUnitDirCount);
end;

procedure AddPasIncDir(const dir: AnsiString);
{ -Fi<dir>: a {$I file} include search root (FPC parity;
  bug-pascal-include-search-silent-miss). }
var s: AnsiString; j: Integer;
begin
  s := '';
  for j := 1 to Length(dir) do AppendChar(s, dir[j]);
  if (Length(s) > 0) and (s[Length(s)] <> '/') then AppendChar(s, '/');
  for j := 0 to PasIncDirCount - 1 do
    if PasIncDirs[j] = s then Exit;
  if PasIncDirCount >= MAX_PAS_UNIT_DIRS then Error('too many -Fi include directories');
  PasIncDirs[PasIncDirCount] := s;
  Inc(PasIncDirCount);
end;
