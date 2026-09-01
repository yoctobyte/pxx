---
slug: bug-a-managed-locals-leak-at-ORDINARY-scope-exit-on-wasm32-and-a-variant-local-traps
track: A
prio: 25
type: bug
status: working
found: 2026-09-01
found-by: frankA
blocked-by: []
summary: "FIXED for the leaks (74e33af46); the Variant row moved to its own ticket because it was never a leak. wasm32's scope-exit release carried a HAND-WRITTEN list of managed kinds -- scalar AnsiString and dynamic array -- while the zero-init pass three lines below it asked ManagedLocalZeroBytes, the shared table. Measured against x86-64 with -dPXX_ALLOC_CENSUS, allocation counts identical on both sides so only the frees differed: COM interface local gone=0 of 50 -> 50, record with managed fields live=543 -> 3, static array of AnsiString live=871 -> 4, all now matching x86-64. The arms are copied from the riscv32 arm of EmitManagedLocalCleanupForTarget in its order and with its predicates, because the set of managed kinds is a SHARED fact and a seventh backend restating it is how six agree and one does not. Guarded by test/wasm/check_scopeexit.sh, which makes the leak PRINT -- the object counts its own destructions -- because a leak is invisible to the native-vs-wasm diff that is every other wasm check's primary assertion; verified to fail against the previous backend at gone=0, exit 1. THE VARIANT ROW IS NOT FIXED AND IS NOT THIS TICKET: `v := 42` traps because IR_VAR_STORE, IR_VAR_BINOP and IR_VAR_BOX have NO wasm32 arms at all, diagnosed from the compiler's own broken-body report (`main$0 - statement IR op 43`) and confirmed on a program-body Variant where scope-exit release cannot be involved -> bug-a-wasm32-has-no-variant-ir-arms-so-any-variant-assignment-traps. The PXXVarClear arm added here is written and UNVERIFIED for that reason; do not read its presence as coverage."
owner: frankC
---

# Managed locals leak at ORDINARY scope exit on wasm32, and a Variant local traps

## Why this is not the unwind ticket

`bug-a-managed-locals-leak-on-an-unwind-on-wasm32-and-xtensa` is priced at p25
on a reachability argument that is correct for what it describes: *"It needs an
exception to unwind through a frame that owns a managed local."*

**This needs no exception.** It fires on every ordinary return from every
procedure holding one of the affected kinds. The two defects share a target and
nothing else, and this one is strictly larger.

## Measured

x86-64 as the oracle, wasmtime 48.0.1 as the host, `-dPXX_ALLOC_CENSUS`.
**The allocation counts are identical on both sides of every row** — only the
frees differ, so nothing here is a difference in how much work the two backends
do.

| managed local, released at ordinary scope exit | x86-64 | wasm32 | |
| --- | --- | --- | --- |
| scalar `AnsiString` | ok | ok | |
| dynamic array | ok | ok | |
| COM interface | `freed=1` | **`freed=0`** | leaks every one |
| record with managed fields | `live=2` of allocs=4274 | **`live=269`** | leaks |
| static array of `AnsiString` | `live=3` of allocs=8671 | **`live=543`** | leaks |
| `Variant` | ok | **trap, exit 134** | crashes |
| promotable int | ok | ok | |

The Variant row is not a leak and should not be filed as one:

```
wasm trap: wasm `unreachable` instruction executed
  0: 0x1e3f8 - <unknown>!<wasm function 241>
```

Reproduce any row with a procedure whose only body is an assignment to a local
of that kind, called 300 times from the program body. Build both sides with
`-dPXX_ALLOC_CENSUS`; build the wasm side with
`--target=wasm32 -Fulib/rtl/platform/wasi` and run it under `wasmtime run`.

**Use a RUNTIME-built string, not a literal.** A literal now costs x86-64 zero
allocations and wasm32 1871 (see the note at the bottom), so a literal-based
probe compares two different workloads and the leak is buried in the difference.
That confounded the first version of this measurement.

## The cause, and it is named in the source

`WasmEmitManagedLocals` (`ir_codegen_wasm32.inc:5448`) has two halves with two
predicates, and its own comment says so deliberately:

> *THE TWO HALVES ANSWER DIFFERENT QUESTIONS AND NOW HAVE DIFFERENT PREDICATES,
> which is the point rather than an inconsistency ... conflating "what must
> start nil" with "what this backend knows how to release" is precisely what hid
> the gap below.*

The ZERO half asks the shared table `ManagedLocalZeroBytes`. The RELEASE half
keeps a hand-written list:

