---
slug: decide-old-style-object-types
track: U
prio: 30
status: decided
---

# Decide: do we implement Turbo Pascal `object` types?

`type TFoo = object ... end;` — the pre-Delphi class construct — is **entirely
unsupported**. Not partially: the parser stops at the first field.

```pascal
type TO1 = object x: Integer; procedure Set1(v: Integer); end;
```
```
pascal26:2: error: unexpected token — Expected: begin, but got: x
```

Every form fails the same way: plain, with `constructor Init`, with `virtual`
methods, with inheritance `object(TParent)`.

## Why it is being asked now

It is the single largest remaining cluster in the FPC conformance suite's skip
list. Three tests are skipped for it outright — `tobject2.pp`, `tsealed6.pp`,
`tprocvar1.pp` — and `tprocvar1` only surfaced today, after four *other* gaps it
was blamed on were each fixed and it still would not run.

## What it actually is — and why it is not "just a class"

An `object` is a **value type with a VMT**, and that combination is the whole
cost. It differs from `class` on every axis that matters to codegen:

| | `class` | `object` |
| --- | --- | --- |
| storage | heap, always | wherever declared — stack local, global, record field, array element |
| a variable holds | a reference | the instance itself |
| assignment | aliases | **copies**, bitwise |
| `SizeOf(T)` | pointer size | the instance's real size |
| lifetime | `Create`/`Free`, refcounted for interfaces | scope, like a record |
| `constructor Init` | returns an instance | initialises **in place**, returns nothing |
| VMT pointer | always present | present only if the type has a virtual method, and `Init` is what sets it |
| inheritance | reference-compatible | layout-prefix compatible; assigning a child to a parent **slices** |

So it is closer to "a record with a VMT and a hidden Self" than to a class, and
it lands in Track A's ground: layout, the VMT emit path, the constructor
protocol, and `SizeOf`. Reusing the `UCls` machinery would get the parsing and
method dispatch nearly free; the value semantics (copy on assign, slicing, no
allocation, in-place `Init`) are the part that has no existing analogue.

## The options

**A. Don't.** `object` is deprecated in FPC's own documentation and Delphi
dropped it. No code in this tree, in `lib/**`, or in any corpus we build uses
it. The three conformance tests stay skipped with an honest reason. Cost: zero.
Loss: three tests, and any old real-world Pascal that walks in the door.

**B. Implement it as a record-with-VMT.** Full semantics per the table above.
Unskips the three tests, and makes pre-Delphi source compile. This is a real
feature, not an afternoon: the value-semantics half touches assignment,
parameter passing, `SizeOf`, and the constructor protocol.

**C. Implement the non-virtual subset only** — `object` as "a record whose
methods may be declared inside it", no VMT, no `virtual`, no `constructor`.
Cheap, since `advancedrecords` already does exactly this and works. But it
accepts the keyword while silently refusing the half of the feature that
motivates it, and a program using `virtual` would then fail deeper in with a
worse message than today's clean one. **The bad middle** — this is the option to
avoid.

## Recommendation

**A for now, B when a real program asks for it.** The conformance tests are the
only caller, and "three FPC tests" is not a reason to add a second object model
to the language — that is conforming to FPC's history rather than to Pascal.
The moment actual source someone wants to build needs it, B, in full; the
per-feature strict-flag pattern does not apply here, since this is a missing
feature rather than a laxness.

Worth noting the asymmetry: this is the mirror of the `compat` tag's usual
direction. Most compat work is "behave exactly like the reference on something
we already do". This is "implement a thing the reference has and we don't",
which is a feature request wearing a compat hat, and should be ranked as one.

## If the answer is B

It is a Track A feature (layout / VMT / constructor protocol / SizeOf), sized in
the several-days range, and would want its own ticket chain rather than one
item. `tobject2.pp`, `tsealed6.pp` and `tprocvar1.pp` are the acceptance set,
plus `object abstract` / `object sealed` modifiers for `tsealed6`.

---

# DECIDED 2026-08-25 — **option A: we do not implement `object` types. Not now.**

Decided by an agent under the no-human-available rule
(`devdocs/progress/decided/README-agent-decisions.md`). **Derived.**

Turbo Pascal `object` stays unsupported. The three FPC conformance tests
(`tobject2.pp`, `tsealed6.pp`, `tprocvar1.pp`) stay skipped with an honest
reason naming this decision.

## The principle

`frontend-compat-philosophy.md`, on what a corpus is for:

> *"**A corpus is a measuring instrument, not a dependency.** ... **Do not
> justify core work with a corpus.** Before proposing a compiler change, ask
> what actually DEPENDS on the thing that motivated it."*

Asked. The answer is: three conformance tests, and nothing else. Measured
2026-08-25 — no `= object` declaration exists anywhere in `lib/`, `compiler/` or
`examples/`. No real-world target on the list (self-host, the FPC RTL subset,
Synapse, fgl, zlib, sqlite, QuickJS) requires it, and the owner's standing
framing is *a pragmatic compiler, not a conformance trophy*.

The ticket's own recommendation says the same thing in the same words —
*"'three FPC tests' is not a reason to add a second object model to the
language — that is conforming to FPC's history rather than to Pascal"* — and it
is right. Adding a second object model with different storage, different
lifetime, different assignment semantics and different inheritance would also
run straight into `root-cause-over-microfix.md`'s *"count the mechanisms serving
one concept ... two is a smell"* for a payoff of zero real programs.

## The revisit trigger, stated so it is unambiguous

**Option B, in full, the moment actual source someone wants to build needs it.**
Not "an FPC test needs it" — a program. The acceptance set is then the three
tests plus `object abstract` / `object sealed`, it is a Track A feature (layout /
VMT / constructor protocol / `SizeOf`), and it wants its own ticket chain rather
than one item.

## Option C stays refused

The ticket calls it *"the bad middle"* and that reading holds: accepting the
keyword while silently refusing `virtual` trades today's clean error for a worse
one deeper in. Nothing about the passage of time improves it.

## Re-filed as work

None — this is a decision to not build something. The only follow-on is
bookkeeping: the three `pxx.skip` entries should name this decided ticket as
their reason, so the next conformance sweep does not re-open the question.
Folded into the skip file's normal maintenance rather than given a ticket.

## Log
- 2026-08-25 — decided, commit PENDING-COMMIT.
