---
prio: 55
track: P
summary: "ONE CAUSE, NINE SPELLINGS, and it is not the one either existing ticket describes. `Read`, `Write`, `ReadLn`, `WriteLn`, `SysOpen`, `SysRead`, `SysWrite`, `SysClose`, `SysFchmod`, `ArgCount`/`ParamCount`, `ArgStr`/`ParamStr` are HARD keywords: the lexer maps each spelling to a dedicated token, so `procedure Write;` fails at the DECLARATION with `expected name` and the name is unusable anywhere. Every other intrinsic (Str, Val, New, Length, SetLength, Reset, Rewrite, Halt, Inc, Ord, Chr, Round, Copy, Insert, Delete, Move, GetMem...) declares fine -- measured across 37 spellings, exactly these fail -- which is what proves the mechanism is the dedicated token and not intrinsic-ness. fpc ACCEPTS all of them as user names. THE FIX SHAPE IS ALREADY IN-TREE AND DOCUMENTED: ord/chr/low/high/length were converted to SOFT keywords under bug-hard-keyword-intrinsics-block-identifier-use -- they lex as tkIdent, the parser dispatches on the NAME, and the tk enum members survive only as -Ord(tkXxx) call ids. The shadow infrastructure exists too: SoftIntrinsicOpen/SoftIntrinsicOpenSym (symtab.inc) with the `System.X` escape hatch. DO NOT START THIS WITHOUT READING THE BLAST RADIUS SECTION -- five files, a token-ORDER dependency, and a second frontend, which is why it is filed rather than done."
owner: frankD
---

# Nine intrinsic spellings are hard keywords, so none can be a user name

- **Type:** bug — Track P (Pascal frontend); the lexer half is shared with A
- **Status:** working
- **Found:** 2026-09-05 (frankB), from frankS's reading during the P staleness pass

## What was measured

frankS noticed that `sysopen` and a user routine named `Read` both fail at the
**declaration** with the identical `expected name`, not at the call site either
of their tickets is written about, and offered it as a reading rather than a
cluster. Testing the breadth turns it into one:

```pascal
program t; procedure Write; begin end; begin Write; end.
```
`error: expected name`

**37 intrinsic spellings tried. Exactly these nine fail:**

| refused | accepted (a sample of the 28) |
| --- | --- |
| `Read` `Write` `ReadLn` `WriteLn` | `Str` `Val` `New` `Dispose` `Length` `SetLength` |
| `SysOpen` `SysRead` `SysWrite` `SysClose` `SysFchmod` | `Assign` `Close` `Reset` `Rewrite` `Halt` `Exit` |
| `ArgCount` / `ParamCount`, `ArgStr` / `ParamStr` | `Inc` `Dec` `Ord` `Chr` `Round` `Trunc` `Copy` `Pos` |
| | `Insert` `Delete` `Concat` `Move` `FillChar` `GetMem` |

**That split is the evidence.** If the cause were "it is an intrinsic", `Str`
and `Length` would fail too. It is exactly the spellings the lexer maps to a
dedicated token kind (`paslexer.inc`), and nothing else.

**fpc 3.2.2 accepts all nine as user names** — `Read`, `Write`, `WriteLn`
verified directly. `ParamStr` and `ParamCount` matter most here: they are
ordinary FPC library names, not pxx inventions, and real code declares methods
with those names (`pasparser_name.inc:33` already carries a partial patch for
exactly that — *"ParamCount/ParamStr as member names (FPC custapp)"*, which is
someone hitting one face of this and fixing that face).

## Why it is one ticket and not two

It absorbs both of these, which describe the same mechanism from the call side:
- [[bug-p-sysopen-intrinsic-shadows-a-user-function-name]]
- [[bug-p-an-unqualified-call-to-a-user-routine-named-read-or-write-is-eaten-by-the-intrinsic]]

