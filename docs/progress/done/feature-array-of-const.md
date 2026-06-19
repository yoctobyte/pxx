# `array of const` (TVarRec) parameter support

- **Type:** feature
- **Status:** done (2026-06-19) — all `vt*` element tags land (int/ansistring/
  Bool/Char/Ptr/Int64/Double, db7b636); call-site `[...]` construction +
  open-array marshalling; self-host bugs fixed. Tested incl. cross i386
  (test_array_of_const, _types, _branch, _string, _alloc_after). `High()` over
  the array stays a lexer gap (use Length-1) — minor, tracked separately.
- **Owner:** —
- **Unblocks:** feature-asm-text-emitter
- **Opened:** 2026-06-14 (design discussion: readable asm emission)

## Done so far (2026-06-14)

- `TVarRec` + `vt*` constants declared in `builtinheap` (PXX-only; FPC uses
  `system.TVarRec`). `FixupTVarRecLayout` overlaps `VAnsiString` onto the value
  union and right-sizes to `2*TARGET_PTR_SIZE`, so layout is target-correct (16
  on x64, 8 on i386) without a variant record (none in the dialect yet).
- `array of const` recognised as a param type → open array of `TVarRec`.
- Call site: `f([...])` parses to `AN_VARREC_ARRAY` (param-directed, so `[...]`
  is not mistaken for a set literal), lowered to a heap dyn-array of `TVarRec`
  built with the existing SetLength + record-element-store IR. `Length(items)`,
  `items[i].VType`, `.VInteger`, `.VAnsiString` all reuse open-array-of-record
  paths. String elements store a NUL-terminated char-data pointer (FPC-parity).
- Added `write(PChar)` (runtime strlen + write) to make the dump test print
  strings; `test/test_array_of_const.pas` matches FPC byte-for-byte and is wired
  into `make test`. Bootstrap stays byte-identical.

Remaining: `High()` (not in lexer — test uses `Length-1`); other `vt*` tags;
i386/cross verification; the array-of-const temp heap-leaks per call (FPC builds
it on the stack) — fine for the asm emitter, revisit if it matters.

### Known divergences from FPC (half-working, by design for now)

- **Single-char string literal tags wrong.** `['a']` → PXX `vtInteger` (char
  code 97); FPC `vtChar` (VType 2). Cause: PXX types a 1-char literal as
  `tyChar`, and the lowering routes non-string elements to `vtInteger`. Use
  multi-char strings to stay FPC-identical (the test does). Fix needs a `tyChar`
  → `vtChar` arm in the `AN_VARREC_ARRAY` lowering once a consumer wants chars.
- **Only `vtInteger` + `vtAnsiString` tags wired.** Booleans, floats, chars,
  pointers, variants in `[...]` are not tagged per FPC (chars fall into the
  `vtInteger` bug above; the rest are untested).
- **Heap, not stack — leaks one TVarRec vector per call** (FPC builds it on the
  stack). Reuses the dyn-array SetLength path; no free.
- Borrowed (non-refcounted) string elements — this part matches FPC.

## Motivation

The dialect has no variadic / mixed-type argument facility. `writeln`/`read`
are compiler magic, not something a user routine can imitate. The Pascal answer
is `array of const` (an open array of `TVarRec`, the machinery behind
`Format()`), which lets a routine take a bracketed, mixed-type argument list:

```pascal
emit(['mov eax, %', 2, 'add eax, %,%', 3, 4]);   { strings + ints interleaved }
```

This is the enabler for `feature-asm-text-emitter` (readable asm-as-data
emission) and for any future `Format`-style routine. It is **FPC-3.2.2
compatible** (verified) so it does not threaten the `make bootstrap` path —
unlike multiline strings (FPC 3.3.1 only) or bare varargs (compiler magic),
both of which we explicitly ruled out for that reason.

## What FPC does (verified 2026-06-14, ppcx64 3.2.2)

`procedure emit(const items: array of const)` — the callee walks `items`,
switching on each element's `VType` tag:

