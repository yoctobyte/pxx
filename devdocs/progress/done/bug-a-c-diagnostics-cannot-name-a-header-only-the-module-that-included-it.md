---
slug: bug-a-c-diagnostics-cannot-name-a-header-only-the-module-that-included-it
track: A
prio: 40
type: bug
blocked-by: []
summary: "FIXED 2026-09-11. THE DIAGNOSIS IN THIS SUMMARY WAS WRONG IN THE HALF THAT SIZES THE JOB, and it is left below so the correction is legible: it said the header-accurate table is DbgRange* and that C lacks Pascal's ungated twin. PasMarkTokFile is NOT a Pascal twin -- it is the SHARED ungated per-token table, with callers in paslexer.inc, pylexer.inc and clexer.inc, and the C one (clexer.inc:975) was already calling it. No table needed building. THE REAL CAUSE WAS UPSTREAM OF THE PRINTER ENTIRELY: CPSyncLine suppressed a line marker when `CPCurFileId = CPMarkFile`, and CPCurFileId is DbgFileId(path), which returns 1 for EVERY path when DebugInfo is off -- so without -g every include boundary tested 1 = 1 and NO RETURN MARKER WAS EVER EMITTED. The marker stream had enter edges only. Keyed the test on the PATH and planted the path from CLexLineMarker; an error in an included header now prints `in: <header>`, and the main .c stays unnamed after the include because its range now closes."
status: done
---

# C diagnostics can name a module but not a header

Split out of `feature-c-diagnostics-name-the-module-they-are-in`, whose C half
landed under the bounded `WriteDiagSourceFile` grant. That change made a C error
inside a pulled crtl module print `in: ./compiler/../lib/crtl/src/string.c`. It
cannot do the same for a header, and the reason is a table, not a printer.

## Measured, not assumed

