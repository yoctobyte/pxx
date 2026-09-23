---
slug: bug-s-c-on-the-esp-profile-cannot-reach-crtl
track: S
type: bug
prio: 45
status: done
owner: ""
created: 2026-09-05
blocked-by: []
summary: "FIXED for the IDF profiles 2026-09-23; the BARE half is by design and only its diagnostic is wrong (see the residual below). The gate `cPullsBuiltinHeap` was spelled `(not NoDefaultRtl) and (TargetPlatform <> PLATFORM_ESP)` where the rest of the compiler asks `not TargetIsEspClass` -- the tree's profile-aware predicate for exactly `may I pull this RTL unit`, used at 24 Pascal-driver sites. The two agree on riscv32 and differ on xtensa, which is PLATFORM_ESP UNCONDITIONALLY, so the gate was permanently False there and NO xtensa C source could reach crtl on ANY profile. That contradicted its own block comment (`xtensa joins riscv32 here for the IDF profile`) and util.inc's header on TargetIsEspClass, which predicted this drift in words. THE TICKET'S CENTRAL CLAIM WAS WRONG AND IT IS WHAT HID THE CAUSE: the discriminator is not the PROFILE -- `--target=esp32c3` built this all along, because riscv32 is posix unless the profile says otherwise, so the failing set is `xtensa on any profile` PLUS `either ISA under bare`, not `PLATFORM_ESP`. Which of the fifteen identical `PXXMemZero not found` sites raises it -- the ticket's own next-step question -- is answered: a BACKEND site, never symtab.inc, so the table was built and the unit was not in it. All fifteen now name their file."
---

# C on the ESP profile cannot reach crtl

- **Type:** bug — Track S (ESP), primary target xtensa
- **Found:** 2026-09-05 (frankS), bounding my own claim after frankC measured it
- **Compiler:** `b67962cb78fa`

## The 2×2, which is the whole diagnosis

Source is `#include <stdio.h>` plus `int main(void) { printf("hello\n"); return 0; }`.

| | `--platform=posix` | ESP profile (default and `--esp-profile=bare`) |
| --- | --- | --- |
| `--emit-obj` | **BUILDS** | `pascal26:11: error: compiler error: PXXMemZero not found` |
| executable | **BUILDS** | refuses earlier, at the C entry stub (correct, by design) |

**The discriminator is the PROFILE, not the output mode.** That matters because
the obvious reading — "the object path is less complete than the executable
path" — is wrong, and it is the reading someone will reach for.

A freestanding C source is fine on both ESP profiles: `int main(void)` with no
includes builds to an object exporting `GLOBAL app_main`. So the entry
machinery works and it is specifically the crtl reach that does not.

## Why "not found" is misleading, and what it is not

`PXXMemZero` is declared at `compiler/builtin/builtinheap.pas:468` and defined at
`:4561`. The body is **unconditional** — only its fast paths carry
`{$ifdef CPUX86_64}` — and it sits after the `{$ifndef PXX_ESP}` block (3671–4356)
closes, so it is not guarded out on ESP.

**So the symbol exists and the lookup is not reaching it.** This is not a missing
implementation; it is the builtin heap unit not being pulled into a C
compilation on `PLATFORM_ESP`. The `compiler error:` spelling is an internal
assertion — one of fifteen identical `PXXMemZero not found` sites across six
backends (`symtab.inc` plus five `ir_codegen_*`), so the message says which
symbol and nothing about which of the six asked.

**Do not "fix" this by defining PXXMemZero somewhere.** It is defined. The
question is unit reachability on this profile, and a second definition would
make the symptom go away while leaving every other builtin in the same unit
just as unreachable — the next one would surface as a different name and read
as an unrelated bug.

## Where this came from, and what it bounds

`decide-should-a-c-main-exist-on-the-esp-profile-at-all` (decided today)
established that `--emit-obj` is how C ships to an ESP32 and that the standalone
refusal is correct. **That is true for freestanding C and I wrote it without the
bound**, which frankC caught by noticing its own `c_va_arg_every_target.sh`
`--emit-obj` row builds only a trivial `main` and a stdarg program and never
reaches printf. The diagnostic in `cparser.inc` now carries the bound and names
this ticket.

## Next step for whoever takes it

The cheap first measurement is which of the six backends raises it here —
`PXXDBG` or a temporary distinct string per site — because `symtab.inc` raising
it means the symbol is absent from the table entirely, while an `ir_codegen_*`
site raising it means the table was built and the unit was still not in it.
Those are different bugs with the same message.

