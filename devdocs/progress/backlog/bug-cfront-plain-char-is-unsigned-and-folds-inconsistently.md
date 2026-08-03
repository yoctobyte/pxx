---
track: C
prio: 80
type: bug
status: open
owner: claude-C@opus5
---

# Plain `char` is unsigned at runtime but signed when constant-folded

- **Type:** bug (C frontend, silent wrong value) — **Track C**
- **Found:** 2026-08-02 by the Track B agent, probing integer semantics against
  gcc for [[feature-crtl-implement-libc-assumptions]].

## Two defects, and the second is the nastier one

### 1. Plain `char` is UNSIGNED where the ABI says signed

On x86-64 and i386 the psABI makes plain `char` **signed**, and gcc follows it.
pxx treats it as unsigned:

| expression (`char c = (char)0xFF;`) | gcc | pxx |
| --- | --- | --- |
| `(int)c` | **-1** | 255 |
| `c < 0` | **1** | 0 |
| `c + 0` | **-1** | 255 |
| global / array element / `*p` | **-1** | 255 |
| `(int)(signed char)0xFF` | -1 | -1 (correct) |

Runtime behaviour is at least *self-consistent*: every plain-`char` form reads
as unsigned, and explicit `signed char` works.

### 2. Constant folding disagrees with runtime — same expression, two answers

```c
char rt = (char)-1;
(char)-1 < 0   /* folded  */  gcc 1   pxx 1
rt < 0         /* runtime */  gcc 1   pxx 0
(int)(char)-1  /* folded  */  gcc -1  pxx -1
(int)rt        /* runtime */  gcc -1  pxx 255
```

So the folder treats `char` as signed while codegen treats it as unsigned. That
is worse than either choice consistently applied: an expression's meaning
depends on whether a value happened to be known at compile time, so moving a
constant into a variable — refactoring, or just a debug print — changes the
answer.

## Why it matters

`char` arithmetic going through a sign is ordinary C, not a corner:

- UTF-8 handling is built on `if (*p < 0)` / `(*p & 0xC0) == 0x80` to spot
  continuation bytes;
- `getchar()`-style loops compare a byte against a negative `EOF`;
- hand-rolled comparators and hash loops do arithmetic on `char`;
- `char`-based flags with the high bit set.

None of it errors. It computes a plausible wrong number, which is this repo's
stated worst class.

## Per-target, since the right answer is not the same everywhere

pxx today, `(char)-1 < 0` folded vs `(int)c` at runtime:

| target | ABI requires | pxx folded | pxx runtime |
| --- | --- | --- | --- |
| x86-64 | signed | signed | **unsigned** |
| i386 | signed | signed | **unsigned** |
| aarch64 | **unsigned** | unsigned | unsigned ✓ |
| arm32 | **unsigned** | **signed** | unsigned |

aarch64 is the only target that is both correct and self-consistent, and only by
coincidence — its ABI happens to match what codegen already does. arm32 has the
fold/runtime split with the signedness flag set the wrong way for its ABI too.

## Fix shape

Make plain `char`'s signedness a **per-target property** — signed on
x86-64/i386, unsigned on aarch64/arm32 (and riscv, which is unsigned) — and use
that one property in *both* the constant folder and codegen, so the two cannot
drift. The bug is really that two places each decided independently.

A `-fsigned-char` / `-funsigned-char` override is worth adding at the same time:
real projects pass it, and once the property is single-sourced it costs almost
nothing.

## Gate

Every row of both tables above matches gcc for the target, and the folded and
runtime forms of the same expression agree with each other on every target. Plus
a UTF-8 continuation-byte probe (`*p < 0` over a multi-byte string) giving the
same answer as gcc.

## Resolution 2026-08-03 (claude-C@opus5)

The ticket's diagnosis was exact: two places decided independently. There is now
**one** — `CPlainCharSigned` (`cparser.inc`), which answers from the target psABI
(signed on x86-64/i386, unsigned elsewhere) with a `-fsigned-char` /
`-funsigned-char` override.

The fix single-sources it at the *type* level rather than by teaching two
consumers to agree: plain `char` now RESOLVES to `tyInt8` on a signed-char
target, in the one place `ParseCDeclType` already mapped `signed char` -> tyInt8
and `unsigned char` -> tyUInt8. Every downstream consumer — codegen extension,
comparison signedness, promotion — already handles tyInt8, so fold and runtime
cannot drift again. `CMakeNarrowIntCast`'s `isSgn` now asks the same property
instead of assuming tyChar is signed, which also fixes the arm32 row (folded
signed, ABI unsigned).

### Verified against gcc

Every row of both ticket tables, diffed against a gcc build of the same source:

