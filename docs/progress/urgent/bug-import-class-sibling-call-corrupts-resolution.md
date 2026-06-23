# bug: importing a unit whose class calls a sibling method corrupts the importer's name resolution

- **Type:** bug (Track A — compiler, symbol resolution / likely a fixed-size table overflow)
- **Status:** urgent (blocks wiring garin/lfmload into the Eliah GUI; capacity bug, may bite other large programs)
- **Found:** 2026-06-23, wiring the .lfm loader into the Eliah IDE (Track B)
- **Severity:** high — spurious, misleading "undefined variable" on perfectly valid
  code; the failure is in the *importer*, far from the unit that triggers it.

## Symptom

Adding one more unit to a large program's `uses` clause makes the program fail to
compile with `undefined variable` errors on the program's OWN class members
(methods *and* fields) — members that resolve fine without that import. The error
points at the importer; the cause is the imported unit.

Real case: the Eliah IDE (`apps/ide/eliah/main.pas`, ~12-unit graph: gtk3,
controls, stdctrls, extctrls, graphics, forms, sysutils, buffer, runner, docmodel,
designer) builds fine. Add `, lfmload` (the garin .lfm box-loader) to `uses` and
nothing else, and it fails:

```
pascal26:198: error: undefined variable (OnPlaceToggle)   { a THandler method }
```

Remove the lfm seeding and the import again → builds. `lfmload` itself compiles
and passes its gate clean (bochan, 31/31) — the defect is purely in the
*combination* large-importer + this-unit.

## What actually triggers it (reduced)

The imported unit only needs a **class with a method that calls another method of
the same class** — by *any* call syntax:

```pascal
unit ubad6;
interface
type TThing = class n: Integer; procedure Reset; procedure Go; end;
implementation
procedure TThing.Reset; begin n := 0; end;
procedure TThing.Go; begin Reset; end;      { bare; Reset() and Self.Reset behave identically }
end.
```

Importing `ubad6` into the Eliah program (`good_main.pas` = the committed
`apps/ide/eliah/main.pas`) reproduces:

```
pascal26:185: error: undefined variable (PlaceMode)   { a THandler FIELD }
```

Variants tested (all against the Eliah importer):
- `Go` calls `Reset` **bare** → breaks.
- `Go` calls `Reset()` (parens) → breaks.
- `Go` calls `Self.Reset` → breaks.
- a paramless **function** `Origin` referenced by a sibling (`n := Origin + v`) → breaks.
- class with a method but **no** sibling call (`ubad4`, `ubad5`) → **does NOT break**.

So the trigger is the *presence of an intra-class method reference* in the
imported unit, not its call syntax.

## Capacity-dependent

A **small** importer does not reproduce, no matter the call form:
- `pmain.pas` (one 2-method class calling a sibling) + `ubad6` → builds fine.
- `pbig.pas` (one 8-method, 5-field class, several sibling calls) + `ubad6` → builds fine.

Only the full Eliah unit graph tips over. This points at a **fixed-size table**
(symbol / method-ref / relocation / fixup) that the large graph nearly fills; the
extra intra-class reference from the imported unit overflows it, and the overflow
corrupts later symbol resolution — surfacing as "undefined variable" on whatever
member the importer references next.

## Expected

Importing a unit must never change how the importer resolves its own class
members. Either grow/guard the table, or fix the indexing so an imported unit's
method-refs don't alias the importer's symbol slots.

## Repro (in-tree)

1. `git show <eliah-with-editable+palette>:apps/ide/eliah/main.pas > /tmp/good_main.pas`
2. create `ubad6.pas` (above) in `/tmp`
3. `sed -i 's/, designer;/, designer, ubad6;/' /tmp/good_main.pas`
4. `stable_linux_amd64/default/pinned -Fulib/rtl -Fulib/pcl -Fuapps/ide/garin -Fuapps/ide/eliah -Fu/tmp /tmp/good_main.pas /tmp/x`
   → `undefined variable (PlaceMode)`. Drop `ubad6` from `uses` → builds.

## Track B impact / parking

`apps/ide/garin/lfmload.pas` + its bochan gate (31/31) land now (garin core, no
GUI graph — under the limit). Wiring it into Eliah (`LoadLfmText` seeding the
designer docmodel) is **parked**: Eliah keeps its hardcoded sample form until this
is fixed. No app-logic workaround applied — the integration is simply blocked.