```pascal
if (Syms[i].Kind = skLocal) and not Syms[i].IsRef
   and (((Syms[i].TypeKind = tyAnsiString) and not Syms[i].IsArray)
        or (Syms[i].IsArray and (Syms[i].ArrLen = -1))) then
```

Two kinds. The comment above it even enumerates what the zero half admits that
this does not — *"a local RECORD with managed fields, a static array of string,
a Variant, a COM interface local and a promotable int"* — which is this ticket's
table, written down before anyone ran it. The gap was disclosed and never
measured; the measurement is the only new thing here.

## Sizing it honestly: this is NOT a predicate widening

`grep` for the helpers this backend can call: **`PXXStrDecRef` and
`PXXDynArrayRelease`, and nothing else.** There is no `PXXIntfRelease`, no
`PXXVarClear`, no record-finalize call wired into wasm32 at all. So widening the
predicate would emit calls to helpers that are not there.

The real job is the same one frankS ran for xtensa — `e1d7977a2` took that
backend's arm from one managed kind to six and `3a1c1dc73` added the seventh —
plus, for the static-array row, an element loop, and, for Variant, a separate
diagnosis because that one is a trap rather than a missing release.

**Do not widen the predicate first.** It is the last line of the change, for the
same reason the unwind ticket says its own predicate arm is last.

## Why it is filed rather than fixed

Wasm backend work, which the owner demoted on 2026-08-30 (*"they simply must not
outrank ordinary Track A work"*), with
`decide-the-wasm-umbrella-at-70-reinstates-everything-the-owner-demoted-to-25`
open on exactly that question. Two agents have already declined the adjacent
ticket on that reasoning and it applies here unchanged.

What has changed is the *input to the ranking*: the adjacent ticket's p25 rests
on an unwind being rare, and the argument was sound. These are ordinary-path
defects and one of them is a crash, so whoever ranks this should do it on the
table above rather than by inheriting p25 from the neighbouring slug. Priority
was set to 55 on that basis as a proposal, not a finding.

**Corrected to 25 the same day.** The decision I filed this under as "open" had
already been ruled: `e9d1b7850`, *"linux only for now — demote the wasm and BSD
umbrellas"*, which caps wasm work at 25 regardless of a defect's severity. The
ruling is about the PLATFORM, not about how bad an individual bug is: wasm32 is
not a current target, so a crash on it blocks nothing, and 25 is the honest
number **for now**. `b2d3eb61a` records the shape this ticket should sit in —
**demoted is not forgotten**: correct, open, parked, and read the moment wasm
comes back. The table above is unaffected; a measurement does not change when
the ranking does.

## An accuracy note on a resolved ticket

`perf-a-every-string-literal-assignment-heap-copies-on-i386-arm32-riscv32-and-xtensa`
named four backends. **wasm32 is a fifth** and was never in that sweep:
`s := 'yy'` 2000 times costs it `allocs=1871`, the same figure the other four
gave, against x86-64's zero. `EmitStaticLitHandle` still has exactly two
implementations. That ticket's title is wrong by omission rather than by claim —
its sweep covered six targets and wasm32 was not one of them, which nothing in
it said. Recorded here rather than by reopening it; the remaining arm is small
(`WasmDataAddr(Strs[si].Offset + 8)`, which this backend already emits
elsewhere) and belongs to whoever takes the wasm work above.


## 2026-09-01 — fixed, and the Variant row was a different animal

`74e33af46`. Four of the five rows in the table above were one defect: the
release half of `WasmEmitManagedLocals` asked its own two-line question while
the zero half asked the shared table. Six arms now, riscv32's order and
riscv32's predicates.

The fifth row was never a leak. `v := 42` traps in a **bare program body with no
procedure in it**, so scope-exit release cannot be involved, and the compiler
had already said why in its broken-body report: `main$0 — statement IR op 43`,
`IR_VAR_STORE`. The whole Variant family is absent from this backend. Filed as
`bug-a-wasm32-has-no-variant-ir-arms-so-any-variant-assignment-traps`.

**The thing worth keeping.** The trap was diagnosed by reading a report the
compiler prints at COMPILE time, having first been diagnosed by running the
program and reading a wasm backtrace. The backtrace named a function index; the
report named the IR op. The report cost nothing and was already on screen — I
had tailed two lines past it.

And the PXXVarClear arm I added is a live example of face 242's cousin: written,
committed, green, and **never executed on this target**, because nothing can
construct its input. It is flagged in both tickets rather than counted.
