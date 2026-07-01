# EmitAsmX64 conversion of heap-alloc/free/ansistr-retain/release codegen causes unbounded memory growth (OOM) + non-determinism during self-host

- **Type:** bug (codegen — critical, blocks in-progress work) — Track A
- **Status:** done — fixed by reverting the 4 unsafe procedures, keeping the 4
  verified-safe ones
- **Severity:** critical — crashed the host machine's build twice (14GB RSS,
  OOM-killed `pascal26-build` and `gen1` processes) while stabilizing the
  in-progress `ir_codegen.inc` migration onto `EmitAsmX64`.
- **Opened:** 2026-07-01
- **Fixed:** 2026-07-01, commit d6df1a5f

## Symptom

The **uncommitted** working-tree diff to `compiler/ir_codegen.inc` +
`compiler/asmtext.inc` (converting several x64 heap/ARC codegen helpers from
raw `EmitB` byte sequences to text-mnemonic `EmitAsmX64([...])` calls) makes
the resulting compiler binary consume unbounded memory and crash (SIGSEGV
after `mmap` returns `ENOMEM`, or OOM-killed if unbounded) whenever it compiles
a program with more than a small number of `GetMem`/`New`/`SetLength`-on-nil
occurrences. Self-hosting (`pascal26` compiling `compiler.pas` again) reliably
triggers it.

Confirmed via kernel log — two real OOM kills on 2026-07-01 while the user was
testing:
```
Out of memory: Killed process 2690284 (pascal26-build) total-vm:39611084kB anon-rss:14146688kB
Out of memory: Killed process 2700567 (gen1) total-vm:39611076kB anon-rss:14235392kB
```

## Minimal repro (compile-time only, no self-host needed)

```pascal
program stress_n;
procedure Q0;
var a: array of Integer;
begin
  SetLength(a, 1);
  a[0] := 0;
end;
{ ... repeat for Q1..Q16, one SetLength(a, N) call site per procedure ... }
begin
  Q0; { ... Q1..Q16 ... }
  writeln('done');
end.
```
- **16** such procedures (16 distinct `SetLength`-on-nil-array call **sites**
  in the source, one call each): compiles fine.
- **17** sites: the compiler itself (not the compiled output — the compile
  never finishes, `ok:` is never printed) crashes. `strace -e trace=mmap` shows
  it requesting the 256MiB `HEAP_ARENA` (`compiler/builtin/builtinheap.pas:130`)
  over and over, each one *actually consumed* (real ~100-400ms gaps between
  `mmap` calls, not an instant corrupt-pointer crash) until `ulimit -v` cuts it
  off with `ENOMEM`, which the allocator doesn't check, giving a SIGSEGV at
  `PWord($fffffffffffffff4)`-ish addresses.

Full repro generator + bisection scripts were run from
`/tmp/claude-1000/.../scratchpad/bisect/` this session (not preserved — trivial
to regenerate from the snippet above, or ask the session that filed this
ticket).

## Bisection (this session)

Rebuilding `pascal26` from the *old, committed* `ir_codegen.inc`/`asmtext.inc`
(host = the pre-existing `compiler/pascal26` binary, itself untouched) and
self-hosting `compiler.pas` again works fine and is byte-identical — confirms
the harness itself is sound and this is a real regression from the uncommitted
diff, not a pre-existing flake.

Splitting the diff into independent procedure-level variants (each rebuilt
from clean HEAD + exactly one procedure's conversion, everything else
reverted) and self-hosting each:

