---
track: A
prio: 30
type: feature
blocked-by: []
summary: "What x86-64 feature level does pxx emit for? Referenced as 'if raised' by two existing tickets and never filed; raised by the user 2026-08-15 when FMA came up. MEASURED: our own gate box plexus is a Xeon E5-2620 v2 (Ivy Bridge, 2013) with AVX but NO FMA and no AVX2 — x86-64-v2, not v3. So a v2 bump is safe and FMA would SIGILL on the machine that gates every push. Includes the answer to the 'dispatch defeats inlining' objection: multiversion whole FUNCTIONS, not instructions."
---

# x86-64 feature level, and how (or whether) to dispatch

- **Type:** feature / policy (**Track O**, file-owned by **Track A**).
- Referenced as `[[feature-opt-arch-level-and-dispatch]] if raised` by
  [[feature-opt-complex-packed-double]] and
  [[feature-opt-pxx-internal-abi-unified-residency]]. Raised by the user on
  2026-08-15, in the FMA discussion following the fast-float work.
- **The baseline row is the user's call**, not an engineering one. Everything
  below is the material for making it.

## The levels, and where the interesting instructions sit

| level | adds | earliest CPU |
| --- | --- | --- |
| **v1** | SSE2 — the guaranteed x86-64 baseline | 2003 |
| **v2** | SSE3, SSSE3, SSE4.1/4.2, POPCNT, CMPXCHG16B | Nehalem ~2009 / AMD ~2011 |
| **v3** | AVX, AVX2, BMI1/2, **FMA**, LZCNT, MOVBE | **Haswell 2013** / AMD Zen 2017 |
| **v4** | AVX-512 family | 2016+, still not universal |

pxx emits **v1** today. The two things that have wanted a bump want *different*
levels, and conflating them is how this gets decided wrongly:

- `addsubpd` / `movddup` for packed complex — **v2**. Effectively universal;
  every x86-64 CPU since ~2005-2009. Cheap to require, and emulable on v1 for
  one extra op.
- **FMA — v3.** Much bigger. Excludes every pre-2013 Intel and every pre-Zen AMD
  in practice.

## The constraint that makes this urgent: our own gate box

The user's observation, 2026-08-15: **plexus (Track T's test server) is from
around that era** and may well be pre-Haswell. If pxx emitted FMA
unconditionally, plexus would `SIGILL` on the generated code — and it would
surface as an incomprehensible compiler bug in a tstate report, not as "your CPU
is too old", because nothing in the pipeline would say so.

**MEASURED on the box itself, 2026-08-15** (the user opened `neo@plexus` for it):

```
model name : Intel(R) Xeon(R) CPU E5-2620 v2 @ 2.10GHz   (Ivy Bridge EP, 2013)
12 cores
sse4_2 YES    avx YES    avx2 NO    fma NO
```

So plexus is **x86-64-v2, not v3**. Ivy Bridge has AVX but FMA and AVX2 both
arrived with Haswell, one generation later. The suspicion was right and the
consequence is hard:

- **Option 2 (bump to v2) is SAFE on plexus.** `addsubpd`/`movddup`/SSE4.2 all
  run there.
- **FMA would `SIGILL` on our own gate box.** Not "slower on plexus" — dead.

Note the middle tier this exposes: plexus has **AVX without FMA**, so 256-bit
VEX float work is available where FMA is not. Anything gated on "AVX" as a proxy
for "modern" would pass the check and then crash on the FMA.

The dev box these measurements came from is an i7-6700 Skylake, which *is* v3 —
so a local `-mfma` experiment passes here and dies there. Exactly the trap, and
the reason this needs to be a policy rather than a per-session judgement.

CPU features are still not recorded in tstate (`plexus.json` and the report
frontmatter carry `host`, `sha`, `tier`, `wall`, `compiler_sha256` and nothing
about the machine), so the next person has to ssh in again, and **borg's level
is still unknown**. That gap is
[[feature-t-record-host-cpu-features-in-tstate]].

## "Dispatch would defeat inlining" — the objection, and the answer

The user's point, and it is correct as stated: a CPU-feature check is a
one-time-per-process thing, so you would hold **function pointers** to the
supported implementations — but you cannot inline through a function pointer,
and inlining is most of why FMA helps a Horner chain in the first place.

The resolution is to **dispatch at FUNCTION granularity, not instruction
granularity**. Compile the whole hot function twice — `Sin_v3` using FMA
throughout, `Sin_v1` not — and bind the pointer once at startup. Each clone is
internally fully inlined; the FMA contraction happens *inside* the clone, where
it pays. What you lose is inlining **through** the dispatch point, at the
outermost call only.

