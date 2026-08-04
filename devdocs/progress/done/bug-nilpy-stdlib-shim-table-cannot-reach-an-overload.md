---
track: N
prio: 50
type: bug
summary: "The stdlib shim table and every hand-built pylib call resolve a NAME with FindProc, which returns ONE proc index and never consults overloads — so os.path.join('a','b','c') fails and adding a Pascal overload has no effect"
status: done
owner: claude-AN
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


## Resolved 2026-08-04 — options 3 and (a generalisation of) 1

The ticket recommended "3 now, then 2 for the shims that need arities". Did 3,
then did **1's arity half** instead of 2, because it turned out to be smaller
than the rename it would have replaced and it removes the trap for everyone
rather than for `os.path.join` specifically.

### 3 — the constraint is now stated where it is violated

`FindProc`'s declaration carries the warning, in the terms this ticket used:
adding a Pascal `overload` for a case a hand-built call gets wrong has **no
effect**, the build is clean, the self-host is green, and the natural next
conclusion is that the runtime is wrong. `PyParseStdlibCall` carries it too.

### 1 (arity half) — `FindProcArity`, and the shim call site uses it

`FindProcArity(name, nArgs)` returns the same-named proc taking exactly that
many parameters. The shim call site already knew its argument count — it used it
to report "takes fewer arguments than were given" — so re-targeting there was a
few lines, and it means an ordinary same-named overload differing only in
**arity** is now reachable from a hand-built call. That is exactly the case that
was silently inert.

The existing `<name>_d` fallback is kept and tried **second**, so the shims that
gave their two arities different names because this lookup did not exist
(`os.environ.get(name)` beside `os.environ.get(name, default)`) answer exactly
as before. Nothing that works today changes.

**Type-based selection is still not reachable this way**, and that is stated
rather than papered over — sightings 1 and 2 (`zip`/`enumerate` on a str, and
`str(<float>)`) were type problems, and their fixes (convert at the call site,
or give the routine a unique name) remain the right answers. Only sighting 3 is
closed by this.

### The immediate open sub-gap is closed

`os.path.join` got its 3- and 4-component overloads back — the ones that were
added, measured to do nothing, and removed again. They are ordinary Pascal
overloads now, reachable because of the arity re-target:

```
os.path.join("a", "b")            a/b
os.path.join("a", "b", "c")       a/b/c
os.path.join("a", "b", "c", "d")  a/b/c/d
os.path.join("/x", "y", "z")      /x/y/z
os.path.join("a", "", "c")        a/c
```

all identical to CPython.

### Verified

`test/test_nilpy_stdlib_shim_arity.npy`, wired into `make test-nilpy`: the four
`join` arities including an empty component and an absolute head, plus the `_d`
fallback. Diffed against CPython, identical. `tools/gate.sh quick` GREEN,
self-host byte-identical.

## Log
- 2026-08-04 — resolved.
- 2026-08-04 — resolved, commit PENDING-COMMIT.
