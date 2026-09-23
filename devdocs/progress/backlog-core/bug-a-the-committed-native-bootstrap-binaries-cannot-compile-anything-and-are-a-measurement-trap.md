---
slug: bug-a-the-committed-native-bootstrap-binaries-cannot-compile-anything-and-are-a-measurement-trap
track: A
type: bug
prio: 55
status: open
owner: ""
created: 2026-09-24
found-by: frank (routed by frank-coordinator after it cost the fleet an evening)
blocked-by: []
summary: "`native/pxx-{aarch64,arm32,i386}` are committed binaries built 2026-06-24 with that era's compiler, and ALL THREE now fail to compile a two-line hello: `pascal26:338: error: unexpected character ()`, identically on every arch, with `--no-default-rtl` making no difference. So the documented promise they exist for -- a bare `git clone` plus `./install.sh` on aarch64/arm32/i386 needing no FPC and no make (install.sh:76 selects native/pxx-$HOSTARCH) -- IS BROKEN, and has been for an unknown part of the 1200 commits that have touched `lib/rtl` and `compiler/builtin` since. THE STALENESS WAS KNOWN AND THE REMEDY WAS RECORDED IN THE WRONG PLACE: feature-native-arch-binaries (done/, June) ends with `these binaries are committed artifacts and go stale on a compiler change; rebuild them when re-pinning (a make target to regenerate is a follow-up)`. There have been 274 pins since and no rebuild, and no such make target exists -- an instruction parked in done/, which CLAUDE.md itself says is a historical record, not maintained and not instructions. SECOND AND INDEPENDENT COST: they are a MEASUREMENT TRAP. Each is ONE RWE LOAD with memsz >> filesz (aarch64 0x462c60 vs 0x8690f0b) where a fresh build at HEAD emits THREE LOADs with the code segment R and filesz == memsz and the BSS moved out of it, so llvm-objdump synthesises a pseudo-section spanning memsz and reads off the end of a shorter file. Two seats measured llvm-objdump honestly and reached opposite conclusions purely because one tested this June file and the other a fresh build. NOT A DELETION: install.sh depends on them, so the fix is to REGENERATE and to make regeneration part of pinning, or to withdraw the no-FPC claim deliberately. THE CONDITION THAT RETIRES IT: each committed native binary compiles and runs a hello for its own arch under qemu, asserted by a row that runs, plus a named mechanism that reproduces it at pin time."
---

# The committed native bootstrap binaries cannot compile anything, and they are a measurement trap

Routed by frank-coordinator after the llvm-objdump investigation cost an
evening. Two independent problems share one cause — the files are three months
old — and they have different owners and different fixes, so they are stated
separately below.

## Measured 2026-09-24, at HEAD

```
$ qemu-aarch64 native/pxx-aarch64 --target=aarch64 hello.pas out
pascal26:338: error: unexpected character ()
```

| binary | `--version` | compiles `program h; begin WriteLn(42); end.` |
| --- | --- | --- |
| `native/pxx-aarch64` | `unknown option: --version` | **NO** — `pascal26:338` |
| `native/pxx-arm32` | `unknown option: --version` | **NO** — `pascal26:338` |
| `native/pxx-i386` | `unknown option: --version` | **NO** — `pascal26:338` |
| `compiler/pascal26` (HEAD) | `pxx (pascal26) — self-hosting Pascal-dialect compiler` | yes |

All three fail at the **same line** with the **same message**, and
`--no-default-rtl` does not change it.

**The diagnostic carries no file name, which in this compiler means the error was
raised inside an IMPORTED unit** — so 338 is a line in something the old binary
pulled in, not in the two-line program. **I have NOT narrowed which unit, and it
is not needed to act**: `lib/rtl` and `compiler/builtin` have taken **1200
commits** since these binaries were built, and a June binary paired with
September sources is the documented incoherent pairing, not a puzzle. (CLAUDE.md:
the pin and `lib/rtl` are one artefact and the pair is only coherent within one
era.) Whoever regenerates them should not spend time on line 338 either.

## Problem 1 — the promise they exist for is broken

`install.sh:76` is `NATIVE="$ROOT/native/pxx-$HOSTARCH"`. The June ticket
[[feature-native-arch-binaries]] states the deliverable:

> *So a bare `git clone` + `./install.sh` on aarch64/arm32/i386 needs no
> FPC/make.*

That is currently false on all three arches. **How long it has been false is not
established here** — it needs a bisect against the binaries, which nobody has a
reason to run; what is established is that it is false now.

## Problem 2 — they are a measurement trap, and this one already cost a night

