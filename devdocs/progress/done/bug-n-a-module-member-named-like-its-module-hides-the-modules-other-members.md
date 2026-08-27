---
track: N
prio: 65
type: bug
blocked-by: []
status: done
summary: "A module that defines a name equal to its own module name makes every QUALIFIED access to the module's other members fail: `import bisect; bisect.bisect_left(...)` gives `no class declares a method or callable field .bisect_left()`, because `bisect` resolves to the module's member rather than the module. CPython's own Lib/bisect.py has `bisect = bisect_right`, so this is ordinary stdlib-shaped code. From-imports are unaffected."
status: working
owner: agent-A
---

# A module member named like its module hides the module's other members

- **Type:** bug — **Track N** (Nil-Python frontend, name resolution).
- **Found:** 2026-08-18 by frank3-fc while writing `lib/rtl/mimic_bisect.py`
  for [[feature-b-module-shims-for-the-html5lib-corpus]].
- **Measured against:** `pinned` **v347** (`f5da30bc9`).
- CPython accepts and runs this. `Lib/bisect.py` really does end with
  `bisect = bisect_right`, and `import bisect; bisect.bisect_left(a, x)` is
  what every caller writes.

## Repro

`mimic_zz.py`:

```python
def zz_left(a):
    return 1

zz = zz_left          # a member whose name is the module's name
```

```python
import zz
print(zz.zz_left([1]))
# error: Nil Python: no class declares a method or callable field .zz_left()
```

Delete the `zz = zz_left` line and the same qualified call compiles and runs.

## The boundary

| shape | result |
| --- | --- |
| module defines a same-named member; `mod.other_member(...)` | **compile error** |
| module defines no same-named member; `mod.other_member(...)` | OK |
| `from mod import other_member` (module defines a same-named member) | OK |
| `from mod import mod_named_member` | OK |
| module whose ONLY member is the same-named one, called qualified | OK |

Reading that fits every row: at a qualified call the name binds to the imported
member in preference to the module, so `zz.zz_left` looks for `zz_left` on a
function. It is a shadowing question, not a missing-feature one. (Hypothesis —
nothing here read the resolver.)

## Severity, and why it is p40 rather than higher

It is a **compile error**, not a wrong answer, and the from-import spelling —
which is what the corpus actually uses (`from bisect import bisect_left`) —
works. So nothing is silently wrong and nothing is blocked; a caller who writes
the qualified form gets told, if confusingly.

Filed because the shape is common in the stdlib (a module exporting a legacy
alias of its own name), and because the report names a "class" for what is a
module and a function, which sends the reader somewhere unhelpful.

## Track B site

`lib/rtl/mimic_bisect.py` keeps the platonic `bisect = bisect_right` alias, so
`test/lib_mimic_bisect.npy` exercises the module through from-imports only and
says why at the site.


---

## RESOLVED — 2026-08-27, agent-A

Fixed. The ticket's hypothesis — "at a qualified call the name binds to the
imported member in preference to the module" — was right in outcome and one step
off in mechanism, and the step matters: nothing binds the name at all. The
qualifier is simply never CONSUMED.

### Measured

One print inside `ConsumeUnitQualifier`, at the `FindSym` early exit:

```
ZZCQ name=zzm sym=468 unit=636 cur=-1 symunit=636 symtxt=zzm
```

`unit=636` — the qualifier WOULD resolve. `symunit=636` — but a symbol exists,
and it is the module's OWN global, living in the very unit the qualifier names,
while `cur=-1` says we are compiling the main program. The function's rule

```pascal
{ A local/param/global SYMBOL shadows a same-named unit (FPC scoping) }
if FindSym(name) >= 0 then Exit;
```

fired, nothing was consumed, and `zzm.zz_left` became a member access on a
function value — hence the report naming a "class" for what is a module and a
function.

That rule is right for Pascal and for the case it was written for
(`function NetToHost(Net: in_addr)` keeping `Net.s_addr` a field access). It is
`FindSym`, though, which is not scope-local: it reaches a global in ANOTHER
unit, and that is a scope Python does not have. In an importing module `bisect`
is bound to the MODULE; the module's internal rebinding of its own name is not
visible there at all.

### The fix

`compiler/pasparser_name.inc` — the early exit keeps the symbol index and lets
exactly one shape through:

```pascal
if not (isNilPy and (SymUnitIdx[u] >= 0) and
        (SymUnitIdx[u] <> CurrentUnitIdx) and
        (PyFindUnitDotted(name) = SymUnitIdx[u])) then Exit;
```

As narrow as the collision: the symbol must live in **exactly the unit this
qualifier names**, and we must not be compiling that unit — because inside it
the module's own binding really does win, which is Python's rule too and is a
row in the witness. A local, a parameter, a same-unit global and a symbol from
some unrelated unit all still shadow, unchanged.

### Verified

| shape | before | after |
| --- | --- | --- |
| module rebinds its own name; `mod.other(...)` | compile error | correct |
| the same-named member itself, `mod.mod(...)` | correct | correct |
| inside the module, its own name | correct | correct |
| `from mod import other` / `from mod import mod as alias` | correct | correct |
| module with no same-named member | correct | correct |

And the case that filed it, against the real shim: `import bisect` then
`bisect.bisect_left`, `bisect.bisect_right`, `bisect.bisect` and
`bisect.insort` all match CPython, on `lib/rtl/mimic_bisect.py` exactly as it is
written, alias line included.

### Track B follow-up (not done here, deliberately)

`test/lib_mimic_bisect.npy` says at its site that it exercises the module
through from-imports only *because of this bug*. That note is now stale, but the
test builds with `$(PXX_STABLE)` — the PINNED binary — so the qualified spelling
only becomes available to it after a pin. Left for Track B to adopt then; this
ticket does not touch B's files.

### Gate

`make compiler/pascal26` → `self-host fixedpoint: verified — 1 round(s)`.
`tools/gate.sh quick` → GREEN. Witness
`test/test_nilpy_module_member_named_like_its_module.npy` + helper module
registered in `test-core`, `.expected` generated by CPython, a compile error at
pinned v381 and green now.

## Log
- 2026-08-27 — resolved, commit PENDING-COMMIT.
