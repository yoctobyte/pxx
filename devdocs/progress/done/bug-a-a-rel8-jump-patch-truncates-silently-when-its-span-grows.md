---
slug: bug-a-a-rel8-jump-patch-truncates-silently-when-its-span-grows
track: A
prio: 55
type: bug
blocked-by: []
status: done
found: 2026-08-30
summary: "The rel8 patch idiom `Code[p] := Byte(CodeLen - (p + 1))` truncates without any diagnostic when the span exceeds 127 bytes. A forward jump silently becomes a BACKWARD jump into the middle of an instruction. Measured: a jns meant to skip 181 bytes was written as -75 and the program segfaulted at a mid-instruction address. Latent today; armed the moment any emitter between a patch site and its target grows."
owner: frankA
---

# A rel8 jump patch truncates silently when its span grows

The idiom, used at ~30 sites across `symtab.inc`, `ir_codegen.inc`,
`exception_emit.inc` and `emit.inc`:

```pascal
EmitB($79); jnsOff := CodeLen; EmitB(0);    { jns .pos — placeholder }
...
Code[jnsOff] := Byte(CodeLen - (jnsOff + 1));
```

`Byte()` truncates. There is no range check and no diagnostic. When the emitted
span between the placeholder and its target exceeds **127 bytes**, the forward
displacement wraps into a negative `rel8` and the jump goes **backwards**,
usually into the middle of an instruction.

## Measured, not reasoned

Found while growing `EmitSyscall` from 2 bytes to ~140 for
[[feature-port-rtl-over-libc]] (that work is reverted; this defect is not).

- The program faulted with `rip = 0x411115`, which is **mid-instruction** — the
  `add $0x80,%rsp` at `0x41110f` is 7 bytes and spans through `0x411115`. A
  mid-instruction `rip` can only be reached by a jump.
- Scanning the executable segment for any `rel8` jump targeting that address
  found exactly one: **`0x41115e: jns rel8, displacement -75`**.
- The intended forward distance at that site (`symtab.inc:9789`) was **181**
  bytes. `181` written as a byte and read back as a signed `int8` is **-75**.

`181 - 256 = -75` is an exact match, so the mechanism is arithmetic, not
inference.

## Why it is worth fixing rather than noting

**It is silent in both directions.** The compiler emits no diagnostic, and the
resulting binary crashes far from the emitter that grew — the fault address is
inside an unrelated instruction, and the emitter that caused it is not on the
stack. This is the repo's expensive shape: a plausible wrong result far from
the cause.

**Today it is latent, not live.** No current emitter spans 127 bytes at these
sites, so every existing patch is in range and the default build is correct.
That is exactly what makes it a landmine: it is armed by *growing an emitter*,
which is a normal thing to do, and it gives no signal that a limit was crossed.
`--rtl-libc` is the first thing to trip it, and only in a non-default mode.

## Fix

Replace the raw `Byte(...)` stores with a checked helper, e.g.:

```pascal
procedure PatchRel8(patchPos: Integer);
var d: Integer;
begin
  d := CodeLen - (patchPos + 1);
  if (d < -128) or (d > 127) then
    Error('rel8 jump span ' + IntToStr(d) + ' exceeds the one-byte '
          + 'displacement: widen this jump to rel32');
  Code[patchPos] := Byte(d);
end;
```

An `Error` is the right response rather than auto-widening: widening changes
every downstream offset and the sites differ in whether they can absorb that,
so the emitter's author should choose. The point is that the limit becomes
**loud at compile time** instead of silent at runtime.

Sites to convert: every `Code[<x>] := Byte(CodeLen - (<x> + 1));` and the
inline `EmitB(Byte(<target> - (CodeLen + 1)));` back-edge form.

## Gate

`make compiler/pascal26` (self-host fixedpoint) — the conversion must be a pure
refactor with the default build byte-identical, which is checkable by comparing
emitted programs against the pinned binary, not only by the fixedpoint (see
face 190: the fixedpoint proves self-consistency, not unchanged output).

