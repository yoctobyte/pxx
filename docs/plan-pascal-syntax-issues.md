# Plan: Open Pascal Syntax / Front-End Issues

Status (2026-05-31): **§A comments DONE** (commit 6525e95), **§B1 GetMem DONE**
(commit a42000f). Remaining: §B0 regressions, and the §B1 sibling builtins
(`FreeMem`/`New`/`Dispose`/`Val`/`Str`).
Companion to `docs/limitations.md` (user-facing boundaries), `docs/pascal-dialect.md`
(the comment switches are documented there), and `docs/todo.md`.
Findings below were reproduced against `compiler/pascal26` on 2026-05-31 (IR
backend default; legacy cross-checked where noted). Each item has a minimal
repro, the mechanism (`file:line`), a fix sketch, and rough effort.

These should land **before** the C-header-import arc
([`plan-c-header-import.md`](plan-c-header-import.md)) — header import will lean
on the same lexer (comments) and exercise pointer/`GetMem` paths heavily.

---

## Design decisions (rationale)

Decisions taken while implementing §A/§B1, recorded so they are not
re-litigated:

- **Both comment-relaxation switches default OFF.** Turbo Pascal and original
  Delphi do **not** nest comments (a long-standing PITA); FPC nests only under
  `{$NESTEDCOMMENTS}`. Default-off preserves the historic flat behaviour — a
  stray inner `}` inside a `{ … }` block, or a `/` adjacent to `*`, parses
  exactly as before — so no existing source changes meaning. Nesting / C-style
  comments are strictly opt-in, per unit.
- **`/* */` gets its own switch (`{$CSTYLECOMMENTS}`), not folded into
  `{$NESTEDCOMMENTS}`.** `/* */` is not standard Pascal at all and has no FPC
  precedent to mirror, whereas `{$NESTEDCOMMENTS}` is a real FPC switch with
  defined semantics. Keeping them separate avoids overloading an established
  switch name with a non-standard extension. `/* */` does not nest (matches C).
- **A3 (the `(* *)` `Exit` bug) is unconditional, not switch-gated** — it is an
  unambiguous correctness fix (same-line code after `*)` was silently
  mis-lexed), not a dialect choice.
- **Section A (comments) was done before §B1 (GetMem)** even though B1 is the
  higher-impact bug: A is smaller, lower-risk, fully contained in the lexer, and
  A3 was actively (silently) biting. B1 touches the parser's statement
  dispatcher and warranted its own commit.
- **Switches are plain boolean lexer state** (`CStyleComments` /
  `NestedComments` in `defs.inc`), wired through `ProcessPasDirective` exactly
  like `strict_overload on/off` — no new directive machinery.

### Dev note — comments in compiler source

The `make`/self-host step compiles the **new** source with the **previous**
seed `compiler/pascal26` (nesting off). So a `{ … }` doc-comment in compiler
source that contains `{$…}`, a `/* */`, or an unbalanced/inner `}` will break
the seed compiler (the inner `}` closes the comment early →
`unexpected character`). Hit this while writing these very fixes. **Keep
compiler-source comments brace-free and directive-free.** This is the same
hazard as putting `{$…}` inside a comment in any compiled unit.

---

## A. Comments — ✅ DONE (2026-05-31)

All four implemented in `SkipSpace` (`lexer.inc`): A3 fixed unconditionally
(paren-star no longer `Exit`s, so same-line trailing code is skipped); A1/A2
nest under `{$NESTEDCOMMENTS ON}`; A4 adds `/* */` under `{$CSTYLECOMMENTS ON}`.
Both switches default off (TP/Delphi-compatible), wired through
`ProcessPasDirective` as boolean lexer state (`CStyleComments`/`NestedComments`,
`defs.inc`). Regression: `test/test_comments.pas` (in `make test`). Self-host
fixedpoint holds. Detail below kept for the record.

**Sequencing note:** B1 is the higher-impact bug, but Section A is the
pragmatic first pass — the fixes are smaller, lower-risk, self-contained in the
lexer, and A3 is silently biting now. Do A first, then B1.

**Dialect / switch note.** Nested `{ }` is **not** classic-standard: Turbo
Pascal and original Delphi did **not** nest comments (a long-standing PITA).
FPC added nesting, gated by a switch — `{$NESTEDCOMMENTS ON/OFF}` (modeswitch
`nestedcomments`), default **off** in tp/delphi/fpc modes. `/* */` is not
standard Pascal at all (harmless to add, no grammar conflict). So both A1/A2 and
A4 should be **switch-gated, default off**, to stay compatible with code that
relies on the flat behaviour (e.g. a stray `}` inside a `{ … }` block, or `/`
adjacent to `*`). Proposed: honour `{$NESTEDCOMMENTS ON}` for `{ }`/`(* *)`
nesting; put `/* */` behind its own switch (e.g. `{$CSTYLECOMMENTS ON}` or fold
into a relaxed-comments mode) since it is a pure extension. A3 (the `Exit` bug)
is **not** switch-gated — it is an unambiguous correctness fix.

