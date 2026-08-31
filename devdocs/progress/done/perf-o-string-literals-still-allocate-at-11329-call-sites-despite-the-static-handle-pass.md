---
track: A
prio: 65
type: perf
blocked-by: []
created: 2026-08-31
owner: frankB
summary: "RESOLVED AS ALREADY CORRECT — the premise was a measurement of the wrong binary. 11,329 is the -O1 call count, not the -O2 one, and it reproduces exactly: at 763233473 the same source gives -O1 = 11,329 calls to the PXXStrFromLit thunk with 3 static-handle sites, -O2 = 1,282 calls with 9,307 static-handle sites. EmitStaticLitHandle converts 87.9% of literal sites and is doing its job. The binary that was disassembled was compiler/pascal26-debug (`make pxx-debug`), which is -O0 by design, and the cited call target 0x400109 is not a function entry in any build. A fresh -O2 profile puts PXXStrFromLit at 0.18%, not 17.1%, and managed-string+heap at 18.2%, not 47%. No code change. The finding that survives is the retarget: the hot managed-string cost is the refcount RELEASE thunk at 7.72% plus PXXAlloc 4.07% / PXXFree 2.48%, not literal construction — see bug-a-string-release-has-two-implementations-that-already-disagree."
status: done
---

# String literals still allocate at 11,329 sites despite the static-handle pass

- **Type:** perf — **Track A**, tag **O**. `compiler/ir_codegen.inc`
  (`EmitStaticLitHandle` and its callers), possibly the IR shape that reaches it.
- **Found:** 2026-08-31, profiling
  [[perf-a-the-compiler-parses-at-12k-lines-per-second-find-out-why]].
  Split out because that ticket asked *where does the time go* and this is one
  of the answers, with its own fix.

## Measured

70-sample gdb profile, `-g -O2` self-compile, binary `c6cf4c33684a`, at
`4b3d34f74`. Frame #0, with the `??` frames resolved through the compiler's own
`.map` file:

| | samples | |
| --- | ---: | ---: |
| `PXXStrFromLit` | 10 | 14.3% |
| its register-save thunk at `0x400109` | 2 | 2.9% |
| `PXXAlloc` | 7 | 10.0% |
| `PXXFree` | 6 | 8.6% |
| inline refcount inc/dec thunks | 6 | 8.6% |
| `PXXHdrSetMeta`, `PXXDynArrayRelease` | 2 | 2.9% |
| **managed-string + heap runtime, total** | **33** | **47%** |

`objdump -d` on that binary: **11,329** call sites to the thunk. Each is the
same three instructions — `movabs $len, %rdi` / `movabs $ptr, %rsi` /
`call 0x400109` — i.e. a heap allocation and a byte copy per evaluation of a
string literal.

## Why that is surprising

`EmitStaticLitHandle` (`ir_codegen.inc`) exists precisely to make a literal an
address rather than a call, using the ready-made managed-string header
`InternStr` lays down in the pool. Its own comment records the prize:
*"PXXStrFromLit was 9.28% of uforth's profile and the allocator around it most
of another 19%."*

