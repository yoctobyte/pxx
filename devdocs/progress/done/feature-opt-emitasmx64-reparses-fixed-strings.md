---
prio: 60
track: A+O
status: done
owner: frank-optimize
---

# `EmitAsmX64` re-parses the same hardcoded assembly strings on every compile — ~12% of a NilPy compile

- **Type:** feature (codegen — compile-time cost) — **Track O** (file-ownership
  **Track A**: `compiler/ir_codegen.inc`, `compiler/asmtext*.inc`).
- **Opened:** 2026-08-26, by the Track O worker on
  [[feature-opt-o3-register-pressure]]. Filed rather than fixed: it is not a
  codegen-quality problem, it is an algorithmic one in a different file set,
  and the register-pressure ticket is about the emitted code.

## The measurement

Sampling profile (`bench-o/pxxprof`, see the parent ticket for why `perf` is
unusable on this box) of the compiler compiling a **one-line** NilPy file,
compiler built at `-O3`, sha `e7c0d1d2a`:

| symbol | share |
| --- | --- |
| `AsmTextLine` | 3.93% |
| `AsmTextSlice` | 1.75% |
| `AsmTextCharAt` | 1.56% |
| `AsmTextTrim` | 1.23% |
| `AsmTextIsSpace` | 1.08% |
| `AsmTextOperand` | 0.98% |
| `AsmTextCStr` | 0.69% |
| `EmitAsmX64` | 1.13% |
| **total** | **~12.4%** |

That is the *text* assembler — `AsmTextLine` tokenising strings like
`'mov rax, [@glob]'` character by character — running while compiling a file
that contains no inline assembly at all.

## Why it fires

The runtime blob emitters (`EmitAcquireHeapLock`, `EmitHeapFreeLocked`,
`EmitAnsiStrRetainLocked`, `EmitReadLine`, the object blobs, ...) are written as
`EmitAsmX64(['mov rdi, rax', 'push rcx', ...])`. That is genuinely nicer to read
than a wall of `EmitB($48); EmitB($89); EmitB($C7);` — the file says so
explicitly, and standing policy forbids the EmitB-rewrite campaign that would
remove it. So the readability is not the thing to attack.

What is attackable is that the **strings are compile-time constants and the
parse result never varies**. The same ~thousand fixed lines are re-lexed on
every single compile, of every program, on every target.

## Options (unranked — this needs a design call, not a patch)

1. **Memoise per string.** A hash map from the literal line to its encoded
   bytes, filled on first use. Smallest change; keeps every call site as-is.
   Care needed: a line with a `%`/`@glob` placeholder encodes differently per
   argument, so the key must include the substituted values (or such lines opt
   out).
2. **Hoist the blob emission.** Most of these blobs are emitted once per
   program into a fixed prelude. Encode them once into a byte array at
   compiler startup rather than at each emission site.
3. **Precompute at build time.** A generator turns the fixed `EmitAsmX64`
   lists into `EmitBytes([...])` arrays as part of the build, keeping the
   assembly text as the source of truth and never parsing it at runtime. Most
   invasive, largest win, and it does not touch the readability the policy
   protects.

## Acceptance
The `AsmText*` share of a one-line NilPy compile drops to noise, with the
compiler's emitted output byte-identical before and after (this changes *when*
bytes are computed, never *which* bytes).

## Links
Parent [[feature-opt-o3-register-pressure]] ·
[[bug-a-fpc-seed-drift-emitasmx64-forward]] ·
[[bug-emitasmx64-heap-helpers-oom-selfhost]]

## 2026-08-30 (frank-optimize) — DONE, and the headline number in this ticket does not survive measurement

Implemented option 1 (memoise per line), with the cacheability rule decided by
**observation rather than a safe-list**. The redundant work is gone — 99.1% to
99.9% of fixed-line parses are eliminated — but it is worth **~1.5% of wall
clock, not ~12%**, and that correction is the more useful half of this ticket.

### What landed

`compiler/asmtext.inc`: `AsmTextLineMemo` in front of `AsmTextLine`, keyed on the
line string, storing the **encoded bytes**. A hit appends them and never enters
the assembler. Plus a `PXXDBG a.asmmemo` counter line (`AsmMemoReport`, called
from `compiler.pas` beside the final `ok:` line) so the ratio is measurable in
tree rather than by profiler archaeology.

**The cacheability rule is watched, not predicted.** A hand-written "these
mnemonics are safe" table would be the same construction as `IRFirstEvaluated`:
a mirror of another routine's control flow, right when written and silently
wrong once the authority moves — which is exactly
`bug-a-o3-drops-the-first-of-two-chained-qword-multiply-xor-statements`, fixed
three days ago by checking the prediction where it is used. So the first encode
of each line is watched, and the line earns a cache entry only if encoding it
moved nothing but `CodeLen`:

| watched | why it disqualifies the line |
| --- | --- |
| `FixCount` | a relocation was recorded; `Fixups[]` stores `CodeLen`, so the bytes are tied to where they were emitted |
| `LibcSyscallCallCount` | `--rtl-libc` lowered `syscall` to a patched call and recorded the site; replaying bytes would emit the call and register nothing, so the thunk would never be patched in |

