---
track: T
prio: 40
type: feature
status: backlog
blocked-by: []
owner: ""
summary: "The csmith oracle is a checksum of the globals, so it is complete for VALUES and structurally blind to LAYOUT: a struct whose members sit at the wrong offsets stores and loads consistently and produces an identical checksum. Predicted 2026-07-13, unacted on, and a real offset bug then survived every batch since -- 443 on 2026-08-30 alone. Proposes a layout dimension: emit offsetof for every member of every generated struct and diff against gcc."
---

# A layout oracle dimension — the checksum is complete for values and blind to offsets

- **Track T** — fuzzing tooling and its oracles (`tools/csmith_fuzz.py`).
- **Found:** 2026-08-30 by frankC, after filing
  `bug-c-a-long-long-bitfield-after-a-smaller-one-puts-later-members-at-the-wrong-offset`.
- **Sibling:** `feature-t-a-second-oracle-dimension-section-alignment` — same
  shape, a second dimension added to a differential because the first cannot see
  a whole class.

## The gap, stated as a property of the instrument

csmith's oracle is **a checksum of every global**. That makes it complete for
values and **structurally blind to layout**: a struct whose members sit at the
wrong offsets stores and loads through those same wrong offsets, self-consistently,
and prints an identical checksum. `MISCOMPILE_VS_GCC` cannot fire. Neither can
`MISCOMPILE_OPT`, which compares our own `-O` levels to each other and is if
anything *more* blind — both arms share the layout.

This is not a shortcoming of a particular batch. **No batch of any size, at any
complexity, on any target, can find a layout defect**, because the quantity that
differs is not in the quantity being compared.

## It was predicted, and the prediction was the whole of the action taken

`feature-c-csmith-differential-fuzzing` has carried this since **2026-07-13**:

> **Bitfield LAYOUT** — `sizeof` of a packed bitfield struct is 12 where gcc gives
> 8. Values are right, so the checksum oracle **CANNOT see it**; it breaks
> ABI/interop instead.

Correct, and nothing followed from it. The consequence, measured:

- A real layout bug sat **unfiled for seven weeks** — not unfixed, *unfiled*.
- Batches kept running past it. On 2026-08-30 alone: 443 comparisons across two
  x86-64 batches, plus 100 aarch64 and 100 i386, **none of which could have seen
  it**, all reported as clean.
- When it was finally measured, the recorded shape (`sizeof` 12 vs 8) **did not
  reproduce** and a worse one did: `sizeof` **matching at 16 both** while
  `offsetof` of a following member differs (12 vs 8).

That last point is the argument for building the dimension rather than
hand-checking layout occasionally. **A size check is what a careful person
writes, and a size check is exactly what misses this.** The July note tested the
metric that cannot see the bug, and the note stood for seven weeks looking like
coverage.

## What to build

For each generated program, emit alongside the checksum a **layout manifest**:
for every struct and union type, `sizeof` and `offsetof` of **every member**.
Build with gcc and with pxx, diff the manifests.

Properties that make this cheap and strong:

- **Both compilers compute the numbers directly.** No execution, no qemu, no
  timing, no UB questions — `offsetof` is a compile-time constant. It can run as
  a compile-only pass over the same generated program the value oracle already
  built.
- **It is a pure differential**, so it needs no judgement, exactly like the
  checksum.
- **It is orthogonal, not redundant** — the checksum is complete for values and
  blind to layout; this is complete for layout and says nothing about values.
  Both are needed and neither subsumes the other.
- csmith generates bitfields, unions, packed structs and nested aggregates
  already; the generator side needs nothing.

**It must compare OFFSETS, not just sizes.** Comparing sizes reproduces the exact
blind spot that hid this bug for seven weeks — the case that matters had matching
sizes. Say so in the implementation, because "diff the sizeof" is the obvious
first cut and it is the wrong one.

A new bucket (`LAYOUT_DIFF`) alongside the existing `LAYOUT_SUSPECT` — which
today triggers only on a *value* divergence in a program that happens to contain
bitfields, and therefore cannot fire when values agree.

## Prio note

p40 rather than higher because nothing is presently silent: the one known layout
defect is now filed with a mapped boundary. The dimension earns its rank by what
it prevents — every future layout defect is otherwise found the way this one was,
by somebody deciding to look, seven weeks late.

## A WORKING PROTOTYPE — frankC, 2026-08-30. Lift this, don't rebuild it.

I built the layout differential to adjudicate
`bug-c-a-long-long-bitfield-after-a-smaller-one-puts-later-members-at-the-wrong-offset`,
and it immediately paid for itself: it turned a one-shape bug report into a
measured **135-of-400 (34%)** divergence and showed the divergence runs in BOTH
directions, which is what ruled out the obvious one-line fix. That is exactly
the value this ticket predicted, so here is the thing itself rather than a
description of it.

### Why the checksum could never have found it

