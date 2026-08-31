---
slug: bug-a-c-diagnostics-cannot-name-a-header-only-the-module-that-included-it
track: A
prio: 40
type: bug
blocked-by: []
summary: "A C diagnostic can now print `in: <the .c module>` (CModRange*, ungated), but an error inside an INCLUDED HEADER prints nothing: the header-accurate per-token file table is DbgRange*, which returns early without -g. Pascal has an ungated twin for exactly this reason (PasMarkTokFile); C does not."
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