Both are written about the CALL being eaten. The call never happens: the
declaration is refused first, so the name cannot exist to be shadowed. The
call-site framing is downstream, and a fix aimed at it would be aimed at the
wrong half.

**And do not fix only the declaration.** Accepting the name at `pasparser_proc.inc:664`
without also routing the call would leave a routine that is declared and then
silently never called, which is strictly worse than today's clean refusal.

## The fix shape, which already exists in this tree

`ord`/`chr`/`low`/`high`/`length` were converted from hard to **soft** keywords
under `bug-hard-keyword-intrinsics-block-identifier-use`. The pattern is written
down at `paslexer.inc:99-103`:

> they lex as plain tkIdent and ParseFactor dispatches on the name, so they are
> legal identifiers like in FPC. Their tk enum members survive only as
> `-Ord(tkXxx)` intrinsic CALL ids.

The shadowing rules are already built: `SoftIntrinsicOpen` and
`SoftIntrinsicOpenSym` (`symtab.inc:9695`), including the `System.X` escape
hatch and the enclosing-class-method case. Nothing new has to be designed.

`ParseFactor` also already does the **inverse** rewrite —
`IntrinsicNamesSelfMethodHere` retags `CurTok.Kind := tkIdent` (and the token
stream, deliberately) when a self method shadows an intrinsic name. Retagging
tkIdent back to the intrinsic token when nothing shadows is the symmetric move
and would let every existing `case` arm run unchanged.

## BLAST RADIUS — read this before starting; it is why this is filed, not fixed

Removing nine lexer mappings makes every site keying on those TOKEN KINDS dead.
There are five files, and two of them are the reason to coordinate first:

- `compiler/paslexer.inc` — 19 mapping lines (both case spellings each).
- `compiler/pasparser_expr.inc` — arms at 1946, 1966, 1989, 2012, 2033.
- `compiler/pasparser_stmt.inc` — arms at 5566, 5588, 5598, 5612.
- `compiler/pasparser_lval.inc` — 4086, 4149 (`tkArgStr`).
- `compiler/pasparser_name.inc` — 33, 57, 105-106; already partially special-cased.
- `compiler/pyparser.inc` — 44020, 44040, 44063, 44086, 44107. **The NilPy
  frontend carries its own copies of these arms**, so this is not a
  Pascal-frontend-only change and the self-host fixedpoint proves nothing about
  that half (`compiler.pas` is Pascal).
- **`compiler/pasparser_prog.inc:1045` is the one that bites:**
  `if (Tokens[i].Kind >= tkSysOpen) and (Tokens[i].Kind <= tkSysFchmod)` — a
  RANGE test over the token enum. It depends on the five `tkSys*` members
  staying adjacent and in order in `defs.inc:1893`. CLAUDE.md requires
  coordinating token/node numbering by message; this makes that mandatory
  rather than advisory, and the range test will silently mean something else if
  anyone reorders.

**Two live topic collisions as of 2026-09-05 evening**, which is the other
reason this is parked rather than started:
- `Read`/`Write`/`ReadLn`/`WriteLn` are `feature-writeln-as-library` phase 2's
  territory (frankH). Those four also have *syntax* the others do not — the
  `:width:prec` format specifiers and the file-first-arg variadic form — so they
  are the expensive four and they belong with whoever owns that parsing.
- `pasparser_lval.inc` is frankA's, actively.

## Suggested split, if it is taken in pieces

The **five `tkSys*` plus `ArgCount`/`ArgStr` are separable** and are the cheap
half: pxx-only or plain-call-syntax intrinsics with no format specifiers, no
variadic form, and no overlap with frankH. Doing those alone would close
`sysopen-intrinsic-shadows-a-user-function-name` outright and fix
`ParamStr`/`ParamCount` shadowing, leaving the four write/read spellings to ride
with writeln-as-library. The `pasparser_prog.inc` range test still has to be
handled either way.

## DONE 2026-09-05 (frankD) — the seven separable spellings, and three corrections to this ticket

