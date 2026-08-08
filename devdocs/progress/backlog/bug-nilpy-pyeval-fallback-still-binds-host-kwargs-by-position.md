---
track: N
prio: 45
type: bug
---

# The pyeval fallback still binds a host method's kwargs by POSITION

The residual of [[bug-nilpy-pyeval-host-kwargs-positional]], which closed
because the compiled-lambda lift fixed the shape it was reported on. A lambda
the lifter REFUSES — more than one parameter, or a body that is not a
discardable call — still runs in pyeval, and that path appends keyword arguments
in the order written.

```python
txt = tk.Text(root); txt.pack()
g = lambda a, b: txt.insert(chars="HELLO", index="end")
g(1, 2)
print("[" + txt.get("1.0", "end") + "]")     # [] — nothing inserted
```

Bound as `insert("HELLO", "end")`: "HELLO" is not a valid Tk index, so Tk
discards the call. Written in declaration order (`index=`, `chars=`) it inserts
correctly. No error either way — the silent-wrong-option class the parent ticket
was opened about, in the one path the lift does not cover.

The one-parameter form of the same lambda is fine: it lifts, binds by name, and
a name that does not exist is a compile error.

## Why it cannot be fixed where it happens

`ParseArgs` (pyeval.pas) has the kwarg NAME but nothing to match it against: the
method RTTI carries param kinds and arity, not param names (`EmitMethInfo`,
rtti_emit.inc). Two routes:

1. **Emit param names in the method RTTI** and bind by name in `PyHostCall`.
   A Track A change to the MethInfo record — note the stride landmine
   ([[project_rtti_method_table_multi_consumer_stride_landmine]]): three
   consumers read that table and must change together.
2. **Widen the lifter** so fewer lambdas fall back at all. Cheaper per step, but
   it narrows the hole rather than closing it — a def, not just a lambda, can
   reach a host method through pyeval.

Failing loudly instead is NOT free: uforth calls `define_word(name, native=_w)`
through this path and depends on the positional behaviour, so a blanket refusal
regresses a live corpus. Any fix has to bind correctly, not just reject.

## Gate

`make test-nilpy` plus a `.npy` calling a host method with kwargs in a
NON-declaration order through a lambda the lifter refuses, asserting the effect
(read the value back off the widget), and uforth still green.

## 2026-08-07 — assessed and put back down deliberately, not started

Read in full and parked rather than begun, so the next session does not
re-derive the cost. Confirmed at `pyeval.pas` ~3184: `ParseArgs` appends every
non-`signed` kwarg with `args.append(v)` and no name matching at all — the
ticket's description is accurate and current.

Why it was not taken:

- **The real fix (route 1) is a Track A RTTI change**, and it lands on the
  method table's THREE stride consumers, which must change together
  ([[project_rtti_method_table_multi_consumer_stride_landmine]]). That is not a
  tail-of-session change.
- **The gate needs a live Tk widget** to assert the effect (insert text, read it
  back), i.e. a display and the xvfb lock — not something to run blind.
- **uforth cannot serve as the corpus check right now**: it fails to compile on
  the PINNED binary at `uforth.py:411` (*"no class declares a method or callable
  field .to_bytes()"*), measured 2026-08-07, so "uforth still green" is not
  currently a signal anyone can read. That blocker should be cleared, or the
  gate reworded, before this is attempted.
- The ticket's own constraint is the sharp one: uforth **depends** on the
  positional behaviour, so a fix must bind CORRECTLY, not merely refuse. Route 2
  (widen the lifter) narrows the hole without closing it and would leave the
  same silent-wrong-option class reachable through a def.

Left claim-free at prio 45. Route 1 remains the right answer; it wants a session
that can hold the RTTI change and a display.

## 2026-08-08 — one of the 08-07 blockers is now STALE

Re-checked before picking this up, and putting it back down for the same
reasons. One item above no longer holds:

- **uforth compiles on the PINNED binary again.** The 2026-08-07 note says it
  died at `uforth.py:411` ("no class declares a method or callable field
  .to_bytes()"), which made "uforth still green" an unreadable gate. Measured
  today at `stable_linux_amd64/default/pinned`: it compiles clean
  (`code=4142630B procs=1543`). A repin has landed since. So the corpus check in
  the Gate section IS usable now and the gate does not need rewording.

Everything else stands unchanged: route 1 is still a Track A change to the
method RTTI with the three-stride-consumer landmine, the effect assertion still
wants a live Tk widget and the xvfb lock, and uforth still DEPENDS on the
positional binding, so a fix must bind correctly rather than refuse.

Left claim-free at prio 45. Not started.