csmith's oracle is a checksum over global VALUES. A struct whose members all
hold correct values but sit at different OFFSETS checksums identically. The
43-case bitfield bug is invisible to every fuzz run we have done, and always
would have been. Layout needs its own oracle; it is not a gap in the corpus.

### The critical design property: ERROR is not DIFF

**`offsetof` on a bit-field member is illegal C.** My first version emitted
probes for bitfields, gcc failed to build them, and the script scored those
cases as DIFF — 20 spurious findings, "could not look" printing as "ruled
out", inside the tool built to catch that class of mistake. The script below
counts a build failure on either side as ERROR and names which compiler
failed. **Keep that separation when you productionize it**; a layout oracle
that reports unbuildable probes as divergences is worse than none.

Probe members are therefore listed explicitly per case (third field), and the
generator only ever probes non-bitfield members.

### Oracle selection carries the same data-model constraint as the checksum

Offsets depend on the data model, not the ISA — pick the gcc whose model
matches the target, or drop the vs-gcc comparison, exactly as `174186b5d` did
for csmith. Note also that i386 has **no oracle on this box at all** (no cross
gcc, no multilib), so an ILP32 run is a self-differential only and must never
be reported as a vs-gcc result.

### tools/laydiff.sh

```bash
#!/bin/bash
# Layout differential: sizeof + offsetof of NAMED NON-BITFIELD members, pxx vs gcc.
# offsetof on a bit-field is illegal C, so probes are declared explicitly per case.
# A gcc build failure is ERROR, never DIFF -- "could not look" must not read as "ruled out".
T="$(dirname "$0")"; C="${PXX:-./compiler/pascal26}"; pass=0; fail=0; err=0
while IFS='|' read -r name body probes; do
  [ -z "$name" ] && continue
  { echo '#include <stdio.h>'; echo '#include <stddef.h>'
    echo "struct S { $body };"
    echo 'int main(void){ printf("sz=%zu", sizeof(struct S));'
    for m in $probes; do echo "  printf(\" $m=%zu\", offsetof(struct S, $m));"; done
    echo ' printf("\n"); return 0; }'; } > "$T/ld.c"
  if ! gcc -w -o "$T/ldg" "$T/ld.c" 2>/dev/null; then
    err=$((err+1)); printf 'ERROR %-30s gcc could not build the probe\n' "$name"; continue; fi
  g=$("$T/ldg")
  if ! $C "$T/ld.c" "$T/ldp" >/dev/null 2>&1; then
    err=$((err+1)); printf 'ERROR %-30s pxx could not build the probe\n' "$name"; continue; fi
  p=$("$T/ldp")
  if [ "$p" = "$g" ]; then pass=$((pass+1))
  else fail=$((fail+1)); printf 'DIFF  %-30s pxx[%s] gcc[%s]\n' "$name" "$p" "$g"; fi
done
printf 'LAYOUT-DIFF-COMPLETE pass=%d diff=%d error=%d\n' "$pass" "$fail" "$err"
```

### tools/genlayout.py — deterministic corpus

```python
#!/usr/bin/env python3
"""Generate random C bitfield struct shapes for the layout differential.
Emits: name|body|probe-members   (one case per line)
Probes are NON-bitfield members only -- offsetof on a bit-field is illegal C."""
import random, sys
seed  = int(sys.argv[1]) if len(sys.argv) > 1 else 20260830
count = int(sys.argv[2]) if len(sys.argv) > 2 else 400
rng = random.Random(seed)
TYPES = [("signed char",8),("unsigned char",8),("short",16),("unsigned short",16),
         ("int",32),("unsigned",32),("long long",64),("unsigned long long",64)]
PLAIN = ["char","short","int","long long","double"]
out = []
for i in range(count):
    parts, probes, nf = [], [], rng.randint(1, 6)
    for f in range(nf):
        r = rng.random()
        if r < 0.10 and parts:                       # anonymous :0 unit break
            t,_ = rng.choice(TYPES); parts.append("%s :0" % t)
        elif r < 0.22 and parts:                     # plain member between bitfields
            t = rng.choice(PLAIN); m = "p%d_%d" % (i,f)
            parts.append("%s %s" % (t,m)); probes.append(m)
        else:                                        # a bitfield
            t,w = rng.choice(TYPES)
            parts.append("%s b%d:%d" % (t, f, rng.randint(1, w)))
    tail = "t%d" % i
    parts.append("int %s" % tail); probes.append(tail)
    out.append("r%d|%s|%s" % (i, "; ".join(parts), " ".join(probes)))
print("\n".join(out))
```

Usage, and the baseline any bitfield fix must beat:

```
python3 tools/genlayout.py 20260830 400 > cases.txt
tools/laydiff.sh < cases.txt
```

Baseline at `239142c9b` (binary `83a767151ffa`): `pass=265 diff=135 error=0`.
Of the 135, **36 have an identical `sizeof` and differ only in member offsets** —
those are the ones neither the csmith checksum nor a size assertion can see, and
they are the concrete case for this ticket.
