---
track: N
prio: 45
type: bug
status: done
owner: claude-AN
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

## 2026-08-14 — FIXED via route 1 (param names in the method RTTI)

Both reasons this ticket was picked up and put down twice are gone.

### The display dependency was never real

The repro was written against `tk.Text`, so every previous attempt wanted xvfb
and the Tk lock. But the defect is **keyword binding**, not Tk — Tk only made it
*silent* (an invalid index is discarded without an error). A NilPy class reached
through `exec()` goes down the identical `PyHostCall` path, so the whole thing
reproduces headlessly:

```python
class W:
    def put(self, index, chars):
        print("index=" + str(index) + " chars=" + str(chars))
w = W()
env = {"w": w}; ns = {}
exec("def __body__():\n    w.put(chars='HELLO', index='end')\n", env, ns)
ns["__body__"]()
```

Before: `index=HELLO chars=end`. After: `index=end chars=HELLO`. CPython agrees
with the latter.

Worth stating on its own: **a repro that needs a display is often a repro
written at the wrong layer.** The Tk widget was incidental to a defect in the
reflected-call marshaller.

### Route 1, without moving the stride

The ticket's route 1 was "emit param names in the method RTTI", flagged with the
three-stride-consumer landmine
(`project_rtti_method_table_multi_consumer_stride_landmine`). That landmine is
avoided entirely rather than navigated: `MethInfo` **does not grow**, and no
mirror moves.

`ParamKinds` now points at `2*arity` words — the `arity` kind words exactly as
before, followed by `arity` param-name pointers. One block, one record field,
`RTTI_METH_SIZE` still 48. Every existing reader wants kinds, reads the first
`arity` words, and is unaffected; `lib/rtl/typinfo.pas`'s mirror needed only a
comment. The reservation happens **before** any `InternStr`, because interning
appends to `Data[]` and would otherwise split the array.

### The binding rule, and what it refuses

`PyBindHostKwArgs` runs in `PyHostCall` — one site, so every caller and every
future one gets it — and applies CPython's rule: positionals fill left to right,
then each keyword goes to the parameter it names. `ParseArgs` grew a `kwNames`
list parallel to `args` ('' for a positional), padded **before** each keyword is
appended so earlier arguments are marked at their own index.

Three shapes are now loud instead of silent: an unknown keyword, a parameter
given twice, and a keyword that would leave a **middle** parameter with no
value. That last one matters — the marshaller can only express omitted TRAILING
params (it tests `(i-1) >= nargs` against a dense list), so a gap has no
representation, and inventing a filler would put this straight back into the
silent-wrong-argument class this ticket exists about.

### uforth's dependency is satisfied, not merely unbroken

The ticket's sharp constraint was that uforth **depends** on the positional
behaviour, so a fix had to bind CORRECTLY rather than refuse.
`vm.define_word(name, native=_w)` passes `name` positionally and `native` by
keyword; the keyword now resolves to the parameter actually called `native`,
which is the same slot the positional append happened to hit. The full ANS Forth
suite still reports Total errors 0 with stdout byte-identical to CPython's.

### Found on the way, not fixed here

A host method with **three** user parameters fails in pyeval's marshaller
(`pyeval: int-return arity 3 unsupported for put`) — reproduced on the PINNED
compiler with all-positional arguments, so it is pre-existing and unrelated to
keywords. Filed separately.

### Gate

`test/test_nilpy_pyeval_host_kwargs_bind_by_name.npy` + `.expected` from CPython
(both orders, positional/keyword mixed, all-positional, and the one-parameter
form by name and by position, with the compiled call sites as a control).
`make compiler/pascal26` fixedpoint + `tools/gate.sh quick` GREEN + the uforth
corpus. A pin, because `compiler/builtin/pyeval.pas` changed.

### One deliberate laxness

Parameter names are matched with `PyEqCI`, case-INsensitively, so
`w.put(INDEX='a')` binds where CPython raises. That is consistent with
`PyFindMethCI`, which already resolves the METHOD name the same way, and with
the host language: a Pascal class cannot declare two parameters differing only
by case, so there is nothing to be ambiguous about. It also lands on the right
side of NilPy's own rule — accepting something CPython rejects is a language
feature, not a defect; the direction that must hold is that working CPython code
works here (`devdocs/dev/nilpy-semantics-divergences.md`).

## Log
- 2026-08-14 — resolved, commit 2185fb6f2.
