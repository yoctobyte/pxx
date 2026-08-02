---
track: N
prio: 50
type: bug
summary: "The stdlib shim table and every hand-built pylib call resolve a NAME with FindProc, which returns ONE proc index and never consults overloads — so os.path.join('a','b','c') fails and adding a Pascal overload has no effect"
---

# `FindProc` name-resolution cannot reach an overload

- **Type:** bug / structural limitation (NilPy) — **Track N**
- **Found:** 2026-08-02. Hit **three separate times in one session**, which is
  why it is filed as its own thing rather than three symptoms.

## The pattern

Anywhere the frontend builds a pylib call by NAME —
`PyStdlibCallProc`'s table, `PyMakeSlice`, `PyMakeZip`, the `enumerate` value
form, the `str()` reroute — it does `FindProc('<name>')`, which resolves to a
**single** proc index. Overload resolution never runs. So:

- passing an argument of the wrong type silently binds to whichever overload
  `FindProc` happened to return, and
- **adding a Pascal `overload` for the missing case has no effect at all** —
  the new overload is simply never selected.

## The three sightings

1. **`zip(s, t)` / `enumerate(s)` on a str** — SIGSEGV. `pyzip`/`pyenumerate`
   take a `TPyList`, the AnsiString handle was passed straight in and
   dereferenced as an object. I added `AnsiString` overloads first, watched them
   be ignored, and had to convert at the CALL SITE instead
   (`PyIterArgAsList`). Fixed in `27e772e75`.
2. **`str(<float>)`** — the reroute called `FindProc('pystr_of')`, which
   returned the *AnsiString* overload and was handed a Double; the program's
   output simply stopped. Fixed by giving the routine a unique name
   (`PyFloatStr`) in `1e9945d19`.
3. **`os.path.join("a", "b", "c")`** — "takes fewer arguments than were given".
   Adding 3- and 4-argument overloads to `pyos_path_join` changed nothing; the
   table's `FindProc` still returns the 2-argument one. The overloads were
   removed again rather than left as dead code, and the arity gap is still open.

## Why it matters beyond the three

The failure mode is the dangerous one: **the fix that looks obvious does
nothing, silently.** Someone adding a shim overload gets a clean build, a green
self-host, and no behaviour change — and the natural next conclusion is that the
runtime is wrong rather than that the call was never routed there.

## Options

1. **Make the shim call site arity- and type-aware.** The call builder already
   knows the argument count when it reports "takes fewer arguments than were
   given", so selecting among same-named procs by arity is reachable; type-based
   selection is the harder half.
2. **Give every shim a unique name per signature** (`pyos_path_join3`, …) and
   have the table map (name, arity) rather than name. Mechanical, no resolution
   machinery, and it makes the constraint visible in the source instead of
   surprising the next person.
3. At minimum: a comment at `FindProc`'s declaration and at
   `PyStdlibCallProc` saying overloads are not consulted. Cheap, and would have
   saved three separate rediscoveries in one night.

Recommendation: do 3 now, then 2 for the shims that need arities.

## Immediate open sub-gap

`os.path.join` accepts exactly two components. Three is ordinary Python and is
what the corpus writes.

## Gate

A `.npy` diffed against CPython calling `os.path.join` with 2, 3 and 4
components, plus whichever other shims gain arities.
