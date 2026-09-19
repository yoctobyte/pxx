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
summary: "ROUTE 1 MEASURED AND IT WORKS AT SCALE (2026-09-16, HEAD, binary b7f9f80c7d80): A 257-APPLET pxx-BUILT BUSYBOX LINKS AND RUNS WITH NO LIBC AND NO CRT. Over the 400 objects `busybox_diff.sh --separate` produces at 258 applets, pxx emits exactly TWO relocation types (R_X86_64_PC32 710066, R_X86_64_64 13891) over a fixed section set, and of 780 undefined references exactly ONE was unsatisfied by another object in the set: pivot_root, which glibc carries a stub for and the ordinary `gcc -o out obj/*.o` link therefore resolved SILENTLY -- the gap was invisible until a link was asked to use no library at all. Added to lib/crtl (sys/mount.c, six lines over the syscall bridge, Track C owns crtl). With it, `ld -static -nostdlib` links all 400 objects rc=0 with ZERO diagnostics and the result runs: cat, echo, sort, uniq, seq, tr, wc, basename, dirname, md5sum and sha256sum all correct (md5 and sha256 of 'abc' match the published vectors), `--list` prints 257 applets, `not a dynamic executable`. SO THE `gcc` IN THE NORMAL LINK IS A LINKER DRIVER AND THE GLIBC IS NOT LOAD-BEARING -- one symbol was, and it now is not. WHAT REMAINS IS THE PROCESS-ENTRY CONTRACT, NOT SYMBOL RESOLUTION: pxx objects define `main` and no `_start` because --emit-obj targets a toolchain supplying crt1.o. BOTH CITATIONS IN THIS SENTENCE WERE STALE BY 2026-09-19 AND ONE WAS WRONG IN SUBSTANCE (re-checked, frankB): elfwriter.inc:472 is the DYNAMIC INTERPRETER path (/lib/ld-linux.so.2), and elfwriter.inc synthesises no `_start` at all -- a pxx EXECUTABLE sets e_entry directly and `_start` appears only as a map-file label, so the stub SUPPLIES an entry the object path never had rather than joining two halves that already existed; cparser.inc:13150 is now __thread warning prose. Find them by name, not by line. A 30-line stub joining them (tools/pxxcrt_x86_64.S) closes it. Repeatable as `tools/busybox_diff.sh --freestanding`, GREEN, byte-identical to the gcc oracle over 29 cases with two controls proven to FIRE (a gcc link has PT_INTERP; a stub-less link has no _start). ROUTE 2 (a pxx --link mode) IS STILL THE END STATE and removes the assembler too. **ITS SIZE WAS UNDERSTATED HERE AND IS CORRECTED 2026-09-19 (frankB): \"two relocation types and a fixed section list is a small --link mode, not a linker project\" was wrong twice.** (1) TWO IS A CENSUS OVER THE BUSYBOX OBJECTS, NOT A CAPABILITY OF THE EMITTER: elfwriter.inc emits THREE x86-64 types -- R_X86_64_64 (1), R_X86_64_PC32 (2) and R_X86_64_32S (11) -- and the third simply did not occur in that corpus, so a --link mode scoped to the census is correct on the program that motivated it and wrong on the first one that is not it. The population was honestly stated and still answered the wrong question: the corpus that MOTIVATES a feature is not the domain the feature must COVER. (2) pxx HAS NO ELF READING CODE AT ALL -- grepped for every shape of it; elfwriter.inc's 6838 lines are entirely writing. So Route 2 is not the other half of something that exists: it is an object READER, a symbol-table merge, a section layout over inputs we did not lay out, relocation application, and only then the executable writer we already have. **Whoever takes this starts at the READER, and its oracle is readelf against a real pxx-emitted .o -- an external instrument that fails differently from anything we wrote. A reader that cannot enumerate symbols and relocations correctly makes every later stage unfalsifiable.** GOAL 5 DOES NOT WAIT ON THIS: Route 1 makes the no-libc claim true, is guarded by a test-core row as of 027443610, and the unity build already has pxx linking it itself. Route 2 is the separate-objects path. Whoever takes this starts at \"write the entry stub\", not \"write a linker\". **ROUTE 1 RE-MEASURED AND NOW GUARDED 2026-09-19 (frankB), origin 696f13d1f / compiler 8f8a089c6812: GREEN at the DEFAULT rung -- 2 applets, 28 translation units, 29 cases, byte-identical to the gcc oracle, no PT_INTERP, entry 0x401000 == _start, no libc.** THE 258-APPLET / 400-OBJECT SCALE ROW ABOVE WAS **NOT** RE-DERIVED and keeps its own tree (2026-09-16, b7f9f80c7d80): reconstructing that applet set needs a generated list from a completed build, so the two rows measure different populations and neither may be quoted for the other. **The bigger finding is that none of this was wired into anything**: busybox_diff.sh was referenced from the Makefile NOWHERE, so every part of the freestanding claim could have regressed silently and only a hand re-run would have noticed. A test-core row now runs `--freestanding`, requires the script's own BUSYBOX-DIFF-COMPLETE token AND the GREEN line AND the no-PT_INTERP control line (a token alone says the script reached its end, not that the comparison passed), and LOUDLY SKIPS when library_candidates/busybox is absent. All three assertions were proven to fire by removing each line from a real green log. STATUS was `new` with owner empty while Route 1 was landed and measured -- the summary had been kept current and the status field had not, which is how a p70 reads as unstarted work and gets dispatched as such. --- ORIGINAL (2026-09-10, 546d4dcbd305): pxx writes static, libc-free ELF executables with NO external linker -- no shell-out to ld/gcc/cc anywhere in compiler/**. THE GAP IS THE OTHER DIRECTION: pxx cannot CONSUME an object. `pascal26 a.o b.o out` answers `pascal26:1: error: unexpected character` -- it parses the .o as source. The external dependency is a LINKER, not a library."
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

