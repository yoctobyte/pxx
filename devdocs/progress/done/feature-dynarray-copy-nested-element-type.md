---
summary: "Copy() on a NESTED dynamic array (`array of array of T`) is refused. It used to segfault: the raw byte copy moved sub-array handles using the DEEPEST element's size. FPC supports it."
type: feature
track: A
prio: 45
status: done
owner: claude-A
---

# `Copy` on a nested dynamic array

- **Type:** feature — Track A (IR lowering). Files: `compiler/ir.inc` (`AN_DYN_COPY`),
  `compiler/parser.inc` (the two guards).
- **Opened:** 2026-08-06, after the crash below was turned into a diagnostic.

## What it did before, and how it was found

```pascal
type TG = array of array of Integer;
var g, h: TG;
...
h := Copy(g, 0, 2);
writeln('h00=', h[0][0], ' h11=', h[1][1]);   { SIGSEGV on h[1][1] }
```

`AN_DYN_COPY` takes its element size from the source symbol's **base** element
type — `TypeSize(tyInteger)` = 4 — but a nested array's elements are sub-array
HANDLES, 8 bytes on x86-64. So the copy strided by 4: `h[0][0]` was right by
luck (offset 0) and `h[1]` read a bogus handle. Reproduced on
`stable_linux_amd64/default/pinned`, so it was never a regression, just a crash
nobody had asked for.

Now refused with a diagnostic, exactly as dynamic-array `Delete` and `Insert`
already refuse the same shape:

```
Copy: nested element type not yet supported for dynamic-array Copy
```

FPC accepts it and prints `lenh=2 h00=1 h11=4`.

## What implementing it needs

Two things, and the second is the one that bites:

1. **The handle stride.** `dcElemSz` must be `TypeSize(tyPointer)` when the
   source's `SymDynDepth > 1` (target-correct: a handle is 4 bytes on i386 /
   arm32 / riscv32), and the fresh temp must be allocated at the source's depth —
   `AllocDynArray('', dcElemTk, dcDepth)` instead of the hardcoded `1` — so its
   scope-exit release recurses through the levels.
2. **The element-aware retain.** The copied sub-array handles need a refcount,
   or the temp's recursive release frees blocks the source still owns. The
   machinery is already there and already used one line away: `AN_DYN_COPY` now
   calls `PXXDynArrayRetainImmediate` for `tyAnsiString` / managed-record
   elements after the byte copy (see the note in that arm). A nested element is
   the same problem with `depth` > 1, which `PXXDynArrayRetainImmediate` already
   takes as a parameter — so this is very likely just widening that call's
   condition and passing the real depth.

Note the semantics `Copy` must land on, verified against FPC and asserted by
`test/test_nested_alias.pas`: `Copy` detaches **one level**. The result gets a
fresh outer block whose elements are the SAME sub-array handles, so writing
`h[0][0]` still reaches `g[0][0]`. A deep copy is per level, which is also why
[[bug-p-copy-rejects-a-dynamic-array-expression-that-is-not-a-bare-name]] matters
— `local[0] := Copy(shared[0])` is how you spell the second level.

## Why only 45

The crash is gone, which was the urgent part, and the diagnostic names the
limitation. Nothing in the tree needs nested `Copy` today. Do it when something
does, or alongside the sibling ticket above since both live in `AN_DYN_COPY`.

## Gate
The repro above matching FPC on every target, `Copy` on a 3-level array,
managed leaf elements at depth (`array of array of AnsiString`), and the whole
thing under `-dPXX_HEAP_DEBUG` — which is what caught the missing retain on the
depth-1 path and is the only way the retain question gets answered honestly.
Plus `test/test_dynarray_copy*.pas` and `test_nested_alias.pas` staying green.

## Triage 2026-08-19 (Track D re-triage pass, pin v363)

**Genuine feature, still wanted, unchanged.** `h := Copy(g, 0, 2)` on
`array of array of Integer` still stops at
`Copy: nested element type not yet supported for dynamic-array Copy`, so
nothing landed incidentally. FPC accepts it, so this is **compat** surface —
but the refusal is loud and replaced a segfault, which is the opposite of the
silent-wrong class that gets promoted to a bug. Stays a feature.

---

## Resolution (2026-08-21)

