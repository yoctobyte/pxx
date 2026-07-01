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

Reverted **4** procedures back to raw `EmitB` (not 3 — `EmitAnsiStrRetainLocked`
turned out unsafe too, see above): `EmitHeapAllocLocked`, `EmitHeapFreeLocked`,
`EmitAnsiStrRetainLocked`, `EmitAnsiStrReleaseLocked`. Kept the 4 verified-safe
conversions: `EmitDynArrayRetainLocked`, `EmitDynArrayReleaseLocked`,
`EmitManagedRecordRetain`, `EmitManagedRecordReleaseLocked` — plus
`asmtext.inc`'s `inc/dec [mem]` addition (needed by
`EmitDynArrayRetainLocked`, itself verified byte-correct and deterministic).

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