---

## 2026-08-30 (frankA, Track A) — slice 1 of 2 landed: 83 of 157 sites converted

**The count in this ticket is wrong by 5x, and one of the three spellings is one
the proposed fix would have missed.** The census came first, and it changed the
job.

### Census — enumerated by SHAPE, not by the idiom

The ticket says *"~30 sites across `symtab.inc`, `ir_codegen.inc`,
`exception_emit.inc` and `emit.inc`"*. Measured at `57585e709`:

| form | spelling | sites | where |
| --- | --- | --- | --- |
| 1 | `Code[p] := Byte(a - (p + 1));` | 121 | ir_codegen.inc 53, symtab.inc 35, ir_codegen386.inc 33 |
| 2 | `EmitB(Byte(t - (CodeLen + 1)));` | 15 | symtab.inc 8, ir_codegen386.inc 7 |
| 3 | **`Patch8(p, CodeLen - (p + 1));`** | **21** | **ir_codegen.inc 21** |
| | **total** | **157** | |

The file list is wrong in **both** directions: `exception_emit.inc` and
`emit.inc` contain **zero** of these sites, and `ir_codegen386.inc` — which
holds **40** of them — is not named at all.

**The denominator is real, not a grep that happened to match.** All 147 writes
of the form `Code[...] := ...` anywhere in `compiler/**` were extracted and
clustered by normalised RHS shape: 121 fall in the displacement cluster
`ID(ID - (ID + N))`, and every one of the remaining 26 is a plain byte store or
a multi-byte `Patch32`/`Patch24` limb. Every form-1 site uses `+ 1` — 121 of
121, no other offset exists. For form 2 the population is the 89 `EmitB(` calls
whose argument contains a subtraction; 15 are rel8 and the other 74 are `EmitI32`
rel32 pairs and ModRM displacements.

### The third spelling, which is the finding

`Patch8(pos: Integer; v: Byte)` truncates **at the call**, because its parameter
is a `Byte` and the argument is an `Integer`. All 21 of its call sites pass
`CodeLen - (pos + 1)`; not one passes anything else. Measured rather than
assumed — a five-line program storing 181 through both routes:

```
Patch8-style=181  Byte()-cast=181  as signed=-75
```

No warning, no error, from either spelling. **`Patch8` is the dangerous one
precisely because it already looks like a checked helper.** This ticket's own
Fix section says *"replace the raw `Byte(...)` stores"* and lists the two
`Byte(` forms as the sites to convert — that fix would have left all 21
`Patch8` sites silently truncating and produced a note saying the conversion
was complete.

That is
[[bug-a-the-abi-oracle-invariant-is-enforced-by-a-grep-that-cannot-fire]]
exactly: an invariant calibrated to a **spelling** rather than to a **shape**
reports clean forever. It is why the guard landed as three named helpers rather
than as a review rule.

### What landed

`CheckRel8` / `PatchRel8` / `EmitRel8` in `compiler/emit.inc` (include 75;
`util.inc` is 64, so `AIntToStr` is in scope). Converted, mechanically, only
where the patch index and the subtrahend are provably the same expression:

- `compiler/symtab.inc` — 35 form-1 + 8 form-2 = **43**
- `compiler/ir_codegen386.inc` — 33 form-1 + 7 form-2 = **40**
- **0 skipped.** Every site in both files had matching index/subtrahend; the
  converter was written to refuse and report any that did not.

### Gate — and the two ways this could have looked green while being wrong

**`make compiler/pascal26`: converged, 1 round, `f3008c7f8fe6`.**

**Output byte-identity, 25/25.** The five-program corpus emitted by the
before-compiler (`631a13d0d8d0`) and the after-compiler, compared with `cmp`,
**for each of i386, x86-64, aarch64, arm32 and riscv32.** This is the check
face 190 asks for: the fixedpoint proves self-consistency, not unchanged output.

