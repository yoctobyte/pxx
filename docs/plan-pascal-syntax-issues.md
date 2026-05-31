# Plan: Open Pascal Syntax / Front-End Issues

Status (2026-05-31): **Delivered.** Comments, assignment regressions, allocator
builtins, and integer `Val`/`Str` are covered by `make test`. The detailed
sections below retain the original reproductions and implementation record.
Companion to `docs/limitations.md` (user-facing boundaries), `docs/pascal-dialect.md`
(the comment switches are documented there), and `docs/todo.md`.
Findings below were reproduced against `compiler/pascal26` on 2026-05-31. Each item has a minimal
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

The compiler source now opts into nested comments at its top. Keep comments
simple anyway: bootstrap work may involve older seeds, and nested directive
text is easy to misread during lexer changes.

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

The live implementation is `SkipSpace`. The dead `LegacySkipSpace` copy found
during this work was removed on 2026-05-31. The C lexer's `CSkipSpace` already
handled `/* */` and `//` and served as a useful reference.

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

**Section A delivered:** the `{`, `(`, `/` branches of `SkipSpace` count
nesting where enabled, continue after a closing delimiter, and support
optional `/* */`. `test/test_comments.pas` covers the regressions.

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
`Dispose`, `Val`, `Str` were **not implemented at all** — not keywords,
hard-erroring `undefined variable (...)` (so they never shared the silent
write-back bug; they failed loudly).

The **allocator family is now complete** on the IR backend (2026-05-31), all
built on the per-block size header `GetMem` gained:

- ✅ **`FreeMem(p[, size])`** — reclaims rather than no-op. `GetMem` gained an
  8-byte size header per block + a single free list; `FreeMem` pushes, `GetMem`
  first-fits before bumping. Two-arg form accepted (size ignored), `FreeMem(nil)`
  safe. Legacy keeps it a no-op. Test `test/test_freemem.pas`.
- ✅ **`New(p)`** — `p := GetMem(SizeOf(p^))`, size from the pointer's element
  type. **`Dispose(p)`** — `FreeMem(p)`. Test `test/test_new_dispose.pas`.
- ✅ **`ReallocMem(p, size)`** — bump-allocates the new block, copies
  `min(oldsize, newsize)` (old size from the header), frees the old block,
  writes the new pointer back to `p`; `ReallocMem(nil, n)` == `GetMem`. IR
  backend (special call -103). Test `test/test_reallocmem.pas`.

The proper hybrid allocator (mmap large blocks straight from the kernel, munmap
on free, size-binning/coalescing) is its own arc — `docs/todo.md` §4 "Heap
allocator".

- ✅ **`Val`/`Str`** (integer) — done as pure-Pascal `lib/rtl/builtin.pas`
  (`StrInt`, `Val`), not asm. The unit is **auto-included only when the program
  calls `Str(`/`Val(`** (token pre-scan in ParseProgram, like the exception
  runtime). `Str(x[:w[:d]], s)` is parsed like `write`'s `value:w:d` and
  rewritten to `s := StrInt(x, w)` (decimals parsed, ignored for integers);
  `Val(s, n, code)` is a plain var-param library call (no parser glue — `:` only
  matters in declarations, never inside a call's arg list). Test
  `test/test_str_val.pas`. Gaps: float `Str`/`Val`, and `:w:d` are literals not
  expressions (matches `write`).

  **Design note — why not a general directive yet.** The `value:w:d` form is a
  localized micro-grammar (only `write`/`writeln`/`Str`). A declarable
  `flexcolumn` calling-convention directive would let formatted routines be
  ordinary library functions, but it would serve a population of one right now
  (`Val` has no `:`; `write`/`writeln` are variadic and already special). Build
  it later, in the **parser** (it resolves the callee's directive — the lexer
  can't), when `write`/`writeln` move to library code. Tracked in `docs/todo.md`
  §4.

Original description kept below.



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
Reproduced in the main body and inside a procedure, so it was a front-end
wiring gap, not a backend store bug.

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
