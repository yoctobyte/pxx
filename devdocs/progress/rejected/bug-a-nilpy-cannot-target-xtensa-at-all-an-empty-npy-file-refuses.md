---
prio: 0
track: A
type: bug
status: rejected
found: 2026-09-22
found-by: frankh-c0
owner: ""
blocked-by: []
summary: "REJECTED 2026-09-22 BY ITS OWN AUTHOR -- THE PREMISE IS FALSE. NilPy builds for xtensa. The default Call0 ABI overflows the addi range; `--xtensa-abi=windowed --xtensa-long-calls` clears it, and with `--emit-obj` (the IDF profile's documented output form -- it emits an object for the IDF link, not a complete executable) an empty .npy builds at 975,588 B and `print(1)` at 975,740 B. Measured by frankh-c0 at 6fb91c73e88e and matching frankb-8e's independent figures byte for byte. The ticket's subject also re-measures clean: vmt/rtti slot 174,350 B / 149 bodies, total live 833,482 B, agreeing to the body with an earlier same-day run at fc53bd2bd. So there is NO break, NO regression and NOTHING to bisect, and the two-day-regression lead recorded here yesterday is dead. WHAT WENT WRONG, because it is the reusable part: the scope table had three xtensa rows (`--target=xtensa`, `+ --platform=esp`, `+ --esp-profile=bare`) and ALL THREE SHARE THE DEFAULT ABI. The platform axis was varied and the axis that decides the outcome was held fixed, so a table with three rows was a table with one. The empty-file floor case -- which was good method and correctly proved the failure was not in user code -- is exactly what produced the confidence, because excluding one axis rigorously was read as locating the cause on another. The diagnostic named the right axis in its own words the whole time (`the code is too large for this BRANCH FORM` is a statement about an encoding choice, i.e. a flag) and this ticket quoted that sentence twice while concluding the target was broken. THE ONE REAL RESIDUAL IS SPLIT OUT AND IS NOT THIS: tools/esp_run_bare.sh defaults to --chip esp32c3 (riscv32), so xtensa NilPy has no routine coverage, which is why two seats believed a flag mistake was a broken target -- see chore-t-the-bare-esp-runner-exercises-riscv32-only-so-xtensa-nilpy-has-no-routine-coverage."
---

# NilPy cannot target xtensa at all — an empty `.npy` file refuses

## The floor case

    $ : > empty.npy
    $ ./compiler/pascal26 --target=xtensa --platform=esp empty.npy empty.o
    pascal26:3380: error: target xtensa: addi immediate displacement 128 is
      outside the encodable range -128..127; the code is too large for this
      branch form

A **zero-byte source**. There is no user construct to reduce, and no program a
user could write that avoids it: the failure is in the NilPy runtime the driver
appends, not in anything the `.npy` contains.

## Scope, one row each

| input | target / flags | result |
| --- | --- | --- |
| empty `.npy` | `--target=xtensa` | **FAIL** |
| empty `.npy` | `--target=xtensa --platform=esp` | **FAIL** |
| empty `.npy` | `--target=xtensa --esp-profile=bare` | **FAIL** |
| `x = 1` (no print) | xtensa | **FAIL** |
| `print("hi")`, a list, a dict, a class, a def | xtensa | **FAIL**, all |
| the same files | riscv32 `--platform=esp` | ok |
| `program p; begin end.` | `--target=xtensa --platform=esp` | **ok** |
| `int main(void){return 0;}` | `--target=xtensa --platform=esp` | **ok** |

So: **NilPy-specific, every xtensa spelling, and not a general xtensa breakage** —
Pascal and C both compile on the identical flags.

## Not today's work — and that is ALL that is established

    HEAD    3854783c605a / 5f986d67044a : FAIL
    PINNED  stable_pinned               : FAIL, same line, same message

The pinned compiler refuses identically, so this is not attributable to the
`--dce` default, `523833fde`, or `324d668b8`.

**This section said "pre-existing, not a regression" when filed, and the second
half was an overstatement I corrected the same day.** What the pinned control
shows is that the failure is older than today. It says nothing about whether
xtensa NilPy ever worked, and the two are not the same claim — a pin is days
old, not months. Treating "the pin refuses too" as "it was always broken" is the
quantifier riding on the verb's credibility again, in a ticket whose author had
just written that phrase into a memory file.

See the cross-reference at the end: there is a concrete lead that this may be a
**two-day regression**, which would make it bisectable and a much better ticket
than this one.

## Why the priority is 70 rather than lower

**xtensa is the PRIMARY ESP target** — the S-lane rule says so in as many words
(*"Primary target xtensa; riscv32 works"*). So the whole NilPy-on-ESP32-S3 path
is closed, while esp32c3 is fine.

