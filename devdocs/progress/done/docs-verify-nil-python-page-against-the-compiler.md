---
track: D
prio: 40
type: docs
summary: "docs/targets/nil-python.md has produced two provably stale claims in one sitting (a four-parameter limit that does not exist, and a dunder list that is wrong) — every remaining behavioural claim on that page needs testing against the pinned compiler, starting with mandatory annotations"
---

# Verify every claim on the Nil Python page by compiling it

- **Type:** docs (Track D — prose only, no compiler or `lib/**` changes)
- **Status:** done
  found false in a single pass.
- **Owner:** frank2-D

## Why this page specifically

Nil Python moved faster than its documentation, and the page has measurably
drifted. Found and fixed on 2026-08-09, both by **testing rather than reading**:

- *"Nil Python is limited to four parameters per function"* — false. Five- and
  eight-parameter functions build and run against the pinned compiler.
- *"there is no operator-overload protocol yet (`__eq__`, `__len__`,
  `__iter__`, `__getitem__`, `__call__`, `__enter__`/`__exit__` are not hooked
  in)"* — mostly false. All of those dispatch except `__iter__`, which is a
  real gap; `with` works on user classes.

Two stale claims in one sitting on one page is a pattern, not bad luck. The
rest of the page was written at the same time and has not been checked.

## The one already known to be unverified

> "It requires explicit type annotations on function parameters and return
> types, while local variables are automatically inferred."

Plausible, matches the design intent, **never tested**. Start here.

## Everything else worth a compile

Walk the page top to bottom and run each behavioural claim:

- **Type inference** — numeric widening to a float slot; retroactive variant
  promotion on incompatible rebinds; static rejection for records/classes/dyn
  arrays. Three claims, three programs.
- **C interop** — return-lifting of trailing `T**` out-params, automatic
  string marshalling both directions, `#define` integer macros as constants.
  (The sqlite CRUD example on the page *was* verified working on 2026-08-09.)
- **Classes** — `@property`/`@x.setter`, module-level `@dataclass`,
  `super().__init__` as a statement-only form, single inheritance refused with
  a diagnostic. (Single inheritance and the diagnostic were verified.)
- **Syntax rules** — tabs/spaces mixing is a compile error; indentation
  suspended inside brackets.

## Rule

Track D's gate applies: **verify by compiling, never by reading the frontend
source** — the source shows intent, the binary shows behaviour, and the two
already disagreed twice here. Any gap found is filed for Track N, not fixed
under D.

## Acceptance

Every behavioural claim on `docs/targets/nil-python.md` either verified against
the pinned compiler or corrected, with the gaps that turn up filed as N
tickets.

## Log
- 2026-08-09 — filed. Two false claims corrected the same day
  (`docs(D): Nil Python targets CPython behaviour; correct the dunder claims`);
  this covers the rest of the page.
- 2026-08-19 — resolved, commit PENDING-COMMIT.
