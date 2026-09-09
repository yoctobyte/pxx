---
slug: bug-n-collections-counter-is-unreachable-through-its-qualified-spelling
track: N
prio: 35
type: bug
status: backlog
owner: ""
created: 2026-09-09
found-by: frankB
tags: [nilpy, stdlib, collections, overload]
blocked-by: []
summary: "`collections.Counter()` is refused with `no member Counter came of the qualifier collections`, while the bare `Counter()` and `from collections import Counter` both work. Measured 2026-09-09. Cause: `collections` HAS a backing unit (lib/rtl/collections.pas, a Pascal generic TList unrelated to Python's module), so the qualifier resolves against it and asks it for a member it has never had. deque was fixed on 2026-09-09 by routing `collections.deque` through the frontend's stdlib-call table, which is consulted BEFORE unit-member lookup; Counter was deliberately NOT routed the same way, because that table re-targets by ARITY and cannot select by argument TYPE, and Counter's two 1-argument overloads differ only by type (TPyList vs AnsiString) -- an entry would compile `collections.Counter(s)` to whichever arity found first and answer a silently wrong count instead of today's honest refusal. So this is blocked on either type-aware selection in that table, or a different mechanism for qualified stdlib members."
---

# collections.Counter is unreachable through its qualified spelling

## Measured 2026-09-09 (compiler 418064fca1d3)

| spelling | result |
| --- | --- |
| `Counter()` (no import at all) | works |
| `from collections import Counter` then `Counter()` | works |
| `import collections` then `collections.Counter()` | **refused** |

The refusal reads `no member Counter came of the qualifier collections — check
what collections resolves to; an import that bound nothing gives exactly this`,
which is accurate and points at the right half of the line.

## Why the qualified spelling is the one that matters

Every use site in the lekkerzeilen corpus is `module.name`; not one is
`from module import name`. The two spellings that work are the ones nobody
writes. That is what made the sibling `deque` gap worth fixing, and it applies
here identically — the difference is only that nothing measured reaches
`collections.Counter` yet, which is why this is prio 35 and deque was not.

## Why it was not fixed alongside deque, stated so nobody "fixes" it wrongly

`collections.deque` is now mapped in `PyStdlibCallProc` (compiler/pyparser.inc),
the same table that carries `math.pow` -> `Power`. That table is consulted
before unit-member lookup — measured with `math.pow`, which resolves through it
while `lib/rtl/math.pas` exists and is loaded — so it needed no resolver-order
change and left `collections.abc` untouched.

**It cannot carry Counter.** `PyParseStdlibCall` resolves its target with
`FindProc(pname)` plus a RE-TARGET BY ARITY step, and its own comment says
"Type-based selection is still not reachable this way". Counter is:

```pascal
function Counter: TPyDict;
function Counter(l: TPyList): TPyDict; overload;
function Counter(const s: AnsiString): TPyDict; overload;
```

The two 1-argument overloads differ only by type. An entry in that table would
make `collections.Counter(some_string)` and `collections.Counter(some_list)`
compile to the same body — a silently wrong count, where today there is a loud
refusal. **That trade is the wrong direction** and this ticket exists to record
that it was considered and declined, not overlooked.

Also declined: adding `deque`'s trick of a distinct internal name
(`pydeque_new`). It removes the SHADOWING hazard, not the overload one.

## Routes that would actually close it

1. Type-aware selection in the stdlib-call table (helps every future entry).
2. A qualified-member fallback: when a qualifier resolves to a unit that has no
   such member, and the root is a known stdlib module name, retry the member as
   a bare pylib symbol. Wider, and it would also fix `itertools.count()`, which
   fails differently today (`undefined variable (itertools)`) for the same
   underlying reason — a qualified stdlib member has no single resolution path.

## A FOURTH MECHANISM EXISTS AND MAY BE THE RIGHT ONE — measure it before choosing a route

Found while landing deque, recorded here because this ticket is where it pays.

`ResolveUsesUnitSource` (compiler/pasparser_proc.inc, ~5320) already refuses a
genuinely-Pascal unit for a BARE NilPy import — *"a bare import means Python, so
a genuinely-Pascal unit is refused BY NAME rather than bound and failed one
token later"* — and, crucially, **it checks `PyMimicShimExists` first**:

> After the .py/.npy and host-header probes and before the shim mapping: a
> mimic_ shim IS the Python module of that name, so if one exists it answers and
> there is no collision to report.

So the resolver may ALREADY prefer a shim over a same-named Pascal unit, which
would mean `lib/rtl/mimic_collections.py` re-exporting `Counter`, `deque` and
the rest is a complete fix for the whole module in one file, with no table entry
and no per-name work — and it would fix `collections.Counter` for free.

**This is a reading, not a measurement.** It sits against the comment at
`PyImportRootPlainIsConsumedOnly`, which says `collections` is deliberately left
out of the plain-import consume list *"so a `collections.Sym` qualifier has a
unit to resolve against"* — and that unit is `lib/rtl/collections.pas`, which can
never carry a Python name, so at least the STATED REASON there is false. What is
not established is which of the two the resolver actually does today, because
the failing diagnostic cannot tell them apart: the error site says so in its own
comment — *"this site cannot tell a receiver that resolved to nothing from one
that resolved and has no such member"*.

**The measurement that settles it** is one file: write
`lib/rtl/mimic_collections.py` exporting one probe name, and see whether
`import collections; collections.probe()` reaches it. If it does, prefer that
route over adding entries to the stdlib-call table, and consider retiring the
`collections.deque` entry with it.
