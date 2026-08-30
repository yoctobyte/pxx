---
track: C
prio: 30
type: bug
status: backlog
blocked-by: []
owner: ""
summary: "`#include \"nosuch.pas\"` from C reports the line AFTER the include (pointing at innocent code), leaks the internal `__pxx_pascal_unit` marker into the `near:` context, and speaks Pascal (`uses:`) at an author who wrote `#include`. Measured at aa78a7faf63a. The raise site is pasparser_proc.inc -- a Track P file -- so the edit is not Track C's, per the string-literal-decay precedent."
---

# A missing Pascal unit, imported from C, is diagnosed at the wrong line in the wrong language

- **Track C** by motive, **Track P by file** — the message is raised at
  `compiler/pasparser_proc.inc:3522` and `:4121`. Filed under `C` for visibility
  per the precedent already set on
  `refactor-c-string-literal-decay-belongs-at-the-producer`: *keep the frontend's
  letter, note in the body which lane owns the file.*
- **Found:** 2026-08-30 by frankC, re-measuring
  `feature-c-import-a-pascal-unit-under-a-mangled-name` at HEAD after re-claiming it.

## The measurement

Compiler `aa78a7faf63a` (self-host fixedpoint at HEAD, converged 1 round).

```c
#include "nosuch.pas"
int main(void){return 0;}
```
```
pascal26:2: error: uses: unit source not found: /abs/path/to/scratch/nosuch
  near: __pxx_pascal_unit /abs/path/to/scratch/ nosuch.pas  >>>  main
```

**Four defects in two lines of output**, and they are not the one the parent
ticket recorded.

### 1. The line number is wrong, and it points at innocent code

`pascal26:2` — the `#include` is on line **1**. Verified as a consistent offset,
not a coincidence of this file:

| `#include` on line | reported |
| ---: | ---: |
| 1 | 2 |
| 5 | 6 |

Always **include-line + 1**. The mechanism is visible in
`CParsePascalUnitMarker` (`cparser.inc`): it consumes the marker identifier, both
string tokens and the semicolon *before* calling `ParseUsesUnit`, so `CurTok` is
already the first token of the **next** line when the error is raised, and the
raise reports the current token's position.

This is the defect that costs time. The line it names is a real, valid line of
the user's own source — `int main(void){return 0;}` — so the author reads a
correct line looking for a fault in it. A diagnostic that points at innocent code
is worse than one that points nowhere.

### 2. It leaks `__pxx_pascal_unit`, which the user never wrote

The `near:` context prints the token-stream marker the preprocessor substitutes
for `#include "<x>.pas"` (`cpreproc.inc:2526`). It is an internal representation:
the author cannot find that token in their source, cannot grep for it, and has no
way to know it stands for the line they *did* write.

Note this is a direct cost of the marker design — and that design is otherwise
right (`cparser.inc:421` records why the state rides in the token stream rather
than a preprocessor global: import ORDER is then preserved for free). The leak is
not an argument against it, only an unpaid bill.

### 3. It speaks Pascal at a C author

`uses:` — the author wrote `#include`. This is the only one of the four the parent
ticket recorded.

### 4. It renames the unit the author asked for

`nosuch` — an absolute path with the `.pas` stripped, where the author wrote
`"nosuch.pas"`. The stripping is deliberate (the loader re-derives the extension)
and correct *as input to the loader*; it is only wrong as **output to a human**.

## Why this is not fixable under Track C, checked rather than assumed

The parent ticket left this alone with a stated reason, and that reason is still
correct but is **not the whole of it**:

> a pre-check in `cparser.inc` would have to duplicate the loader's
> case-insensitive + `.pp` + `-Fu` search to avoid refusing files that do exist.

That rules out C **refusing** on its own check. It does not, on its face, rule out
C checking only to produce a better *message* — so I looked for that escape and
there isn't one: the loader's failure is fatal at the raise site, so there is
nothing for C to intercept and reword. Every actual fix needs one of

1. `ParseUsesUnit` to accept a caller-supplied position and vocabulary — a
   **Track P** signature change (`pasparser_proc.inc`); or
2. a shared "diagnostic origin" the raise site reads — new state in `defs.inc`,
   which is **Track A**; or
3. C resolving the unit itself before the call — the duplicated search the parent
   ticket already rejected, and rightly.

**(1) is the right one** and it is small: the marker handler already knows both
things the message is missing — the author's own spelling (`spec`) and the line
the marker sat on, which it can capture before `Next` consumes it.

## Scope note — this is error REPORTING, and prio 30 reflects that

CLAUDE.md is explicit that diagnostic wording is deferred work (*"we seek LANGUAGE
compliance, not error-handling compliance"*), and nothing here changes what
compiles: every one of these four is cosmetic in the sense that no correct program
behaves differently.

It is filed anyway, at a low prio, for the one reason that survives that rule:
**defect 1 is not wording, it is a wrong answer to "where".** The line number is
data, the data is wrong by a fixed offset, and the wrongness sends the reader to
code that is fine. Defects 2-4 are wording and would not have earned a ticket on
their own.

## Gate

Track P's, since the edit is P's file: `make compiler/pascal26` to fixedpoint +
the repro above reporting line 1, naming `nosuch.pas`, without `__pxx_pascal_unit`
in the context. A `test/` case belongs beside the `c_pasunit_*_fail` block in
`test-core`, which already has eight refusal recipes to copy the shape from.

## Related

- Parent: `feature-c-import-a-pascal-unit-under-a-mangled-name` (this was its last
  open non-§6 item; §6 is blocked on a user permission grant).
- Precedent for the track/file split: `refactor-c-string-literal-decay-belongs-at-the-producer`.
