---
slug: bug-a-every-object-defines-the-whole-of-crtl-globally-so-no-two-objects-link
title: "Two --emit-obj objects cannot be linked together: each defines all 116 crtl entry points globally"
track: A
prio: 70
type: bug
status: done
created: 2026-09-01
found-by: frankD
owner: frankA
blocked-by: []
summary: "CORRECTED 2026-09-01: weakening only the CODE is NOT sufficient -- crtl STATE is object-local with no linkage at all (`nm` finds no errno symbol), so a program touching errno/optind BY NAME reads its own copy; measured against gcc, errno=0 vs 2 and optind=1 vs 2, and that is exactly why the busybox separate build diverges from the oracle while still linking and running. Every --emit-obj object carries the WHOLE of crtl and exports each entry point as a GLOBAL definition, so any two pxx objects collide on 116 symbols and ld refuses the link. Measured on a two-line .c: 117 global symbols, 116 of them crtl, exactly one the program's own; .text 162KB, .data 11KB, .bss 56KB per object. meta-a-pxx-produces-linkable-code establishes that a gcc-built main links ONE pxx object; nobody had attempted TWO. Found attempting busybox's own build model. SEPARATE COMPILATION OTHERWISE WORKS: all 41 busybox TUs became objects with zero failures and the link produced a working multiplexer (--list, echo, and ash arithmetic all correct) -- but only with -Wl,-z,muldefs to get past THIS bug, and at 13.7MB because every object carries a full crtl."
---

# Two objects cannot be linked together

Found by attempting separate compilation of busybox for
[[feature-c-corpus-busybox-multi-applet]] -- NOT because the unity was
exhausted (it was not; nine of twelve candidate applets build fine as a
fourth, see the logbook correction of 2026-09-01), but because separate
compilation is busybox's OWN model and a strictly stronger claim. It became
worth attempting once
[[bug-a-an-object-neither-exports-nor-imports-data-symbols-and-links-silently-wrong]]
landed and made it worth attempting. Compiler `eb0cff098`.

## The measurement

```c
/* alloc_a.c */                          /* alloc_b.c */
void *make_it(void) {                    void *make_it(void);
  char *p = malloc(64);                  int main(void) {
  strcpy(p, "allocated in TU A");          char *p = make_it();
  return p;                                printf("1 %s\n", p);
}                                          free(p);
                                         }
```

```
pascal26 --emit-obj alloc_a.c alloc_a.o     # ok
pascal26 --emit-obj alloc_b.c alloc_b.o     # ok
gcc -o twotu alloc_a.o alloc_b.o
  multiple definition of `__pxx_va_start_impl'
  multiple definition of `malloc' ... 116 symbols in total
```

`nm --defined-only alloc_a.o | grep ' [A-Z] '` is **117 symbols: 116 crtl
entry points and `make_it`.** The object is `.text 162027  .data 11080
.bss 56120` — for a two-line file whose only calls are `malloc` and `strcpy`.
So crtl is linked in **wholesale, not on demand**.

## What the two halves of a routine do NOT agree on

The collision is the visible half. The interesting half is that
`nm --defined-only | grep ' [A-Z] '` finds **zero global DATA symbols**:

- crtl **code** is GLOBAL (`T malloc`, `T free`, `T printf`)
- crtl **state** is object-LOCAL (the heap, the stdio buffer list, the env
  table are all in that 56KB of local `.bss`)

The obvious fix — mark the crtl definitions weak, or put them in COMDAT
groups, so the linker keeps one copy — resolves each symbol to its FIRST
definer. If the sets of crtl symbols differed between objects, `printf` could
come from object A and `fflush` from object B, and B's `fflush` would flush
B's buffer list while A's `printf` filled A's. That is this repo's expensive
shape: no crash, a plausible wrong value, far from the cause.

**It does not happen, and the reason is worth writing down rather than
rediscovering.** Because the pull is WHOLESALE, every object defines the same
116 symbols, so the first definer is the first object uniformly and code and
state stay together. Verified rather than argued:

```
gcc -Wl,-z,muldefs -o twotu alloc_a.o alloc_b.o    # what weak linkage would do
./twotu
1 allocated in TU A          <- malloc in TU A
2 free-crossed-TU-ok         <- freed in TU B
3 stdio from B
```

**That is TRUE AND NOT SUFFICIENT, and the second half was measured a few
hours later, on busybox.** Wholesale-pull makes the CODE consistent: every
caller reaches A's heap because the surviving `malloc` has A's heap compiled
into it. It does nothing at all for state a program touches **directly by
name**, never going through crtl code that could funnel it. busybox does that
constantly. Two more two-object repros, gcc as the oracle:

```
                      gcc                                  pxx (-z muldefs)
errno    fopen in A   errno=2 [No such file or directory]  errno=0 []
optind   getopt in A  opt=u optind=2                       opt=u optind=1
```

`nm` finds **no `errno` symbol in a pxx object at all** — it is object-local
state with no linkage, so the reader gets its own untouched copy.

This is not hypothetical. It is exactly and only why the busybox separate
build diverges from the oracle:

```
< cat: can't open '.../missing.txt': No such file or directory
> cat: can't open '.../missing.txt'
> cat: can't open '-u'
```

The missing reason is split `errno`. `-u` becoming a filename is split
`optind`. One mechanism, twice.

