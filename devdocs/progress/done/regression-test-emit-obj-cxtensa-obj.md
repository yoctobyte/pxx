---
prio: 70
track: A+S
status: done
owner: frankA
---

# regression: `--target=xtensa` on a C source selects the POSIX platform backend

- **Type:** regression. Auto-filed by the twatch watcher (host plexus)
  2026-08-27T09:35:04Z; **triaged and re-laned 2026-08-28 by Track T (face 2).**
- **Failing job:** `test-emit-obj#src:test/cxtensa_obj.c@1` (positionally
  `test-emit-obj#02` — use the `src:` selector, the index moves).
- **Standing red for ~16 hours across 13 consecutive deep-tier runs**, from
  `32fba2082684` through `aca7f699288e`. Still red in the v389 pin verify.

## Re-laned from C to A+S, and why the original guess sent it nowhere

The stub was auto-laned **C** by the "guess the track from the test source"
rule, because the test file is `test/cxtensa_obj.c`. That rule reads the
extension of the *test*, which here says nothing about the *defect*: the error
is `undefined variable (SYS_openat)` raised inside
`lib/rtl/platform/posix/platform_backend.pas`. A Track C agent opening
`cparser.inc` on that evidence finds nothing, which is a plausible reason this
sat unclaimed for a day while being red in every deep run.

**This is not a criticism of the guess** — a stub must guess or park in T's
queue. It is a note that the guess is weakest exactly when the test source and
the failure site are in different languages, and that is worth remembering the
next time a `.c`-named ticket looks like it belongs to C.

## Reproduced — 0.6s, at the PINNED v389 binary

    ./stable_linux_amd64/default/pinned --target=xtensa test/cxtensa_obj.c out.o

    pascal26:350: error: undefined variable (SYS_openat)
      in: lib/rtl/platform/posix/platform_backend.pas
    pascal26:355: error: undefined variable (SYS_read)
    pascal26:360: error: undefined variable (SYS_write)
    ... (SYS_lseek, SYS_fsync, SYS_close, SYS_rt_sigaction)

Compiling **for xtensa** pulls in the **POSIX** backend, which references Linux
syscall numbers that do not exist on that target. The undefined variables are a
symptom; the defect is one level up, in which platform backend the target
selects.

## The 2x2 that localises it — one frontend, one target

Same pinned binary, four compiles, all under a second each:

| frontend | target | result |
| --- | --- | --- |
| Pascal (`test_emit_obj.pas`) | xtensa | **ok** — 211180B code, 172 procs |
| C (`cxtensa_obj.c`) | xtensa | **FAIL** — posix backend, 7 undefined SYS_* |
| C (`cxtensa_obj.c`) | riscv32 | **ok** — 332952B code, 432 procs |
| C (`cxtensa_obj.c`) | x86-64 | `#error LONG_MAX is not the 32-bit value` — **expected**, the file's own guard |

So it is not "C is broken" and not "xtensa is broken". It is **C + xtensa
specifically**. The Pascal arm reaches the ESP platform class for the same
target; the C arm does not.

## Range — one commit, and its shape matches

The watcher narrowed this to a single commit:

    cbfdb5de8  fix(A+S): xtensa reaches the IDF profile — entry jump and profile-aware ESP class

It touches `compiler/pasparser_prog.inc` (+16), `compiler/cparser.inc` (+5),
`defs.inc`, `ir_codegen.inc`, `util.inc`, `xtensaenc.inc`, and
`builtin/builtinheap.pas`; its sibling ticket in the same commit is
*"amputate the builtin unit on the ESP class targets"*. A change that teaches
one frontend's program-setup path about the ESP class and gives the other
frontend five lines is exactly the shape the 2x2 above measures.

(The stub's original warning that the named sha `32fba2082684` "cannot be the
cause — it touches no buildable file" was correct and still applies: that is
the sha that was TESTED, the upper bound of an untested range. The cause is
`cbfdb5de8`, below it.)

## Why A+S and not C

Which platform backend a target class selects is shared machinery, so it is
filed under A per the standing rule, with the **S** tag because the class in
question is ESP.

**Stated plainly because it may go the other way:** if the fix turns out to be
entirely inside `compiler/cparser.inc`, that is Track C's file and A should
hand it over rather than edit it. What must not happen is the reverse of what
already happened — the ticket routed by the *test's* extension rather than by
the mechanism.

**And a `normalise-dont-special-case` note for whoever takes it,** offered as a
question and not a diagnosis: two frontends now answer "is this target ESP
class?" independently, and one of them is wrong. That is the two-mechanisms-
for-one-concept smell the doc names. Whether the right fix is the third line in
`cparser.inc` or moving the decision below both parsers is the owning lane's
call — but the cheap fix leaves the second mechanism standing, and the second
mechanism is the one that stays broken.

