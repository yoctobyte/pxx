# `Length()` of a pointer-dereferenced frozen `string` returns 0 on the cross targets

- **Type:** bug
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-19 (found while porting streaming/LFM, feature-cross-streaming-lfm)

## Symptom

`Length(p^)` / `Length(rec.pf^)` where the dereferenced value is a frozen
`string` returns **0** on i386 / aarch64 / arm32. x86-64 returns the correct
length. A direct `Length(s)` over a plain `string` variable works on all four.

```pascal
type PStr = ^string;
     TRec = record np: PStr; end;
var s: string; ps: PStr; r: TRec;
begin
  s := 'TRoot'; ps := @s; r.np := @s;
  writeln(Length(s));      { 5 everywhere — baseline OK }
  writeln(Length(ps^));    { 5 on x86-64; 0 on i386/aarch64/arm32 }
  writeln(Length(r.np^));  { 5 on x86-64; 0 on i386/aarch64/arm32 }
end.
```

Repro: `/tmp/lenscope.pas` shape above; compile per target and run under
`tools/run_target.sh`.

## Root cause

Same root as the frozen-string-equality cross bug fixed in 25eb50d: a frozen
string reached through a pointer deref or pointer field is lowered to the inner
pointer-load node, which keeps **IRTk = tyPointer** (its value is the buffer
address, but the tag is not tyString). The `Length` codegen dispatches on the
operand's IR shape/type:

- **x86-64** (`ir_codegen.inc:2931`) has an `else` catch-all: evaluate the
  operand to the buffer address and read the length prefix at `[buf+0]`
  (`mov rax,[rax]`). The tyPointer-tagged frozen deref lands here → correct.
- **i386 / aarch64 / arm32** (`ir_codegen386.inc:1875`,
  `ir_codegen_aarch64.inc:1285`, `ir_codegen_arm32.inc:1480`) only read
  `[buf+0]` when the operand is *recognised as a frozen string* (operand IRTk =
  tyString, or an `IR_LEA` of a `tyString` symbol). A tyPointer-tagged frozen
  deref misses that branch and falls to the dynamic-array/handle default, which
  reads the element/length header at `[value-8]` → garbage → 0.

This did **not** affect streaming/LFM (the RTL compares such strings via `=`,
which is now fixed, and never calls `Length` on a deref'd frozen string), so it
is latent, not a regression.

## Fix direction

Mirror the equality fix on the three cross `Length` handlers: treat a
tyPointer-tagged operand whose value is a frozen-string buffer address as a
frozen string and read the length at `[buf+0]` (like x86-64's `else` branch),
instead of the `[value-8]` handle path. Take care to keep genuine
dynamic-array / managed-handle `Length` (which legitimately read `[value-8]`)
working — the discriminator is the operand's source type, so this likely wants
the same "tyPointer-as-frozen when context is a string" decode used in the
string-eq branches, or a properly threaded type tag. Cross-bootstrap must stay
byte-identical.

## Acceptance

`Length(p^)` and `Length(rec.pf^)` over a frozen `string` return the correct
length on i386 / aarch64 / arm32 (output-equal to x86-64); a regression test
covers the local-pointer and pointer-field forms on all four targets; bootstrap
+ cross-bootstrap stay byte-identical.

## Log
- 2026-06-19 — opened. Found during the streaming/LFM cross port; the sibling
  string-equality manifestation of the same tyPointer-tag root was fixed in
  25eb50d, but `Length` was left (not exercised by the streaming RTL).