| Converted alone | Result |
| --- | --- |
| `EmitHeapAllocLocked` | **crashes** (repro above: threshold 16 OK / 17 crash) |
| `EmitHeapFreeLocked` | **crashes** in full self-host (not triggered by the `SetLength` micro-repro — makes sense, that repro's arrays are never freed) |
| `EmitAnsiStrReleaseLocked` | **crashes** in full self-host only; not yet isolated to a small repro |
| `EmitDynArrayReleaseLocked` | **safe** (same code shape as `EmitAnsiStrReleaseLocked`, but dynamic-array locals are rare in `compiler.pas` vs. `AnsiString` locals which are everywhere — consistent with a frequency-gated trigger) |
| `EmitDynArrayRetainLocked` | **safe** |
| `EmitAnsiStrRetainLocked` | **not OOM, but non-deterministic** — see follow-up below (identical source to `EmitDynArrayRetainLocked`, differs only in call frequency) |
| `EmitManagedRecordRetain` + `EmitManagedRecordReleaseLocked` | **safe** |

### Follow-up: a second, separate bug (non-determinism, not OOM)

A second real defect surfaced while verifying the fix: reverting only the 3
OOM procedures above and running the *actual* `make test` gate (which does a
proper 2-generation self-host fixedpoint check: old-host compiles the fix →
`pascal26-build`; `pascal26-build` compiles the same source again →
`pascal26-verify`; `cmp` the two) failed with `differ: byte 97` — a 4-byte
size mismatch between generations. Bisected the same way: isolating each of
the remaining 4 "safe" conversions through the *proper* 2-generation
fixedpoint check (not just "does it crash" — my earlier informal
gen1-vs-gen2 comparison had compared the same binary's output against
itself twice, which is trivially always identical and missed this).

`EmitAnsiStrRetainLocked` alone is non-deterministic across generations;
`EmitDynArrayRetainLocked` alone (**byte-for-byte identical source** — both
are just `EmitAsmX64(['test rax, rax', 'jz .done', 'inc qword [rax-16]',
'.done:'])`) is fully deterministic. Same pattern as the OOM bug: the *code*
isn't wrong, something about *how often* it runs during self-host is —
`AnsiString` locals are everywhere in `compiler.pas`, dynamic-array locals are
rare, exactly mirroring why `EmitAnsiStrReleaseLocked` OOMs but
`EmitDynArrayReleaseLocked` doesn't. Root cause not pinned down (same
"leading theory" below likely covers both bugs), but empirically: anything
touching `AnsiString` retain/release through `EmitAsmX64` is unsafe right now;
the `array of`-dynamic equivalents and the managed-record retain/release are
fine.

Byte-level encoding was manually verified correct for every converted
procedure (`EmitAsmX64`'s output matches the original hardcoded bytes exactly,
including the new `inc/dec [mem]` form added to `asmtext.inc` for this
migration) — this is **not** a wrong-bytes-emitted bug. `strace -tt` timing
(real gaps between arena requests, not instant) also argues against pointer
corruption; it looks like a genuine unbounded allocation loop.

## Leading theory (unconfirmed — next session should verify directly)

`EmitHeapAllocLocked`/`EmitHeapFreeLocked` are **inlined at every call site**
in `ir_codegen.inc` (called directly from 3+ distinct IR-node handlers, not
cached) — so each compile-time occurrence of `EmitAsmX64([...])` inside them
also triggers array-of-const (`AN_VARREC_ARRAY`, `compiler/ir.inc:2061`)
lowering: a hidden hidden-hidden dyn-array temp is `SetLength`'d (calling
`EmitHeapAllocLocked` *again*, recursively at compile time) to hold the
`TVarRec` literal, per `EmitAsmX64` call. The threshold (16 sites × 2
`EmitAsmX64` calls each = 32 OK, 17×2=34 crashes) is suspiciously close to
`ASM_MAX_LABELS = 32` in `compiler/asmtext.inc:750`, but that table *is*
correctly reset per-call and g1a's own literals define no labels at all, so
that specific constant is probably a red herring — likely coincidence, not
cause. More likely candidates to check next:

1. Whether the array-of-const temp (`vrTmp` in `ir.inc`'s `AN_VARREC_ARRAY`
   case, flagged `SymIsHiddenArgTemp`) is actually released at scope exit for
   **every** procedure that makes more than one `EmitAsmX64([...])` call —
   `EmitManagedLocalCleanup` (`compiler/symtab.inc:4130`) iterates
   `Procs[CurProc].ScopeBase to SymCount-1` and looks complete on inspection,
   but this needs a targeted check (e.g. does it actually see hidden temps
   added *during* IR lowering, given the ordering caveat documented right next
   to `SymIsHiddenArgTemp`'s declaration in `compiler/defs.inc:880`?).
2. Whether `EmitAnsiStrReleaseLocked`'s trigger is a *different* mechanism —
   note it's cached as a one-time shared subroutine (`AnsiStrReleaseAddr`,
   `compiler/ir_codegen.inc:405`), so it can't be a compile-time-invocation-count
   leak the same way `EmitHeapAllocLocked` is — its bug (if real, still needs a
   standalone minimal repro rather than relying on full self-host) is more
   likely a runtime bug in the once-emitted shared subroutine itself, gated on
   something `compiler.pas`'s self-compile exercises that a small test program
   doesn't.