## Repro / verification

    ./stable_linux_amd64/default/pinned --target=xtensa test/cxtensa_obj.c /tmp/x.o   # must exit 0

Full job, for the record (Track T runs this; do not run a deep tier by hand):

    tools/testmgr.py --job 'test-emit-obj#src:test/cxtensa_obj.c@1'

## Gate

Track A's: `make compiler/pascal26` (the byte-identical self-host fixedpoint)
plus the one-line repro above. Cross matters here — the change is in target
class selection — so let Track T sweep the matrix against the pushed sha rather
than running it locally.

---

## RESOLVED 2026-08-29 (frankA) — the platform axis, not the profile

**Root cause is one predicate answering the wrong question**, and the ticket's
own `normalise-dont-special-case` note called it: two mechanisms decide "is
there an OS under this program", and they stopped agreeing.

`cbfdb5de8` made `TargetIsEspClass` *profile*-aware — `EspBareBoot and (XTENSA
or RISCV32)` — which is correct for the question that predicate now names
("is this bare metal, so pull no RTL"). But the C driver's default-RTL guard was
still spelled `not TargetIsEspClass`, and that branch pulls `pxxcio`. The
question **that** branch splits on is not bare-ness, it is *"does this target
have posix syscalls under it"* — and those two stopped being the same predicate
on the day of that commit.

The compiler already had the right answer, twenty lines from the damage:

```pascal
{ compiler.pas:1553 }
if EspBareBoot or (TargetArch = TARGET_XTENSA) then TargetPlatform := PLATFORM_ESP
```

— *"xtensa has no hosted leg"*, said in the platform derivation and not consulted
by the guard. So plain `--target=xtensa` derived `PLATFORM_ESP` and pulled the
**posix** PAL anyway.

### Fix

`compiler/cparser.inc`, both arms of the C default-RTL split, from
`TargetIsEspClass` to `TargetPlatform = PLATFORM_ESP`. Track A machinery in
Track C's file; A holds C this session, so it is self-resolved rather than
handed over (combined-track rule). No change in `compiler.pas`, `util.inc` or
`builtinheap.pas`.

The widening is deliberate and is the normalisation: xtensa under IDF now takes
the ESP-class arm (on-demand softfloat from a token scan) instead of the hosted
arm, which is what it always needed — riscv32, genuinely dual-role, keeps posix
unless the profile says otherwise.

### `SYS_openat` was the second error, not the first

Worth recording because it sent the original triage to the wrong file. The
reported symptom is seven undefined `SYS_*` in
`lib/rtl/platform/posix/platform_backend.pas`, which reads as a PAL-selection
bug — and `AddDefaultPasUnitDirs` (compiler.pas) does guard the posix PAL dir on
the same stale predicate, so that reading is not wrong, just not the cause.
Measured: supplying the ESP PAL by hand gets *past* all seven and then dies at

```
pascal26:329: error: target xtensa: unsupported node in IR codegen: syscall
  in: lib/rtl/pxxcio.pas
```

`pxxcio.__pxx_exit` is a raw `exit_group` syscall and **the xtensa backend has
no syscall lowering at all**. So no PAL choice could have fixed this: the defect
is that the hosted C RTL is pulled onto a target that cannot express a syscall.
Fixing the PAL dir alone would have moved the error, not removed it — which is
what a same-shaped fix looks like from the outside.

`AddDefaultPasUnitDirs`' stale guard is therefore **still there and still
wrong**, merely unreachable on this path now that nothing pulls the PAL. Filed
as `bug-a-the-posix-pal-dir-is-added-on-esp-platform-targets` rather than fixed
here: it needs the esp PAL to be added as the counterpart, which changes what
`riscv32 --platform=esp` resolves and is Track S's call.

### Verified

| arm | before | after |
| --- | --- | --- |
| C / xtensa | 7x undefined `SYS_*` | **ok** — 354B, 2 procs |
| C / riscv32 | ok, 432 procs | ok, 432 procs (unchanged) |
| C / x86-64 | the file's own `#error` | unchanged |
| Pascal / xtensa | ok, 172 procs | ok, 172 procs |
| hosted C `printf` | ok | ok, runs, 613 procs |

All six of the Makefile job's `readelf` assertions pass on the xtensa object:
REL, `Xtensa`, `FUNC GLOBAL DEFAULT 1 app_main`, `UND ext_notify`,
`R_XTENSA_32`, plus the riscv32 pair.

Gate: `make compiler/pascal26` — `converged after 1 round(s)`, self-host
fixedpoint verified at `e469b947f167`. `tools/gate.sh quick` green.
Cross matters here; Track T sweeps the matrix against the pushed sha.

## Log
- 2026-08-29 — resolved, commit PENDING-COMMIT.