## AND IT SCALES TO A REAL PROGRAM: A FREESTANDING BUSYBOX RUNS (2026-09-10)

`tools/busybox_diff.sh --separate --applets "cat echo"` produced **28 objects,
one per translation unit, every one emitted by pxx.** Then, with no libc and no
glibc crt files:

```
$ ld -static -e main -o bb obj/*.o
LINKED — no duplicate symbol errors at all
```

**The collision hazard did not fire.** That is the specific thing that killed
`--separate --pinned` at v399 (`multiple definition of abort, abs, accept, …`),
and at 28 objects with a post-`static`-emits-LOCAL compiler, 28 weak copies of
crtl resolve cleanly.

With a six-line entry stub reading the kernel's stack (`argc` at `(%rsp)`, `argv`
at `8(%rsp)`, then `call main`, `call exit`):

```
$ ld -static -e pxx_start -o bb_run start.o obj/*.o
$ file bb_run  -> ELF 64-bit LSB executable, statically linked
$ ldd bb_run   -> not a dynamic executable
$ ./cat t.txt          -> hello from a freestanding busybox
$ ./echo one two three -> one two three
```

**A multi-call busybox, built entirely by pxx, linked with no GNU library.** The
only non-pxx artefact is that stub, and the logic in it already exists in the ELF
writer for executables.

### The residual is SIZE, not correctness, and it changed another ticket's value

`bb_run` is **12327880 bytes** against roughly 1 MB for the gcc-linked
equivalent, because every object carries its own full copy of crtl
([[feature-a-every-emit-obj-object-links-its-own-full-copy-of-crtl-so-n-objects-cost-n-runtimes]]).
At 28 objects that is a curiosity. **At 521 it is the thing standing between this
and a bootable initramfs**, which is goal 5's actual deliverable
(*"linux kernel + busybox executable + pxx compiler as minimal system"*). That
ticket has been carried as runtime-duplication tidiness; it is now on the
critical path and should be ranked as such by whoever takes this group.

**Still unmeasured:** 521 objects. 28 is not 521, and the thing that scales badly
here is known to scale with object count.

### What to build, in order

1. **Emit the entry stub from pxx** — `--emit-obj --entry` or an equivalent, so
   no hand-written `.s` is needed. Small; the ELF writer has the logic.
2. **Run the 394-applet `--separate` set through `ld`** with that stub and
   measure the size.
3. **Then** route 2 (a pxx `--link` mode), which removes the `ld` call. A
   convenience now, not an enabler.