# Resolution (2026-09-23, frank) — IDF fixed, bare is by design

## The fix

One predicate, `cparser.inc`:

```
- cPullsBuiltinHeap := (not NoDefaultRtl) and (TargetPlatform <> PLATFORM_ESP);
+ cPullsBuiltinHeap := (not NoDefaultRtl) and (not TargetIsEspClass);
```

`TargetIsEspClass` is the tree's profile-aware predicate for this exact
question and the Pascal driver asks it at 24 sites. It differs from the
platform spelling on **xtensa, which is `PLATFORM_ESP` unconditionally** — so
the gate was permanently False there and no xtensa C source could reach crtl on
*any* profile.

Two things in the tree already said so:

- the block's own comment, a few lines below the gate: *"xtensa joins riscv32
  here for the IDF profile — same reason, same date"*. The gate could never let
  that happen.
- `util.inc`'s header on `TargetIsEspClass`, which predicted this precise
  drift: *"the C frontend and the -Fu default-path setup ask the identical
  question and had drifted into their own copies, each with its own comment
  saying 'same guard as the Pascal default-RTL pull' — the sameness was
  documented in prose and not in code."* That pass replaced one `cparser.inc`
  site; this was a **second spelling of the same question in the same file**,
  written over `TargetPlatform` instead of by hand, so the grep that found the
  other 24 could not see it.

The neighbouring `pxxcio` gate **is** correctly spelled over `TargetPlatform`
— it asks *"are there posix syscalls under this target"*, a different question
with its own note — which is why two adjacent gates disagreeing read as
deliberate.

## Correction — the 2×2's conclusion was wrong, and it is what hid the cause

The ticket says *"the discriminator is the PROFILE, not the output mode"* and
flags the alternative as the reading someone would wrongly reach for. The
profile is not the discriminator either:

| | default (IDF) | `--esp-profile=bare` |
| --- | --- | --- |
| xtensa / esp32 / esp32s3 | **refused** | refused |
| esp32c3 / esp32c6 | **BUILT ALL ALONG** | refused |

`esp32c3` is the ESP platform on riscv32 and built this the whole time, because
riscv32 is posix unless the profile says otherwise. So the failing set is
**xtensa on any profile, plus either ISA under bare** — an ISA×profile shape,
not a profile one. Measuring only the primary target made an ISA effect look
like a profile effect, and the fix a profile reading suggests (widen the
platform test) would have dragged the whole RTL into bare-metal images.

## The ticket's own next-step question, answered

*"The cheap first measurement is which of the six backends raises it."* It is
an **`ir_codegen_*` site, never `symtab.inc`** — so, in the ticket's own terms,
the table was built and the unit was still not in it. Measured by making all
fifteen sites name their file, which is kept: the message now reads
`PXXMemZero not found (xtensa)`. Nothing asserted on the old string.

## Verified

All IDF profiles build (`xtensa`, `esp32`, `esp32s3`, `esp32c3`, `riscv32`),
and the xtensa object is sound rather than merely accepted: `ET_REL`/Tensilica,
`PXXMemZero` a **defined** local, `app_main` the global entry, and every
undefined symbol IDF- or newlib-provided (`calloc`, `free`, `putchar`,
`vTaskDelete`, `read`, `write`, `fopen`…).

Seven rows in `test-emit-obj`, of which **three fail under pinned v416** — both
xtensa compiles and the xtensa `nm` row. The `esp32c3` rows pass under the pin
too, deliberately: they are there to record that a riscv32-only row would have
passed throughout. `nm ... ' t PXXMemZero'` is asserted separately from the
compile because *"the compiler accepted it"* and *"the unit got pulled"* are two
claims and only the second was broken.

Full `test-emit-obj` GREEN, `gate.sh quick` GREEN, fixedpoint converged.

## Residual — owned, not left silent

Bare metal deliberately gets no default RTL, so **bare refusing this source is
correct** and the negative-control row pins it. What is still wrong there is
only the *diagnostic*: it is an internal assertion (`compiler error:`) naming a
symbol, with no remedy a C programmer could act on, because C has no `uses`
clause to add. Filed as
[[bug-s-the-bare-esp-refusal-for-c-that-needs-the-rtl-is-an-internal-assertion]].
Low prio, and lower still under the owner's 2026-09-23 ruling that IDF is the
assumed profile and bare is a test vehicle.

## Log
- 2026-09-23 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit e65ee9a5d.