`nHoles = 0` is required separately (a `%` line's bytes vary with its argument),
and that also excludes `@data`/`@glob`, which `EmitAsmX64` counts as holes.
Staging mode (`EncToAsmBuffer`) is excluded outright — there `EncB` writes to
`AsmB`, so there is no byte range at `Code[CodeLen]` to capture.

**The guard demonstrably fires**, which matters because this repo has an open
ticket about a guard that cannot
(`bug-a-the-abi-oracle-invariant-is-enforced-by-a-grep-that-cannot-fire`):

```
$ PXXDBG='a.asmmemo:*' pascal26 --rtl-libc h.pas h
PXXDBG a.asmmemo POISON (emitting it moved a counter): syscall
PXXDBG a.asmmemo hits=379 misses=64 poisoned=1 no-room=0 pool=156/8192
```

Nobody told it `syscall` is special. It found out by emitting one.

### Effectiveness

| workload | hits | misses | poisoned | pool |
| --- | ---: | ---: | ---: | --- |
| one-line NilPy | 8,032 | 74 | 0 | 189 B |
| `compiler/compiler.pas` | 48,820 | 71 | 0 | 182 B |

Misses are one-per-distinct-line and never recur; 182 bytes of pool holds the
entire fixed-line working set of a self-compile.

### The measurement that contradicts the ticket

Interleaved A/B, same box, both compilers built at `-O3` (this ticket's stated
condition), compiling the one-line NilPy file, 8 runs each:

```
mean old = 1.6137 s     mean new = 1.5900 s     delta = 1.47%
```

At the default `-O` the delta is ~0.8%, inside run-to-run noise.

**So the filed 12.4% does not correspond to 12% of wall time.** The arithmetic
says why, and it is checkable without a profiler: a one-line NilPy compile issues
**8,106** `AsmTextLine` calls in ~2.26 s. Even at a generous 2 µs per line that is
~16 ms, i.e. **~0.7%** — which is what the A/B measures. Removing 99.1% of the
parses cannot buy 12% when all of the parsing was never 12%.

The 12.4% came from a `pxxprof` sampling run, and this ticket's own tooling note
lists the traps that inflate exactly this kind of figure (samples outside `.text`
swinging 8-38%; builtin units without DWARF collapsing into the first symbol's
range). My own attempt to re-take that profile put **73% of samples outside
`.text`**, so I could not reproduce the 12.4% attribution at all — see the
blocker below.

**The work was still worth doing** — it deletes a genuinely redundant
computation, it is free at run time, and the mechanism is now measurable — but
nobody should pick up the remaining options 2 and 3 expecting a 12% compile-time
win. **On this evidence the ceiling for the whole line of work is ~1.5%.** If
compile time is the goal, the profile should be re-taken (once `-g -O2` works)
and the real hot path attacked instead; `ParseFactorCore`, `IRLowerAST` and
`UNameMatch` were the top attributed symbols in my run.

### Verification

- `make compiler/pascal26`: `converged after 1 round(s)`, `19ee024e3d07`.
- **Byte-identical emitted output, the acceptance criterion**, proven on the
  largest program available rather than a sample: `compiler/compiler.pas`
  compiled by the pre-change and post-change compilers —
  at `-O3` both give `b8a0dd72cb03`, at default `-O` both give `19ee024e3d07`.
- Named tests, old vs new binaries compared byte for byte and run:
  `test_ansistring` ✓, `test_cross_exception` ✓, `test_scheduler` ✓,
  `test_mutex --threadsafe` ✓ (this one exercises the `[@glob]` atomic slot,
  i.e. the relocation path the hole guard excludes) — all identical, all pass.
- `--rtl-libc` hello: identical output, poison fires as shown above.
- `tools/gate.sh quick`: **GREEN**.

One false alarm worth recording, because it is the trap CLAUDE.md names: an
earlier `gate.sh quick` went RED on `self-host fixedpoint` with "the fixedpoint
reached from PINNED differs from compiler/pascal26". That was **my own A/B
procedure**, not the change — I had `git stash`ed to build a comparison binary
and left the pre-change binary on disk while the sources carried the change. The
gate was right and its message said so precisely. Re-verified by rebuilding and
re-running the authoritative `tools/selfhost_fixedpoint.sh`: `agrees with
compiler/pascal26`, exit 0. **Hunt async, verify against a known sha.**

### Filed while here

`bug-a-g-with-o2-or-o3-overflows-the-dwarf-buffer-on-compiler-pas` [A] — `-g`
alone compiles the compiler fine, `-g -O2` and `-g -O3` both die with
`error: DWARF buffer overflow (-g)`. That is what blocked re-taking this
ticket's profile at its own stated build configuration, and it blocks the
debugging playbook's "step through it with `-g -O2` + gdb" row generally.

### Not done, deliberately

Options 2 (hoist blob emission) and 3 (precompute at build time) are untouched.
Option 1 already removes 99%+ of the parses, so they can only compete for the
remaining fraction of ~1.5% — the ceiling above applies to them too. The other
targets (`asmtext_386/arm32/a64/rv32/xtensa/wasm`) have the same shape and were
left alone: same reasoning, and `asmtext_wasm.inc` is another lane's file.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
