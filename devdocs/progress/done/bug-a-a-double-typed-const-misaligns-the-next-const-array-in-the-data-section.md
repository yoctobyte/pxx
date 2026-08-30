---
slug: bug-a-a-double-typed-const-misaligns-the-next-const-array-in-the-data-section
track: A
prio: 55
type: bug
blocked-by: []
status: done
summary: "The typed-const data path does not align at all. A const array lands at whatever offset the preceding emitted bytes leave -- ANY residue, ODD ones included -- while the `var` path is 8-aligned in every cell measured. Originally filed as `a Double typed const misaligns the NEXT const array`; that framing is WRONG and is kept only so the links resolve. The Double is not a trigger, nothing is: with nothing declared before it, `const A: array[0..3] of Int64` is already misaligned, on all six targets."
owner: frankA
---

# A `Double` typed const misaligns the next typed-const array

> ## CORRECTION, and it invalidates this ticket's own table (frankS, 2026-08-30)
>
> **Read this before using anything below.** The title and the per-target table
> are wrong in a way that matters, and both are left in place only because three
> pushed tickets and a Makefile comment link to this slug.
>
> **1. The `Double` is not the trigger. Nothing is.** frankB measured ten
> preceding shapes x five targets: 31 of 50 cells misaligned, residues
> 0/1/2/4/5/6, on every target. With *nothing* declared before it,
> `const A: array[0..3] of Int64 = (1,2,3,4)` is already misaligned. The bisection
> below is real but it was reading noise as signal: what it actually varied was
> how many bytes got emitted first.
>
> **2. The control that settles it holds on all SIX targets**, xtensa included
> (measured here, the cell frankB could not build):
> `var V: array[0..3] of Int64` is `mod 8 = 0` everywhere; the same declaration
> as a typed `const` is not. It is the const path that never aligns, and the
> defect is that, not any interaction between two declarations.
>
> **3. The per-target table below MUST NOT be used to validate a fix.** The
> offset is a function of every byte emitted before it, so any compiler or RTL
> change moves every number. Re-measured at `840d4edf1c00` with the identical
> five-line program, **x86-64 gives `mod 8 = 3` and xtensa gives `0`** — the exact
> reverse of the table. Nothing changed but the compiler binary.
>
> **4. So the "odd residue is xtensa-specific" question is closed: it is not.**
> `mod 8 = 3` was the only odd residue in fifty cells and it looked like a
> distinct additional effect on xtensa. It is reachable on **x86-64** with
> today's binary, on the minimal control, with no `Double` and no xtensa
> anywhere. It was an artefact of which binary took the measurement.
>
> **5. Tested and false, recorded so nobody re-derives it:** an odd-length
> string literal is *not* the knob. Const strings of 3, 4 and 5 characters ahead
> of the array give **identical** residues on all six targets. The plausible
> mechanism was worth ten seconds to check and would have been worth a wasted
> afternoon to write down unchecked.
>
> What survives unchanged: the *category* — shared typed-const data accounting,
> not a backend arm — and the consequence, that on xtensa an unaligned const
> array is a **SIGBUS** rather than a silent under-alignment. That is why this is
> not Track F, and why it is worth prio 55 despite being invisible on five of six
> targets.


> **WIDENED 2026-08-30 — read the boundary measurement at the bottom first.**
> The title and the two tables below describe a `Double`-triggered defect on two
> backends. Measured, it is neither: typed-const arrays get no alignment on any
> target, and a `Double` is one of many things that can leave the cursor odd.
> The original filing is kept intact — its diagnosis of *shared* data-section
> accounting was right, and its numbers are a faithful record of what one
> program did on one binary.

## Repro — five lines

```pascal
program c5;
const Pi: Double = 3.14159;
      A: array[0..3] of Int64 = (1,2,3,4);
begin
  writeln('Pi @ ', PtrUInt(@Pi) mod 8, ' A @ ', PtrUInt(@A[0]) mod 8);
end.
```