The Pascal whitespace skipper exists in two copies — `LegacySkipSpace`
(`compiler/lexer.inc:12`) and the live `SkipSpace` (`compiler/lexer.inc:718`).
Only `SkipSpace` is on the current path (`LexOne` → `SkipSpace`,
`lexer.inc:790`). Findings apply to `SkipSpace`; `LegacySkipSpace` has the same
shape and should be fixed or deleted in lockstep to avoid drift. The C lexer's
`CSkipSpace` (`clexer.inc:39`) already handles `/* */` and `//` — useful
reference.

### A1. Nested `{ }` comments not supported — 🔴 bug

```pascal
{ outer { inner } still outer }
writeln('A');
```
→ `pascal26:N: error: unexpected character ()`. The brace branch
(`lexer.inc:748`) scans to the **first** `}` with no depth counter, so the inner
`}` closes the comment and `still outer }` is lexed as code.

Fix: maintain a nesting depth in the `{` branch — `Inc` on `{`, `Dec` on `}`,
stop at depth 0 — **gated by `{$NESTEDCOMMENTS ON}`, default off** (TP/Delphi did
not nest; FPC nests only under this switch). Effort: small.

### A2. Nested `(* *)` comments not supported — 🟡 bug

The `(*` branch (`lexer.inc:756`) scans to the first `*)` with no depth. Same
class as A1. Lower priority (rarely nested in practice). Fix alongside A1.
Note: FPC also nests `{` and `(*` across kinds (`{ (* } *)` rules); a full fix
tracks a single comment-nesting depth shared by both delimiters. A pragmatic
first cut nests each kind independently.

### A3. `(* *)` immediately followed by code on the same line breaks — 🔴 bug

```pascal
x := 5; (* c *) writeln(x);
```
→ `pascal26:N: error: unexpected character ()`. The `(*` branch **`Exit`s**
`SkipSpace` after consuming `*)` (`lexer.inc:763`) instead of continuing the
skip loop. The space before `writeln` is never skipped, so `LexOne` tries to
tokenise it. `(* *)` only works today when followed by end-of-line/EOF — which
is why it has not bitten yet. The `{ }` and `//` branches `continue` the loop
correctly; only `(*` wrongly `Exit`s.

Fix: replace the `Exit` after `*)` with loop continuation (mirror the `{ }`
branch). Effort: tiny. High value — silent, position-dependent breakage.

### A4. C-style `/* */` comments not supported — ⬜ wanted

```pascal
x := 1 /* mid */ + 2;
```
→ `pascal26:N: error: expected expression`. The `/` branch (`lexer.inc:769`)
only recognises `//`; `/*` falls through to `Exit`, so `/` lexes as a token.

No grammar conflict: Pascal has no `/* … */` construct and `//` already coexists
with `/` (division). Adding `/* */` (non-nesting, like C) is safe but is a pure
extension — **put it behind a switch, default off** (e.g. `{$CSTYLECOMMENTS ON}`
or a relaxed-comments mode), so a `/` directly followed by `*` in existing code
is not silently swallowed. `CSkipSpace` (`clexer.inc:39`) already implements the
scan — port the same logic into the `/` branch. Effort: small.

**Section A fix plan:** rework the `{`, `(`, `/` branches of `SkipSpace`
(and `LegacySkipSpace`, or retire it) into a single loop that: counts `{ }`
depth, counts/handles `(* *)`, continues (never `Exit`s) after a closing
delimiter, and adds `/* */`. One focused edit; add a `test/test_comments.pas`
regression covering nested `{}`, nested `(*)`, `(* *)`-then-code-same-line, and
`/* */` mid-expression.

---

## B. Assignment / type determination

The user's recollection of an "assign-to-a-temp-local" workaround was
investigated directly. **Most of the type-on-direct-assignment cases are now
fixed** (see B0). One genuine workaround-forcing bug remains (B1).

### B0. Verified working now — workaround no longer needed ✅

All reproduced clean on the IR backend (2026-05-31):

- String concat into a target directly: `s := a + b + 'baz';` → `foobarbaz`.
  Additive typing at `parser.inc:2409` marks the `+` node `tyString` when either
  side is string (or char+char). Matches `todo.md` §1 "string concat fixed".
- Function-result inside a concat assignment: `s := Greet('world') + '!';`
  (call result carries `RetType` via `ASTTk[node] := Ord(Procs[pi].RetType)`,
  `parser.inc:2275`).
- `char` → `string` field assignment: `r.s := c;` materialises a 1-char string.
- Function-returning-`string` → record field directly: `r.s := F;`.
- Boolean expression → bool var: `ok := x > 3;`.
- Single-char literal → string: `s := 'x';` (was a documented landmine; fixed
  2026-05-30, `todo.md` §1).