`CLexLineMarker` (`clexer.inc:402`) already receives the header's path — the
preprocessor emits `# <line> "<path>"` markers in **every** build, not only
under `-g` (`CPSyncLine`, `cpreproc.inc:386`, whose own comment says so; the
file's header comment claimed otherwise and has been corrected). The marker
handler then splits the path two ways:

```pascal
if CPathIsCModule(path) then CMarkTokModule(TokCount, path);   { .c only, UNGATED }
if path = DbgSrcName then DbgMarkTokFile(TokCount, 1)
else DbgMarkTokFile(TokCount, DbgFileId(path));                { any file, -g ONLY }
```

- `CModRange*` is ungated but records **`.c` modules only** — a header is
  deliberately attributed to the module that included it, which is right for the
  duplicate-definition check it was built for.
- `DbgRange*` is header-accurate and **gated**: `DbgMarkTokFile` and `DbgFileId`
  both `if not DebugInfo then Exit`.

So the header path is in the lexer's hand, ungated, and is discarded.

Measured with `PXXDBG=c.srcmap` (added in the same change) on an error inside an
included header: `tok=10 paspath="" cmod=-1` — no answer from either table.

## The fix, and why it is Track A

The symmetric one already exists on the Pascal side. `PasMarkTokFile` /
`PasSrcOfTok` (`dbg_filetable.inc:109`) are a per-token *source* table
**deliberately not gated on DebugInfo**, and their own comment gives the reason:
*"it exists so a diagnostic can say which file it is talking about, which a build
without -g needs just as much."* C needs the same twin — `CMarkTokSrc` /
`CSrcOfTok`, ungated, marking every file transition rather than only `.c` ones.

That is new arrays in `defs.inc` and new routines in `dbg_filetable.inc`, both
Track A. The consumer is one `else if` in `WriteDiagSourceFile`, which is inside
Track C's existing grant and is a two-line change once the table exists.

Cheaper alternative worth weighing first: ungate `DbgRange*` itself. It is
already the right shape; the gate is there to keep a non-`-g` build from paying
for it. `MAX_DBG_RANGES` entries of two integers is not obviously a cost worth a
second table, and one table beats two that answer the same question — the
normalise-don't-special-case call. Either way the decision is A's.

## Gate

An error inside an included header names the header. An error in a pulled crtl
module still names the module (`cdiag_module` in `test-core`). The main `.c`
still prints nothing (`cdiag_main`). Pascal's `test_incdiag_*` rows unchanged.
Self-host byte-identical.

## THE LINE NUMBER IS THE HALF THAT MAKES THIS WORSE THAN ITS TWO SIBLINGS

**Measured here 2026-09-11 at `06f130b576f5`** (frankuser, corroborating frankB's
third-arm find rather than relaying it). The two fixed arms and this one do NOT
fail the same way, and the difference decides how a reader experiences it:

| arm | the diagnostic | what a reader sees |
| --- | --- | --- |
| NilPy (fixed `584ca8ea8`) | `pascal26:10:` against a **1-line** driver | **out of range** — self-evidently broken, so the reader distrusts it immediately |
| C (**open**) | `pascal26:2:` for an error at `inc.h:2`, against a **2-line** `m.c` | **IN RANGE.** `m.c:2` is `int main(void){return f();}` — a real, innocent line with no `nope` in it. Nothing marks the location as false |

**An in-range wrong line is strictly worse than an out-of-range one**, because
out-of-range is its own warning and in-range is believable. This is the same
mechanism CLAUDE.md already names for two subjects failing at an identical line
number — **the diagnostic manufactures a plausible location and the reader supplies
the file** — and it is an argument that this arm is worth more than its `prio: 40`,
not less, now that the blocker is known to be a plant rather than a build.

Unchanged from frankB's write-up and not re-measured here: the two unchecked
consequences (planting into `PasSrcRange*` from C makes the C-module branch dead
for those tokens, which changes existing `in:` output; and the
`<crtl-prototype-pull>` synthetic marker is filtered in the C branch but would
print as a filename from the Pascal one).

**frankuser's two carried-over caveats were both checked when this was fixed.**
The C-module branch does go dead for those tokens — recorded as a residual under
Resolved below, NOT verified and NOT deleted. The `<crtl-prototype-pull>` marker
reaches the module table through CInsertTokModuleRange and not through
CLexLineMarker, so it cannot arrive on the Pascal path; the plant carries the
same `'<'` guard as the C arm anyway, kept in step deliberately.

**And the ranking argument above was right for a reason neither of us had:**
the cause was not a plant at all. See Resolved.

## Resolved 2026-09-11 (frankH, Track C/A)

Two changes, and the second is the one that mattered.

**`compiler/cpreproc.inc` — CPSyncLine now keys its suppression on the PATH.**
It read:

```pascal
if (CPCurFileId = CPMarkFile) and
   (CPStmtLine = CPMarkLine + (CPOutLine - CPMarkOutLine)) then Exit;
```

`CPCurFileId := DbgFileId(CPCurPath)`, and `DbgFileId` opens with
`DbgFileId := 1; if not DebugInfo then Exit;` — **1 for every path in a build
without `-g`.** So in an ordinary build the first conjunct was `1 = 1` at every
include boundary, the line arithmetic happened to agree, and the marker was
suppressed. Measured, same source, same binary:

```
with -g:      # 1 "h2.h" "good.c"   int f(void);   # 2 "good.c"   ...
without -g:   # 1 "h2.h" "good.c"   int f(void);                  ...
```

The marker stream carried **enter edges only**. That is why `CPEnclosingCModule`
exists and why the C module table takes a second quoted field — the module
attribution was worked around rather than fixed, and its own comment records
the symptom exactly (*"an include-guarded header that was already pulled
produces an enter marker with no matching return"*). That comment reads as a
statement about include guards; the measured cause is this guard.

**`compiler/clexer.inc` — CLexLineMarker plants the ungated path.** One line
beside the `DbgMarkTokFile` it already did, guarded against a synthetic
`<...>` marker in step with the C arm of `WriteDiagSourceFile`. Planted
unconditionally, the main source included, because the return marker must
CLOSE the header's range or every later token keeps the header's name;
`WriteDiagSourceFile` suppresses `path = DbgSrcName` by itself.

### Why the original diagnosis pointed at the wrong layer

It concluded "C needs an ungated per-token source table — PasMarkTokFile's
twin". `PasMarkTokFile` is not a Pascal routine with a C twin missing; it is
**the shared table**, called from `paslexer.inc`, `pylexer.inc` AND
`clexer.inc:975`. The C call was already there, passing `''`. Nothing needed
building. Credit to frankB for catching that half, and frankuser for verifying
it independently and relaying it.

### Controls

- Both pre-existing rows still pass: `cdiag_module` (an error in a pulled crtl
  module names that module) and `cdiag_main` (the main `.c` is never named).
  `cdiag_module` now answers through the Pascal arm rather than the C arm, with
  the same string.
- **Positive control**: with both compiler changes stashed, the new header row
  fails — no `in:` line is printed at all.
- DWARF under `-g` is byte-for-byte the same decoded line table.
- A crtl-heavy program (`stdio`+`string`+`stdlib`) builds and runs correctly;
  307 markers against `MAX_DBG_RANGES` = 65536, and repeats collapse.
- Self-host fixedpoint: `converged after 1 round(s)`.

### Residual, with an owner named

The C arm of `WriteDiagSourceFile` (`else if path = ''`) is probably now
unreachable for C, since every C token is covered by a marker range. **I did
not verify that and did not delete it** — CLAUDE.md's rule is that deleting
code you *believe* is dead is still wrong. Whoever next touches
`WriteDiagSourceFile` should measure it rather than assume it either way.

### The class

This is the THIRD arm of the same bug. The other two landed nine minutes apart
and neither commit named the other:

| | | |
| --- | --- | --- |
| Pascal | a lowering diagnostic in a used unit names its file | `d3d5098a5` |
| NilPy | an error in an imported `.py` module names the module | `584ca8ea8` |
| C | an error inside an included header names the header | this one |

**The C arm failed worse than either.** A Pascal or NilPy miss produced an
OUT-OF-RANGE line number, which warns the reader on sight. Here the header's
line number is usually in range for the `.c`, so `inc.h:2` reads as `m.c:2` —
a real, innocent line. The reader opens it and finds nothing wrong.

## Log
- 2026-09-11 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 7e6d97826.