| target | `Pi @` | `A @` | effect |
| --- | --- | --- | --- |
| x86-64 (oracle) | 0 | 0 | correct |
| i386 | 0 | 0 | correct |
| aarch64 | 0 | 0 | correct |
| riscv32 | 0 | 0 | correct |
| **arm32** | 0 | **4** | under-aligned; survives because two `ldr`s only need 4 |
| **xtensa** | 0 | **3** | **not even 4-aligned — SIGBUS on any index** |

Measured by printing the addresses from the program itself, not inferred from
the emitter. `Pi` is always fine; it is the array *after* it that moves.

## The boundary, bisected

Each of these is one edit away from the one before it:

| shape | result |
| --- | --- |
| `const Coef: array of Double` alone | **ok** |
| `const K: Integer` then the array | **ok** |
| `const K: Int64` then the array | **ok** |
| **`const Pi: Double`** then the array | **SIGBUS** |
| `const Pi: Double` then `array of Int64` | **SIGBUS** |
| `const Pi: Double` then a **`var`** array | **ok** |
| array first, `Pi` second | **SIGBUS** |

So the trigger is *a scalar `Double` typed const anywhere in the same const
section as a typed-const array*, and the victim's element type is irrelevant —
`array of Int64` faults identically. Order does not matter, which rules out a
simple "the previous item advanced the cursor by the wrong amount" reading of
just one direction and points at how the Double's storage is accounted for.

`var`-initialised arrays are unaffected, so this is the **const/data** path only.

## Why this is not Track F

Rank the mechanism, never the datatype. A `Double` is the *trigger*; the
*subject* is a data-section cursor that ends on an odd byte, and the observable
is a **crash**, not a wrong digit. The clinching evidence is that the program
that dies contains no float arithmetic at all — it sums an `array of Int64`.
CLAUDE.md: *"A crash, a hang, a wrong signature, a control-flow or codegen bug
that merely lives in float code — all stay ordinary bugs in their own lane at
their own prio,"* and *"when it is a close call it is NOT F."*

## Grep the sibling — and it pays

arm32 shows `A @ 4`: the same under-alignment, one notch less severe, and
**silent**, because arm32 loads an 8-byte value as two 4-byte loads and never
faults. Four backends are correct and two are wrong in the same direction by
different amounts, which is the shape of a bug in the SHARED data-section
alignment accounting rather than in either backend's arm. Fixing it in
`ir_codegen_xtensa.inc` would leave arm32 quietly emitting under-aligned
constant arrays.

Related but distinct: `599000083 fix(A): an array frame slot is pointer-aligned`
fixed the same category for **frame** slots. This is the data section.

## Provenance

Found by [[feature-s-the-xtensa-row-of-the-posix-syscall-table]]:
`test_cross_float_const` could not compile for xtensa until the syscall table
existed, and diverged from the oracle the moment it could —
`pi=3.14159 scale=2.00` then a bus error, with `coef=8.25` never printed.

---

## Boundary measured, 2026-08-30 (frankB — probes only, no fix)

Dispatched to test one thing: *does arm32 really mis-align in the same
conditions, and is there a case with every property of the failing set that
comes out aligned.* The answer to the first is yes — **and so does every other
target, including the one this ticket names as the oracle.** The defect is
larger than the ticket describes and its trigger is not a `Double`.

All measurements at pin **v393** (`1d69760deabe`), addresses printed by the
program itself.

### `Double` is not the trigger — nothing is

With **nothing at all** before it, the typed-const array is already misaligned:

```
program t;
const A: array[0..3] of Int64 = (1,2,3,4);
begin writeln(PtrUInt(@A[0]) mod 8); end.      -> 1 on x86-64, 4 on i386, 4 on arm32
```

Ten preceding shapes × five targets, `const array mod 8` / `var array mod 8`:

