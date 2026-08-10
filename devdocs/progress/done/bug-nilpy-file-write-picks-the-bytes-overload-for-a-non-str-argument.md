---
prio: 55
track: N
type: bug
blocked-by: []
status: done
owner: claude-ACPN
---

# `f.write(x)` picks the BYTES overload whenever x is not statically a str

- **Type:** bug (NilPy; valid CPython → uncatchable-looking runtime TypeError) —
  **Track N**
- **Found:** 2026-08-09, realistic-program sweep (a log writer whose helper is
  `def wr(path, t): h = open(path, "w"); h.write(t)`).

```python
def wr(t):
    h = open("p.txt", "w")
    h.write(t)          # CPython: writes;  pxx: TypeError: expected an object argument, got str
    h.close()
```

Measured, at `8070feee2`:

| argument | pxx |
| --- | --- |
| `h.write("literal")` | ok |
| `h.write(str(t))` | ok |
| `h.write(t)` (an unannotated parameter) | **TypeError** |
| `h.write("x" + t)` | **TypeError** |
| `h.write("%s!" % t)` | **TypeError** |
| via a local first (`s = "%s!" % t; h.write(s)`) | **TypeError** |

So the shape that fails is "the argument is not statically an AnsiString" —
which, in an unannotated def, is the ordinary case. `str(...)` around it is the
workaround, and it is exactly the kind of workaround a user cannot guess.

## Cause

`TPyFile` declares

```pascal
function write(b: TPyBytes): Int64; overload;      { declared FIRST }
function write(const s: AnsiString): Int64; overload;
```

and the class-method call site picks by NAME and ARITY, not by argument TYPE —
the known landmine (`project_findproc_by_name_ignores_overloads`, whose arity
half was fixed with `FindUMethArity` while the **type half still bites**). A
statically-str argument happens to land on the right overload; a variant one
takes the first declaration, so the string handle is passed as a buffer object
and pylib raises.

Note the history: the AnsiString overload was ADDED to fix
`bug-nilpy-file-write-drops-data-and-read-to-print-dumps-rtti-memory`, which was
the same mis-pick with a literal argument. That fix moved the boundary rather
than removing it.

## Shape of the fix

The general repair is overload selection by argument type for class methods —
valuable well beyond `write`, and the honest root. Failing that, the codebase's
own precedent for "the static type is unknown, decide at run time" is the `_any`
suffix used for `startswith`/`endswith` (`pystr_startswith_any`): route a
non-str-typed argument to a Variant-taking entry point that dispatches on the
tag. Do NOT simply swap the declaration order — that re-breaks the bytes case in
the same silent way.

## Log
- 2026-08-10 — resolved, commit PENDING-COMMIT.

## Resolution (2026-08-10) — the general repair, not the `_any` fallback

The ticket named two options and called overload selection by argument type
"the honest root". That is what landed; the `_any`-suffix workaround was not
needed, because the two halves compose.

### 1. Overload selection by argument TYPE (the root)

`PyPickOverloadByArgTypes` (`compiler/pyparser.inc`) runs after
`FindUMethArity` at the class-method call site: among the same-name,
**same-arity** candidates it prefers the one whose parameter types fit the
arguments actually written.

Deliberately conservative, because this sits under **every** NilPy method call:

- **exact type-kind equality only**, one point per argument — not an
  assignability lattice. The job is to separate overloads that differ by
  argument type, not to re-litigate calls that already resolve.
- **a tie keeps the incumbent**, and a single candidate can never score
  *strictly better* than itself, so a non-overloaded call and every
  previously-working call are unchanged by construction.

This is the type half of `project_findproc_by_name_ignores_overloads`, whose
arity half `FindUMethArity` had already fixed.

### 2. A Variant-taking `TPyFile.write` (what the root then selects)

An unannotated argument is a **variant**, and neither `TPyBytes` nor
`AnsiString` matches one — so type scoring alone had nothing better to pick.
`TPyFile.write(const v: Variant)` gives it an exact match, and dispatches on the
runtime TAG: a string tag writes text, a `TPyBytes` object writes bytes, and
anything else (int/float/bool/None) raises `TypeError` — which CPython does too,
and which beats writing the value's decimal spelling and looking like it worked.

**The declaration order was NOT swapped**, per the ticket's warning: that would
have re-broken the bytes case in the same silent way.

### Measured

Every row of the ticket's table, against the CPython oracle:

| argument | before | now |
| --- | --- | --- |
| `h.write("literal")` | ok | ok |
| `h.write(t)` (unannotated param) | TypeError | **ok** |
| `h.write("x" + t)` | TypeError | **ok** |
| `h.write("%s!" % t)` | TypeError | **ok** |
| via a local first | TypeError | **ok** |
| `h.write(b"bytes")` (control) | ok | **ok** |

Output is byte-identical to CPython for all six.

### Regression test

`test/test_nilpy_write_overload_by_arg_type.npy`, wired into `make test-nilpy`.
The bytes row and the direct-literal row are in as **controls** — they always
worked, and they are precisely what a declaration-order "fix" would have broken.

### Gate

`tools/gate.sh quick` GREEN; `make test-nilpy` **exit 0, zero make errors** —
the suite that matters here, since the picker sits under every NilPy method
call; self-host fixedpoint byte-identical. `compiler/builtin/pylib.pas` changed,
so `make stabilize-fast && make pin`: **pinned v255**
(`259f2580d97fc9ae67a985586a057a69b2da38773b9b02692c51d9f198fb1668`).

### Found alongside, filed separately

`print(open(p).read().strip())` — a method chained directly onto `open()`'s
result — fails to parse ("unexpected token"), while the same call through a
local works. Unrelated to overload selection; filed as
[[bug-nilpy-method-chained-on-open-result-fails-to-parse]].
