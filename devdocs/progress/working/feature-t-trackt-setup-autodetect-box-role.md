---
summary: "trackt's profile wizard asks instead of detecting, and its NON-INTERACTIVE default is 'dedicated' — so a Pi provisioned headless over ssh enrols itself as a full-matrix fuzzing box, the exact opposite of its role"
type: feature
track: T
prio: 70
status: working
owner: claude@xeon
---

# `trackt setup` should detect the box and default to the right role

- **Type:** feature (Track T, provisioning) — **Track T**
- **Opened:** 2026-08-01. Prerequisite for
  [[feature-t-host-roles-native-vs-qemu-topology]] — enrolling arm boxes is only
  cheap if setup gets the role right by itself.

## The bug hiding in the current wizard

`configure_profile()` (`tools/trackt.py:615`) reads `nproc` and `MemTotal`, then
**prints them at the user and asks**. Both defaults are `dedicated`:

- bare Enter at the prompt → `dedicated`
- **no TTY → `dedicated`, unconditionally**

A Raspberry Pi is provisioned *headless over ssh* — very likely non-interactive.
So the most probable deployment path for the most constrained box in the fleet
enrols it as: full matrix, all cores, idle opt + bench + **fuzzing**, web server
on. That is the precise opposite of its intended role, and nothing warns.

The data needed to decide is already read two lines earlier and then only used
for a printout.

## The right discriminator is ARCHITECTURE, not core count

The natural framing is "crippled vs powerhouse", but that under-describes it. A
non-x86_64 box's unique value is that **it can run its own architecture
natively, which QEMU cannot verify** — that is the whole reason to own one. A
fast ARM server (Ampere, Graviton) should still be native-only in *role*, and a
weak x86 box makes a poor oracle no matter how slow it is; it is just a slow
runner. So:

| detected | role |
| --- | --- |
| `uname -m` != x86_64 | **native-oracle** — own-arch native jobs only, no cross matrix, no idle work |
| x86_64, no desktop session, many cores + RAM | **dedicated** — the matrix |
| x86_64, desktop session present, or few cores | **limited** — polite: leave cores, slower cadence, no fuzz |

Signals all cheaply available: `platform.machine()`, `os.cpu_count()`,
`MemTotal`, `/proc/device-tree/model` (contains "Raspberry Pi"), and a desktop
check (`$XDG_CURRENT_DESKTOP`, or a `loginctl` session of type x11/wayland).

`restricted` already sets `tier: "native"`, so it is most of the native-oracle
profile — what it lacks is a job-class allowlist (that gap is the sibling
ticket's item 1).

## MEASURED — and the constraint is the opposite of what the estimate says

Written first from `testmgr`'s own figure, then measured, and the measurement
wins. Recorded in full because the wrong number would have shaped which boxes
get bought and how they are provisioned.

`testmgr` estimates the selfhost job at **1200 MB** (`"selfhost": {"est_mem":
1200 << 20}`). Actual peak RSS on x86_64, self-hosted binary at `19ee697d3`:

| workload | peak RSS |
| --- | --- |
| self-compile (`compiler.pas` + all `.inc`, 5.6 MB of source) | **156 MB** |
| `test/hello.pas` | **24 MB** |

So the estimate is **~8x the real cost**. The fixedpoint compiles twice but
SEQUENTIALLY, so peak stays ~156 MB, not double.

Consequences, all the opposite of the first draft of this section:

- A **512 MB arm32 Pi should self-compile fine.** arm32 is ILP32, so the
  pointer-heavy structures get *cheaper*, not dearer — the direction is
  favourable, though this number is x86_64 and wants confirming on real
  hardware before it is relied on.
- Ordinary test-suite compiles are ~24 MB, so a small Pi runs the suite
  comfortably. That much was already expected.
- The thing to fix is therefore **the estimate, not the Pi**: at 1200 MB,
  `est_mem` will exclude or serialise selfhost on boxes that could run it
  perfectly well, and it under-packs concurrency on big ones. Filed as its own
  item — see below.

Note the `bss=151388300B` in every build line is a ~151 MB *reservation* of
static arrays, not resident cost: only touched pages land in RSS, which is why
`hello.pas` sits at 24 MB while a self-compile reaches 156 MB.

**Follow-up for T:** re-derive `est_mem` for the `selfhost` class from
measurement rather than a guess, and check the other job classes' estimates the
same way — an 8x error in one suggests the others were not measured either.

## Asked for

1. Detect, then **propose** — print what was found and what role follows, with
   Enter to accept: `detected aarch64 Raspberry Pi 5, 4 cores, 8192 MB →
   native-oracle [Enter to accept, or choose 1/2/3]`.
2. **Non-interactive uses the detection**, never a blanket `dedicated`.
3. Always print the chosen role and the resulting caps. Silent auto-config is
   worse than a wrong prompt, because nobody notices it.
4. Keep every profile fully overridable — the conf is still written in full and
   `trackt config <key> <val>` still tunes it.
5. Optional, mentioned as desirable: a `nice_level` knob so a shared workstation
   runs at low priority rather than merely using fewer cores.

## Gate

On each of an x86_64 workstation with a desktop session, a headless many-core
x86_64 box, and an arm64 Pi, `trackt setup` **with no TTY** writes the intended
profile unprompted, prints what it detected and why, and a small-RAM Pi does not
get a selfhost job it cannot run.
