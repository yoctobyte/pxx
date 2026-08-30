---
slug: bug-c-an-unclosed-initializer-list-reports-the-next-error-instead-of-itself
track: C
prio: 30
type: bug
blocked-by: []
summary: "`int a[] = { 1, 2` reports `main function not found`. NOT merely a wording problem: with a real `main` present it is CONSUMED as initializer text and the same message appears, so a function silently leaves the program. Diagnosed to one loop; unstarted."
status: backlog
---

# An unclosed initializer list reports the next error instead of itself

```c
int a[] = { 1, 2
```

```
pxx:  pascal26:1: error: main function not found
gcc:  error: expected '}' at end of input
```

Split from `bug-c-an-unterminated-declaration-still-parses-the-appended-pascal-rtl`.
That ticket gave the C token stream a real `tkEOF` and taught `CBlockContinues`
and `SkipBraceBlock` to refuse there, which fixed the struct and enum cases. The
initializer walkers (`CInitWalkArray`, `CInitWalkRecord`, `CInitSkipScalar`,
`CDeferScalarPtrInitSkip`, `CSkipCInitElement`) already test `tkEOF` and stop
correctly — **they just do not complain**, so the parse completes and the user
is told about the missing `main`, which is a real but secondary fact.

Milder than its siblings for that reason: nothing is consumed that should not
be, no Pascal is quoted, and the program does fail. It is a message pointing at
the second consequence instead of the cause.

## What to fix

Those walkers carry a `braced` flag. Reaching `tkEOF` while `braced` is the same
refusal `CBlockContinues` makes; `CRefuseUnterminated` already exists and words
it. Check each walker for whether the flag is in scope at the loop rather than
assuming it is.

## Gate

The example names the unclosed initializer on line 1. `cunterm*` and `cnomain`
stay green. 12 C corpus programs still compile. Self-host byte-identical.


---

## Diagnosis, 2026-08-30 (frankC) — measured, not applied. Ticket released unstarted.

Stopped on the owner's fleet-wide pause before a merge + re-pin, with the tree
reverted to HEAD. **No compiler change is committed.** What follows is worth more
than the fix would have been, because the ticket's stated cause is wrong in a way
that would have sent the next person to five routines that never run.

### The ticket under-reports the defect, in the face-238 direction

It says *"nothing is consumed that should not be"*. That is true of the bare
shape and false of the shape that matters:

```c
int a[] = { 1, 2
int main(void){return 0;}
```

```
gcc:  error: expected '}' before 'int'
pxx:  pascal26:2: error: main function not found
```

**`main` is present on line 2 and the compiler says it does not exist**, because
the initializer swallowed it. Same silent-consumption class as
[[bug-c-a-function-definition-after-an-unclosed-struct-is-eaten-as-a-member]] —
and I priced this one from the quiet shape too, having just written face 238
about doing exactly that.

### The named cause is wrong — measured, not reasoned

The ticket names `CInitWalkArray`, `CInitWalkRecord`, `CInitSkipScalar`,
`CDeferScalarPtrInitSkip`, `CSkipCInitElement`. I probed all five at entry.
**None of them is called for this input.** I had already built and discarded two
plausible fixes against them before probing; both changed nothing, because they
were edits to code that does not execute on this path. Two wrong root causes, both
arrived at by reading rather than measuring — the playbook's own rule, paid for again.

A probe on the file-scope loop showed pass 1 seeing exactly **one** item (`int`,
line 1) and one `ParseCGlobalVarDecl` call consuming the entire file.

### The actual site — `compiler/cparser.inc:8592-8601`

The balanced-brace skip for a global `= { ... }` initializer:

```pascal
depth := 0;
repeat
  if CurTok.Kind = tkBegin then Inc(depth)
  else if CurTok.Kind = tkEnd then Dec(depth);
  Next;
until (depth = 0) or (CurTok.Kind = tkEOF);
```

On the input above: the brace opens (depth 1), the loop walks `1 , 2 int main (
void )`, main's own opening brace lifts depth to 2, its closing brace drops it to
1, and the loop then exits **on `tkEOF` with `depth` still 1**.

**The exit condition conflates "the list closed" with "the tokens ran out", and
nothing afterwards asks which happened.** `depth <> 0` at exit IS the
unterminated signal — computed, correct, and discarded.

### The same shape a second time, which is what makes it a class

`CBraceTopLevelInitCountAt` (`cparser.inc:6908`) ends with
`if depth <> 0 then Result := -1`. It has detected this exact condition since it
was written. **All five of its callers read `-1` as "no count available"** — the
same value they get when there was simply nothing to count. One value, two
meanings, and the meaning that mattered is the one no caller can act on. That is
the playbook's *"'ruled out' and 'could not look' must never print the same"*,
inside a compiler rather than a harness.

### What the fix is, and why I did not land it

One line after the loop above — `if depth <> 0 then CRefuseUnterminated;` — plus
the same at `CBraceTopLevelInitCountAt`'s tail. `CRefuseUnterminated` already
exists and already words it.

**Not landed because it is not one arm.** The identical
`until (depth = 0) or (CurTok.Kind = tkEOF)` shape appears at `cparser.inc:4896`,
`8263` and `11419`, and `SkipBraceBlock` at 8589 is a fourth. Fixing one and
closing the ticket is precisely what
`devdocs/dev/normalise-dont-special-case.md` says produces the arm that stays
broken. The right change normalises all of them onto one refusal, and that is not
a change to land in the hour before a binary is blessed.

### One shape is a different bug and needs its own ticket

```c
char *p[] = { "a", "b"
int main(void){return 0;}
```
```
pxx:  Expected: }, but got:  (Kind: 57, Line: 2)
```

A raw internal dump — token *ordinal*, no source path, no `error:` prefix,
reaching the user through a different path from every other diagnostic here.
Worth its own ticket rather than folding into this one.

### Verified NOT broken (already correct, keep as fencing rows when this is fixed)

nested array `{ {1,2}, {3,4`, struct init, `.x =` designated init, and a
function-local `int a[] = {1,2` — all four already report
`unterminated C construct: end of file before its closing backtick-brace`,
from the `tkEOF` work earlier tonight.
