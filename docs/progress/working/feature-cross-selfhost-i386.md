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

2026-06-13 (latest): the apparent endless loop was quadratic include expansion,
not parser/codegen recursion. `ExpandIncludes` appended a 1.37 MB expanded
compiler source one byte at a time with `SetLength` on each byte; the
i386-generated compiler made that look like an endless CPU/memory-growth run.
Bulk span/string append now gets past include expansion and completes the
deeper fixed-point compile.

## Current wall

2026-06-13 (Int64 codegen landed). `feature-i386-int64-codegen` is done: the
i386 backend now has a real edx:eax model (commits 7756241, 68bef67). This
cleared the zeroed-float-constant divergence (it was `IRIVal[node] shr 32`
mis-lowered by the old low-dword model) and the `PWord = ^Int64` machine-word
landmine that, once Int64 access became truly 8-byte, wrote 8 bytes into
i386's 4-byte handle slots and corrupted neighbours.

The i386-hosted compiler now starts and mmaps its heap without crashing. The
next wall is a token/parse divergence: compiling any program (even
`begin end.`) the i386-hosted compiler reports

```
Expected: unit, but got:  (Kind: 0, Line: 1)
```

i.e. `ParseProgram` reaches an `Expect(tkUnit)` after consuming the whole
source, so the lexed token stream / program-vs-unit dispatch is wrong under
the i386-hosted compiler. Isolated Int64 records, file load, managed-string
index-write, and div/mod all match native (`make test-i386` green incl. the
new oracle), so this is a narrower miscompile in the lexer / `LexAll` /
dispatch path, not a general Int64 gap — suspect another machine-word /
global-record-array width mismatch the old low-dword model masked.

### Earlier note (the float-constant wall, now cleared by the Int64 work)

The deeper self-fixedpoint probe now terminates and produces matching
code/data/BSS sizes, but the binaries are not byte-identical:

```sh
./compiler/pascal26 -dPXX_MANAGED_STRING --target=i386 \
  compiler/compiler.pas /tmp/compiler_i386_native
/tmp/compiler_i386_native -dPXX_MANAGED_STRING \
  --target=i386 compiler/compiler.pas /tmp/compiler_i386_self
cmp /tmp/compiler_i386_native /tmp/compiler_i386_self
```

Observed 2026-06-13: both compilers report
`[code=1467327B data=43304B bss=131496552B procs=794]`, but `cmp` first differs
at byte 24194. The diff is in the emitted x86-64 float writer code embedded in
the i386 compiler: native emits the double bits for `1000000000000000.0`
(`0x430c6bf526340000`), while the i386-hosted compiler emits zero. This is the
same underlying problem seen repeatedly in this burn-down: i386's scalar model
only carries low dwords for many `Int64` operations/stores, so `shl`/`shr`,
large integer constants, float bit patterns, pointer serialization, and related
codegen paths keep needing local workarounds. See
`feature-i386-int64-codegen.md`; fixing that should be treated as the next
foundation task before more self-host patching.

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
- 2026-06-13 — fixed the include-expansion performance wall by adding bulk
  append helpers for string/span copies. The same fixedpoint probe now completes
  quickly and reaches `cmp`; first diff is a zeroed 64-bit float constant in
  generated x86-64 float-writer code. Handover: stop adding narrow `shr 32`
  workarounds and implement real i386 `Int64` codegen/support next.
- 2026-06-13 — real i386 Int64 codegen landed (feature-i386-int64-codegen, now
  done; commits 7756241, 68bef67). The float-constant divergence is gone (it
  was `shr 32` under the low-dword model). Found+fixed the `PWord = ^Int64`
  machine-word landmine: with true 8-byte Int64 access, PXXStrUnique's
  `PWord(slot)^ := handle` wrote 8 bytes into i386's 4-byte handle slot and
  nulled the neighbouring managed-string handle (then crashed on deref). PWord
  is now `^NativeInt` (pointer-sized). The i386-hosted compiler no longer
  crashes; next wall = the `Expected: unit` token/dispatch miscompile described
  under Current wall. `make test{,-i386,-aarch64,-arm32}` all green.
