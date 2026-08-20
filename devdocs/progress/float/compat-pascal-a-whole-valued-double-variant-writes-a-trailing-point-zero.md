---
track: P+F
prio: 20
type: compat
blocked-by: []
summary: "`writeln(v)` on a Variant holding a whole-valued Double prints `15.0` where FPC prints `15`. Rendering only — the value is right, and the same Double in a plain variable renders identically to FPC. Float FORMATTING, so it parks here."
status: float
owner: unassigned
---

# A whole-valued Double variant writes `15.0`, FPC writes `15`

- **Track P + F** (F owns the rendering; the file is `VariantToStr` in
  `compiler/builtin/builtin.pas`, which is Track A/P ground).
- Found 2026-08-20 while fixing
  `bug-p-variant-arithmetic-on-a-string-reads-the-payload-as-a-number` — the
  test for that fix tripped over it, and it is NOT part of it: measured
  identical on the PINNED binary, so it predates the change.

## Measured

```pascal
var v: Variant; d: Double;
begin
  v := 7.5; writeln(v * 2);   { FPC: 15      pxx: 15.0 }
  v := 15.0; writeln(v);      { FPC: 15      pxx: 15.0 }
  d := 15.0; writeln(d);      { FPC:  1.5000000000000000E+001  pxx: same }
  v := 7.5; writeln(v * 3);   { FPC: 22.5    pxx: 22.5 }
end.
```

Only the WHOLE-valued variant case differs. A fractional variant matches, and a
plain `Double` variable matches (both render FPC's scientific form). So FPC's
variant-to-string drops a `.0` that pxx keeps.

## Why it is F, and therefore low prio

Float FORMATTING is Track F by the owner's rule, and F is low prio by
definition. The VALUE is right in every case; only its rendering differs, and
only for a variant. Picked up on request, or for fun.

## Where

`VariantToStr` (`compiler/builtin/builtin.pas`) routes `VT_DOUBLE` through
`FloatToStr`. FPC's variant path uses its own shortest-round-trip rendering,
which prints an integral double without a fraction. Fixing it means giving
`VariantToStr` a whole-value test, NOT changing `FloatToStr` — the plain-Double
`writeln` path already agrees with FPC and must stay as it is.
