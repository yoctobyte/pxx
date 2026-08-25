---
track: A
prio: 82
type: bug
blocked-by: []
summary: "`make test-fpjson` — the fcl-json 203-case suite, a rung recorded as green 203/203 — no longer compiles: `error: data ptr fixup overflow` from elfwriter.inc, i.e. the program needs more than `MAX_DATAPTRFIX = 4096` data→data pointer relocations. A fixed-size table, a real program that exceeds it, and nothing in any testmgr tier that would have caught it."
status: done
owner: frank1-A-dataptr
---

# The fpjson suite overflows the fixed 4096-entry data-ptr fixup table

- **Type:** bug (core — ELF writer capacity limit)
- **Track:** A (`compiler/defs.inc`, `compiler/elfwriter.inc`)
- **Found:** 2026-08-25, verifying the Pascal corpus ladder's rungs while
  landing [[feature-pascal-corpus-fgl]].

## Measured

Compiler: dev HEAD `20c989a5e`, both the pinned stable
(`stable_linux_amd64/default/pinned`, VERSION 374) and a freshly self-hosted
`compiler/pascal26` at that sha. Corpus: `library_candidates/fcl-json` at the
pinned FPC commit `0d122c49…` — **the corpus has not moved**, so whatever
changed is on our side.

Running the `test-fpjson` recipe by hand (the `make test*` hook blocks the
target):

```
compile exit=1
pascal26:2: error: data ptr fixup overflow
  in: .../stable_linux_amd64/default/builtin/builtinheap.pas
```

(The `in:` file is wrong — that is a separate, already-filed diagnostic bug,
[[bug-p-a-diagnostic-in-a-used-unit-names-the-wrong-source-file]].)

The error is raised at `compiler/elfwriter.inc:106`:

```pascal
if DataPtrFixCount >= MAX_DATAPTRFIX then Error('data ptr fixup overflow');
```

against `compiler/defs.inc:229`:

```pascal
MAX_DATAPTRFIX  = 4096;  { data->data 8-byte pointer relocations (RTTI blobs) }
```

So this is a **fixed-size table**, and a real program has outgrown it. fpjson +
fpcunit is class-dense (203 registered test cases across a deep fixture
hierarchy), which is exactly the shape that mints RTTI blobs.

## Not diagnosed here, deliberately

I did not bisect when it started, did not measure how far over 4096 the count
runs, and did not change the constant — the constant and the writer are Track A
files and the sizing question is a real one (bump it, grow it dynamically, or
stop emitting the relocations that are avoidable). Recording what is measured
and leaving the design call to whoever owns the file, per
`devdocs/dev/root-cause-over-microfix.md`: raising 4096 to some other fixed
number is the microfix, and a real program will find the new number too.

## Why nobody noticed

`make test-fpjson` is in **no testmgr tier** — absent from every list in
`TIERS`. It was landed green (`feature-pascal-corpus-fpjson`, 203/203) and then
nothing ever ran it again. Its sibling `make test-fgl` had the same problem in a
different shape. Both are covered by [[task-t-enrol-the-fgl-corpus-rung]], which
should now be read as urgent rather than tidy-up: **the rung that was not
enrolled is the rung that rotted.**

## Repro

```sh
tools/install_lib_candidates.sh fcl-json
# then the test-fpjson recipe body from the Makefile, or:
make test-fpjson        # needs PXX_ALLOW_FULL_SUITE=1 past the hook
```

## Gate
`make compiler/pascal26` (self-host fixedpoint) + the fpjson suite reaching
`run: 203  failures: 0  errors: 0` + `tools/gate.sh quick`.

## Links
Rung: [[feature-pascal-corpus-fpjson]] (done, now red) · ladder
[[feature-pascal-corpus-expansion]] · enrolment
[[task-t-enrol-the-fgl-corpus-rung]]

## Raised 60 -> 82 (coordinator, 2026-08-25)

A real library we **cannot compile at all**, and it is a regression: fpjson
landed green at 203/203 and nothing ran it again until today, because it sits in
no testmgr tier. The corpus is pinned, so the change is ours. That is the
project's stated priority order almost verbatim -- "we are not seeking utopia,
we are seeking a pragmatic tool", real-world targets over edge cases -- and a
pinned real program going from 203/203 to not-building is as real-world as the
board gets.

Ranked below the 88s (segfaults, and the text-`read` chain) and just under the
NilPy 9s constant at 80, which pays out across the whole matrix rather than one
corpus.

Endorsing the reporter's judgement call explicitly so nobody "fixes" it the
cheap way: **do not just bump MAX_DATAPTRFIX.** A fixed 4096-entry table that a
class-dense real program outgrows will be outgrown again by the next one, and a
larger constant only moves the cliff. See `devdocs/dev/root-cause-over-microfix.md`.

## Resolved 2026-08-25 (frank1-A-dataptr) — the tables grow; the constants are gone

### The boundary, measured before choosing anything

Instrumented build (`MAX_DATAPTRFIX` temporarily 1M, `DataPtrFixCount` /
`MethodFixCount` printed on the `ok:` line), then reverted:

| program | data-ptr fixups | method fixups |
| --- | --- | --- |
| `compiler.pas` (self-host) | 253 | 24 |
| the fpjson suite runner | **4582** | 2994 |

So fpjson wants 4582 against a cap of 4096 — **12% over, not 10x**. That is the
worst possible answer for a bump, because 8192 would have "worked" today and
looked fine for months.

### The growth shape — linear in the RTTI surface, so no constant is safe

