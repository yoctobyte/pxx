---
summary: "A variant argument to a typed receiver's overload set picks the CLASS overload by declaration order; ttk Notebook.select(idx) with idx from JSON raises TypeError"
type: bug
track: N
blocked-by: []
prio: 30
status: backlog
---

# A variant argument picks the class overload without a tag test

Found building songformatter (2026-10-27, peer session). ttk.Notebook.select
has the overloads select(child: Widget) and select(index: Integer). With
`idx = json.loads('{"i":0}').get("i", 0)`, both `nb.select(idx)` and
`nb.select(int(idx))` raise "TypeError: expected an object argument, got int"
(pylib pyvarobj_arg). `nb.select(0)` and `k: int = idx; nb.select(k)` work.

## What is known

- `int(<variant>)` is typed VARIANT on purpose (pyparser.inc, the int() arm):
  the variant may hold a bignum, so int() cannot narrow to Int64. So
  `int(idx)` is no better than `idx` here.
- The typed receiver goes through FindUMethOverloadAhead
  (pasparser_call.inc), and OverloadArgRank ranks Variant->class and
  Variant->Integer both at 2 ("merely compatible"). The tie keeps the first
  declared overload, the Widget one.
- It does NOT go through PyParseClassMethodCall / PyPickOverloadByArgTypes, so
  a fix in the NilPy scorer does not reach it (tried and backed out).
- Choosing at compile time is wrong either way: `nb.select(tabs[i])`, a
  variant holding a widget, is just as ordinary. Only the run-time tag can
  decide.

## Shape of the fix

`pyvar_is_inttag(t) ? select(pyvar_to_int(t)) : select(t)`, with the argument
hoisted to a temp so it is evaluated once. That applies when exactly one
argument is a Variant against a tyClass parameter and a same-arity sibling
takes a (non-Boolean) machine int at that slot with every other parameter of
equal kind. A draft of that arm was written for PyParseClassMethodCall. It
needs to sit where the Pascal-side method paths (pasparser_expr.inc /
pasparser_lval.inc, every FindUMethOverloadAhead caller) build their call
node, or once in IR lowering of a NilPy method call. ir.inc is included before
pyparser.inc, and PXX_NO_NILPY builds lack the latter.

App-side workaround until then: `k: int = idx; nb.select(k)`.

Related: an unhandled exception prints only "Unhandled exception: TypeError:
..." with no location, so finding this site took print-marker bisecting.

## 2026-11-11: the reported case fixed in the library; the general tie stays

`Notebook.select(const v: Variant)` added to lib/pcl/tkinter.pas. It decides
by the run-time tag (an int is an index, anything else goes through
pyvarobj_arg as a Widget). A Variant argument now matches it exactly, so the
tie never arises for this overload set. `nb.select(idx)` with idx from
json.loads, `nb.select(int(idx) - 1)` and `nb.select(tabs[1])` all give
CPython's answers under Xvfb: examples/tk/notebook_select_by_variant.npy
(row tknbsel26, in the Xvfb block, expected = python3).

That is the "shims are the path" route (owner, 2026-09-10), and it is the whole
fix for songformatter. The compile-time tie itself is unchanged: any other
Pascal overload set with a class overload and an int overload at the same
slot still picks the first declared for a Variant argument. Re-ranked 50 -> 30
on that basis; add a Variant overload to the next library that hits it, and
build the general tag test (the shape above) if a third one does.
