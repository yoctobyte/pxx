---
slug: bug-n-an-override-changing-the-result-type-in-a-late-laid-out-class-is-refused
title: An override changing the result type, in a class laid out after its base was compiled, is refused
track: N
type: bug
prio: 35
status: backlog
owner: ""
created: 2026-09-19
found-by: frankH
tags: [nilpy, class, override, layout]
blocked-by: []
summary: "MECHANISM: when an override's result type differs from its base method's, the override join (PyOverrideRetJoinsToVariant) widens the BASE method's RetType to Variant, which is only sound before any body is compiled. The member prepass (PyClassHeaderSweep) guarantees that for every class it hoists, but a class it DEFERS to PyParseClass -- several bases, a mixin base, an unresolved base, or a subclass of any of those -- is registered after the bodies of its already-hoisted bases have been compiled returning the narrow type. Widening then made a caller read a variant out of an int routine: `class D(P, Tag)` overriding `P.v -> int` with a float, then `P().v() + 1`, is a SIGSEGV on pinned v411. The widening is now refused by name in that position ('... in a class laid out after its base was compiled ...'), so the crash is a diagnostic. COST OF THE REFUSAL: the same shape where only the override is ever called ran correctly on pinned and is now refused too. Workaround for a program: annotate both results with the same type. Fix: run the result join for deferred classes in the prepass as well (the override's signature is known there even when its layout is not), or compile the base bodies after the sweep has joined every override."
---

# An override changing the result type, in a late-laid-out class, is refused

Found 2026-09-19 (frankH) while fixing the `test_nilpy_line_continuation` red
that `f646378ff` introduced: that fix deferred a subclass of a deferred class,
which put `class Base(object)` / `class Derived(Base)` on this path. That pair
is fixed separately (a sole `object`, `Generic[...]` or `Protocol[...]` base is
now "no parent" in the prepass, so neither class is deferred). The residual is
the multi-base shape.

Fixture: `test/test_nilpy_an_override_widening_a_compiled_base_is_refused_fail.npy`
(Makefile must-refuse row). When this is fixed, that row flips: turn it into a
positive fixture against CPython (`P().v() + 1` prints 1, `D().v() + 1` 2.5).
