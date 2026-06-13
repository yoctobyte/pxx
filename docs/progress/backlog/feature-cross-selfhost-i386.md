# Cross self-host: i386 generated compiler runs under Linux

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Unblocks:** feature-cross-bootstrap-selfhost
- **Opened:** 2026-06-13 (split from cross self-host rollup)

## Goal

Make the i386 compiler binary emitted by native `pascal26` work as a compiler.
Tackle this platform independently from AArch64 and ARM32, even if root causes
turn out to overlap.

## Current failure

Repro from repo root:

```sh
./compiler/pascal26 -dPXX_MANAGED_STRING --target=i386 \
  compiler/compiler.pas /tmp/compiler_i386
./compiler/pascal26 -dPXX_MANAGED_STRING --target=x86_64 \
  test/hello.pas /tmp/hello_native_to_x64
tools/run_target.sh i386 /tmp/compiler_i386 -dPXX_MANAGED_STRING \
  --target=x86_64 test/hello.pas /tmp/hello_i386_to_x64
```

Observed 2026-06-13: `tools/run_target.sh i386 /tmp/compiler_i386 ...`
segfaults (`rc=139`) before producing a comparable output.

## Acceptance

- The i386-generated compiler compiles `test/hello.pas` to x86-64 under
  `tools/run_target.sh i386`.
- The emitted x86-64 `hello` is byte-identical to native `pascal26` output for
  the same command.
- The emitted x86-64 `hello` runs and prints `Hello, World!`.
- Then extend to `compiler/compiler.pas -> i386` self-fixedpoint and compare
  byte-identical outputs.

## Current wall

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

Next step: implement AnsiStrUnique-style copy-on-write for i386 managed-string
index writes (and audit `res := s` share semantics), mirroring the x86-64
COW path. This is the remaining sizable feature for i386 self-host.

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