**And it LOOKED like it worked.** 41 objects linked, the binary ran, `--list`,
`echo` and `ash` arithmetic were all correct. Only the 62-case differential
caught it. A smoke test on a runtime-state bug is not a weaker version of the
claim; it is a different claim.

So a fix that weakens only the 116 CODE symbols leaves `errno` and `optind`
split N ways and ships. **The state must get linkage too** — exported and weak
alongside the code — or option 2 below, which removes the question instead of
balancing on it.

## The options, and a recommendation

1. **Weak / COMDAT the crtl definitions — CODE AND STATE BOTH.** Small, but
   not as small as it first looked: weakening the code alone is measurably
   wrong (see the errno/optind rows above), so this is "give the state global
   linkage and weaken both", not "mark the functions weak". Leaves N copies of
   a 162KB runtime in the objects, which `--gc-sections` could reap and
   nothing currently does.
2. **Emit crtl ONCE into its own object or archive; objects import it.** The
   real answer, and how every other toolchain does it. Makes the state
   question disappear rather than balancing on it, and makes object size
   proportional to the source. Bigger: needs a crtl build product, and the
   auto-pull (`CPAutoPullCrtlImpl`) stops being per-TU.
3. Leave it, and require `-z muldefs` at every link. Not a fix; recorded
   because it is what the busybox attempt used to get past this and measure
   what lies BEYOND it.

**Recommend 2, with 1 as a stepping stone if a measurement is wanted sooner** —
and if 1, the invariant written next to the code is the STATE one above, not
the wholesale-pull one, which is the half that is true and insufficient.

**UNMEASURED, and it should be measured before either option lands:** whether
a WEAK pxx `malloc` still beats libc's when a gcc-built main links the object.
A strong definition in a `.o` beats `libc.so` today, which is what
`test-emit-obj` relies on. A weak DEFINED symbol should also stop ld pulling
the archive member, but "should" is not a measurement. My attempt with
`objcopy --weaken` failed for an unrelated reason (the object carried an
undefined data symbol and ld refused the PIE relocation), so this is absence
of evidence, not evidence.

## Why this is not covered by the meta

[[meta-a-pxx-produces-linkable-code]] measures **a gcc-built main linking ONE
pxx object**, on four targets, and that all works. Two pxx objects is a
different claim and had never been attempted — an umbrella cell with no
blockers because nobody had tried it, not because it was clear.

## Resolved: three changes, not one — and the first two each looked like the fix

frankA, 2026-09-01. Two objects now link with no `-z muldefs` and share one
heap, one `errno` and one `optind`, matching a gcc build of the same sources.
Compiler `742e616ec446`. Regression row: `test-emit-obj` block 4b-septies over
`test/c_obj_runtime_state_{a,b}.c`, with the gcc build as the oracle rather
than a literal.

Each stage below was measured on the same repro, and the first two produce a
program that links and runs and answers WRONGLY — which is why they are
recorded as stages rather than as one diff.

1. **crtl code exported WEAK** (`ObjProcBind`, `$20`). The 116 collisions go.
   The link still fails rc=2 — on `stdin` and `stdout`. Those were already
   strong globals, because the old membership test asked "did the user's file
   mention this name" and `#include <stdio.h>` puts `extern FILE *stdin;` in
   the user's TU. So the runtime's data surface was inconsistent before this
   ticket: `stdin`/`stdout` exported strongly, `errno`/`optind` not at all.
2. **crtl state exported WEAK too.** Link rc=0, and `errno` reads 0 where gcc
   says 2 — frankD's number, reproduced exactly. The cause is a layer below
   binding: every data reference in an object relocated against `.bss + n`, the
   SECTION, so the linker's choice between two definitions of a name reached
   nobody. Both copies still existed and each object read its own.
3. **An exported definition relocates against its own SYMBOL**
   (`ObjDataExportSymForOff`). `errno=2`, `optind=2`, cross-TU `free` works.

The import side of that contract was wired by
[[bug-a-an-object-neither-exports-nor-imports-data-symbols-and-links-silently-wrong]];
the export side never was. Sharing a definition is two-sided, and one side
alone is the silent-wrong-read bug pointed the other way.

**The membership rule that made stage 1's leftovers disappear as a side effect
rather than as a special case: the question is WHOSE DEFINITION, not whose
mention.** A crtl definition makes a name runtime state however many user files
declare it (`ObjDataIsRuntime`).

**One regression caused and guarded.** Widening the candidate set made `errno`
an UND IMPORT in a TU that pulls crtl's declaration without the module that
defines it — `test/test_shared_lib.c` does exactly that — and ld then refuses
libc.so outright: "TLS definition in libc.so.6 section .tbss mismatches non-TLS
reference". A hard refusal, not a warning. **A name our own runtime owns is
never imported**, whatever the extern-fold says; we ship a C runtime, so asking
the host's libc for a piece of its state is always wrong.

**What is NOT fixed, and it is the 13.7MB.** Weak resolves the symbol; it does
not drop the bytes. The two-object binary here is 580088 against 310544 for one
object, so both copies of crtl are still linked in. Section-granular
deduplication is a separate mechanism (a crtl archive, or function sections
plus COMDAT groups) and is filed as
[[feature-a-every-emit-obj-object-links-its-own-full-copy-of-crtl-so-n-objects-cost-n-runtimes]].

## Log
- 2026-09-01 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 243137302.
