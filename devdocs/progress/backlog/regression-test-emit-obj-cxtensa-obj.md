---
prio: 70
track: A+S
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
