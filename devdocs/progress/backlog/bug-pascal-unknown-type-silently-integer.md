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
Tried 2026-07-13. It is the right change and it does NOT break forward references (the
declaration pre-scan registers the type section up front). But it breaks the **flagship
fgl-compiles test**, and for an instructive reason:

`fgl` uses `types`, and FPC's `types.pp` declares `TPoint` in its non-Windows branch via
`{$i typshrdh.inc}` — an include we do not resolve (it lives in `rtl/inc`, and adding
`-Fi` to it did not help, so the include itself is not being processed). So `TPoint` is
undefined, and the flagship "we compile real FPC source" test **passes only because the
missing type quietly becomes an Integer**.

That is worth saying plainly: our headline FPC-compat result is currently leaning on this
bug.

## So the fix is two-part, and must land together
1. Make the unknown `{$i}` in FPC's `types.pp` actually resolve (or find why the include
   is skipped — a missing include is supposed to be a HARD error already, per
   bug-pascal-include-search-silent-miss, so something is letting this one through).
2. THEN turn the unknown-name fallback into an error.

Landing (2) alone regresses the fgl gate. Landing (1) alone leaves the truncation hole.

## Gate
`make test` + self-host byte-identical + cross. The fgl-compiles test is the one to watch.