| `char c = (char)0xFF;` | before | after | gcc |
| --- | --- | --- | --- |
| `(int)c` | 255 | **-1** | -1 |
| `c < 0` | 0 | **1** | 1 |
| `c + 0` | 255 | **-1** | -1 |
| global / `*p` | 255 | **-1** | -1 |
| `(char)-1 < 0` vs `rt < 0` | 1 vs 0 | **1 vs 1** | 1 vs 1 |
| `(int)(char)-1` vs `(int)rt` | -1 vs 255 | **-1 vs -1** | -1 vs -1 |
| UTF-8 continuation bytes via `*p < 0` | 0 | **2** | 2 |

`-funsigned-char` and `-fsigned-char` both match gcc under the same flag.

Regression test `test/cchar_plain_signedness.c` (gated, exit 42), with its
expectations guarded on the target so it states the right answer on every
backend rather than only where it was written — which is why
[[bug-cfront-arch-predefines-always-x86-64]] had to be fixed alongside it, or
the guard would have taken the x86 branch on aarch64.

### Found while verifying, filed separately

`(int)arr[0]` for a file-scope `char arr[2] = { (char)0xFF, 0 }` still answers 0
— because **any cast in a static aggregate initializer folds to 0**, for every
type, `(int)0xFF` included. Reproduced identically on `pinned`, so it predates
this work and is not a regression from it. Filed as
[[bug-cfront-cast-in-static-aggregate-initializer-folds-to-zero]] (urgent,
prio 85).

`tools/gate.sh quick` GREEN.


## REOPENED 2026-08-03 — the resolution above was reverted

The type-level shape claimed "every downstream consumer already handles tyInt8".
That was **false**, and it is the load-bearing sentence in the resolution above.
`tyInt8` is `ShortInt`: an 8-bit INTEGER, not a character type. Resolving plain
`char` to it kept the arithmetic and threw away the identity, taking out five
gated jobs — see [[bug-c-plain-char-lost-its-type-identity-not-just-its-signedness]],
filed by Track T off the `test-core` matrix:

- `writeln` of a C `char` struct field printed `104` / `88` instead of `'h'` / `'X'`
  (`test_c_struct_fields`, `test_c_packed_aligned`) — it dispatches on the type,
  and the type had stopped being a character;
- a string literal's element stayed `tyChar` while `char *` became `^tyInt8`, so
  `_Generic("hi", char *: …)` matched **no association** (`cgeneric_selection_b209`,
  and `00219.c` in the c-testsuite, on x86-64 **and** i386);
- plain `char` became indistinguishable from `signed char`, which C requires
  `_Generic` to tell apart (C11 6.2.5p15: three distinct types).

It also made the *same* program print `'X'` on aarch64 and `88` on x86-64, since
only the signed-char targets were remapped — on its own enough to show the axis
was wrong.

**The one-line remap was reverted; plain `char` is `tyChar` again.** Everything
else from that commit stands and is still correct: `CPlainCharSigned` as the
single source, `-fsigned-char` / `-funsigned-char`, and `CMakeNarrowIntCast`
asking the property instead of assuming `tyChar` is signed — which keeps the
**arm32 fold row fixed** (folded signed, ABI unsigned) rather than regressing it.

### What is still open — exactly the original defect 2, x86-64/i386 only

| target | ABI | pxx folded | pxx runtime |
| --- | --- | --- | --- |
| x86-64 | signed | signed | **unsigned** ← gap |
| i386 | signed | signed | **unsigned** ← gap |
| aarch64 | unsigned | unsigned | unsigned ✓ |
| arm32 | unsigned | unsigned ✓ (kept) | unsigned ✓ |

`test/cchar_plain_signedness.c` is **parked, not deleted or weakened** — it
states gcc's answer and is correct C. It is commented out of the `Makefile` C
battery with a `blocked-by:` pointing here; pxx returns 1, gcc returns 42.
Re-enable it with the fix.

### Fix shape — signedness is a PROPERTY, not a type kind

The property must be applied to the *value* where C applies it: at the **integer
promotions**. A plain-`char` rvalue on a signed-char target has to sign-extend
when it widens to `int` — that is the one thing codegen does not do, and the
only thing left. `CIntegerPromoteTk` today computes the promoted *type* only; it
has no value-level counterpart, and promotion is otherwise implicit in codegen,
so the sites have to be found rather than being one hook. **A missed site is a
silently wrong value, so this needs an oracle sweep against gcc, not a spot fix**
— sweep the operator × operand-type grid, do not just re-run the one test.

The alternative, if the promotion sites prove too diffuse to cover safely, is a
distinct type kind (a character type that is *also* signed) rather than reusing
`tyInt8`. That is a shared-`defs.inc` change and therefore **Track A**, and it
carries the usual new-type-kind fallout across every `case` on `TTypeKind`.
Worth a Track U call before starting down it — the two options differ a lot in
cost and risk.

Do **not** re-attempt the `tyInt8` remap.

## Log
- 2026-08-03 — resolved, commit a31f53dfc (landed as 07414aa8944b).
- 2026-08-03 — REOPENED: that fix regressed five gated jobs and was reverted.
  Identity restored; signedness gap on x86-64/i386 still open.
