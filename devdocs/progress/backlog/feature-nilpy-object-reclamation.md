---
track: A
prio: 55
type: feature
---

# NilPy object reclamation — dict/list/instance/bound-method lifetime

The user's resolution of [[decide-uforth-exec-leak-strategy]] (2026-07-22):
**uforth stays untouched** — it is a test case; improvement suggestions go to
the uforth repo itself, not here. The compiler must not leak on Python code:
"let leaks be due to application bugs, not compiler errors." So this is the
work item, and it must land either way.

## Current state
- Variant SLOT lifetime is handled: scope-exit release, ARC-correct
  var_store/copy, promo-tier clears, aggregate-dest release, call-result
  boxing ownership (the five fixed layers of
  [[bug-a-runtime-variant-heap-grows-unbounded]]).
- CLASS INSTANCES (TPyDict, TPyList, TPyBytes, user classes) and
  bound-method boxes have NO lifetime management at all: a dict whose
  binding dies is never freed. `xs = []` reassignment reclaims (special
  case); frame exit, dict-internal churn, and instance fields do not.

## The concrete driver
uforth's `exec_python_inline` allocates per PYTHON-word call: env TPyDict
{vm, push, pop, fpush, fpop} + ns TPyDict + 5 bound-method pairs + wrapper
string → ~4-5 KB/call orphaned. 20k-iter doloop = 553 MB peak vs CPython's
24 MB (`make bench-uforth` tracks it). Per-op RSS probes and the reduction
ladder live in the umbrella ticket.

## Shape (not decided here — implementation's call, escalate if forked)
Refcount class instances like AnsiString handles (retain on bind, release
on unbind/scope-exit, recursive release of variant-slot payloads/fields),
OR scope-tied arena for instances that provably don't escape. Watch: cycles
(vm ↔ words) — CPython solves with GC; a refcount-only scheme leaks cycles,
which for uforth's env-per-call pattern is still ~all of the 553 MB, so
refcounting is a legitimate first rung. The user's caution from FPC history
(threaded ansistring leaks): threading × memory management is hard — the
threadsafe heap lock discipline (heap-size-class allocator, PXXStr* lock
protocol) applies to every new release path.

Gate: uforth doloop RSS bounded and near-CPython; test-nilpy green;
self-host byte-identical; the vstr/vbox probes in the umbrella stay flat.