That asymmetry is **structurally easy to miss**: `tools/esp_run_bare.sh` defaults
to `--chip esp32c3`, which is riscv32, so anyone exercising NilPy on ESP by the
usual route measures the working half and sees nothing. This is the
"measured on the default target" class — the same reason a width bug hides on
x86-64.

## What is NOT diagnosed

- **Which routine in `pyeval.pas` exceeds the range.** The error names a line in
  the compiler (`pascal26:3380`), not in the source being compiled, so locating
  the offending body needs a probe I did not run.
- **What the fix is.** The diagnostic's own wording — *"the code is too large for
  this branch form"* — suggests a backend that picked a narrow encoding and has
  no relaxation step to widen it. Whether the repair is a wider form, a
  relaxation pass, or splitting the body is not established here.

The diagnostic is honest and names its own cause, which is why this is filed as
a bounded backend gap rather than an investigation.

## Provenance

Found while checking a remark from frankb-8e that a ticket's subject *"cannot be
re-measured today"* on xtensa. Reproduced independently rather than filed from
the report, and the scope turned out wider than the remark: it is not that one
measurement is blocked, it is that the frontend does not build for the target at
all. Existing mentions of the same message live in
`done/bug-a-riscv32-dce-keeps-135-more-bodies-than-xtensa-on-one-program` and in
`working/feature-a-unreferenced-class-rtti-keeps-every-method-alive`, neither of
which is a ticket for it.

## Cross-reference, and it runs both ways

`working/feature-a-unreferenced-class-rtti-keeps-every-method-alive` (frankb-8e)
tells its reader to **re-measure its headline number before quoting it** — and
if that number is a NilPy-on-xtensa measurement, it currently asks for something
that cannot be done at all. So whatever closes this ticket also unblocks that
one, and until then that instruction is unsatisfiable rather than merely
expensive.

Worth stating the direction plainly, because it is the useful half: **the RTTI
ticket is evidence about THIS ticket**, not the other way round. If its number
was taken on xtensa at `857dcdaac`, then xtensa NilPy built two days ago and
this is a two-day regression with a 1233-commit range to bisect. That is a
different and much better ticket than the one filed here. One person building
`857dcdaac` settles it.

**What would retire this section:** either a confirmation that the RTTI number
was taken on riscv32 (in which case this is a standing gap and the lead is
dead), or a build of `857dcdaac` that compiles an empty `.npy` for xtensa (in
which case reopen this at a higher priority as a regression).

## REJECTED BY ITS OWN AUTHOR, 2026-09-22 — the premise is false

    empty .npy  --target=xtensa --platform=esp                     FAIL (addi displacement)
    empty .npy  + --xtensa-abi=windowed --xtensa-long-calls        FAIL (in the WRITER, not codegen)
    empty .npy  + those two + --emit-obj                           BUILDS, 975,588 B
    print(1)    + those two + --emit-obj                           BUILDS, 975,740 B

Measured at `6fb91c73e88e`; byte-identical to frankb-8e's independent run, which
is why this is stated flatly. The middle row matters: windowed + long-calls gets
past the codegen limit, and what then fails is the IDF profile being asked for a
complete executable when its documented output is an OBJECT for the IDF link.
`--emit-obj` is the right form and it builds.

**Everything above this section is retained and is wrong.** It is left in place
rather than deleted because the measurements in it are real — they are just
measurements of one ABI, presented as measurements of a target.

## The axis error, which is the only thing worth keeping

Three "xtensa spellings" were tested and **all three share the default Call0
ABI**. The platform axis was varied; the ABI axis — the one that decides the
outcome — was held fixed and never listed. A table with three rows that all fix
the deciding axis is a table with one row.

**The floor case is what produced the confidence, and it was answering a
different question.** An empty `.npy` proves the failure is not in the user's
program. It says nothing about whether the cause is the TARGET or the FLAGS.
Excluding one axis rigorously got read as locating the cause on another, and
because the exclusion was genuinely rigorous, the location inherited its
credibility. That is the hedge-the-premise failure with premise and inference on
different axes.

Worse, the author had been *pleased* with the floor case — it was the one
quantifier checked carefully all day, after three earlier failures of exactly
that kind. **Checking the quantifier on the axis you thought of does not protect
the axis you did not.**

**The diagnostic named the right axis the whole time.** *"The code is too large
for this branch form"* is a statement about an ENCODING CHOICE. This ticket
quoted that sentence twice while concluding the target was broken. A message
naming a *form*, *mode*, *encoding* or *model* is pointing at a flag, not at a
capability.

## Before calling a target or subsystem broken

List the axes varied and the axes held fixed, and name the ones you have no
reason to trust. For a compiler invocation that is at minimum: target,
platform/profile, **ABI**, output form (`--emit-obj` vs executable), and
optimisation level.

## What survives

Nothing about a compiler defect. One coverage gap, split out at its real size:
`chore-t-the-bare-esp-runner-exercises-riscv32-only-so-xtensa-nilpy-has-no-routine-coverage`.