## 2026-09-10 — the `ld` route is PROVEN, with a shell, and the missing compiler piece is the ENTRY, not the link

Compiler `69c84acb1501` at `907015c58`. 19 applets **including `ash`**, 86
translation units, `tools/busybox_diff.sh --separate --keep --targets x86_64`:

| link | libc | result |
| --- | --- | --- |
| `gcc` (what the harness does) | glibc, dynamic PIE | GREEN — byte-identical to the gcc oracle over 132 cases |
| `ld -static -e _start` + entry stub | **none** | static, `ldd`: *not a dynamic executable*, 38444672 bytes; ash, cat, cp, date, dmesg, echo, grep, ls, mkdir, mount, mv, ps, pwd, rm, sleep, sync, umount, uname, wc all run |

So there is no duplicate-symbol wall and no `errno` TLS wall: **dropping glibc
removes the conflict**, exactly as the summary predicted. `tools/link_freestanding.sh`
performs this link and ASSERTS the result (no `PT_INTERP`, `ldd` agrees).

**THE REAL MISSING PIECE IS THE ENTRY, AND IT IS FOUR THINGS, NOT ONE.** A
6-instruction stub that reads argc/argv and calls `main` is enough for echo, ls,
wc, grep and pwd — and produced **three** failures that look like three
unrelated compiler bugs:

* `ash` SIGSEGV in `hashvar` on a NULL `varinit` pointer
* `date -u -d @0` SIGSEGV
* `uname -a` printing `Linux` eight times — a plausible WRONG VALUE, no crash

One cause: **the link has 84 function pointers in `.init_array` and glibc's
`crt1.o` was running them.** A constructor that does not run leaves its
subsystem's tables zeroed, which is why every symptom appears far from the cause
and in a different subsystem. The other three duties are the `%gs` control block
(`getrlimit(RLIMIT_STACK)`, `gettid`, `{self,tid,stack_low,stack_top}`,
`arch_prctl(ARCH_SET_GS)` — transcribed off a pxx executable's own entry with
gdb `starti`), `environ = argv + argc + 1`, and `.fini_array` via `exit`.

**ASKED FOR: `--emit-obj --entry`** (or equivalent) that writes those bytes into
an object. `elfwriter.inc` already emits all of it for executables; today it is
hand-copied in `tools/pxx_freestanding_start.s`, and a hand copy of a codegen
detail goes stale silently — with a segfault in somebody else's library as the
symptom.

**Residual is still SIZE and it is now measured against `--dce`:** 38444672 plain,
32553944 with `--dce` — **15%, not the 6x** a single TU shows. So `--dce` does not
touch this; the bulk is
[[feature-a-every-emit-obj-object-links-its-own-full-copy-of-crtl-so-n-objects-cost-n-runtimes]],
which this puts on the critical path for image size (the ISO is 34 MB, of which
the busybox is 32.5).

Shipped in `tools/mkminimal.sh` — a bootable BIOS+EFI ISO whose entire userland
is this binary. `MINIMAL-IMAGE OK` under qemu: kernel boots, shell launches,
on-board pascal26 compiles and runs a Pascal program, **0 shared libraries in the
image**.

## ROUTE 1 MEASURED 2026-09-16 (frankb-56) — it works, and the linker's hard part turns out to be already done

This ticket said route 1 "is the cheap one to measure first". Measured, at HEAD,
compiler binary `7c0d39cb5e1b`, on the 28 objects `tools/busybox_diff.sh
--separate --applets "cat echo" --targets x86_64 --keep` leaves in `$WORK/obj`.

**A pxx-built busybox links and runs with no libc and no crt.**

```
$ ld -static -nostdlib -e _start -o bb pxxcrt.o obj/*.o
$ echo $?            # 0, and ZERO diagnostic lines
$ file bb
ELF 64-bit LSB executable, x86-64, statically linked
$ ldd bb
        not a dynamic executable
$ ./bb cat t.txt     # prints the file;  ./bb echo / ./bb --list also correct
```

`pxxcrt.o` is a 30-line `_start` described below. Everything else is pxx output.

### The three numbers that make this cheap

