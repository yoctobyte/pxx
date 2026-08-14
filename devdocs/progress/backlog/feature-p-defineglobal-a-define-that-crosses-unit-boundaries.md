---
track: P
prio: 40
type: feature
summary: "`{$DEFINEGLOBAL xyz}` — a conditional define that outlives the unit that sets it. Measured: pxx matches FPC today, a unit's {$DEFINE} does not reach the program, which is correct Pascal and is also why two units cannot coordinate. The motivating case is 'first implementation loaded claims the name, second skips itself' — the shape that would have dissolved the pylib/sysutils Exception problem."
---

# `{$DEFINEGLOBAL xyz}` — a define that crosses unit boundaries

- **Type:** feature (dialect extension) — **Track P** (Pascal frontend; the
  implementation is in the shared `lexer.inc`, so it lands under Track A's
  no-concurrent-edit rule).
- Raised by the user 2026-08-14, having circled it earlier the same day:

> *"In Pascal, `$define`s are per unit, by definition. A unit has no way of
> setting a global `$define`. Because if we could, there would be no issue — we
> can just implement one or the other, whichever gets loaded first sets the
> global define and the second implementation can skip it."*

## Measured — the current behaviour is correct, and is the constraint

```pascal
unit u1;  {$DEFINE FROM_UNIT}   …
program p;  uses u1;  {$IFDEF FROM_UNIT} … {$ENDIF}
```

| | result |
|---|---|
| pxx | `define stayed in the unit` |
| FPC | `define stayed in the unit` |

Identical. So this is **not a bug and not a gap** — it is standard Pascal, and
`{$DEFINE}` must keep behaving this way. The feature is a *new, explicitly
named* directive alongside it, not a change to the existing one.

## What it is for

The motivating pattern is **claim-and-skip**: two units can supply the same
capability, and whichever is compiled first claims it, so the second compiles
itself out rather than colliding.

```pascal
{$IFNDEF PXX_HAS_EXCEPTION_CLASS}
  {$DEFINEGLOBAL PXX_HAS_EXCEPTION_CLASS}
  type Exception = class … end;
{$ENDIF}
```

That is the shape the user identified as dissolving the pylib/sysutils
`Exception` problem — see [[decide-merge-variant-c-with-bare-name-collision]]
and [[decide-class-namespace-scoping]]. Whether it is the right answer *there*
is settled separately (that case was closed as synthetic); the mechanism is
useful regardless, and this ticket is the mechanism, not the application.

## Design questions to settle before building

1. **Ordering makes it order-dependent by construction.** "First one wins"
   means the answer depends on `uses` order — the exact property
   [[bug-p-uses-order-does-not-decide-which-unit-wins]] worked to make
   deterministic. That is acceptable *when the program asked for claim-and-skip*
   and unacceptable as an accident, so the directive's name and documentation
   have to make the dependence obvious. `{$DEFINEGLOBAL}` reads as "global",
   not as "order-sensitive"; a name like `{$CLAIM}` might be more honest.
2. **Can it be undefined?** A global `{$UNDEF}` reopens the same race. Probably
   set-once, never cleared, which also makes it cheap.
3. **Scope of "global".** Whole compilation, presumably — not "all units
   compiled after this point in the uses graph", which would be subtler and
   harder to reason about.
4. **Does it survive into a used unit's own conditionals?** i.e. is it visible
   to units compiled *before* the setter, if they are re-entered? Almost
   certainly no, and saying so is cheaper than discovering it.

## Not a substitute for scoping

Worth stating so it is not reached for as a shortcut: claim-and-skip papers over
a name collision, it does not resolve one. Where the real answer is unit-scoped
resolution ([[bug-pascal-uses-is-transitive]]), this must not become the excuse
not to do it.

## Related

- [[feature-a-strict-flags-scope-to-dialect-ownership-not-program-vs-unit]] —
  sibling idea from the same conversation; both are about a unit declaring
  something about itself that the rest of the compilation must respect.

## Gate

A unit setting `{$DEFINEGLOBAL X}` is visible to `{$IFDEF X}` in the program and
in units compiled after it; a plain `{$DEFINE X}` in a unit still is **not**
(the FPC-parity test above, which must keep passing); and two units guarding the
same capability with claim-and-skip compile with exactly one of them active.
