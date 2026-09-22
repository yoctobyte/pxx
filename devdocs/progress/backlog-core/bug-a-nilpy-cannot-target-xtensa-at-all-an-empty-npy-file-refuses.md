---
prio: 70
track: A
type: bug
status: new
found: 2026-09-22
found-by: frankh-c0
owner: ""
blocked-by: []
summary: "NILPY CANNOT TARGET XTENSA AT ALL, AND THE FLOOR CASE IS AN EMPTY FILE. A zero-byte `.npy` refuses with `pascal26:3380: error: target xtensa: addi immediate displacement 128 is outside the encodable range -128..127; the code is too large for this branch form`. Because the empty program fails, nothing a user writes can avoid it -- this is not a construct that trips it, it is the NilPy runtime (pyeval.pas) failing to encode for this backend. SCOPE, measured one row each: all three xtensa spellings fail (`--target=xtensa` alone, `+ --platform=esp`, `+ --esp-profile=bare`); riscv32 builds the same files clean; and a Pascal `program p; begin end.` and a C `int main(void){return 0;}` BOTH compile fine on the identical xtensa flags, so it is NilPy-specific and not a broken xtensa backend in general. PRE-EXISTING, not a regression: the PINNED compiler refuses at the same line with the identical message, so this is not any of today's work. WHY IT MATTERS more than the line count suggests: xtensa is the PRIMARY ESP target per the S-lane rule (riscv32 merely also works), so the entire NilPy-on-ESP32-S3 path is closed while esp32c3 is fine -- and that asymmetry is invisible to anyone measuring on c3, which is the default chip in tools/esp_run_bare.sh. The diagnostic is honest and names the cause (a branch form chosen too narrow to reach), so this is a backend encoding/relaxation gap rather than a mystery. NOT DIAGNOSED BEYOND THAT: I did not find which routine in pyeval.pas exceeds the range, nor whether the fix is a wider branch form, a relaxation pass, or splitting the offending body."
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

## Pre-existing, not a regression

    HEAD    3854783c605a / 5f986d67044a : FAIL
    PINNED  stable_pinned               : FAIL, same line, same message

The pinned compiler refuses identically, so this predates today's work and is
not attributable to the `--dce` default, `523833fde`, or `324d668b8`.

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