- Pointer **record-field** indexed directly: `r.buf[0] := 65; b := r.buf[0];`
  works once the pointer is allocated correctly (see B1). The old
  "copy ptr field to a local before indexing" landmine appears **stale** — the
  segfault it described traces to B1 (the `GetMem` form), not to field
  indexing. Re-verify before relying on it; if confirmed, drop that note from
  the RTL-landmines memory.

These should be captured as regressions (`test/test_assign_types.pas`) so they
do not silently regress, and `docs/` notes/memories that still prescribe the
temp-var workaround should be corrected.

### B1. `GetMem(p, size)` two-arg procedure form does not write back — ✅ FIXED (2026-05-31)

Fixed: a `tkGetMem` case in `ParseStatementAST` (`parser.inc`) now parses the
two-arg form as `dest := GetMem(size)` — `ParseExpr` for the destination lvalue
(ident/field/index/deref), then an `AN_ASSIGN` wrapping the existing one-arg
`GetMem(size)` call node. The function form `p := GetMem(size)` is unchanged.
Verified for plain `Pointer`, typed pointer (then indexed), and record-field
destinations. Regression: `test/test_getmem_proc.pas` (in `make test`).
Self-host fixedpoint holds.

**Sibling audit (the other procedure-form builtins):** `FreeMem`, `New`,
`Dispose`, `Val`, `Str` are **not implemented at all** — they are not keywords
and hard-error `undefined variable (...)`. So they do *not* share the silent
write-back bug (they fail loudly). Follow-ups, not part of this fix:
`FreeMem(p[, size])` is a trivial accepted **no-op** (the heap is bump-only, no
reclaim) and pairs with `GetMem`; `New(p)`/`Dispose(p)` need the element size
from the pointer's type; `Val`/`Str` are conversion routines. Original
description kept below.



This is the real workaround driver.

```pascal
var p: Pointer;
begin
  GetMem(p, 16);
  if p = nil then writeln('NIL') else writeln('GOT');   { prints NIL }
end.
```
`p` stays `nil` (then any use segfaults). The working form is the FPC function
form:
```pascal
p := GetMem(16);   { GOT }
```
Reproduced on **both** IR and legacy backends, in the main body and inside a
procedure — so it is a front-end wiring gap, not a backend store bug.

Mechanism: `tkGetMem` is parsed (`parser.inc:1759`) as a **single-argument
expression** — `ParseExpr` reads one operand as the *size* and the node returns
the allocated pointer. There is no two-operand form that takes a destination
lvalue and stores the result into it. Standard Pascal `GetMem(var p; size)` (and
`New(p)`) are *procedures* whose first parameter is effectively `out` — that
write-back is missing. The first argument, when present, is consumed as if it
were the size, so `GetMem(p, 16)` silently misbehaves rather than erroring.

This is the same shape as a builtin `var`/`out` parameter not being honoured —
worth checking the sibling allocators/IO builtins for the same gap:

- `New(p)` / `Dispose(p)`, `FreeMem(p)` — verify the lvalue is used/written.
- `Val`, `Str`, `Insert`, `Delete`, and any other procedure-form builtin whose
  first argument is a `var`. (`ReadLn(x)` and `SetLength(a,n)` are known-good —
  use them as the reference for how a write-back builtin should be wired.)

Fix sketch: at the `GetMem` statement parse, detect the two-argument form
`GetMem(<lvalue>, <size>)`: parse arg1 as an lvalue address, arg2 as size, emit
the allocation, and store the result pointer into the lvalue (an `AN_ASSIGN`
wrapping the existing `GetMem(size)` call node, or a dedicated path mirroring how
`SysOpen` at `parser.inc:1770` takes a destination lvalue then a second
argument). Keep the one-arg function form working. Effort: small–medium.
Regression: `test/test_getmem_proc.pas`.

---

## Priority order

1. **A3** (`(* *)` Exit) — tiny, silent breakage, trivially correct fix.
2. **B1** (`GetMem(p,size)`) — real workaround driver; audit sibling `var`-arg
   builtins while there.
3. **A1** (nested `{ }`) — standard Pascal; small.
4. **A4** (`/* */`) — wanted, easy, `CSkipSpace` is the template.
5. **A2** (nested `(* *)`) — fold into the A1 rewrite.
6. **B0** — write the regressions; correct stale workaround notes/memories.

Shared prerequisite for A1/A2/A4: wire the new switches
(`{$NESTEDCOMMENTS ON/OFF}`, the C-style toggle) into the existing `{$...}`
directive handler (`ProcessPasDirective`, reached from `SkipSpace:744`) as
boolean lexer state. A3 needs none of this.

All low-risk and independent of the C-header arc, but A1/A3/A4 harden the shared
lexer that header import will stress, and B1 de-risks the pointer-heavy code
that import will generate. Protect the self-host fixedpoint: re-run `make test`
(gen2 == gen3) after the lexer change in particular, since every source file
flows through `SkipSpace`.
