---
prio: 70
track: A
type: bug
status: new
found: 2026-09-22
found-by: frankh-c0
owner: ""
blocked-by: []
summary: "NILPY CANNOT TARGET XTENSA AT ALL, AND THE FLOOR CASE IS AN EMPTY FILE. A zero-byte `.npy` refuses with `pascal26:3380: error: target xtensa: addi immediate displacement 128 is outside the encodable range -128..127; the code is too large for this branch form`. Because the empty program fails, nothing a user writes can avoid it -- this is not a construct that trips it, it is the NilPy runtime (pyeval.pas) failing to encode for this backend. SCOPE, measured one row each: all three xtensa spellings fail (`--target=xtensa` alone, `+ --platform=esp`, `+ --esp-profile=bare`); riscv32 builds the same files clean; and a Pascal `program p; begin end.` and a C `int main(void){return 0;}` BOTH compile fine on the identical xtensa flags, so it is NilPy-specific and not a broken xtensa backend in general. NOT TODAY'S WORK -- the PINNED compiler refuses at the same line with the identical message. That is ALL that is established: this ticket first said `pre-existing, not a regression` and the second half was an overstatement, corrected the same day. Whether xtensa NilPy EVER built is unmeasured, and there is a concrete lead saying it may have: frankb-8e's RTTI ticket carries a headline number it describes as measured on a NilPy ESP target at 857dcdaac, which is 2026-09-20 and 1233 commits back. If that measurement really did require building NilPy for xtensa, this is a REGRESSION inside a two-day window and therefore bisectable and far cheaper to fix than a standing gap. Nobody has built 857dcdaac to check, and the phrase in that ticket is ambiguous about which chip it names (its directory is nilpy-c3, and c3 is riscv32), so this is recorded as a LEAD and not as a finding. WHY IT MATTERS more than the line count suggests: xtensa is the PRIMARY ESP target per the S-lane rule (riscv32 merely also works), so the entire NilPy-on-ESP32-S3 path is closed while esp32c3 is fine -- and that asymmetry is invisible to anyone measuring on c3, which is the default chip in tools/esp_run_bare.sh. The diagnostic is honest and names the cause (a branch form chosen too narrow to reach), so this is a backend encoding/relaxation gap rather than a mystery. NOT DIAGNOSED BEYOND THAT: I did not find which routine in pyeval.pas exceeds the range, nor whether the fix is a wider branch form, a relaxation pass, or splitting the offending body."
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
