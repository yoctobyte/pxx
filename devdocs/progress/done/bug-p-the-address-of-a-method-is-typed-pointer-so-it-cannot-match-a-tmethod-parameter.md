---
summary: "@obj.Method is typed Pointer, so passing it to a TMethod parameter fails overload resolution — test_pcl_tabbar and examples' eliah_ide do not compile, on HEAD and on the pin"
track: P
prio: 60
type: bug
blocked-by: []
status: done
owner: frankH
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

## Resolution — 2026-09-19 (frankH)

**The premise was half right, and the half that was wrong decided the fix.**
`@obj.Method` IS typed `Pointer`, deliberately, so `TakesPtr(@h.M)` works. But
it DOES bind a TMethod parameter on a FREE call: measured, `Take(@h.Pick)`
compiled and fired with the instance on HEAD and on the pin. Both free-call
paths (pasparser_expr.inc, pasparser_stmt.inc) report an AN_METHODREF argument
as tyRecord. The method-call overload selector (`FindUMethOverloadAhead`,
pasparser_call.inc) never had that line, so only METHOD calls refused it. A
half-wired door: same construct, second call path. Fixed there, with the
siblings' wording.

(FPC 3.2.2 refuses `Take(@h.Pick)` for a TMethod parameter: "Incompatible
type for arg no. 1". We accept it on purpose, on both paths now, and that is
not a defect: accepting what FPC rejects.)

Positive control (`test_methodref_arg_to_a_method_call.pas`, row
test_mramc26.1), per the body above:
- bare `@Pick`, `@Self.Pick` and a VIRTUAL method through a base-typed var
  all reach the OVERRIDE with the INSTANCE (`der tag=9`);
- an `Ov(Pointer)` / `Ov(TMethod)` overload pair picks TMethod on the method
  path, exactly as `FOv` does on the free path.

The row fails on the pin (rc=2). Sibling rule checked on the method path: a
dyn-array-returning call passed to an open-array parameter already works there.

Unblocked: `test_pcl_tabbar` is OK in tools/gui_suite.sh, and `eliah_ide`
builds and passes its smoke and real-window rows. **Its size check still
answers 0x0, exactly like solitaire_gui**, so the positive control this was
meant to restore for bug-b-solitaire-gui-... fails the same way. That is now
that ticket's question: is it a shared pcl cause, or a check that cannot see
windows here?


## Log
- 2026-09-19 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
