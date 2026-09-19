---
summary: "@obj.Method is typed Pointer, so passing it to a TMethod parameter fails overload resolution — test_pcl_tabbar and examples' eliah_ide do not compile, on HEAD and on the pin"
track: P
prio: 60
type: bug
blocked-by: []
status: open
owner: ""
---

# `@obj.Method` is typed `Pointer`, so it cannot be passed as a `TMethod`

Measured 2026-09-19 by frankH while running the pcl GUI suite under
`--ro-rtti`. **Not caused by that flag** — identical with the flag on and off,
and **red on the PINNED compiler too**, so it is pre-existing and not a
regression from this week's work.

## Symptom

`lib/pcl/extctrls.pas:111` declares:

```pascal
function AddButton(ATab: Integer; const ACaption: string;
                   AOnClick: TMethod): TButton;
```

and the ordinary call site

```pascal
Bar.AddButton(tStd, 'Btn', @h.PickA)
```

is refused with

```
no overload ... (Integer, ShortString, Pointer)
```

**`@obj.Method` is typed `Pointer`.** A method pointer is two words — code
address plus instance — and `TMethod` is the type that carries both, so a
bare `Pointer` cannot match it and the overload set has nothing to bind to.

## Who is blocked

- `test_pcl_tabbar` — does not COMPILE.
- `examples/` **`eliah_ide`** — does not COMPILE. That is a demo program, which
  is goal-list surface (*"have a nice list of working demo's"*), not an
  internal fixture.

## What is NOT the question

- Not `--ro-rtti`: asserted both ways, identical.
- Not new: reproduces on the pin.
- Not `TMethod`'s declaration: `AddButton` assigns `b.OnClick := AOnClick`
  at `extctrls.pas:354`, so the parameter type is doing its job; the argument
  never reaches it.

## Where to start

Type `@` applied to a method reference as a method pointer (code + instance)
rather than as a plain `Pointer`, and check the sibling spellings before
closing — the same address-of construct is reachable through a bare method
name, a qualified one, and an interface method, and the one that stays broken
is the one nobody grepped for.

**Positive control:** a program whose ONLY use is `@obj.Method` passed to a
`TMethod` parameter must compile and the handler must fire — asserting that it
compiles is not enough, because a `Pointer` that merely type-checks would call
with no instance.