The first run of that comparison was **x86-64 only, and it was vacuous for the
larger half of the change** — `ir_codegen386.inc` is the *i386* backend and no
program in the corpus had been built for it. Adding the four cross targets is
what made the 25 mean something.

**Proof the guard is on the live path, because byte-identical output is also
what you get if the new code never runs.** The bound was temporarily tightened
from ±127 to ±4 and the compiler rebuilt:

```
x86-64 : pascal26:5321: error: rel8 forward jump displacement 42 does not fit ...
i386   : pascal26:2151: error: rel8 forward jump displacement 10 does not fit ...
aarch64: 0 rel8 errors          <- negative control: no converted sites there
```

Both converted backends reach the guard; a backend with no converted sites does
not fire. Bound restored, rebuilt, fixedpoint re-verified, byte-identity re-run
at 25/25.

### Deferred: the 74 sites in `ir_codegen.inc`

53 form-1 + 21 form-3, untouched. `compiler/ir_codegen.inc` is held by
frank-optimize (on `feature-opt-emitasmx64-reparses-fixed-strings`), and the
coordinator asked to be told before that file is entered.

**The fix does NOT have to be atomic**, which was the coordinator's stated
stop-condition, and this slice is the evidence: the sites are independent, the
conversion changes no emitted byte, and 83 of them landed green while the other
74 kept the old idiom. So the remaining half is an ordinary sequenced slice, not
a reason to hold the whole thing.

**The tree is not half-applied in the dangerous sense.** The `unfinished/` rule
warns that a partial Track A change can break the stable-binary or self-host
gate. This one cannot: the fixedpoint converged and output is byte-identical on
five backends. `ir_codegen.inc` still uses the old, working, latent-bug idiom —
which is exactly the state it was in this morning.

### Still open after slice 2, worth knowing now

The 74 deferred sites include the only appearances of form 3, so **until
`ir_codegen.inc` is converted, `Patch8` remains a live truncating path.** A
grep for the two `Byte(` forms will report `ir_codegen.inc` as 53 sites
remaining when the true figure is 74.

**Gate for slice 2:** identical to this one — fixedpoint, plus output
byte-identity on all five backends, plus the tightened-bound reachability proof
re-run for the x86-64 backend.

---

## RESOLVED 2026-08-30 (frankA, Track A) — slice 2 landed; **the campaign is CLOSED**

**This ticket is done, not half-done.** It ran as two slices because
`ir_codegen.inc` was held by another lane for the first one, and a two-slice
ticket that closes on slice 2 is exactly the shape a later reader mistakes for
abandoned work. All **157** sites are converted. There is no slice 3.

### Slice 2: the 74 sites in `ir_codegen.inc`

- 53 form-1 (`Code[p] := Byte(CodeLen - (p + 1))`) → `PatchRel8(p)`
- 21 form-3 (`Patch8(p, CodeLen - (p + 1))`) → `PatchRel8(p)`
- **0 skipped** — the converter refuses any site whose patch index and
  subtrahend differ, and none did.

### `Patch8` is DELETED, not deprecated

After the 21 conversions it had **zero callers anywhere** — `compiler/`, `lib/`,
`tools/`, `test/`. It was the third and worst-disguised spelling of this defect:
a `v: Byte` parameter truncating an `Integer` argument silently, in a helper
that already looked checked. Leaving an unused truncating byte-patcher in a file
full of emitters is an invitation, not a convenience, so it is gone and the
reason is recorded where it stood. `Code[pos] := v` is what to write if a raw
byte store is ever genuinely wanted.

### The helpers moved to `compiler/rel8.inc`, and that was the enabling change

The condition on this slice was **one test that proves the refusal fires**. That
test has to include the *real* shipped code, not a copy — a copy proves the copy
works. Including `emit.inc`, where the helpers landed in slice 1, would need
~30 mocks (`Procs`, `Syms`, `Strs`, `TargetArch`, …), and that is precisely how
`test_asm_emit_rv32.pas` rotted three times, most recently on the morning of
2026-08-30. `rel8.inc` needs **five**: `Code`, `CodeLen`, `EmitB`, `Error`,
`AIntToStr`.