| question | answer |
| --- | --- |
| distinct relocation types across all 28 objects | **2** — `R_X86_64_PC32` (47476), `R_X86_64_64` (799) |
| undefined refs across all 28 objects | 70 |
| **of those, not satisfied by another object in the set** | **0** |

Sections are `.text .data .bss .init_array .fini_array` plus the matching
`.rela.*`, `.symtab`, `.strtab`. Symbol bindings are LOCAL / WEAK / GLOBAL with
`FUNC WEAK` dominant (11989) — the shape that lets two objects carrying the
whole of crtl link at all.

**So no library is load-bearing in the current build.** `gcc -o out obj/*.o`
is being used as a *linker driver*, and the binary is dynamic because that is
gcc's default — not because a glibc symbol is wanted. That is a sharper
statement than this ticket could make before, and it is sharper than CLAUDE.md's
goal-5 note, which reads the `gcc` in that command line as a dependency on
glibc. The `gcc` is real; the glibc is not.

### What is ACTUALLY missing: the process-entry contract, not symbol resolution

pxx's objects define `main` and no `_start`, because `--emit-obj` targets a C
toolchain that supplies `crt1.o`. Linking with `-e main` links clean and then
**segfaults**, which is the correct shape: nothing has set up argc/argv/envp and
nothing has run `.init_array`.

Both halves of the fix already exist and have never been introduced to each
other:

- `elfwriter.inc:472` — the executable writer already synthesises a `_start`
  and records it in the map.
- `cparser.inc:13150` — the C frontend already emits an `.init_array` thunk
  that takes `(argc, argv, envp)` and calls `__pxx_set_environ`, deliberately
  under the same convention glibc uses for `DT_INIT` and `.init_array` alike.

The stub that proved it (MEASUREMENT ONLY — not proposed as the shipping
artefact, and assembled with `gcc -c`, which route 2 would remove):

```asm
_start:
    xor  %rbp, %rbp
    mov  (%rsp), %r12            /* argc */
    lea  8(%rsp), %r13           /* argv */
    lea  8(%r13,%r12,8), %r14    /* envp = argv + argc + 1 */
    and  $-16, %rsp
    lea  __init_array_start(%rip), %rbx     /* ld PROVIDEs both under -nostdlib */
    lea  __init_array_end(%rip), %r15
1:  cmp  %r15, %rbx
    jae  2f
    mov  %r12, %rdi ; mov %r13, %rsi ; mov %r14, %rdx
    call *(%rbx)
    add  $8, %rbx
    jmp  1b
2:  mov  %r12, %rdi ; mov %r13, %rsi ; mov %r14, %rdx
    call main
    mov  %eax, %edi ; mov $60, %eax ; syscall
```

Running `.init_array` is not optional dressing: skip it and `environ` is never
set, which is a wrong-value failure rather than a crash.

### Verified against the gcc-linked build, error paths included

47 cases replicating `busybox_diff.sh`'s `run_cat_cases` / `run_echo_cases` /
dispatch list, freestanding vs the harness's own `gcc`-linked binary from the
SAME objects: **byte-identical**, 5694 bytes of transcript.

**The three failing cases are the control** and they are why this is not a
guard that cannot fail: a missing file gives `cat: can't open '...': No such
file or directory` and exit 1; an unknown applet gives `applet not found` and
exit 127; `--list` prints both applets. A binary that segfaulted on everything,
or one that printed nothing, would agree with neither. 20 cases exit 0, 3 exit
nonzero, and the nonzero ones match byte for byte.

### THE QUANTIFIER, MEASURED — and it found the one thing the gcc link was hiding

Everything above is 28 objects at 2 applets, so it was re-run at **258 applets,
400 objects** (`--separate --targets x86_64`, GREEN, 663 cases byte-identical to
the gcc oracle). The wide census was the point: more busybox means more libc
surface, and **a genuinely needed glibc symbol would have been satisfied
SILENTLY by the `gcc` link**, so no existing run could tell you either way.

| | 28 objects | **400 objects** |
| --- | --- | --- |
| relocation types | 2 | **2** (PC32 710066, `R_X86_64_64` 13891) |
| undefined references | 70 | 780 |
| **unsatisfied by the set** | 0 | **1** |

