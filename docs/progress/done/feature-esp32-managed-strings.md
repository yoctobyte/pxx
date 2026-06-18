# ESP32 managed strings (tyAnsiString runtime on xtensa + riscv32)

- **Type:** feature
- **Status:** done 2026-06-18 (all core paths; also exercised on bare-metal in feature-esp32-bare-boot)
- **Owner:** —
- **Opened:** 2026-06-17 (from feature-esp32-managed-features)
- **Depends-on:** feature-esp32-managed-features

## Progress

- 2026-06-17 — **core done** (commit eb849b3): builtinheap restructured so the
  target-independent ARC runtime (PXXStrFromLit/Concat/IncRef/DecRef/Unique/Eq/
  SetLen + MemMove/MemZero + PXXDynSetLen) is no longer behind the blanket
  `{$ifndef PXX_ESP}` — only file I/O, managed-element dynarray/record retain,
  variant and float formatting stay ESP-excluded. Codegen on both ESP backends:
  IR_STORE_SYM tyAnsiString (literal/char/frozen/handle build + DecRef-old
  publish), IR_LEA scalar tyAnsiString (read=load handle, write=slot addr),
  Length `[handle-8]`, index `handle+(i-1)`. test_esp_string → 3/PXX/PXX both
  ISAs == oracle.
- 2026-06-17 — **concat done** (commit dd91333): `a + b` → PXXStrConcat on both
  backends (handle/tyString/char operands, fresh-temp DecRef, nested concat).
  test_esp_strcat → "PXX rocks"/"PXX rocks!"/9 both ISAs == oracle.
- 2026-06-18 — **riscv32 compare + harness fix** (commit c7309b0): PXXStrEq on
  riscv32 (Y/N/Y/Y/N == oracle); shared EmitStrOperandRISCV32 decomposition;
  esp_run.sh force-relinks (was running stale images — see Known bugs). xtensa
  compare + the concat-of-two-string-literals bug remain (below).
- 2026-06-18 — **xtensa compare done**: PXXStrEq path in the xtensa IR_BINOP
  (operand decompose mirrors concat: a4=lenA,a5=srcA,a6=lenB,a7=srcB; xor for
  tkNeq). test_esp_strcmp Y/N/Y/Y/N both ISAs == oracle.
- 2026-06-18 — **SetLength + s[i] COW + scope-exit DecRef done** (both ISAs).
  SetLength(s,n)->PXXStrSetLen (tyAnsiString IR_LOAD_SYM lvalue, mirrors
  aarch64). s[i] write COW: IR_INDEX clones-if-shared via PXXStrUnique when base
  is an IR_LEA scalar tyAnsiString in write position; IR_STORE_MEM now sets
  InLValueWrite around the address eval so the IR_LEA keeps the slot addr.
  Scope-exit DecRef of tyAnsiString locals in EmitProcEpilog (xtensa+riscv32).
  **ROOT-CAUSE FIX**: the ESP prologue managed-local nil-init (parser.inc) was a
  no-op placeholder -> uninitialised local strings held stack garbage and
  scope-exit DecRef wild-freed them (Guru Meditation / Load access fault). Now
  zeroes the pointer-sized handle slot. Tests: test_esp_strmut
  (QXX/QYX/QXX/QY), test_esp_strscope (4000-churn arena survival -> OK4/kept).
  Full ESP suite byte-equal to x86-64 oracle both ISAs; make test green.

## Known bugs (found 2026-06-18)

- ~~concat of two string literals crashes~~ **FIXED (commit e1c9198).** Root
  cause was not the EmitStrOperand decomposition: `tyString + tyString` has no
  frozen-concat codegen on ESP, so it fell through to the *integer* binop
  (adding two const_str addresses), then the sum was read as a string ->
  garbage len -> arena overflow -> crash. In managed mode the only tyString
  operands are literals, so `'a' + 'b'` (string/char literals) now folds to a
  single interned literal at IR-lowering (ESP-gated; self-host byte-identical).
  Residual unfolded tyString concat (nested pure-literal `'a'+'b'+'c'`) raises a
  clear ESP-backend error instead of miscompiling.
- ~~xtensa string compare not wired~~ **FIXED 2026-06-18.** PXXStrEq path added
  to the xtensa IR_BINOP (decomposition inlined like the xtensa concat, no
  shared helper). test_esp_strcmp Y/N/Y/Y/N both ISAs.

## Remaining

All core paths done (compare, SetLength, s[i] COW, scope-exit DecRef). Ticket
ready to close pending board move. Open follow-ups (minor):

- Managed-aggregate locals on ESP (array of AnsiString / record-with-managed
  fields) still raise "managed aggregate locals not yet supported" in the
  prologue zero-init — only the scalar pointer-sized handle is nil-inited.
- xtensa char-concat operand uses `addi a6, sp, off` (±128 imm) — deep nesting
  with a char operand could overflow; revisit if hit.
- Scope-exit DecRef on ESP only releases scalar tyAnsiString locals (not local
  dynarrays — those leak on the static arena, harmless; mirror later if needed).

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