It is **not** disabled. Its gate is `if OptLevel < 2 then Exit`, and `-O2` is
the default (`compiler.pas:877`), so it fires in every ordinary build —
promoted from `-O3` by `440c822e6`. (The paragraph above it still said "behind
-O3 for now"; corrected in the same commit as this ticket.)

So the pass runs and 11,329 sites still call the runtime. **That gap is the
ticket.**

## The suspicion, explicitly unverified

`EmitStaticLitHandle` takes the static path only for a node with
`IRKind[node] = IR_CONST_STR`. A literal that reaches codegen wearing a
different IR shape — a `const AnsiString` parameter, a comparison operand, a
concat operand, a literal already folded into another node — would miss it and
fall to the runtime call. **This is a hypothesis from reading one guard, not a
measurement.** Confirm it by attributing the call sites before changing
anything: they carry their length and pointer in the two `movabs` immediates,
so the pool offset identifies the literal and `Strs[]` maps it back to text.

## Gate

The static-literal count in a self-compiled `-O2` compiler binary drops
materially from 11,329, `PXXStrFromLit`'s share of a fresh profile drops from
14.3%, and an interleaved min-of-N self-compile is faster. Self-host fixedpoint
byte-identical; `optdiff` clean, since this changes emitted code at the default
level.

## Do not re-derive

- `rejected/feature-opt-lazy-token-sval` — "stop materialising token strings"
  was prototyped in full in July and measured **no win** (3.406s → 3.455s).
  Different mechanism from this one, but adjacent enough to be worth knowing.
- The runtime is not the problem: `builtinheap.pas` already grows geometrically
  and the bulk copy is done. This is about not making the call at all.


---

## RESOLUTION 2026-08-31 (frankB) — no defect; the ticket measured a -O0 binary

Binary `f92c42a698509b6112d882bac1097efd63b1eefed50e960d6c2bad9e77e320a1`
(`converged after 2 round(s)`), tree at `763233473`.

### The premise does not survive a positive control

Same source, two opt levels, counting the `call` sites to the PXXStrFromLit
register-save thunk and the static-handle sites (`inc QWORD PTR [rax-0x10]`):

| | calls to PXXStrFromLit thunk | static-handle sites |
| --- | ---: | ---: |
| `-O1` (pass gated off) | **11,329** | 3 |
| `-O2` (pass on) | **1,282** | **9,307** |

**11,329 is the -O1 number, and it reproduces to the digit.** The pass converts
9,307 of 10,589 literal sites — **87.9%** — exactly as designed. There was never
a gap between "the pass runs" and "the sites remain"; the sites counted were
from a build where the pass was gated off.

Two further tells, both checkable without rebuilding anything:

- `compiler/pascal26-debug` on disk has **3** static-handle sites. That is
  `make pxx-debug`, which is `-O0` by design —
  `compiler.pas:1736  if DebugInfo and not OptLevelExplicit then OptLevel := 0`.
- The ticket's cited call target **`0x400109` is not a function entry in any
  build.** In the debug binary the thunks sit at `0x4000d1` (StrFromLit) and
  `0x4000ff` (release); `0x400109` lands *mid-instruction* inside the release
  thunk, two bytes into `jne`. In the `-O2` binary the same thunks are at
  `0x400156` and `0x400184`. An address was carried across two binaries with
  different layouts.

### The two competing explanations, both tested

The profile in `06524ef5b` landed ~10 minutes before `191af3440`, the fix for
the `-O2` inliner dropping a narrowing store. So there were two live
explanations, and they predict opposite things:

- **(a)** the profiled binary was not `-O2` at all; or
- **(b)** the `-O2` binary *of that hour* was miscompiling, and the pass really
  was failing to fire until `191af3440` fixed it.

**(b) is ruled out by direct measurement.** Building the fixedpoint at
`4b3d34f74` — the exact sha the profile was taken at, seeded from
`stable_linux_amd64/default/pinned` with the seed's mtime backdated,
`converged after 2 round(s)`, sha `b11f52fb431669ab5701ca70a494d2cda640ed48327f3a2dca46032dd04a8186`:

| `4b3d34f74`, default `-O2` | |
| --- | ---: |
| static-handle sites | **9,307** |
| calls to PXXStrFromLit thunk | **1,282** |

Identical to today's numbers, digit for digit, on a tree that predates the
inliner fix. **The pass was firing normally at the sha the profile was taken
at**, so no `-O2` binary of that hour could have shown 11,329 sites. Only (a)
survives, and the `0x400109` tell above says the same thing independently.

`devdocs/dev/debugging-playbook.md` already carries this exact trap under
**"Profile the SHIPPING binary — `-g` alone silently means `-O0`"**, including
the instruction to check that `-O2 -g`'s reported `code=NNNN` matches the plain
build's. Doing that check is what closed this: `-O2 -g` gives
`code=9821976B`, identical to the default build.

### The real -O2 profile

`tools/pxxprof`, 30,520 samples, self-compile of `compiler.pas` by the `-O2 -g`
build, symbolised through the compiler's own `.map` (3,849 entries) so the
runtime blobs resolve. `user 12.80` vs `wall 13.18` — pure user CPU — and the
`<outside .text / vdso>` bucket came out at **0.00%**, so no renormalisation is
needed.

| | share | ticket claimed |
| --- | ---: | ---: |
| string RELEASE thunk (`dec [rax-16]` + PXXFree) | **7.72%** | 8.6% (as "refcount thunks") |
| `PXXAlloc` | 4.07% | 10.0% |
| str-slot assign thunk (StrFromLit + release) | 2.93% | — |
| `PXXFree` | 2.48% | 8.6% |
| str RETAIN thunk | 0.30% | — |
| `PXXStrDecRef` | 0.21% | — |
| **`PXXStrFromLit`** | **0.18%** | **17.1%** |
| `PXXStrAppend` / `PXXStrConcat` / `PXXHdrSetMeta` / `PXXDynArrayRelease` | 0.24% | 2.9% |
| **managed-string + heap, total** | **18.2%** | **~47%** |

`PXXStrFromLit` is **0.18%**. It is not a target and there is nothing here to
optimise. The 1,282 residual sites are literals that legitimately do not reach
codegen as `IR_CONST_STR`; at 0.18% total, attributing them would cost more than
it could return. The hypothesis in "The suspicion, explicitly unverified" is
therefore left untested on purpose, not abandoned.

### What survives, and where it goes

The group's real target moved, and it moved onto an existing ticket. The hot
managed-string cost is **refcount release traffic**: one thunk, **300,745 call
sites**, **7.72%** — the hottest thing in the compiler after `ParseFactorCore`
(9.88%) — and its sample distribution piles onto the entry `test rax,rax`
(3.35%) and the `ret` (2.60%) rather than the body, which is the signature of
call overhead rather than work.

That thunk is the same x86-64 hand-emitted blob that
`bug-a-string-release-has-two-implementations-that-already-disagree` documents
as diverging from `PXXStrDecRef`. That ticket is now the centre of the string
group, and it is a perf ticket as much as a correctness one.

### Gate

None run beyond the build: **no code changed.** The self-host fixedpoint above
is the build itself.

## Log
- 2026-08-31 — resolved, commit 848f51734.