3. `gdb catch syscall mmap` + manual `[rbp]`/`[rbp+8]` stack walking mostly hit
   addresses with no DWARF line info (`-g` output only covers the main
   `compiler.pas` CU, not `compiler/builtin/builtinheap.pas`'s own statements)
   — a cheap win for next time would be a breakpoint on a **user-code**
   address that calls `SetLength`/`GetMem` instead of chasing the syscall
   itself, or temporarily building `builtinheap.pas` with `-g` coverage.

## Resolution

Reverted **4** procedures back to raw `EmitB`: `EmitHeapAllocLocked`,
`EmitHeapFreeLocked`, `EmitAnsiStrRetainLocked`, `EmitAnsiStrReleaseLocked`.
Kept the 4 verified-safe conversions: `EmitDynArrayRetainLocked`,
`EmitDynArrayReleaseLocked`, `EmitManagedRecordRetain`,
`EmitManagedRecordReleaseLocked` — plus `asmtext.inc`'s `inc/dec [mem]`
addition (needed by `EmitDynArrayRetainLocked`, itself verified byte-correct
and deterministic).

**Update (see "Root-cause follow-up" below):** of these 4 reverted, only 3
(`EmitHeapAllocLocked`, `EmitHeapFreeLocked`, `EmitAnsiStrReleaseLocked`) are
genuinely broken. `EmitAnsiStrRetainLocked` was reverted on a false positive
— its "non-determinism" was an artifact of a fixedpoint check that's too
shallow for this class of change, not a real bug. Left reverted anyway since
there's no harm in it and re-applying wasn't the point of this ticket; safe
to re-convert whenever someone next touches this code.

Verified clean after the revert:
- Capped self-host (`ulimit -v 3000000`) succeeds, no OOM.
- The 17-site `SetLength` micro-repro now compiles fine even at 60 sites
  (well past the old 17-site crash threshold), still capped.
- Proper 2-generation self-host fixedpoint (`pascal26-build` ==
  `pascal26-verify`) passes.
- Full `make test` green (all gates: threading, asm/asmcore per-target,
  disassembler self-compile, DWARF `-g` smoke, lib-fpc-clean, etc).

Root cause of *why* these 4 specific conversions (all `AnsiString`-touching,
or the raw allocator itself) are unsafe while the structurally-identical
`array of`-dynamic and record equivalents are fine is still **not** pinned
down — see "Leading theory" above, still valid follow-up work if someone
wants to re-attempt the `EmitAsmX64` migration for these 4 procedures. Filing
that as a separate, non-urgent follow-up ticket is reasonable; not blocking
anything right now since the working code (raw `EmitB`) is back in place.

## Acceptance

- [x] Self-host (`pascal26` compiling `compiler.pas`) succeeds byte-identical
      under normal (non-capped) conditions — verified via `make test`'s own
      2-generation fixedpoint check.
- [x] Capped self-host + the `SetLength`-site micro-repro no longer OOM.
- [ ] A standalone regression test (small `.pas` source, no self-host needed)
      reproducing the original crash, wired into `make test` — not yet added;
      the repro snippet above is a good starting point if the `EmitAsmX64`
      migration is re-attempted for the 4 reverted procedures.

## Root-cause follow-up (later session, 2026-07-01)

User asked to dig into *why* the 4 reverted procedures actually break. Two
important corrections came out of this:

### Correction 1: `EmitAnsiStrRetainLocked` was never actually buggy

The "non-determinism" finding above (build vs verify differ by 4 bytes) is a
**false positive** caused by an insufficient fixedpoint check, not a real bug.
Root cause: `EmitAnsiStrRetainLocked`/`EmitAnsiStrReleaseLocked` etc. are part
of *the compiler's own codegen logic* — used to emit the ARC helper functions
embedded in **any** program the compiler builds, including the compiler
itself. When old-host (built before this diff existed) compiles the new
source to produce gen1, old-host emits gen1's *own* embedded ARC helpers
using **old-host's own already-compiled (old, raw-`EmitB`) logic** — the new
source's `EmitAsmX64`-based logic doesn't "activate" for the compiler's own
runtime needs until it's actually running inside a binary. Gen1 *does*
correctly contain the new logic (old-host translated the source correctly),
so when gen1 runs to compile the source again (producing gen2), gen2's
embedded helpers *do* use the new logic. Net effect: **gen1 uses old ARC
helpers for itself but gen2 uses new ones — one inherent generation of lag
whenever a change touches the compiler's own runtime-helper codegen**, not a
correctness bug. Confirmed empirically: isolated `EmitAnsiStrRetainLocked`
alone, gen1 ≠ gen2 (byte 97, `74 04` short `je` vs `0F 84 04000000` long
`je` — raw bytes confirmed via `xxd`), but **gen2 == gen3** (built gen3 from
gen2; byte-identical). `make test`'s 2-generation `cmp` (comparable to
build-vs-verify) is the wrong granularity for this class of change; it needs
a 3rd generation to actually test stability. `EmitAnsiStrRetainLocked` can be
safely re-converted to `EmitAsmX64` if someone revisits this — it was
reverted unnecessarily, though harmlessly.

