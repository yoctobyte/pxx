---
slug: bug-a-every-object-defines-the-whole-of-crtl-globally-so-no-two-objects-link
title: "Two --emit-obj objects cannot be linked together: each defines all 116 crtl entry points globally"
track: A
prio: 70
type: bug
status: backlog
created: 2026-09-01
found-by: frankD
owner: ""
blocked-by: []
summary: "Every --emit-obj object carries the WHOLE of crtl and exports each entry point as a GLOBAL definition, so any two pxx objects collide on 116 symbols and ld refuses the link. Measured on a two-line .c: 117 global symbols, 116 of them crtl, exactly one the program's own; .text 162KB, .data 11KB, .bss 56KB per object. meta-a-pxx-produces-linkable-code establishes that a gcc-built main links ONE pxx object; nobody had attempted TWO. Found attempting busybox's own build model. SEPARATE COMPILATION OTHERWISE WORKS: all 41 busybox TUs became objects with zero failures and the link produced a working multiplexer (--list, echo, and ash arithmetic all correct) -- but only with -Wl,-z,muldefs to get past THIS bug, and at 13.7MB because every object carries a full crtl."
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

**So weak/COMDAT is SOUND ONLY WHILE THE PULL STAYS WHOLESALE.** Anything that
makes crtl inclusion demand-driven — an obvious size win, and someone will
want it — breaks the property that makes it safe, silently. Whoever does that
must move the state to global linkage in the same change, or the two halves
part company.

## The options, and a recommendation

1. **Weak / COMDAT the crtl definitions.** Small. Correct today, for the
   reason above. Leaves N copies of a 162KB runtime in the objects, which
   `--gc-sections` can reap but nothing currently does. **Carries the hazard
   above as an undocumented invariant unless this ticket's note goes with it.**
2. **Emit crtl ONCE into its own object or archive; objects import it.** The
   real answer, and how every other toolchain does it. Makes the state
   question disappear rather than balancing on it, and makes object size
   proportional to the source. Bigger: needs a crtl build product, and the
   auto-pull (`CPAutoPullCrtlImpl`) stops being per-TU.
3. Leave it, and require `-z muldefs` at every link. Not a fix; recorded
   because it is what the busybox attempt used to get past this and measure
   what lies BEYOND it.

**Recommend 2, with 1 as a stepping stone if a measurement is wanted sooner** —
but only with the wholesale-pull invariant written next to it.

## Why this is not covered by the meta

[[meta-a-pxx-produces-linkable-code]] measures **a gcc-built main linking ONE
pxx object**, on four targets, and that all works. Two pxx objects is a
different claim and had never been attempted — an umbrella cell with no
blockers because nobody had tried it, not because it was clear.
