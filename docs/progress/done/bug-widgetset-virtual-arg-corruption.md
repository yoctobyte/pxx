# bug: new virtual method on TWidgetSet miscompiles its object argument

- **Type:** bug
- **Status:** done (resolved — not reproducible; codegen verified correct)
- **Track:** A
- **Opened:** 2026-06-23
- **Resolved:** 2026-06-24

## Summary

Adding a new `virtual` method to `lib/pcl/uwidgetset.TWidgetSet` (overridden in
`gtk3widgets.TGtk3WidgetSet`, dispatched through the base-typed global
`WidgetSet: TWidgetSet`) miscompiles the method's **first object argument**: the
callee receives a garbage pointer in place of the object, while a trailing
`Integer` argument arrives correct. Dereferencing the bad pointer segfaults.

Discovered building the `TPaned` widget (Track B, draggable splitters). Three new
methods were added — `CreatePaned(AComp; AVertical)`, `SetPanedPosition(AComp;
APos)`, `GetPanedPosition(AComp)`. Observations:

- `WidgetSet.SetPanedPosition(P, 150)` ran the right method body (confirmed via a
  debug `writeln`) but `TControl(APaned).Handle` read `0x41E654`-ish (a
  code-segment address), not the real gtk handle. `APos` was the correct `150`.
- The identical call inlined as `gtk_paned_set_position(P.Handle, 150)` (direct,
  no widgetset) worked.
- `CreatePaned` "worked" only because its body never dereferences `APaned` (it
  uses only the `AVertical` flag).
- Existing widgetset methods with the same `(TComponent, Integer…)` shape
  (`SetBounds`, slot 16) work fine — so it is not simply "object arg through a
  base-typed global virtual."

## Not yet minimally isolated

A single-unit class with 42 `(TThing, Integer)` virtuals does **not** reproduce
(args intact). A 2-unit attempt reproduced a crash but turned out to be a
*different* issue — a unit `initialization` section assigning the global was not
running, leaving it nil; an explicit init call fixed that case. So the precise
trigger (cross-unit + ~42-slot vtable + the managed-`string`-returning methods
that sit mid-vtable, e.g. `GetMemoText`/`SelectFolder`, + override dispatch)
is not yet reduced to a clean repro. The PCL-context failure is 100% reproducible
(see git history of this change / the `TPaned` work).

## Workaround in tree (undo when fixed)

`lib/pcl/extctrls.pas` `TPaned` talks to gtk **directly** via `gtk3_c`
(`gtk_paned_new` / `gtk_paned_set_position` / `gtk_paned_get_position`) instead of
routing through `TWidgetSet` methods — the same direct-gtk style `graphics.pas`
already uses, so it is idiomatic here, not a hack. The child packing
(`gtk_paned_pack1/2`) lives in the **existing** `TGtk3WidgetSet.SetParent`
(`TPaned` branch), which is an established virtual slot and works.

Undo once this ticket lands: move paned create/position into proper `TWidgetSet`
virtuals (`CreatePaned` / `SetPanedPosition` / `GetPanedPosition`) and drop the
`gtk3_c` calls from `extctrls`. Grep marker: `bug-widgetset-virtual-arg-corruption`.

## Log
- 2026-06-23 — filed from Track B (TPaned / draggable splitters). Workaround:
  TPaned calls gtk directly.
- 2026-06-24 (Track A) — **could not reproduce; codegen proven correct.** Closed.

## Investigation 2026-06-24 (Track A)

Reproduction was attempted four ways; none miscompiled the object argument:

1. **Faithful synthetic, current compiler.** Two/three-unit program: a 42-virtual
   base class (matching `TWidgetSet`'s exact slot order, incl. the mid-vtable
   `string`-returning `GetMemoText`/`SelectFolder`), a derived class in a separate
   unit overriding those + 3 new tail methods (`CreatePaned`/`SetPanedPosition`/
   `GetPanedPosition`), dispatched through a base-typed global, called from a third
   unit that sees only the base, and also from inside a method passing its own
   `Self`. Object arg always correct.
2. **Real PCL, current compiler.** Re-added the three methods to the actual
   `uwidgetset`/`gtk3widgets`, routed `TPaned.SetPosition` through
   `WidgetSet.SetPanedPosition(Self, v)`, compiled `examples/solitaire_gui`.
   Disassembled `TPaned.SetPosition`: the call site is **correct** —
   `rdi`=WidgetSet (Self), `rsi`=the TPaned object arg (`[rbp-0x8]`), `rdx`=pos,
   `mov rax,[rdi]` / `call [rax+0x140]` (slot 40). No corruption.
3. **Real `uwidgetset` (42-slot) runtime, gtk-free.** Derived widgetset in its own
   unit over the *real* base + real `TComponent`, run for real: prints
   `AControl.Name=PanedX APos=150`. Correct.
4. **Bug-era compiler (v44, a452136, the day the ticket was filed).** Built that
   compiler in a temp dir and recompiled both the faithful synthetic and the real
   PCL against the current libs. Byte-identical correct call site (same `rdi`/`rsi`/
   `rdx`, slot 40). So even the compiler in use when the bug was reported emits
   correct code for this exact scenario.

### Conclusion

No compiler defect is reproducible for "new TWidgetSet virtual miscompiles its
object argument", on the current compiler or the one in use when filed. The
reported symptom (object arg = a code-segment address / garbage pointer) matches
the **fixed** v48 method-context family — `bug-method-miscompiled-by-context`
(closed 9c54a91) and the local-var-shadows-method parser hang (435d565), both of
which produced garbage/uninitialised values from surrounding context. The
original report also notes a 2-unit attempt that turned out to be a *different*
issue (an `initialization` not running, leaving the global nil) — i.e. the
diagnosis was already known-contaminated.

`TWidgetSet` virtuals with `(TComponent, …)` signatures dispatch correctly. The
Track B workaround in `extctrls` (TPaned talks to gtk directly) is therefore
**safe to lift** whenever convenient — left in place here to avoid colliding with
the live Eliah/TPaned work. If the miscompile ever recurs, **capture the exact
failing `.pas`** and reopen: a concrete repro is the missing piece, not more
structural guessing.