```pascal
for i := 0 to High(items) do
  case items[i].VType of
    vtInteger:    use items[i].VInteger;
    vtAnsiString: use AnsiString(items[i].VAnsiString);
  end;
```

Captured facts PXX must reproduce **bit-for-bit** (the same compiler source is
read by both FPC during bootstrap and PXX during self-compile, so layout and
constants must agree):

- `SizeOf(TVarRec) = 16` on x86-64 — `VType` is pointer-sized (`PtrInt`, 8
  bytes) + an 8-byte union. **Target-dependent**: on i386 it is 8 bytes (4 + 4).
  compiler.pas self-compiles to i386 in the fixedpoint, so PXX must emit the
  per-target size, not a hardcoded 16.
- Tag constants: `vtInteger = 0`, `vtAnsiString = 11`, `vtChar = 2`,
  `vtString = 4` (shortstring). With `{$h+}` (ansistrings, which compiler.pas
  uses) a **string literal in an `array of const` is `vtAnsiString` (11)**, not
  shortstring — so we only need two tags for the asm use case: `vtInteger` and
  `vtAnsiString`.
- TVarRec layout: `VType` first (offset 0), then the value union at the
  pointer-aligned offset (8 on x64, 4 on i386). `VInteger` and the
  `VAnsiString` pointer share the union.

## Scope

Minimum viable for the asm emitter (int + ansistring elements):

1. **Type recognition** — accept `array of const` as a parameter type; expose
   `TVarRec`, the `vt*` constants, and the element fields (`VType`, `VInteger`,
   `VAnsiString`) to source. Match FPC's names/values so one source compiles
   under both.
2. **Call-site construction** — for `f([a, 1, 'x', expr])`, lower each element
   to a stack/temp `TVarRec`: integer expr → `{VType:=vtInteger; VInteger:=v}`;
   ansistring expr/literal → `{VType:=vtAnsiString; VAnsiString:=handle}`. Build
   the contiguous array, pass it as an open array `(ptr, High)` like other open
   arrays. **Target-correct element size** (16 on 64-bit targets, 8 on i386).
3. **Callee read** — `items[i].VType` / `.VInteger` / `.VAnsiString` and
   `High(items)`/`Length(items)` already fall out of open-array + record field
   access; just need the field offsets right per target.
4. Refcounting: an `array of const` does **not** own its ansistring elements
   (FPC convention — `VAnsiString` is a borrowed pointer; the caller's string
   outlives the call). So no IncRef/DecRef on construction — simpler, and
   matches FPC so behaviour is identical.

Defer: the other `vt*` tags (vtChar, vtBoolean, vtExtended, vtPointer,
vtVariant, …) until a consumer needs them. Two tags carry the asm-emit ticket.

## Acceptance

- A routine `procedure dump(const a: array of const)` reading `VType` +
  `VInteger`/`VAnsiString` compiles and runs identically under FPC and PXX, on
  x86-64 and (self-compiled) i386.
- `dump(['s', 1, 't', 2, 3])` prints the same on native and i386 target.
- New `test/test_array_of_const.pas` wired into `make test` (+ test-i386).
- Compiler still bootstraps (`make bootstrap`) and self-compiles byte-identical.

## Notes / landmines

- Same self-host discipline as always: the feature is used *in* compiler.pas
  (by the asm emitter), so PXX must self-host it, and the layout/constants must
  match FPC exactly or the bootstrap and the self-build diverge.
- Watch the i386 8-byte TVarRec (pointer-sized `VType`) — easy to assume 16.
- See [[project_tsymbol_field_landmine]] only if touching symbol tables; this
  is mostly parser (literal lowering) + codegen (element store) + a record-type
  registration.

## Log

- 2026-06-14 — opened from the "readable asm emission" design thread. FPC
  array-of-const interleaving verified (`emit(['mov a,%',2,'etc %,%',3,off])`
  compiles & walks). Layout/constants captured above. Gate for
  feature-asm-text-emitter.
