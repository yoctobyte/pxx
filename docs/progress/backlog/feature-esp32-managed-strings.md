# ESP32 managed strings (tyAnsiString runtime on xtensa + riscv32)

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-17 (from feature-esp32-managed-features)
- **Depends-on:** feature-esp32-managed-features

## Motivation

PXX **defaults to managed strings**: `PasInitDefines` (lexer.inc) seeds
`PXX_MANAGED_STRING`, so `AnsiString`/`String` are `tyAnsiString` (tk=23) — a
refcounted handle to a `[refcount:8][length:8][data]` block (handle = data
pointer, length at `[handle-8]`, chars at `[handle+0]`, `s[i]` = `handle+(i-1)`
1-based). `-uPXX_MANAGED_STRING` opts into the frozen `tyString` (tk=4) inline
buffer.

On ESP the managed-string runtime (`PXXStr*`) is currently **guarded out**
(feature-esp32-managed-features keeps only the allocator + lean dynarray). So
`s := 'lit'` silently stores the frozen-literal pointer instead of building a
managed handle, and `Length(s)` reads `[ptr-8]` = garbage. Real string support
on ESP needs the runtime ported.

## Scope

1. **Port `PXXStr*`** off the `{$ifndef PXX_ESP}` guard in `builtinheap.pas`:
   `PXXStrFromLit`, `PXXStrConcat`, `PXXStrIncRef`, `PXXStrDecRef`,
   `PXXStrUnique`, `PXXStrEq`, `PXXStrSetLen`. They cross-reference each other +
   `PXXAlloc` (not external strings), so they should compile on ESP once
   un-guarded; fix any stage-1 codegen gaps they surface. Register them for ESP
   in `parser.inc` (currently allocator-only).
2. **Wire managed-string codegen** on both ESP backends (mirror i386/aarch64):
   - `s := <literal>` → `PXXStrFromLit(len, src)` then publish handle (release
     old).
   - `s := t` (lvalue) → IncRef new + DecRef old (ARC).
   - `a + b` → `PXXStrConcat`.
   - `Length(s)` → `[handle-8]` (nil → 0) — already wired; verify it takes the
     managed path, not the dynarray one.
   - `s[i]` (read/write) → `handle + (i-1)`; write position clones via
     `PXXStrUnique` (COW).
   - comparisons → `PXXStrEq`; `SetLength(s, n)` → `PXXStrSetLen`.
   - scope-exit DecRef of locals (ARC bookkeeping).
3. `IR_LEA` for a scalar `tyAnsiString` read must load the handle (mirror i386
   `tyAnsiString` branch); write position keeps the slot address for
   `PXXStrUnique` to publish.

## Validation

Print a built/concatenated string char-by-char via `PutC(Integer(s[i]))`
(passthrough already landed) and compare to the x86-64 oracle on both
esp32s3 + esp32c3 under `tools/esp_run.sh`. Cover: literal assign, var copy
(refcount), concat, `Length`, index, `SetLength`. `make test` + self-host
byte-identical after each step.

## Notes

- A frozen-`tyString` Length/store path was prototyped + reverted during
  feature-esp32-managed-features (wrong layer — frozen is off-by-default).
- Use `--dump-ir` to confirm types: tk=23 managed, tk=4 frozen; `tkLength`
  builtin id = -44.
- ESP self-host is NOT a goal; validate by output-equality vs x86-64.
