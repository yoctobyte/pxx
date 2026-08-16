---
track: N
prio: 60
type: bug
blocked-by: []
summary: "`map(bool, xs)` / `filter(str, xs)` segfaulted: the callable-pointer unwrap handed a VT_BTYPE variant's payload (a small type CODE) to the dispatcher as a code address. `sorted(xs, key=bool)` never crashed, because the ordinary call path rewrites the argument — map/filter build their callable elsewhere and never saw that rewrite."
status: done
---

# A builtin type passed to `map`/`filter` segfaults

- **Type:** bug (crash, wrong lowering) — **Track N** (`compiler/pyparser.inc`,
  `compiler/builtin/pylib.pas`).
- **Found:** 2026-08-16, by a CPython-differential sweep over callable-valued
  arguments.

## Measured boundary (before the fix)

```
CRASH rc=139 | print(list(filter(bool, [0,1,2])))
CRASH rc=139 | print(list(filter(str, ["","a"])))
CRASH rc=139 | print(list(map(bool, [0,1])))
ok           | filter(None,...), filter(len,...), map(str,...) [the conversion
               form], sorted([1,0], key=bool), f = bool; f(0)
```

## Root cause — one concept, two sites

A builtin type in value position is `pybtype(<code>)`, a **VT_BTYPE (13)
variant whose payload is a small CODE**. `PyMakeCallablePtrArg` wraps a
variant callable in `pyvar_callable_ptr`, whose whole body was
`Result := Pointer(PPyVarRec(@v)^.Payload)` — so the program jumped to 4.
The faulting PC being a small tag number is the tell, exactly as
`project_nilpy_callable_has_three_representations` records.

`sorted(xs, key=bool)` worked because the ordinary call path rewrites such an
argument to the type's one-argument conversion routine in
`PyFixCallableTypeArgs` (`bug-nilpy-a-builtin-type-as-a-key-callback-segfaults`,
already fixed). map/filter do not go through argument matching at all — they
build their callable directly — so the rewrite never reached them. The second
site of one concept, which is the shape this frontend keeps producing.

## Fix

1. `PyMakeCallablePtrArg` performs the **same rewrite** — recognises the
   `pybtype(<literal>)` node and emits `AN_PROCADDR` to
   `PyBuiltinTypeCallbackProc(code)` — rather than growing a second mechanism.
   Every callable-pointer slot is built here, so this is the normalising point.
2. `pyvar_callable_ptr` / `_opt` refuse a VT_BTYPE variant by name instead of
   jumping to its payload. Only the codes with no conversion routine
   (`bytes`, `tuple`, `bytearray`, `frozenset`, `type`) can now reach it, and
   `map(bytes, [1])` says so instead of crashing — a known, named gap where
   CPython answers `[b'\x00']`.

## Result vs CPython

`test/test_nilpy_builtin_type_as_a_map_callback.npy` — bool/str/int/float/list
through both `map` and `filter`, plus the four shapes that already worked —
diffs clean against CPython's output.

## Gate

`make compiler/pascal26` + the test above + `tools/gate.sh quick`. pylib is not
linked by the compiler, so no re-pin.

## Log
- 2026-08-16 — resolved, commit 3812f8c5f.
