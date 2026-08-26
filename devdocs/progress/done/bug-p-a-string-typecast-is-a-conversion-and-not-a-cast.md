---
track: P
prio: 55
type: bug
blocked-by: []
summary: "`String(x)` is routed to a conversion intrinsic that demands a Char/string operand, so the hard typecast `String(p^)` of an untyped-pointer deref is rejected — while `Integer(p^)`, `PtrUInt(p^)`, `Pointer(p^)` and `TObject(p^)` all compile. Blocks every string-instantiated FPC container (`TFPGList<string>`, `TFPGMap<string,…>`) in real `fgl.pp`."
status: backlog
owner: —
---

# A `String(...)` typecast is treated as a conversion, not as a cast

**RESOLVED 2026-08-26.** The branch now ENDS in the cast instead of in an error.
See Outcome at the end -- including what the two fgl drivers hit one layer
deeper, which is NOT this.

- **Type:** bug (Pascal frontend — typecast vs intrinsic)
- **Track:** P — tag: compat
- **Found:** 2026-08-25, bringing up the fgl rung of the Pascal real-world
  corpus ladder ([[feature-pascal-corpus-fgl]]).

## Measured (pxx `stable_linux_amd64/default/pinned`, VERSION 374; oracle FPC 3.2.2)

Hard-cast an untyped-pointer dereference to each of several target types:

| expression | FPC 3.2.2 | pxx |
| --- | --- | --- |
| `Integer(p^)` | compiles, `5` | compiles, `5` |
| `PtrUInt(p^)` | compiles, `9` | compiles, `9` |
| `Pointer(p^)` | compiles | compiles |
| `TObject(p^)` | compiles | compiles |
| **`String(p^)`** | compiles | **`error: String(): operand must be Char or string`** |

```pascal
program t;
var s: string; p: Pointer;
begin s := 'x'; p := @s; writeln(String(p^)); end.
```

Same wall through a generic type parameter, which is how library code reaches
it — `T(p^)` where the specialization substitutes `T = string`:

```pascal
type
  generic TBox<T> = class function Get(p: Pointer): T; end;
  TStrBox = specialize TBox<string>;
function TBox.Get(p: Pointer): T; begin Result := T(p^); end;   { T = string -> error }
```
`specialize TBox<Integer>` compiles and runs; only the `string` instantiation
fails, so the generic machinery is fine and the defect is purely in how the
name `String` is resolved in cast position.

## Root shape

`String(...)` resolves to the **conversion intrinsic** (the one that turns a
`Char` into a one-character string) instead of to a **type name in a typecast**.
Every other builtin type name resolves as a cast target. Two mechanisms serve one
concept — see `devdocs/dev/normalise-dont-special-case.md`; the fix is to make
`String` a cast target like the rest and keep the intrinsic only where the
argument genuinely needs converting, not to add a third special case.

Grep for the sibling before closing: `Char(x)`, `AnsiString(x)`,
`WideString(x)`, `ShortString(x)` and `UnicodeString(x)` are the names most
likely to share the routing.

## Why it matters (the real-world hit)

FPC's `fgl.pp` — the reference RTL's generic-container unit — is unusable for
**any string-instantiated container** because of this. Two independent sites:

- `rtl/objpas/fgl.pp:892` — `TFPGListEnumerator.GetCurrent`:
  `Result := T(FList.Items[FPosition]^);` → blocks `TFPGList<string>`
- `rtl/objpas/fgl.pp:1602` — `TFPGMap` key handling → blocks
  `TFPGMap<string, …>` and `TFPGMapObject<string, …>`

String-keyed maps and string lists are the most-used containers in real Object
Pascal code, so this single resolution bug removes most of fgl's practical value.

## Repro / gate

`test/fgl/list_str.pas` and `test/fgl/map_str.pas` are the corpus drivers,
currently skip-listed against this ticket in `test/fgl/pxx.skip`. Remove the skip
lines when fixed and `tools/run_fgl_corpus.sh` enforces the passes against the
recorded FPC 3.2.2 oracle output.

Gate = `make compiler/pascal26` (self-host fixedpoint) + `tools/gate.sh quick`.

## Links
Rung: [[feature-pascal-corpus-fgl]] · umbrella
[[feature-pascal-corpus-expansion]]


---

## Outcome (2026-08-26)

Fixed as the ticket asked: not a third special case, but by making the
`tkString_T` branch END in the same `AN_PTR_CAST` the identifier-cast path
builds. The conversions above it are untouched -- a Char, a managed string and a
Variant are genuine conversions and are still answered first -- and everything
past them is a cast.

The shape of the old code is the lesson. The branch read
`if tyPointer then <cast> else Error`, and that pointer arm was ITSELF a previous
fix of this same wall ([[bug-p-string-of-a-pchar-is-rejected-while-ansistring-of-it-works]]):
`String(p)` on a PChar had been rejected while `AnsiString(p)`, `s := p` and
`StrPas(p)` all worked. It landed as one more operand KIND rather than as the
rule, so the next operand kind hit the wall unchanged -- which is exactly what
`devdocs/dev/normalise-dont-special-case.md` predicts and what
`root-cause-over-microfix.md` means by two mechanisms being a smell.

No operand kind is refused there any more. That matches what the identifier path
already did: pxx accepts `AnsiString(i)` where fpc says *Illegal type conversion*.
Accepting a form fpc rejects is not a defect under the FPC-parity ceiling; the
two spellings DISAGREEING was.

Pinned in `test/test_string_typecast_is_a_cast.pas` -- the untyped-deref rows, the
raw-block row that is fgl's own shape, the generic rows (with the Integer
instantiation, which always worked and is what says the generic machinery was
never the problem), and the char/string rows that prove the cast did not swallow
the conversions.

## The fgl rung: 3 pass -> 4 pass, and what the last two really hit

`objectlist.pas` un-skipped and PASSES -- that is
[[bug-p-inherited-ignores-the-parents-default-parameter-values]], fixed earlier
the same day, whose skip line nobody had removed.

`list_str.pas` and `map_str.pas` now COMPILE: the String-typecast wall this ticket
names is gone from both. They fail one layer deeper, and measuring that split it
cleanly:

```pascal
ps := PStr(blk); ps^ := 'alpha';
WriteLn(String(p^));       { read  through the cast: 'alpha'  -- fixed here }
string(p^) := s;           { WRITE through the cast: silently writes NOTHING }
```

So the read half is this ticket and is done; the write half is
[[bug-p-a-cast-as-lvalue-does-not-accept-a-builtin-type-name]], which
`ifclist.pas` was already skip-listed against. Their skip lines are rewritten to
name that ticket and to record the extra fact measurement turned up: for a
STRING target the cast-as-lvalue is not rejected the way `Pointer(Dest^) :=` is
-- it is ACCEPTED and silently writes nothing, so the list reads back empty and
the map raises EListError on a key it thinks it stored. Silent, which is worse
than the error its sibling gives.

Fixing that one closes all three remaining fgl drivers.