The one is **`pivot_root`**. busybox declares it itself
(`util-linux/pivot_root.c:35`, a bare `extern` with no header, because no POSIX
or glibc header declares it) and glibc carries a stub, so `gcc -o out obj/*.o`
resolved it and **nothing was ever red**. It is exactly the shape this section
predicted and it is the reason the wide run was worth an hour.

Fixed in `lib/crtl/src/sys/mount.c` — six lines over the same syscall bridge as
`mount`/`umount2`, plus a declaration in `<sys/mount.h>` so the crtl name map
can route an undeclared call. crtl is **Track C's** by the lane table, so this
needed no handover. Test: `test/ccrtl_pivot_root.c`, wired as `ccrtlpivot26`.

**With it, the 400-object freestanding link is `rc=0` with ZERO diagnostics**, and
the binary runs:

```
$ ./busybox --list | wc -l          257
$ ./md5sum   <<< abc (no newline)   900150983cd24fb0d6963f7d28e17f72
$ ./sha256sum                       ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
$ ldd busybox                       not a dynamic executable
```

`cat`, `echo`, `sort`, `uniq`, `seq`, `tr`, `wc`, `basename`, `dirname`, `true`
and `false` all behave, and both digests match the published vectors — so this
is not a binary that starts and prints something, it is one doing real work.

### Repeatable, because a claim about an instrument decays like a lock

`tools/busybox_diff.sh --freestanding` (implies `--separate`, x86_64). It goes
through the SAME probe discipline as every other linker candidate — link a real
object AND run it — so a stub that assembles and then faults is a skip with a
reason rather than a green. **Two controls, both proven to FIRE rather than
asserted:** a `gcc` link has `PT_INTERP` (so the mode cannot silently measure
the gcc path under a freestanding name), and a stub-less `-e main` link has no
`_start`. Verified end to end at 2 applets: GREEN, byte-identical to the gcc
oracle over 29 cases.

### Route 2 is still the end state

`ld` is an external tool. The owner's own framing allows it — *"that we have to
run make files and link steps is fair game"* — so route 1 is a legitimate
shipping answer for "no external **libraries**". But two relocation types and a
fixed section list is a small `--link` mode, not a linker project, and route 2
removes the assembler for the stub as well. What this measurement changes is the
starting point: whoever takes this begins at *write the entry stub*, not at
*write a linker*.

## THE FULL-SCALE VERDICT, 2026-09-16 — 663 cases, no libc

`tools/busybox_diff.sh --freestanding --applets "<258 applets>"`, compiler
`b7f9f80c7d80`:

```
  note    x86_64   400 objects linked separately with `ld -static -nostdlib -e _start .../pxxcrt_x86_64.o`
  PASS    x86_64   freestanding: no PT_INTERP, entry 0x401000 == _start, no libc
  PASS    x86_64   byte-identical to the gcc oracle over 663 cases
busybox-diff: GREEN
```

`file` says `statically linked`, `ldd` says `not a dynamic executable`, zero
PT_INTERP segments, `--list` prints 257 applets, 181281688 bytes.

**Why this run exists when the previous one was already green.** The earlier
report rested on a spread of applets *I chose* — cat, echo, sort, uniq, seq,
tr, wc, basename, dirname, md5sum, sha256sum. That is a list a person writes
when they want it to work, and it is the same shape as a suite grown by adding
more of what already passes. This replaces it with the harness's own 663-case
population. (The digests were the strong half regardless: md5 and sha256 of
`abc` check against RFC vectors — an oracle outside this repo, this compiler
and this harness — where an applet that merely exits 0 tells you only that it
did not crash.)

**What it does not claim.** The entry stub is assembled with `gcc -c`. No
external *library* is in that binary; two external *tools* are still in the
toolchain. Route 2 removes both.

## The owner confirmed route 2, 2026-09-17, and named the thing that makes it tractable

> *"having 'pxx --link' feature would bring its own set of headaches, still a fun
> project, and well testable against ld"*

**`ld` is the differential oracle, and the harness that uses it already exists.**
`tools/busybox_diff.sh --freestanding` links the pxx objects with
`ld -static -nostdlib` and asserts the result carries no libc and no
`PT_INTERP`. Route 2 does not need a new test rig: it needs **the same run with
`pxx --link` substituted for `ld`**, over the same 400 objects and the same 29
behavioural cases, with the two controls that are already proven to FIRE (a gcc
link has `PT_INTERP`; a stub-less link has no `_start`). That is a rare position
to start a project from — a reference implementation, a real corpus, a passing
baseline, and a positive control, all in place before the first line is written.

