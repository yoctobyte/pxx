---
track: A
prio: 30
type: bug
status: backlog
owner: ""
created: 2026-09-04
blocked-by: []
summary: "A `QWord` passed to `array of const` boxes as `vtInt64` (16); FPC boxes the same source as `vtQWord` (17). Measured side by side. `vtQWord` IS declared in builtinheap.pas and appears in EXACTLY ONE place in the whole tree -- its own declaration: zero producers, zero readers. So any consumer that dispatches on the tag the way FPC's does takes the signed branch and renders a value >= 2^63 negative. NOT fixable inside a quick gate: the emit change lands on four backend asm-text readers (x86-64/i386/arm32/riscv32) that test `<> vtInteger and <> vtInt64`, and three of those are invisible on this host."
---

# A QWord boxes as vtInt64, so `array of const` loses unsignedness

Measured 2026-09-04 at `c94252bb92cd`, against `fpc 3.2.2 -Mdelphi -O1`, one
program printing `a[i].VType` for fourteen declared types:

| source type | pxx tag | fpc tag |
| --- | --- | --- |
| `QWord` | 16 `vtInt64` | **17 `vtQWord`** |
| `ShortString` | 11 `vtAnsiString` | 4 `vtString` |
| everything else measured | identical | identical |

The `ShortString` row is **not** a defect — `builtinheap.pas:99` says so at the
declaration (*"vtString = 4; { shortstring; unused with ansistrings }"*), it is
a chosen consequence of this RTL's string model, and it is recorded here only
so the next person measuring this table does not re-file it.

The `QWord` row has no such note anywhere.

## The tag exists and nothing on either side of it is wired

```
$ grep -rn vtQWord compiler/ lib/
compiler/builtin/builtinheap.pas:112:  vtQWord      = 17;
```

One hit, and it is the declaration. Nothing emits it and nothing reads it,
while FPC emits it for ordinary source. A consumer written against FPC's tag
set — `case v.VType of vtQWord: ...` — compiles here and silently takes a
different branch.

## Why it is quiet

Below 2^63 the signed and unsigned readings of the same 8 bytes are equal, so
the divergence is invisible on every small value and appears only at the top of
the range. `IntToStr(PInt64Rec(v.VInt64)^)` on `18446744073709551615` gives
`-1`.

**Do not reach for `Format('%d', [q])` as the repro — it prints `-1` under BOTH
compilers**, so it looks like agreement and proves nothing about the tag. FPC's
own `%d` reads its `vtQWord` signed; that is FPC's formatter choice, not the
tag. The tag is where we differ, and the probe has to print `VType` to see it.

## Why this is filed rather than fixed

Not size — **verifiability.** Emitting `vtQWord` is one line at the
`AN_VARREC_ARRAY` boxing site, but the readers are the constraint:

- `lib/rtl/sysutils.pas` — `FmtArgInt`, `FmtArgStr`, `FmtArgFloat` each `case`
  on the tag with an `else` returning `0`/`''`. A newly-emitted `vtQWord` falls
  into that `else`, so QWord arguments to `Format` would start rendering as
  empty rather than wrong. **The fix makes things worse until the readers land
  in the same commit.**
- `compiler/asmtext.inc`, `asmtext_386.inc`, `asmtext_arm32.inc`,
  `asmtext_rv32.inc` — all four test
  `(VType <> vtInteger) and (VType <> vtInt64)` and REFUSE anything else. This
  is the compiler's own asm-text emitter, i.e. self-host critical, once per
  backend.

Three of those four backends are cross targets. `gate.sh quick` and the
self-host fixedpoint both run on x86-64, so a break in the i386/arm32/riscv32
emitters is **structurally invisible to the gate that would have to approve
it** — the exact defect class this repo has been bitten by twice
(see `bug-a-method-pointer-record-is-hard-sized-16-bytes-on-32-bit-targets`).
Whoever takes it should land emit + all seven readers together and verify on a
cross target, not on this host.

## Ranking

30. The divergence is certain, but nothing in the tree reads `vtQWord` today,
so nothing is currently wrong *because* of it — the cost is that a
tag-dispatching consumer ported from FPC misbehaves silently. Raise it if
`feature-writeln-as-library` phase 3 lands, since a library `writeln` reading
the vector cannot render a large QWord the way the builtin does, and that is a
parity row it will fail.

## Repro

```pascal
procedure Dump(const a: array of const);
var i: Integer;
begin
  for i := 0 to High(a) do write(a[i].VType, ' ');
  writeln;
end;
var q: QWord;
begin
  q := 3; Dump([q]);     { pxx: 16    fpc: 17 }
end.
```
