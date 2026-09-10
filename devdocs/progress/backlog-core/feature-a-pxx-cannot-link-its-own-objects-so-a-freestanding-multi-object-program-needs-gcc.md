---
slug: feature-a-pxx-cannot-link-its-own-objects-so-a-freestanding-multi-object-program-needs-gcc
title: "pxx cannot link its own .o files, so the only freestanding build shape is a unity"
track: A
prio: 70
type: feature
blocked-by: []
status: new
created: 2026-09-10
found: 2026-09-10
found-by: frank-user, answering the owner's question
owner: ""
summary: "MEASURED 2026-09-10 at 546d4dcbd305. pxx writes static, libc-free ELF executables with NO external linker -- there is no shell-out to ld, gcc or cc anywhere in compiler/**, and `lib/crtl` is our own C library, so a C `#include <stdio.h>` resolves to our header. Proof, same source both sides: the busybox rung-1 unity (25 TUs, tools/busybox_diff.sh --applets cat) built by pxx is 539008 bytes, `statically linked`, `not a dynamic executable`, and cats a file; the gcc oracle built from the identical unity is 65888 bytes, `dynamically linked, interpreter /lib64/ld-linux-x86-64.so.2`, needing libc.so.6. THE GAP IS THE OTHER DIRECTION: pxx cannot CONSUME an object. `pascal26 a.o b.o out` answers `pascal26:1: error: unexpected character` -- it parses the .o as source; there is no link mode and --help lists none. So a program too large for one translation unit cannot be built freestanding by pxx alone: busybox's real shape (`--separate`, 400-521 objects) emits every object with --emit-obj and then links with a plain `gcc -o out obj/*.o` (tools/busybox_diff.sh:1429), which is what makes that binary dynamic. The external dependency is a LINKER, not a library. Two routes: invoke `ld` over our own objects plus crtl (an external tool, no external library -- the owner has said make and link steps are fair game), or a pxx --link mode, which is the cleaner end state since elfwriter.inc already emits static executables. NOT the same work as [[meta-a-pxx-produces-linkable-code]], which is about being linked INTO something else; this is about being the linker. The one recorded obstacle is not one: mkkiosk.sh:80 says -static is refused because `errno is a non-TLS weak .bss object in every pxx object and ld refuses it against libc.a's TLS one` -- that is about linking our objects AGAINST glibc, and dropping glibc removes the conflict."
---

# pxx cannot link its own objects

## What the owner asked, and the answer

2026-09-10: *"can we compile busybox so, that it does not depend on any existing
external libraries. that we have to run make files and link steps is fair game,
i think"*

**For a unity build: already yes, today.** For busybox's real build shape: no,
and the missing piece is a linker rather than a library.

## Measured, not inferred

Compiler at `546d4dcbd305`, tree `08d8d5170`.

**pxx shells out to nothing.** A grep of `compiler/*.pas` and `compiler/*.inc`
for any invocation of `ld`, `gcc`, `cc` or `system()` returns no linker call.
`elfwriter.inc` writes the executable.

**Both ends of the contrast, from one source file.** The rung-1 unity
(`tools/busybox_diff.sh --applets cat`, 25 translation units, generated into the
work dir) built two ways:

| | built by | size | `file` | `ldd` |
| --- | --- | --- | --- | --- |
| subject | `pascal26 -I. -Iinclude -Ilibbb busybox_unity.c out` | 539008 | ELF 64-bit LSB executable, **statically linked** | **not a dynamic executable** |
| oracle | `gcc` (the harness's own) | 65888 | ELF 64-bit LSB **pie** executable, **dynamically linked** | libc.so.6, ld-linux-x86-64.so.2 |

The subject runs: `./pxx_busybox cat t.txt` prints the file.

**And the gap.** Two translation units, each compiled to an object by pxx
(`--emit-obj`, both `ok:`), then handed back to pxx to link:

```
$ pascal26 a.o b.o out
pascal26:1: error: unexpected character
```

It is parsing the object as source text. `--help` lists `--emit-obj` and
`--function-sections` and no consumer for what they produce.

## Why this is the whole of the busybox answer

`--separate` — the mode that builds busybox the way busybox does, one object per
TU and a real link — emits all 400-521 objects with pxx and then links with
`gcc -o out obj/*.o` (`tools/busybox_diff.sh:1429`). That gcc call is the only
reason the 394-applet binary is dynamic. It was chosen so both sides of the diff
are the same program, not because pxx could not have produced the objects.

So the dependency to remove is **the linker**, and there are two ways:

1. **Use `ld` directly** over our objects plus our own crtl. An external *tool*,
   no external *library*. This is what the owner's "link steps are fair game"
   already permits, and it is the cheap one to measure first.
2. **Teach pxx `--link`** — consume its own `.o`s and run the ELF writer it
   already has. The end state, and it makes the claim unqualified.

## What is NOT in the way

`tools/mkkiosk.sh:80` records that `-static` is unavailable because *"errno is a
non-TLS weak .bss object in every pxx object and ld refuses it against libc.a's
TLS one"* ([[bug-a-errno-is-one-global-across-all-threads-so-a-thread-reads-another-threads-failure]]).
That is a conflict between our objects and **glibc's** `libc.a`. It cannot arise
in a link that contains no glibc. It is an argument for this ticket, not against
it.

## Relation to the neighbours

- [[meta-a-pxx-produces-linkable-code]] — the other direction: our objects being
  consumed by someone else's linker. Nearly closed. Wire to it, do not merge:
  an object that gcc can link says nothing about pxx being able to link one.
- [[feature-a-every-emit-obj-object-links-its-own-full-copy-of-crtl-so-n-objects-cost-n-runtimes]]
  — a pxx-driven link is where that duplication would be cheapest to fix, since
  both ends would then be ours.
- [[feature-busybox-kiosk-selfhosting-target]] — the consumer. Its `--separate`
  rung is green through gcc; this is what would make it freestanding.

## First measurement for whoever takes it

Link the busybox `--separate` objects with `ld` and no glibc:
`ld -static -o out obj/*.o <crtl objects> ` with our own entry. Whether that
link resolves at all — and what it is missing — is one run, and it decides
whether route 1 is a morning or a project.

## MEASURED 2026-09-10: `ld` ALREADY DOES THIS. THE GAP IS A crt0, NOT A LINKER.

Route 1 from the ticket above was run, and it works. At `49489e5ca437`:

```
$ pascal26 --emit-obj -Ilib/crtl/include -Ilib/crtl/src a.c a.o    # main(), calls twice()
$ pascal26 --emit-obj -Ilib/crtl/include -Ilib/crtl/src b.c b.o    # twice()
$ nm -u a.o
                 U twice
```

**One undefined symbol in the whole object, and it is the other translation
unit's function.** Nothing from libc. The runtime is already in there, exported
weak — `exit`, `_exit`, `_Exit`, `atexit` all present as `W`.

```
$ ld -static -e main -o out a.o b.o      # no libc, no crt files, no -L
$ file out   -> ELF 64-bit LSB executable, statically linked
$ ldd out    -> not a dynamic executable
$ ./out      -> 42          (correct), then SIGSEGV
```

The link succeeds and the program computes the right answer. The segfault is the
whole remaining gap: entering at `main` leaves no exit path, so it returns into
nothing. **pxx's ELF writer synthesises an entry stub for an EXECUTABLE (entry
`0x4000e8` in `compiler/pascal26`) and does not emit one into an object.**

### Three lines close it

```c
extern int main(int argc, char **argv);
extern void exit(int);
void pxx_entry(void) { exit(main(0, (char **)0)); }
```

compiled with `--emit-obj` like any other TU, then:

```
$ ld -static -e pxx_entry -o out crt0.o a.o b.o
$ ./out   -> 42
$ echo $? -> 0
```

**Statically linked, `not a dynamic executable`, correct output, clean exit, no
glibc anywhere in the link.**

### What this changes about the ticket

- **Route 1 is not a project; it is done as a mechanism.** "pxx cannot link its
  own objects" is true and **no longer the blocker it reads as** — `ld` links
  them, and `ld` is an external *tool*, not an external *library*, which the
  owner has said is fair game.
- **The real work is a proper crt0**, which the probe above fakes: it passes
  `argc=0, argv=NULL`. A real one must pass the kernel's stack arguments through
  (argc, argv, envp) and should come from pxx rather than from a hand-written C
  file — the ELF writer already contains this logic for executables.
- **Route 2 (a pxx `--link` mode) stays the better end state** and is now clearly
  a convenience rather than an enabler: it would remove the `ld` invocation and
  the separate crt0 step, not unlock anything.
- **SCALE IS UNMEASURED AND IS THE REAL RISK.** Two objects is not 521. The known
  hazard has a name and a history in this repo: every `--emit-obj` object carries
  its own full copy of crtl
  ([[feature-a-every-emit-obj-object-links-its-own-full-copy-of-crtl-so-n-objects-cost-n-runtimes]]),
  exported weak, and the weak export is precisely what stopped 116 duplicate
  symbol collisions at `243137302`. Whether 521 weak copies resolve as cleanly as
  2 is the question, and at pin v399 `--separate --pinned` failed on exactly that
  (`multiple definition of abort, abs, accept, …`). A busybox-scale `ld` run is
  in flight.