Implemented exactly as the ticket predicted, and the ticket was right that item
2 is the one that bites. Three changes in `AN_DYN_COPY`, and they only work
together:

1. **The stride.** `dcElemSz := TypeSize(tyPointer)` when the source still has
   levels left, because a nested array's elements are handles. `TypeSize`
   rather than a literal 8 — a handle is 4 bytes on i386 / arm32 / riscv32,
   which is why those three targets are the ones that would catch a hardcoded
   width, and they are in the test matrix for that reason.
2. **The temp's depth.** `AllocDynArray('', dcElemTk, dcDepth)` instead of a
   hardcoded 1, so the temp's scope-exit release recurses through the levels
   instead of treating a buffer of handles as a buffer of base values.
3. **The retain.** `PXXDynArrayRetainImmediate` with the real depth. The RTL
   already had the whole answer: at `depth > 1` it IncRefs every handle in the
   buffer and ignores `baseKind` entirely. One extra arm passes a neutral
   `baseKind` there rather than falling into the record branch, which would
   index the RTTI table with `dcElemRec` — `REC_NONE` for
   `array of array of Integer`, i.e. a garbage data offset.

`NodeDynDepth` already existed and needed nothing.

### The negative control, because otherwise the retain claim is a story

The ticket says the retain question "only gets answered honestly" under
`-dPXX_HEAP_DEBUG`. Confirmed by removing the retain and rebuilding:

```
plain run           after-copy-scope g11=4            <- looks perfect
-dPXX_HEAP_DEBUG    after-copy-scope g11=-572662307   <- $DDDDDDDD
```

`-572662307` is `$DDDDDDDD`, the freed-memory poison. So without the retain the
copy's recursive release frees sub-arrays the SOURCE still owns, the plain run
is indistinguishable from correct, and only the poisoned-heap run says so —
`devdocs/dev/debugging-playbook.md`'s "the expensive bugs produce a plausible
wrong value, not a crash", demonstrated on a live example. That is also the
proof this test is not vacuous: the assertion it makes is one a broken build
actually fails.

### Measured, against FPC

All eight output lines byte-identical to FPC on **all five hosted targets**,
plain and under `-dPXX_HEAP_DEBUG`:

```
lenh=2 h00=1 h11=4
one-level-detach g00=99
inner=4
after-copy-scope g11=4 g22=6
t3 len=2 u111=7 u010=2
str v00=row v11=end
source-survives s11=end
```

Everything the gate asked for is in `test/test_dynarray_copy_nested.pas`: the
depth-2 repro, **depth 3** (depth 2 alone can pass with an off-by-one, since 1
and "the source's depth" differ only from 2 upward, and 2-vs-3 catches a
hardcoded 2), managed leaves under nesting (`array of array of AnsiString`),
and a copy whose scope ENDS while the source lives on — which is what makes the
missing retain observable at all.

`test_nested_alias.pas` and the four existing `test_dynarray_copy*` tests were
each checked plain and under `-dPXX_HEAP_DEBUG`, identical output both ways.

### What is deliberately still refused

- **`SymElemDynDepth > 0`** — a dyn array whose ELEMENT is a *separately named*
  dyn-array type (`type TA = array of Integer; TG = array of TA;`). That is a
  different shape from syntactic nesting and `NodeDynDepth` does not fold the
  two, so lifting its guard would go straight back to striding by the wrong
  size. Its message now names this ticket and says "dynamic-array element
  type", not "nested", so the two refusals are no longer confusable. Folding
  the shapes is its own piece of work.
- **NilPy.** `pyparser.inc` carries its own copy of the guard (the
  duplicate-the-parser-per-language rule), and Track N is deferred, so `.npy`
  code still refuses. The shared lowering underneath it is ready, so lifting it
  there is a guard deletion whenever N is picked up.

Both guards in `pasparser_expr.inc` were edited together and now carry a note
saying so — they are the double case
`devdocs/dev/normalise-dont-special-case.md` warns about, and the ticket records
that they had already drifted apart once (different messages for the same
condition).

### Gate

`make compiler/pascal26` (byte-identical fixedpoint) + the five-target FPC
differential + the heap-debug negative control + `tools/gate.sh quick`.
Cross-target breadth is Track T's, against this sha.

## Log
- 2026-08-21 — resolved, commit PENDING-COMMIT.
