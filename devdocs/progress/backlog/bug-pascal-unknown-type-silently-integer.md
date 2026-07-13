---
prio: 65
---

# An UNKNOWN type name silently becomes a 4-byte Integer (pointers truncate)

- **Type:** bug (correctness — silent wrong code, no diagnostic)
- **Track:** P — Pascal frontend (shared `parser.inc`, so Track A file-lane)
- **Status:** backlog — opened 2026-07-13.

## Symptom
`ParseTypeKind`'s final fallback is `Result := tyInteger` — meant for enum names, but an
**unknown** name lands there too. So a typo compiles:

```pascal
var x: Integr;      { typo for Integer — compiles, becomes a 4-byte Integer }
```

and, far worse, a pointer type the source never declared becomes a 32-bit int, so every
address stored through it is **TRUNCATED**:

```pascal
var p: PSomethingUndeclared;   { silently a 4-byte Integer }
p := GetMem(64);
```
```
heap-addr = 131751131217928
via-p     = 18446744072423997448     <- corrupted, no diagnostic
```

## This hole has bitten before
`bug-tobject-param-truncated-32bit` was exactly this: `Sender: TObject` fell through to
tyInteger and truncated. That fix special-cased TObject. **It patched the symptom, not the
hole** — and the hole then swallowed `TClass` (a class reference, truncated) and
`Int8`/`Int16`/`Int32` (all silently 4 bytes) until 2026-07-13, when those were fixed the
same one-at-a-time way. The next missing name will do it again.

## Why it was not simply made an error
Tried 2026-07-13 (one line: error instead of `Result := tyInteger`). It does NOT break
forward references — the declaration pre-scan registers the type section up front. It DOES
break the **flagship fgl-compiles test** with `unknown type: TPoint`.

### A wrong lead, recorded so nobody re-walks it
My first hypothesis was that FPC's `types.pp` declares `TPoint` via `{$i typshrdh.inc}`
and that we fail to resolve that include. **That is WRONG.** Checked directly:

```
uses types;         -> SizeOf(TPoint) = 8   (the record from the include: two Longints)
uses fgl;           -> SizeOf(TPoint) = 8   (transitively, same)
uses fgl, types;    -> SizeOf(TPoint) = 8
```

The include IS found and TPoint IS registered — and a missing include in a unit is already
a hard error (verified), so it could not have been silently skipped anyway. So the
"headline FPC-compat leans on this bug" claim in the first draft of this ticket was
**false**; ignore it.

What the strict error's true source is has NOT been isolated. Something in the `fgl` ->
`types` chain references a type name that is unknown AT THAT POINT, and today it quietly
becomes an Integer. Note that `typshrdh.inc`'s TPoint is an ADVANCED RECORD (methods,
`public`, a self-referencing `constructor Create(apt: TPoint)`), and pxx does not parse a
record with a `public constructor` at all — so how much of that declaration actually lands
is worth checking first.

## How to pick this up
1. Re-apply the one-line strict error in ParseTypeKind's final `else`.
2. Compile `test/test_fgl_use.pas --mimic-fpc -Fu/usr/share/fpcsrc/3.2.2/rtl/objpas` and
   find WHICH name is unknown and where. Do not assume it is the include.
3. Fix that, then keep the error.

The truncation hole is the prize and it is worth the dig: it is a silent wrong-code bug,
and it has already produced two shipped symptoms (TObject, then TClass/Int8/Int16).

## Gate
`make test` + self-host byte-identical + cross. The fgl-compiles test is the one to watch.