Fitted on synthetic programs of N classes x M published properties, compiled
with the instrumented binary:

```
classes=1  props=0   dptrfix=53      classes=1   props=16  dptrfix=89
classes=2  props=0   dptrfix=58      classes=4   props=8   dptrfix=148
classes=4  props=0   dptrfix=68      classes=8   props=8   dptrfix=248
classes=16 props=0   dptrfix=128     classes=16  props=16  dptrfix=704
```

`dptrfix ~= 48 + 5*classes + 2.25*published_members` (the 48 is the RTL floor;
the per-member slope wobbles between 2.25 and 2.5 with string interning). One
entry per emitted RTTI cross-reference, unbounded in program size. Every fixed
ceiling here is a wall some real library eventually walks into — `MAX_METHFIX`
had already been bumped 1024 -> 8192 for Synapse's blcksock, which is the same
cliff moving once already.

### Choice: GROW, not bump, and not "remove the need"

Removing the need was considered and is not available: these entries *are* the
relocations. The absolute address of `Data[]` is not known at emission time, and
for `-c` object output they become real ELF `RELA` records. There is nothing to
delete.

So: the established [[feature-dynamic-compiler-tables]] pattern — `array of T` +
`Count` + `Capacity`, doubling from a base at the append chokepoint. `GlobFix`,
`CallFix`, `CodeRef`, `Tokens`, `Syms`, `AST` and `IR` are already converted
this way; these two were simply left behind.

**The RSS caution in that campaign's ticket does not apply at this scale.** It
says converting more tables now costs resident memory, because `SetLength` is
allocate-copy-free and each doubling strands its predecessor
([[feature-opt-dynarray-grows-in-place]]). True — but that was measured on
multi-MB tables. These two are 8 bytes per entry: the old fixed reservation was
32 KB + 64 KB, and fpjson's worst-case stranded garbage is ~57 KB. The
conversion buys a removed cliff and costs nothing worth measuring, so it does
not wait on the allocator ticket.

### What landed

- `MAX_DATAPTRFIX` and `MAX_METHFIX` **deleted**. Replaced by
  `DATAPTRFIX_BASE` / `METHFIX_BASE` = 1024, which are initial reserves, not
  caps. Both tables are `array of T` grown geometrically.
- `AddDataPtrFix` moved from `elfwriter.inc` to `emit.inc`, next to
  `RecordCodeRefAt` and the `GlobFix` grower — the file that already owns
  relocation recording, and early enough in the include order for every
  frontend to see it.
- **`AddMethodFix` is new, and it is the point of the change.** There were
  **nine** hand-written `guard / store / store / Inc(MethodFixCount)` quartets
  across `rtti_emit`, `pasparser_decl`, `pasparser_prog`, `pasparser_proc` and
  `pyparser`. All nine now call one procedure.
- `QueueMethCodeFixup` (rtti_emit) was a second name for the same append and is
  gone; its four call sites call `AddMethodFix` directly.

Net `-56` lines of duplicated append code for `+42` of chokepoint.

### A latent memory-corruption bug this deletes on the way past

Two of those nine sites — NilPy's VMT emitter, `pyparser.inc:31240` and
`:31261` — had **no cap check at all**. A class-dense NilPy program wrote past
the end of the fixed `MethodFixups` array into whatever BSS followed, silently.
Nothing would have reported it; the corruption is in a neighbouring global.

That is the argument for a chokepoint over a bigger constant, in one example: a
guard that must be written nine times is a guard that is written eight times.
The `MAX_*` grep the campaign mandates found the *capacity* uses; it could not
have found the site that never mentioned the constant.

### Verified

- `make compiler/pascal26` — **converged after 1 round, byte-identical**
  (self-host fixedpoint, default `-O`).
- The fpjson suite **compiles again** and runs: `run: 203  failures: 2
  errors: 0`. Emitted program identical in shape to the big-cap instrumented
  build (`code=769329B data=156568B procs=1683`), confirming the table change
  is behaviour-neutral.
- `tools/gate.sh quick`.
- Compiler BSS is ~96 KB smaller (the two reservations), which is noise.

### The suite is NOT back to 203/203 — 2 failures were hidden behind the overflow

`TTestFactory.ArrayCreateInteger` and `.ObjectCreateInteger` fail: *expected
`<TMyInteger>` but was `<TMyInt64>`*. These are **not** caused by this change —
the emitted program is byte-shape-identical to the instrumented big-cap build,
and a relocation table cannot pick a class. They were simply unreachable while
the suite would not build.

Differentially confirmed against the FPC oracle, on fpjson's own sources:

```
                            pxx                    fpc
CreateJSON(Longint)      -> TJSONIntegerNumber     TJSONIntegerNumber   agree
CreateJSON(1)            -> TJSONIntegerNumber     TJSONIntegerNumber   agree
CreateJSONArray([1])[0]  -> TJSONInt64Number       TJSONIntegerNumber   DIVERGE
```

The direct calls agree; only the `array of const` path diverges, inside
`VariantToJSON`'s `With Element do case VType of vtInteger: CreateJSON(VInteger)`.
Filed as [[bug-p-array-of-const-integer-arm-picks-the-int64-overload]] for the
Pascal frontend; this ticket does not chase it.

So the rung goes from **does not compile** to **201/203**, and the remaining
delta has its own ticket and its own oracle.

### Not done here
No pin. Two are already owed and the coordinator is holding them; this change
does not need one to be useful (nothing outside `compiler/**` moved), so it does
not add a third.

## Log
- 2026-08-25 — resolved, commit PENDING-COMMIT.