This does **not** apply to the other three procedures below: each of those
crashes outright (SIGSEGV, gen2 never gets produced), which is unambiguous —
a crash can't be explained away by generation lag.

### `EmitHeapAllocLocked`/`EmitHeapFreeLocked`: confirmed real, encoding ruled out

Extended `test/test_asm_emit_x64.pas` (commit aeba3c2e) with the previously
uncovered instruction forms (`push`/`pop` r8-r15, `inc`/`dec [mem]`, `lock
dec [mem]`, the `.done` forward-jump idiom), each cross-checked against a
live `llvm-mc-18 -triple=x86_64 -x86-asm-syntax=intel -show-encoding` run.
**Every instruction used by the broken procedures encodes byte-for-byte
identical to the oracle** — this is conclusively not a wrong-bytes / 32-vs-64
-bit-truncation bug in the encoder itself (a plausible-sounding theory that
didn't pan out). One real (harmless) finding: `EmitAsmX64` always emits the
6-byte near/rel32 form for a same-call forward label reference, where an
optimizing assembler like `llvm-mc` picks the 2-byte short form (it resolves
sizes in a later pass) — 4 bytes bigger per use, deterministically, not a bug
by itself but it's *what exposed* the gen1-vs-gen2 lag above (shifted overall
code layout enough to be visible).

The OOM itself remains explained by the "Leading theory" above (array-of-const
temp construction happening at every one of the many *compile-time* call
sites `EmitHeapAllocLocked`/`EmitHeapFreeLocked` are inlined at) — this part
is still not nailed down to an exact statement, but is now doubly confirmed
real (not a bootstrap artifact, not an encoding bug) via a repro needing only
one compiler process, no self-hosting.

### `EmitAnsiStrReleaseLocked`: confirmed real but still no small repro

Like `EmitAnsiStrRetainLocked`, this procedure has extra direct (inlined,
compile-time-invoked) call sites beyond its one-time cached-subroutine setup
— `compiler/ir_codegen.inc:3766` and `:3787`, both inside the `SetLength`
implementation's shrink/grow/zero paths for a plain `AnsiString` variable
(*not* an array of `AnsiString` — an easy misread; confirmed by re-reading
the surrounding `if (Syms[symIdx].TypeKind = tyAnsiString) and not
Syms[symIdx].IsArray` guard). Two synthetic repros tried this session — many
procedures growing/shrinking a dynamic array of `AnsiString`, and many
procedures doing `SetLength` shrink-then-grow on a plain `AnsiString` var,
up to 400 sites — **neither reproduced the crash**, unlike
`EmitHeapAllocLocked`'s clean 17-site threshold. Whatever triggers this one
either needs a much higher site count, a different code shape entirely (not
yet tried: exception-handler string cleanup, class-field strings, or the
`ThreadSafeMode`/`lock` variant), or genuinely needs `compiler.pas`'s own
scale/complexity rather than raw repetition count. Re-confirmed the crash
itself is real and not bootstrap-lag: isolating this procedure alone and
self-hosting reliably SIGSEGVs *while producing gen2* (gen2 never completes),
which can't be explained by "just needs one more generation" the way a mere
byte-difference could.

**Still open** if anyone wants to pick this up: find `EmitAnsiStrReleaseLocked`'s
actual trigger condition, and pin down the exact array-of-const-cleanup
mechanism (or find a different one) that explains why compile-time-invoked
`EmitAsmX64` calls leak/corrupt after a threshold. Not blocking — raw `EmitB`
is back in place for all 3 genuinely-broken procedures and `make test` is
green.