`SysOpen`, `SysRead`, `SysWrite`, `SysClose`, `SysFchmod`, `ArgCount`/`ParamCount`
and `ArgStr`/`ParamStr` are soft keywords. All seven declare as routine,
parameter, local, field and method names; the intrinsics are unchanged when
unshadowed; a user routine or in-scope symbol shadows them and `System.X`
reaches the intrinsic anyway. `test/test_soft_keyword_sysargs.pas`, 20 rows,
wired at `Makefile:7994`; it refuses on pin v404 at the first declaration, which
is its positive control. Gate GREEN with the FPC seed canary running.

**Read/Write/ReadLn/WriteLn are NOT done** and stay with `feature-writeln-as-library`
phase 2 (frankH) exactly as the split above proposed. They are the negative
control in the probe: still `expected name`, deliberately.

### Correction 1 — the blast radius did not include the codegens, and does not include NilPy

The five files list reads as if the token kinds were consumed widely. They are
not: **every codegen site keys on `-Ord(tkXxx)` as an intrinsic CALL id, never on
a token kind**, so `ir_codegen*.inc`, `ir.inc` and `wasmenc.inc` needed zero
edits across all seven targets. Only the parser and the lexer key on kind.

**And `pyparser.inc`'s five arms are DEAD CODE, not a second copy to keep in
sync.** NilPy's lexer cannot produce those kinds. Proven two ways: statically —
`pylexer.inc` has exactly one variable-kind emit site, `k := PyKeyword(s)`, and
`PyKeyword`'s table yields only tkIdent/tkIf/tkIn/tkOr/tkFunction/tkAnd/tkNot/
tkTry/tkElse/tkTrue/tkNil/tkWhile/tkFalse/tkBreak/tkClass/tkRaise/tkExit/
tkExcept/tkUses/tkFinally, every other `PyEmitToken` call passing a literal `tk`
from a set containing none of ours; and dynamically — a NilPy program declaring
`paramstr` and `paramcount` compiles and binds the user's names. **Left in
place**: deleting another frontend's code from a P ticket is the wrong lane.
Track N should remove `pyparser.inc:44020, 44040, 44063, 44086, 44107`.

### Correction 2 — `pasparser_prog.inc` was the real hazard, and it fails SILENTLY

The ticket flagged the range test for its ORDER dependency. The order was never
the problem: **the test stops matching anything at all** the moment the kinds
stop being emitted, and nothing says so. Measured by reverting just that hunk
against the finished lexer: a wasm32 program calling `SysOpen` compiled `ok:` and
produced **0 WASI file symbols in 71,461 bytes** — byte-for-byte the size of a
program that never touches a file — so the module would have trapped at run time
on a host function that was never imported. With the name scan it is 8 symbols
and 81,752 bytes. Nothing in the quick tier compiles for wasm32; the fixedpoint
cannot see it. Now a name scan on the `LoadFile` model directly below it.

### Correction 3 — the hard-keyword-ness was already inconsistent

The lexer matched only two casings per spelling (`sysopen` and `SysOpen`), so
`SYSOPEN` and `Sysopen` already lexed as identifiers and already declared fine.
The refusal was case-dependent, which no ticket mentioned.

### Not fixed, noted: `SysOpen`/`SysRead` have no STATEMENT form

`SysRead(fd, buf, 4);` as a statement is refused — before this change too (pin
v404: `a statement cannot start with 'SysRead'`; now: `undefined variable
(SysRead)`, which is the truthful answer for an unbound soft name). `SysWrite`,
`SysClose` and `SysFchmod` have statement arms and `SysOpen`/`SysRead` do not.
Pre-existing asymmetry, out of scope here, and a separate three-line fix.

### Also found, filed elsewhere

`bug-b-copy-cannot-compile-at-all-on-the-frozen-string-path` — any use of `Copy`
refuses under `-uPXX_MANAGED_STRING`. Nothing to do with this change; the pin
fails identically.