So the extraction is not tidying. It is what makes the guard testable at a mock
cost that will not rot.

### `test/test_rel8_guard.pas` — and it is proven able to fail

13 checks, wired into `test-core`. **Two-sided on every boundary**: +127
accepted *and* +128 refused, −128 accepted *and* −129 refused, plus the stored
byte asserted for an in-range forward span (100 → 100) and a negative back edge
(−5 → $FB, since two's complement is what the field wants and "reject negatives"
is the obvious wrong implementation).

A guard that refused everything would pass a refusal-only test, so the
acceptances are the half that gives it meaning.

**Mutation-tested rather than assumed:**

| mutation of `rel8.inc` | harness result |
| --- | --- |
| `if False then` — accept everything (the pre-fix behaviour) | **4 failures** |
| `if True then` — refuse everything | **6 failures** |
| `(d > 128)` — off-by-one bound | **2 failures** |

The measured case is asserted by value: span **181** must be refused, and
`Integer(Shortint(Byte(181))) = -75` is checked so the ticket's central number
is executable rather than prose.

### Gate

- `make compiler/pascal26` — converged, 1 round, `02ad0bc54dfd`.
- **Byte-identity 20/20** — four programs × five backends, baseline
  `4bc7cd1205bc` vs `02ad0bc54dfd`, **both built at one HEAD** (stash, build,
  emit, pop, *rebuild*, emit — a `stash pop` restores sources, not binaries).
- **Reachability, attributed to this slice's sites specifically.** Slice 1's ±4
  tightening proves *a* `PatchRel8` runs, not *which* file's. So all 74
  `ir_codegen.inc` call sites were temporarily renamed to a `PatchRel8IRC` that
  errors unconditionally, and the marked compiler was asked to build
  `test/hello.pas`:

  ```
  pascal26:2: error: MARKER: an ir_codegen.inc converted site was reached
  ```

  Every compiled program takes these paths. Marker removed, rebuilt, fixedpoint
  re-verified, byte-identity re-run.

### Final state of the census

| form | sites | status |
| --- | --- | --- |
| 1 `Code[p] := Byte(a - (p + 1))` | 121 | converted |
| 2 `EmitB(Byte(t - (CodeLen + 1)))` | 15 | converted |
| 3 `Patch8(p, CodeLen - (p + 1))` | 21 | converted, and `Patch8` deleted |
| | **157** | **0 remaining** |

Verified by re-running the shape census at the final tree: zero form-1 sites
remain in `symtab.inc`, `ir_codegen386.inc` or `ir_codegen.inc`, zero form-2,
and `Patch8` does not exist.

**Measured at the final tree, not asserted:**

```
form 1 remaining, repo-wide          : none
form 2 remaining, repo-wide          : 1  -> rel8.inc:69, PROSE
procedure Patch8                     : deleted
Code[...] := writes, repo-wide       : 28  (was 147)
  of which displacement-shaped       : 0   (was 121)
PatchRel8/EmitRel8 call sites        : symtab 43 + ir_codegen 74 + 386 40 = 157
```

157 call sites against a 157-site census is the closure check: every site the
census found is now a checked call, and none were invented.

The single form-2 "hit" is `rel8.inc:69` — the doc comment saying *"as the
`EmitB(Byte(target - (CodeLen + 1)))` idiom it replaces"*. A sentence explaining
the idiom matches a grep for the idiom. That is the same trap frankC hit on the
`cir.inc` census (a comment naming a routine defeated a reached-only-from-C
test), here in the harmless direction — it inflates a count rather than hiding
a candidate. Worth noting because the harmful direction is invisible and this
one is not: had I trusted the grep's number instead of opening the line, the
closure check would have read "1 site remaining" forever.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
