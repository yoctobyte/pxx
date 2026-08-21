---
prio: 70
status: done
---

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.


# regression CASCADE: 11 jobs newly red in 4f526e338..8654c4d55 (241 commits) — auto-filed by twatch

- **Type:** regression cascade (auto-filed by Track T watcher, host plexus).
  Untriaged. 11 jobs went red in ONE sweep — treat as ONE root cause until
  triage proves otherwise; do NOT fan out per-job tickets.
- **Found:** 2026-08-21T10:19:04Z
- **Root-cause suspects in the red set:** none of the known root jobs — likely a broken build or harness event

## Range
> **The named sha `8654c4d55b61` CANNOT be the cause** — it touches no buildable file (docs/tickets/tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range, and the cause is somewhere below it.

bad `8654c4d55b61`, last good `4f526e338205`, **241 commit(s) in range** (16 of them buildable). **No idle bisect will happen** — the watcher skips cascades deliberately (one synthetic key matches no job), so this range is narrowed by hand or not at all.

**Buildable commits in the range, newest first:**
- `b8ce37d5bfc4` chore(stable): pin v369
- `ef895b743c14` feat(A): emitted nil checks on method-call receivers
- `a90ad49efdb2` fix(A): `OnClick := nil` segfaulted at the store
- `97b1812fece0` feat(A): a nil procvar call is catchable now, on every target
- `3bf6f623fa95` test(P): a helper's const is not a global — the test was asserting the leak
- `59cddd3b7780` fix(A): a unit's {$mode} turned delphi mode off for the whole program
- `09aaae653d25` fix(A): line numbers after an {$I} include named no line of any file
- `0e452e1aa16a` fix(A): AIntToStr('-5') was '', not '-5'
- `8f851204d193` refactor(A): the last three copies of "is this an ESP-class target?"
- `15db37e627b5` feat(A): Copy() on a nested dynamic array
- `bda942a0b02d` feat(A): --mimic-fpc-compiler — the FPC-compiler build-config define profile
- `8b2d2d7c5c40` fix(A): sigaltstack + SA_ONSTACK on i386, arm32 and aarch64
- ...and 4 earlier commit(s) in the range, not listed

## Repro (start with a suspect, or any listed job)
`tools/testmgr.py --tier native --job '<job>'` at 8654c4d55b61605fc5dea51a38887e713d5b9fc0

(The sha above is the right one to REPRODUCE at — the jobs really are red
there — even when the Range section says it cannot be the CAUSE. Reproducing
and blaming are different questions and this line answers the first.)

## Newly red jobs
- `test-asm#src:compiler/compiler.pas`
- `test-core#src:test/test_rust_advanced.rs`
- `test-core#src:test/test_rust_assoc_fns.rs`
- `test-core#src:test/test_rust_chess_engine.rs`
- `test-core#src:test/test_rust_chess_perft.rs`
- `test-core#src:test/test_rust_chess_perft_full.rs`
- `test-core#src:test/test_rust_chess_search.rs`
- `test-core#src:test/test_rust_else_if.rs@1`
- `test-core#src:test/test_rust_else_if.rs@2`
- `test-core#src:test/test_rust_struct_array.rs`
- `test-core#src:test/test_rust_tuple_struct.rs`

*Cascade stub: one signal for one event. Track T agent (face 2) or the owning
dev track triages the root; individual tickets only for whatever remains red
after the root is fixed.*

## Triaged and fixed — 2026-08-21 (agent-A)

**TWO root causes, not one.** The cascade heuristic ("11 jobs in one sweep =
one event") was right that nothing per-job needed filing and wrong that a single
commit explained it; the 10 Rust jobs share a cause, `test-asm` has its own.

### 1 — the ten Rust jobs: `.rs` was handed to the Pascal include pre-pass

Every `.rs` file failed at line 1 with `Rust: expected [ after # (attribute)` —
including a bare `fn main() {}`, which contains no `#` at all. `--debug` gave it
away in one line: *Loaded file length: 14 / After include expansion: 107*.

`ExpandIncludes` prepends a `# <line> "<path>"` marker since the -g line-table
fix (`09aaae653d25`), and the guard that keeps non-Pascal sources away from it
is a hand-written chain of eleven `(not isXxx)` terms — which never listed
`isRust`. So the Rust lexer got a leading `#`, read it as an attribute, and
demanded a `[`. Before the markers landed the same omission was harmless, which
is why it survived: the guard was already wrong and only became visible when
`ExpandIncludes` started changing the text of files with no `{$I}` in them.

The chain existed in THREE places and had already drifted apart — the
include-expansion site listed NilPy but not Rust; the RTTI site listed Rust but
not NilPy (deliberately, per its own comment); `dce.inc` had all twelve. Fixed
by root cause rather than by adding a twelfth term: one `IsPascalFrontend`,
assigned once beside the extension tests, used at all three sites (the RTTI one
as `IsPascalFrontend or isNilPy`, preserving exactly what it meant).

A second, latent bug fell out of the same lines — **missing `begin`/`end`**:

```pascal
  if (not isC) and ... and (not isErl) then
    ExpandIncludes(Source, SourceFileDir, DbgSrcName);
    ExpandPasMacros(Source);      { <- ran for EVERY frontend }
```

The indentation claimed the guard covered both calls; it covered one. The FPC
text-macro pre-pass has been running over C, Rust, Zig, Ada, BASIC, NilPy and
the rest since it was added. Harmless in practice (it acts only on
`{$define x := y}`, which is Pascal-only syntax) but it is a Pascal pass reading
non-Pascal text with Pascal string and comment rules, and it is now inside the
`begin`/`end` the layout always implied.

### 2 — `test-asm#src:compiler/compiler.pas`: the disassembler met CPUID and RDRAND

Unrelated to the Rust half. The row is `./pascal26 -S compiler/compiler.pas`
followed by `! grep -q "^    db "` — no undecodable bytes allowed. Four appeared,
in `__pxxCpuidRdrand` and `__pxxHwRandom64`: `0F A2` (cpuid) and `48 0F C7 F0`
(rdrand rax) had no arm in `asmdisasm_x64.inc`.

RDRAND was the worse of the two. `db 48 / db 0f` resynchronised ONE BYTE LATE
and printed `mov eax, 0x48c2920f` — an instruction that is not there, assembled
out of the `C7 F0` that follows plus the next four bytes. A `db` line announces
"I do not know this"; a plausible wrong mnemonic does not, and `-S` output is
read by people. Added `0F A2` and the `0F C7 /6` `/7` group (rdrand/rdseed, REX.W
selecting the 64-bit destination); `/1` (cmpxchg8b/16b, memory form) deliberately
still falls through to `db` rather than guess.

### Verified
All ten Rust jobs compile, run, and match their recorded output/exit codes —
including `test_rust_chess_perft_full` (kiwipete included) and the `--strict-ir`
variant of `else_if`. `-S compiler/compiler.pas` now yields **zero** `db` lines
and decodes `cpuid` / `rdrand rax` / `setb dl` correctly; `-S test/hello.pas`,
`test_asm_mvp.asm` (exit 42) and `test_asmcore_x64` still pass. Zig, Ada, BASIC,
C and NilPy sources all still compile after the `ExpandPasMacros` narrowing.

Gate: `make compiler/pascal26` + `tools/gate.sh quick` GREEN.

## Log
- 2026-08-21 — resolved, commit 89b5c896e.
