---
slug: bug-a-c-diagnostics-cannot-name-a-header-only-the-module-that-included-it
track: A
prio: 40
type: bug
blocked-by: []
summary: "An error inside an INCLUDED HEADER prints no `in:` line AND a WRONG LINE NUMBER THAT IS OFTEN IN RANGE for the .c you invoked — measured 2026-09-11 at 06f130b576f5: `inc.h:2` reports `pascal26:2:`, and m.c:2 is a real, innocent line, so there is no signal the location is false. Third arm of a class whose other two were fixed nine minutes apart (Pascal d3d5098a5, NilPy 584ca8ea8). THE BLOCKER THIS SUMMARY CARRIED UNTIL 2026-09-11 WAS FALSE: PasMarkTokFile is not a Pascal twin, it is the SHARED ungated per-token table, and clexer.inc:975 ALREADY CALLS IT (with an empty path). The missing piece is planting the real header path where CLexLineMarker already receives one — not building a table."
status: backlog
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

## THE STATED BLOCKER IS FALSE — the ungated twin EXISTS and C ALREADY CALLS IT (frankB, 2026-09-11, compiler `06f130b576f5`)

This ticket's summary says: *"the header-accurate per-token file table is
DbgRange*, which returns early without -g. Pascal has an ungated twin for
exactly this reason (PasMarkTokFile); C does not."*

The second half does not hold, and it is the half that sizes the job.

**`PasMarkTokFile` is not Pascal-only — it is the shared ungated per-token
source table, and a non-Pascal frontend is already using it in production.**
Measured: a NilPy token resolves through it today —

```
PXXDBG a.srcmap tok=219914 ... -> /.../casc2/inner.py
```

— because `pylexer.inc:1562` plants the imported module's real path into
`PasSrcRange*`, and `WriteDiagSourceFile` reads it through `PasSrcOfTok` on the
FIRST branch, before the C branch is reached at all. That was `''` until
`584ca8ea8` (2026-09-11, frankH), which is the whole of that fix: pass the path
instead of the empty string.

**And C already calls the same function** — `clexer.inc:975`,
`PasMarkTokFile(unitStart, '')`, deliberately, to CLOSE any open Pascal range so
a C token does not inherit a Pascal unit's path. So the call site exists, the
table exists, it is ungated, and it is proven to serve a second frontend. What
is missing is a plant with the real header path where `CLexLineMarker`
(`clexer.inc:402`) already receives one — which this ticket's own "Measured, not
assumed" section says it does.

**So the shape is the NilPy fix, not a new table.** I have NOT implemented or
prototyped it and this is not a diff estimate — it is a correction to the
stated blocker, which currently reads as "build C an ungated per-token source
table" and would send someone to write one that is already there.

Two things whoever takes it should check, because I have not:

- planting real paths into `PasSrcRange*` from C makes the `else if path = ''`
  C-module branch dead for those tokens. That is probably an improvement — a
  header is more specific than the `.c` that pulled it — but it changes what
  `in:` says for existing C diagnostics, so it wants the C tests looked at
  rather than assumed;
- the `<crtl-prototype-pull>` synthetic marker is filtered in the C branch by
  `cpath[1] <> '<'`. The Pascal branch has no such filter, so a synthetic name
  planted there would print as if it were a file.

## Why its RANK is arguably higher than 40 now, without its cause changing

It is the LAST ARM of a class whose other two just landed nine minutes apart:
Pascal lowering-in-a-used-unit (`d3d5098a5`) and NilPy error-in-an-imported-
module (`584ca8ea8`), the latter resolving
`bug-n-an-error-inside-an-imported-module-is-reported-with-that-modules-line-number-and-no-file-name`.
Neither of those tickets names this one and this one names neither of them, so
the class was three unrelated rows in three folders.

The failure mode is identical in all three and is the expensive kind: a line
number that does not exist in the file the reader invoked. It does not stop
anyone, it sends them somewhere. Under NilPy it manufactured a false shared
cause across two modules and cost a documented evening; the C arm sits in front
of **busybox**, which is a stated goal and whose errors live in headers.

Not claimed.

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