**Compare the OUTPUT and the BEHAVIOUR, and do not require byte-identity with
`ld`.** Two linkers may lay out sections differently and both be correct; that is
the same class as `SizeOf` reporting each compiler's own representation
faithfully. The claim to hold is *"the program `pxx --link` produces behaves
identically to the program `ld` produces"*, which the 29 cases already measure.
A byte-diff against `ld` is a useful tripwire, never the acceptance bar.

**THE ONE FORK THAT DECIDES THE SIZE, and it should be settled before starting:
do we link OUR objects, or ANYONE'S?** The measured two relocation types
(`R_X86_64_PC32`, `R_X86_64_64`) over a fixed section set is a fact about **pxx's
own output**, which is why this is a `--link` mode and not a linker project. The
moment it must consume a gcc- or fpc-produced object it inherits the full x86-64
psABI — GOT, PLT and TLS relocation families, archive (`.a`) semantics, section
groups — and that IS a linker project. The existing decided answer next door
points the same way: *"the dialect is the target and the implementation is not"*
(owner, 2026-09-09, on FPC interop). **Linking foreign objects is the same shape
of want, and nothing in the six goals requires it.** Scope route 2 to pxx's own
objects, and say so in the flag's help text so nobody later reads the omission as
a defect.

**Known headaches, named so the estimate is honest:** symbol resolution order and
duplicate-definition rules; section and symbol-table merging across 400 inputs;
`--function-sections` already exists, so dead-strip becomes both possible and
expected; and the i386 story is NOT the x86-64 story — that target already has a
text-relocation history (`bug-a-an-i386-object-carries-text-relocations-as-soon-as-it-uses-sysutils`),
so **x86-64 is the small case and must not be quoted as the size of the others.**

## SCOPE, settled with the owner 2026-09-17 — three rungs, and they are not one slope

He raised the harder shapes himself and took the scoping below. **Read this
before estimating: the difficulty is not a gradient, and rung 3 is a different
kind of thing rather than a harder version of rung 1.**

**RUNG 1 — our objects, `ld` still present. THIS IS THE TICKET.** And the design
is **shadow `ld`, do not replace it**: keep the external linker a supported
backend and add `--link` beside it, selectable. Two reasons, both practical.
The differential harness stays alive permanently instead of only during
bring-up; and a missing relocation or a bad layout decision is then one flag
away from a known-good build rather than a regression. Our emitter already
knows six relocation types and the 400-object corpus exercises exactly two.

**RUNG 2 — third-party (`gcc`/`fpc`) objects. NOT THIS TICKET, and probably not
a goal.** The cost is not the relocation count, it is the **RELAXATIONS**: gcc
emits `GOTPCRELX` and TLS `GD` sequences *expecting the linker to rewrite the
instructions* (GOTPCRELX collapsing to a direct `lea`; TLS going GD -> IE -> LE
by what the final link turns out to be). Applying those faithfully without
relaxing gives slow code at best and, for TLS, frequently something that does
not work. Then COMDAT section groups, archive pull-until-fixpoint semantics,
`.eh_frame_hdr` synthesis, `.init_array` ordering. **The nearest decided
precedent is the owner's own, 2026-09-09: *"the dialect is the target and the
implementation is not"* — binary interop with another toolchain is not a goal.**
Take rung 2 only when something we actually want to build needs it, and say
which thing.

**RUNG 3 — consume a `.so` as if it were a `.o`. DECIDED NO** — see
`decide-linking-a-so-as-if-it-were-an-object`. Not hard; mostly not coherent. A
`.so` has already been linked and the link-time information was discarded.

**Say the scope in `--link`'s own help text**, so a later reader does not read
the omission as a defect.

**Background for whoever takes this and wants the concepts first:**
`devdocs/dev/linking-in-this-tree.md`, ~130 lines / ~2k tokens — a MAP onto our
own source, not a tutorial. Its first pointer is `tools/pxxcrt_x86_64.S`, 76
lines, which is the entry contract end to end.