```
preceding const            x86-64  i386   arm32  riscv32 aarch64
(nothing)                  1/0    4/0    4/0    0/0    0/0
Double                     4/0    6/0    4/0    0/0    4/0
Int64                      6/0    1/0    0/0    0/0    4/0
Integer                    5/0    6/0    0/0    0/0    4/0
Byte                       5/0    6/0    0/0    0/0    4/0
Char                       5/0    6/0    0/0    0/0    4/0
AnsiString                 0/0    1/0    4/0    4/0    4/0
Double + Double            1/0    0/0    4/0    0/0    0/0
Single                     5/0    2/0    0/0    0/0    4/0
array of Byte x3           1/0    4/0    4/0    0/0    0/0
```

**31 of 50 cells misaligned. Observed residues: 0, 1, 2, 4, 5, 6.** Per target:
x86-64 9, i386 9, aarch64 7, arm32 5, riscv32 1. A `Double` before the array is
one row of ten and not the worst one.

### The control, and it is a clean one

**`var V: array[0..3] of Int64` is `mod 8 = 0` in all 50 cells.** Same element
type, same size, same program, same ten shapes, same five targets — and it is
aligned every single time. The only difference is typed-const versus `var`.

That is the case with every property of the failing set that does not fail, and
it localises the defect precisely: the `var`/BSS path aligns, the typed-const
data path does not align at all.

A second, weaker control worth keeping: `Int64 before` on arm32 gives 0. It is
**aligned by arithmetic, not by correctness** — the preceding bytes happened to
land right. Any row that reads 0 in the grid above is that kind of zero, which
is why the grid must not be read as "these cells are fine".

### Consequences for this ticket as written

- **The per-target table is not reproducible, by construction.** On this
  ticket's exact five-line program at v393 I measure i386 4, riscv32 4,
  aarch64 4 and **arm32 0** — three targets the ticket calls correct are
  misaligned, and the one it calls broken is not. Nothing changed except the
  compiler binary. The offset is a function of everything emitted before the
  array, so any change to the compiler or RTL shifts every number in the table.
  **A fix must not be validated against those numbers.**
- **The "boundary, bisected" table is measuring luck.** `Int64 then array -> ok`
  and `Integer then array -> ok` are cells that happened to land on 0; with
  nothing at all in front, the array is still misaligned. There is no shape
  that makes it right, only shapes that make it lucky.
- **The conclusion is right and understated.** The ticket says this is shared
  data-section accounting rather than a backend arm, and that a xtensa-only fix
  would leave arm32 silently under-aligned. Correct — and it is not two
  backends, it is all six. The others differ only in what their hardware
  tolerates: x86 permits any alignment, arm32 splits an 8-byte load into two
  4-byte loads, xtensa faults. **`sum of an array of Int64` returned the right
  answer at `mod 8` = 2, 4, 5 and 6 on every runnable target.** Silence here is
  hardware tolerance, not correctness.
- **Not Track F stands, and more firmly than the ticket argues.** Rank the
  mechanism: the mechanism has nothing to do with floats at all. The array is
  misaligned with no `Double` in the program.

### What a fix must assert

- The typed-const array is 8-aligned in **all 50 cells** of the grid above, not
  in the ticket's original program.
- `var` stays 0 everywhere (it is correct today; a fix that aligns const by
  routing everything through a new path must not disturb it).
- Alignment holds with **nothing** preceding the array — the case that shows
  there is no alignment step rather than a wrong one.
- Element types wider than the target word (`Int64`, `Double`) *and* an array
  whose element is a record, since the required alignment comes from the
  element type.

### Not measured, and left visibly absent

**xtensa.** It does not build here — `target xtensa: external (dynamic) …` from
the plain `writeln` probe, i.e. it needs the ESP platform flags this lane is not
set up for. Every xtensa claim in this ticket remains frankS's measurement,
uncorroborated by me. The `mod 8 = 3` figure in particular is the only observed
residue that is not even 4-aligned, and nothing in my grid reproduces an odd
residue on any other target — so it may be a distinct additional effect on that
backend rather than the same one worse. Untested either way.

