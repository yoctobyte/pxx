---
track: A
prio: 65
type: perf
blocked-by: []
created: 2026-08-31
owner: frankB
summary: "EmitStaticLitHandle turns a string literal into an address instead of a PXXStrFromLit call, and it IS active at -O2 — yet the -O2 compiler binary still contains 11,329 `movabs len / movabs ptr / call PXXStrFromLit` sites, and that call plus its thunk is 17% of a self-compile profile (12/70 samples). Find which literal contexts never reach the pass and route them through it."
status: working
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