That is exactly what the C world does: glibc uses **IFUNC** (the dynamic linker
resolves the symbol once, via a resolver function that reads CPUID), and gcc
exposes it as `__attribute__((target_clones("fma","default")))`. It is a solved
shape, not a novel one.

### ...but it does NOT generalize, and that limit decides the ticket

The user's follow-up, 2026-08-15: *"so you suggest to inline, but make compile
the outer function twice. so, what if the outer function is really a big
draconian piece of code?"* — correct, and the paragraph above was written off a
cherry-picked example.

The thing you clone is whatever function **contains** the arithmetic, so the
question is *whose* function that is:

- **Ours** (`Sin`, `Exp`, a matrix kernel, a hash round): bounded, because we
  choose the list. `Sin` is ~800 instructions; a dozen of those doubled is a few
  KB and one indirect call per invocation is noise.
- **The user's** (`z := a*b + c` inside a 3000-line render loop): the function
  that would have to be cloned is *their* render loop. Double the code, double
  the I-cache footprint, and nobody but the author can judge whether it is worth
  it.

Which is exactly why gcc does **not** multiversion user code automatically:
`target_clones` is an attribute the author writes on a function they chose. For
the general case gcc offers `-march=`/`-mfma` — a global baseline, decided once,
by the human.

The rule underneath is granularity of work per dispatch, not function size:

> **Runtime dispatch pays only when there is a chunk of work big enough to
> amortize one indirect call.**

`memcpy` qualifies (one call, N bytes) — which is why glibc multiversions it.
`Sin` qualifies. Scalar `a*b+c` does **not**: one FMA is ~4 cycles and an
indirect call is ~5, so per-operation dispatch is *slower than having no FMA at
all*. The middle move — factor the FMA-able part into a cloned helper — only
works if that helper does **bulk** work (a whole array, a whole block), because
it reintroduces a call at that boundary. That is an algorithm restructuring, not
a compiler switch.

**So the option set collapses:** cloning covers the RTL hot list and nothing
else. Arbitrary user code can only be served by a compile-time baseline. Option
4 is therefore *narrower* than it first reads — it is not an alternative to
option 3, it is a supplement to it for a dozen named functions.

The cost model that follows:

- **Worth cloning:** `Sin`, `Cos`, `Exp`, `Ln`, a matrix kernel, a hash round —
  body big enough that one indirect call is noise, small enough that doubling it
  is free.
- **Never clone:** `Abs`, `DdMul`, `Dd2Sum` — tiny leaves where the call *is*
  the cost, and where you would pay the indirect call *and* lose the caller's
  ability to inline.
- **Cannot clone:** anything in user code. Flag territory.

(Note `Abs()` is currently a real call even after hand-inlining, per
[[feature-opt-float-register-temporaries]] — fix that first regardless.)

## Options

1. **Stay v1. Do nothing.** Costs the ~20% FMA was worth on float kernels.
   Everything runs everywhere including plexus. *This is the status quo and it
   is defensible.*
2. **Bump to v2** for the packed-double work. Low risk, ~universal, unlocks
   `addsubpd`/`movddup`. Does **not** give FMA.
3. **Opt-in compile flag** (`-mfma`, or `--cpu=v3`). Default off, so nothing
   breaks; whoever knows their target gets the codegen. Cheapest way to *have*
   FMA at all, and the natural fit for a compiler that already has `--target`.
4. **Runtime multiversioning** of a short list of RTL hot functions, per the
   shape above. Most machinery — pxx would need CPUID emission, a startup
   resolver, and a cloning pass — and per the limit above it buys **only** those
   named functions. User code still needs option 3.

A sane ladder is 3 then 4, with 2 decided independently on the packed-double
ticket's own merits. Note 4 does not replace 3: even with full multiversioning,
a user's own hot loop gets FMA only by compiling for a baseline.

## Ordering — do this AFTER the value model, not before

The measured decomposition of pxx `Sin` vs glibc
([[feature-opt-float-register-temporaries]], 2026-08-15):

| | |
| --- | --- |
| x86-64 float value model (Double carried as bits in RAX) | **7.2x** |
| FMA | ~1.2x |

**The 7.2x needs no ISA bump at all** — it runs on every x86-64 chip back to
2003, plexus included. FMA is a ~20% follow-on that costs a compatibility
decision. Doing the ISA work first would be paying the hard price for the small
win.

## aarch64 needs none of this

`FMADD` is baseline in ARMv8 — no dispatch, no feature level, no clones. So all
of the above is x86-64-only complexity, which is itself an argument for option 3
over option 4.

## Gate

Whatever lands: `make test` + self-host byte-identical, plus **a run on plexus
specifically** (not just the dev box) before anything ISA-gated is turned on by
default — the whole point of the ticket is that the gate box may be the oldest
machine in the fleet.
