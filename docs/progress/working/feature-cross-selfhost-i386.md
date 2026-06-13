# Cross self-host: i386 generated compiler runs under Linux

- **Type:** feature
- **Status:** working
- **Owner:** codex
- **Unblocks:** feature-cross-bootstrap-selfhost
- **Opened:** 2026-06-13 (split from cross self-host rollup)

## Goal

Make the i386 compiler binary emitted by native `pascal26` work as a compiler.
Tackle this platform independently from AArch64 and ARM32, even if root causes
turn out to overlap.

## Probe

Repro from repo root:

```sh
./compiler/pascal26 -dPXX_MANAGED_STRING --target=i386 \
  compiler/compiler.pas /tmp/compiler_i386
./compiler/pascal26 -dPXX_MANAGED_STRING --target=x86_64 \
  test/hello.pas /tmp/hello_native_to_x64
tools/run_target.sh i386 /tmp/compiler_i386 -dPXX_MANAGED_STRING \
  --target=x86_64 test/hello.pas /tmp/hello_i386_to_x64
```

Observed 2026-06-13 after the i386 managed-string COW slice: the probe passes.
The i386-generated compiler emits `/tmp/hello_i386_to_x64`, `cmp` matches the
native x86-64 output byte-for-byte, and the result prints `Hello, World!`.

## Acceptance

- The i386-generated compiler compiles `test/hello.pas` to x86-64 under
  `tools/run_target.sh i386`.
- The emitted x86-64 `hello` is byte-identical to native `pascal26` output for
  the same command.
- The emitted x86-64 `hello` runs and prints `Hello, World!`.
- Then extend to `compiler/compiler.pas -> i386` self-fixedpoint and compare
  byte-identical outputs.

## Cleared walls

2026-06-13 (later): no longer a crash. The i386-emitted compiler now starts,
lexes, parses, and compiles ~118 lines of the heap RTL before failing with a
semantic error:

```
pascal26:119: error: no overload of heapmmap matches these arguments
```

Root cause: **i386 has no copy-on-write for managed-string writes** (already
flagged in the IR_INDEX comment in `ir_codegen386.inc`). `LowerCase` does
`res := s; res[i] := Chr(...)`, which shares `s`'s handle and then mutates it
in place. With no COW, the in-place write corrupts the *shared* original, so
the call name `HeapMmap` is folded to `heapmmap` in a buffer that is still
aliased by the case-preserved decl name — MatchProcCall's exact `=` then
misses (`Procs[40].Name = 'HeapMmap'` vs lookup `'heapmmap'`).

Minimal repro:

```pascal
function LowerCase(const s: ansistring): ansistring;
var i: integer; res: ansistring;
begin res := s; for i:=1 to Length(res) do if res[i] in ['A'..'Z'] then res[i]:=Chr(Ord(res[i])+32); LowerCase:=res; end;
// x:='HeapMmap'; LowerCase(x) leaves x='heapmmap' on i386, 'HeapMmap' on x86-64
```

2026-06-13 (latest): the `heapmmap` COW wall is cleared. i386 now has
AnsiString index-write clone-if-shared handling via `PXXStrUnique`, and the
byte-identical `compiler.pas --target=i386` then `hello.pas --target=x86_64`
probe passes under `-dPXX_MANAGED_STRING`.

## Current wall

The deeper self-fixedpoint probe now starts but does not terminate in practice:

```sh
./compiler/pascal26 -dPXX_MANAGED_STRING --target=i386 \
  compiler/compiler.pas /tmp/compiler_i386_native
tools/run_target.sh i386 /tmp/compiler_i386_native -dPXX_MANAGED_STRING \
  --target=i386 compiler/compiler.pas /tmp/compiler_i386_self
```

Observed 2026-06-13: `/tmp/compiler_i386_native` stays CPU-bound on one core
and memory grows steadily without visible compile progress. User confirmed this
same loop/memory-growth shape across the last 3-4 iterations and killed the
run manually. This is past the COW wall and should be investigated as a new
i386 self-host loop, likely in parser/IR/codegen state growth while compiling
`compiler.pas` to i386.

## Log

- 2026-06-13 — opened with current failure (`rc=139` segfault).
- 2026-06-13 — burned down the startup→lex→parse→codegen segfaults. Fixed seven
  i386 codegen bugs (commits on master): IR_LEA scalar-AnsiString handle load;
  nil-init of hidden managed-string arg temps; char/byte-width param-home store;
  width-aware (movzx/movsx) function-result load; open-array param load (data
  pointer, not slot address); by-ref AnsiString deref moved from IR_LEA into
  Length/IR_INDEX; IR_ZERO_SYM handler. The compiler now runs as a compiler and
  fails on the COW wall above instead of crashing. `make test` +
  `test-i386/arm32/aarch64` stay green throughout.
- 2026-06-13 — i386 managed-string COW wall cleared. The i386 compiler can now
  compile `test/hello.pas` to x86-64 under `tools/run_target.sh`; the generated
  output is byte-identical to native `pascal26` output and runs successfully.
  During this repro, fixed narrow i386 self-host 64-bit serialization cases
  where `shr 32` on small values duplicated or lost the low dword. General
  full-width i386 `Int64` codegen is still tracked separately as a backend gap.
- 2026-06-13 — deeper `compiler.pas -> i386 -> compiler.pas -> i386`
  fixedpoint probe reaches the next wall: apparent endless compile loop with
  steady memory growth. The process remains CPU-bound; no byte comparison is
  reached.