| | segments | code segment |
| --- | --- | --- |
| `native/pxx-aarch64` (June) | **ONE** LOAD, `RWE` | filesz `0x462c60`, memsz `0x8690f0b` |
| `native/pxx-arm32` (June) | **ONE** LOAD, `RWE` | filesz `0x5c4abc`, memsz `0x863abdf` |
| `native/pxx-i386` (June) | **ONE** LOAD, `RWE` | filesz `0x2e577e`, memsz `0x835b89f` |
| fresh build at HEAD (all three arches) | **THREE** LOADs | code is `R` with **filesz == memsz**; BSS in the RW segment (`0x38` vs `0x82d0`) |

`memsz >> filesz` on the segment carrying the code is the discriminator.
**llvm-objdump synthesises a pseudo-section spanning memsz and reads off the end
of a shorter file**, so it fails on the June binaries and succeeds on a fresh
build — on the same host, at the same tool version.

**Two seats measured llvm-objdump honestly and reached opposite conclusions**,
and the entire disagreement was that one tested the committed file and the other
a fresh build.

**Two earlier diagnoses of that were WRONG and are recorded here so they are not
re-derived:** *"llvm-objdump cannot read a sectionless image at any version"*
(withdrawn — sectionlessness is not the discriminator) and *"llvm-objdump-20 is
too old"* (withdrawn — version is not the discriminator either; llvm-objdump-21
fails on the August file and succeeds on a fresh one).

**What made it resolvable in an evening rather than a week is worth copying:**
one of the two reports said that its subject was *the committed file* and not a
fresh build. The **vintage appearing in one report** is the whole reason the two
measurements could be reconciled at all. So when reporting a measurement against
anything in `native/`, say so — it is not the same artefact as a build.

`tools/aarch64_cabi_prologue_probe.sh` already carries this in its header
(around :108 and :123). That is the right place for it and it is not enough on
its own: a note inside one probe script is invisible to the next seat that
reaches for `native/pxx-aarch64` as a convenient aarch64 binary.

## Why it went three months, which is the part that generalises

The June ticket **recorded the staleness and prescribed the remedy**:

> *NOTE: these binaries are committed artifacts and go stale on a compiler
> change; rebuild them when re-pinning (a `make` target to regenerate is a
> follow-up).*

- **274 pins** have happened since 2026-06-24. The rebuild happened **zero**
  times.
- **No such make target exists** — `grep -nE '^native|native/pxx' Makefile`
  returns nothing. The follow-up was never filed as a ticket either.

**The instruction was parked in `done/`, which is the one place guaranteed not to
be read at pin time** — CLAUDE.md says outright that resolved tickets and `done/`
write-ups are historical records of what a past session ran, *not instructions,
not maintained*. So a correct, prescient note was written into the file whose own
precedence rule says nobody must obey it. **An instruction that recurs belongs in
the recurring procedure, never in the ticket that discovered the need for it** —
the pin path, or a target the pin path calls.

That is the transferable finding, and it is not about these three files.

## What to do — and deletion is NOT it

`install.sh` depends on them, so deleting them removes a documented install path.
Three options, and the choice is a real one:

1. **Regenerate now and wire regeneration into pinning.** Matches the June
   intent. Cost: cross-building three compilers on every pin, which the pin
   budget (~35s) will notice — measure before promising it.
2. **Regenerate now, and add a CHEAP staleness GUARD rather than a rebuild** —
   a row that fails when `native/pxx-*` cannot compile a hello for its arch
   under qemu. The binaries then go stale loudly instead of silently, and
   whoever hits the row decides. Cheaper per pin and it is the option that fixes
   *Problem 2* as well, because a loud stale binary is not a trap.
3. **Withdraw the no-FPC claim deliberately** and delete the binaries, updating
   `install.sh` and the June ticket's deliverable. Legitimate if nobody installs
   on those hosts — but that is a question about who uses this, so it is not
   mine to decide.

**Option 2 is my recommendation** and it is the one that makes the other two
safe to defer.

## Positive control for whoever fixes this

A row that asserts each `native/pxx-<arch>` **compiles AND runs** a hello for its
own arch under qemu. Not `--version`, and not that the file exists: the current
binaries would pass an existence check and a `--version` check is exactly what
they already fail for an unrelated reason. Assert the program's OUTPUT — see the
playbook on an exit code standing in for the property.

## Related

- [[feature-native-arch-binaries]] — June, `done/`. The deliverable and the
  never-actioned note.
- `tools/aarch64_cabi_prologue_probe.sh` — carries the `memsz >> filesz`
  mechanism in its header.

# Umbrella

[[meta-a-pxx-produces-linkable-code]]