---

## RESOLVED 2026-08-30 (frankA, Track A) — already fixed at HEAD by `75d2ba662`; the grid was measured against a binary that predates it

**No code change was needed for the defect.** It is fixed on every runnable
target at HEAD, it was fixed by a commit that was not trying to fix it, and the
reason two rounds of measurement disagreed with each other is that both were
right about different binaries.

### The measurements

All at `4cec00985`, each binary named, each a self-host fixedpoint build.

| binary | provenance | x86-64 | i386 | aarch64 | arm32 | riscv32 |
| --- | --- | --- | --- | --- | --- | --- |
| `53800fbeb0b6` | **pin v394**, blessed 04:12Z from git `43c8e3412049` | **6** | **6** | **4** | **4** | 0 |
| `41e452a55913` | self-hosted at `eb340e59d` = `75d2ba662^` | **6** | **6** | **4** | **4** | 0 |
| `a3f0f9e3325f` | self-hosted at `75d2ba662` | 0 | 0 | 0 | 0 | 0 |
| `06487471bcc0` | self-hosted at `8ce19ac98` = `df98fea47^` | 0 | 0 | 0 | 0 | 0 |
| `aa78a7faf63a` | self-hosted at HEAD | 0 | 0 | 0 | 0 | 0 |

Program is this ticket's own five-liner, unmodified. **The full 10-shape grid
this ticket demands is 50/50 aligned at HEAD** — ten preceding shapes × five
runnable targets, const and `var` both 0 in every cell.

`75d2ba662^` and `75d2ba662` are an adjacent pair, so the boundary is exact:
**`75d2ba662 perf(O): page-separate code from data in the ELF writer` is the
commit that fixed it**, six weeks of ticket history notwithstanding. It was
measured, not inferred from the elfwriter comment that credits it — that comment
was the hypothesis, and building both sides is what turned it into a result.

### Why the ticket's grid could never be reproduced from source

**frankB measured with the PINNED binary, and the pin lags master.** Track B's
standing rule is *build with `$(PXX_STABLE)`, never rebuild the compiler*, so
that was the correct thing for a Track B agent to do — but it makes the
measurement's provenance the pin, not a commit.

The ticket says *"All measurements at pin v393 (`1d69760deabe`)"*, and
`1d69760deabe` is **the binary's sha256 prefix, not a git sha**. `pin.log` gives
the git sha for v393 as `1fb9774b7417`. So every attempt to "re-verify at that
sha" was checking out something unrelated, or nothing. That is the whole reason
this ticket looked irreproducible and its numbers looked like noise: two
honest measurements, taken against two different compilers, neither of them the
one the other names.

Recorded because the trap is general and cheap to re-enter: **a pin ledger entry
has three identifiers — a version, a binary hash and a git sha — and only the
third one is a commit.** Anything that says "measured at pin vNNN" should carry
the git sha, or the next reader re-derives this.

### The diagnosis this ticket carries is wrong, and the correction is sharper

Both framings — the original *"a `Double` misaligns the NEXT array"* and
frankB's correction *"the typed-const data path does not align at all"* — put
the defect in typed-const accounting. **It was never there.**

The address is two terms, `dataBase + offset`:

- **`offset` was always right.** `TryBakeConstArrayIntoData` has aligned it
  since the commit that created the function (`e34687fe2`):
  `base := AlignTo(DataLen, TypeAlign(elemTk))`, `compiler/symtab.inc`. There is
  no earlier unaligned version — `git log -S 'base := DataLen'` returns nothing.
- **`dataBase` was the broken half.** Every ELF writer places data straight
  after code (`LOAD_ADDR + codeOffset + CodeLen`), so the section began wherever
  the last instruction ended. `75d2ba662` page-separated code from data, which
  aligned the base to 4096 and therefore to 8 as a side effect.

**The prediction that distinguishes the two diagnoses, and it could have
failed.** If the fault is per-array accounting, arrays in one program should
carry *different* residues; if it is a shifted section, they must all carry the
*same* one. Three arrays, two element types, one program:

```
pin v394 (broken):  A=7  B=7  C=7      HEAD (fixed):  A=0  B=0  C=0
```

Identical residues, across `array of Int64` and `array of Double` alike. It is
one whole-section shift, and it also settles this ticket's open question about
odd residues: **7 is odd, on x86-64, with no `Double` and no xtensa anywhere.**
The "is the odd residue xtensa-specific" thread is closed — it never was.

This also explains, without any appeal to noise, why the grid's numbers moved
with every preceding declaration and with every compiler rebuild: the residue is
`dataBase mod 8`, and `dataBase` is a function of `CodeLen`. Every byte of code
emitted before it moved the whole section. frankB's *"the offset is a function
of every byte emitted before it"* was exactly right about the mechanism and one
level off about the location.

### `df98fea47` is still load-bearing, and this is not a case of two fixes for one bug

`75d2ba662` fixed it **by accident and only for hosted images** — its page pad
is what supplies the 8, and four routes remove that pad (a second PT_LOAD, a
16 KiB-page host, `--emit-obj`, and any bare-metal ESP image, which skips the
page pad outright). `df98fea47` made the 8-alignment explicit and unconditional
(`AlignCodeForData`, `ELF_DATA_ALIGN`, plus `CheckDataBaseAligned` raising an
Error rather than miscompiling). **The bare-metal xtensa path — the one target
where this is a SIGBUS rather than a tolerated under-alignment — was misaligned
until `df98fea47`, not until `75d2ba662`.** So the six-target claim needs both
commits, and neither is redundant.

### What is actually still broken: the PIN

**Every lane that builds with `$(PXX_STABLE)` still has this defect.** Track B,
Track E and Track D all build against `stable_linux_amd64/default/pinned`, which
is v394, blessed 04:12Z from `43c8e3412049` — measured above at 6/6/4/4/0. The
fix has been on master since `75d2ba662` and is not in anyone's stable compiler.

That is the one open action, and it is **not mine to take**: a pin holds the
repo-wide lock. Flagged to the coordinator rather than performed.

### Regression test added

`test/test_const_array_align.pas`, wired into `test-core` natively and across
i386/aarch64/arm32/riscv32.

It guards the **offset** half specifically — the half nothing asserted. The base
half is already covered by `7720f02c8`'s `esp-bare-*-data-align8` rows, and on a
hosted image the base is a PT_LOAD boundary and so page-aligned, which is
precisely why a residue observed by this test can only have come from the offset.

**It is not a test that cannot fail:** against pin v394 all five rows report
MISALIGNED and the OK token is absent. Run before trusting it, not after.

**Each array is asserted to its own element alignment, not uniformly to 8.** An
`array of Cardinal` is contracted to 4 and lands on 8 today only because of what
precedes it — asserting 8 for it would be asserting luck, which is this ticket's
own central warning turned on the test that closes it.

**No float-element array, and that is a finding rather than an omission.**
`@C[0]` where C is an `array of Double` does not COMPILE on i386/arm32/riscv32
(`unsupported float operator`, in a program with no float operation). Filed as
[[bug-a-taking-the-address-of-a-float-array-element-is-a-float-operator-on-32-bit]],
with controls in both directions. A `Double` element needs the same 8 an `Int64`
does, so no alignment coverage is lost; the test carries a comment saying to add
the float rows when that ticket closes.

### Left alone deliberately

The two tables in the body above are **not** corrected in place. They are a
faithful record of what two binaries did, they are already carrying frankB's and
frankS's correction blocks, and three pushed tickets plus a Makefile comment
resolve to this slug. Rewriting them would falsify the history that made the
provenance trap visible in the first place.

**Gate:** `make compiler/pascal26` (converged, self-host fixedpoint) +
`test/test_const_array_align.pas` green natively and on all four cross targets +
the 50-cell grid at HEAD.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
