---
summary: "trackt's profile wizard asks instead of detecting, and its NON-INTERACTIVE default is 'dedicated' — so a Pi provisioned headless over ssh enrols itself as a full-matrix fuzzing box, the exact opposite of its role"
type: feature
track: T
prio: 70
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

## Hard constraint that must be encoded, not discovered

`testmgr` estimates the **selfhost job at 1200 MB** (`"selfhost": {"est_mem":
1200 << 20}`). The `restricted` profile caps memory at **half the box**
(`_mem_frac: 0.5`). So:

- a 1 GB Pi cannot run the selfhost fixedpoint **at all**
- a 2 GB Pi capped to 1 GB cannot either

A native-oracle profile must therefore exclude selfhost from its job set on
small boxes rather than let it OOM or thrash — and the wizard should say so at
setup time instead of leaving it to be discovered as a mysterious red.

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
