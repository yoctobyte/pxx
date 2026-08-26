---
track: N
prio: 80
type: bug
blocked-by: []
summary: "`from collections import Counter` binds a name that SILENTLY answers 0 for every key instead of counting — `Counter('aab')['a']` is 0, CPython says 2. And `OrderedDict` from the same import is `undefined variable`. The consume-and-ignore rule promises an unsupported name walls VISIBLY at its use site; Counter breaks that promise by answering wrongly instead."
status: done
owner: worker-N-counter
---

# `from collections import Counter` binds something that always answers zero

```python
from collections import Counter
c = Counter("aab")
print(c["a"], c["b"])     # pxx: 0 0        CPython: 2 1
```

```python
from collections import OrderedDict   # error: undefined variable (OrderedDict)
```

Both reproduce identically on `PXX_STABLE` and on HEAD — **pre-existing**,
found while fixing
[[bug-n-from-collections-abc-import-is-swallowed-by-the-collections-root-rule]]
and confirmed unaffected by that fix (the point of checking was that the
consumed arm had not changed; it had not, in either direction).

## Why this one is worse than the OrderedDict half

`PyImportIsConsumedOnly` consumes `from collections import ...` on a stated
promise, written in its own comment: *the names it exports that we support are
ordinary pylib symbols, and an unsupported name walls visibly at its use site.*

`OrderedDict` keeps that promise — `undefined variable`, loud, at the use site.
**`Counter` breaks it.** It binds to something that constructs without
complaint and then answers 0 for every key. That is the expensive failure mode
`devdocs/dev/debugging-playbook.md` opens with: a plausible wrong value far
from the cause, in code where a count of zero reads as "not present" and simply
takes the other branch.

So this is not "Counter is unimplemented". It is "Counter is half-implemented in
a way that lies", and the fix is either to make it count or to make it wall.

## Where to look

`PyStdAliasRecord` / `PyStdProvidesMember` (`compiler/pyparser.inc` ~32985) decide
which members of a consumed root get bound; pylib has `TPyCounter` constructors,
which is what the consume rule was counting on. Measure whether the binding
reaches `TPyCounter` at all, or lands on a same-named empty container — the
answer decides which of the two fixes applies.

## Resolution (2026-08-26)

### What the name was actually bound to

**`Counter` was bound to the right thing all along.** pylib has a real
`collections.Counter`: three `function Counter` overloads (pylib.pas ~2229 /
~7685) returning a `TPyDict` with `FCounterMode := True`, and Counter mode is
what makes a missing key read as 0 instead of raising KeyError. It is an
ordinary pylib proc, so **`Counter("aab")` compiles with no import at all** —
the from-import binds nothing, it only stops the module line erroring. The
consume-and-ignore rule was never involved.

The ticket's "Where to look" pointed at `PyStdAliasRecord` /
`PyStdProvidesMember` / `TPyCounter`, and all three were the wrong tree.
**`TPyCounter` is the `itertools.count` shim** — an int cursor with `nextval`,
reached only through `PyParseCountCreate`/`PyCountAlias`. It shares nothing with
`collections.Counter` but four letters. `PyImportIsConsumedOnly`'s own comment
asserted the connection (*"Counter -> pylib's TPyCounter constructors"*), which
is how the wrong lead got into the ticket; both copies of that comment are
corrected in this commit, and `lib/rtl/collections` is likewise a Pascal generic
`TList`, not a Python-collections shim.

### The actual root cause

`function Counter(const s: AnsiString)` counted with

```pascal
c.store(s[i], pyvar_to_int(c.fetch(s[i])) + 1);
```

`s[i]` on a Pascal string is a **`Char`**, which boxes as `VT_CHAR` (5), not
`VT_STRING` (6). `PyVarEq` bails on `if p^.VType <> q^.VType then Exit` before
any text compare, and `PyVarHashKey` has no VT_CHAR arm — so every entry stored
perfectly and then missed every lookup arriving with a string. `len()`,
`items()`, `keys()` and `most_common()` were all *correct* (they never compare a
key), and a VT_CHAR reprs as `a`, so the dict printed exactly right while
answering 0. That is what made it silent.

### How many sites shared the rule, how many were already right

The rule is *"convert a Pascal Char to a one-character string at the boundary,
with `pystr_ofchar`"*, and the record already existed — this was the sixth
spelling, not a new mechanism:

| site | crosses with pystr_ofchar |
| --- | --- |
| `list(s)` (pylib.pas:7187) | yes |
| `set(s)` (:7514) | yes |
| variant concat (~8438) | yes |
| `PyVarText` / repr (~8825) | yes |
| `str.maketrans` (~3313) | n/a — uses `Ord()`, which is what CPython does |
| **`Counter(s)` (~7708)** | **no — the bug** |

One site wrong out of six. Grepped for further Char-into-a-NilPy-value leaks
(`append(s[i])`, `store(...[i]...)`): none remain.

### The fix

Not a patched `store` call — the counting loop moved into a new
`TPyDict.update(const s: AnsiString)` arm and `Counter(const s)` now delegates
to it, so there is **one** string-counting loop rather than two copies to drift.
That mirrors CPython (`Counter(x)` *is* `Counter(); update(x)`) and the list arm
above it, and it fixes a second defect for free: `c.update("aab")` used to raise
`TypeError` because no string arm existed. `update(const v: Variant)` routes a
tag-5/6 payload there too, which is the spelling an unannotated parameter takes
(`def feed(c, t): c.update(t)`).

### Boundary shapes measured (CPython oracle throughout)

Broken → fixed, against `python3`:

- `c["a"]` **0 → 2**, `.get("a", -1)` **-1 → 2**, `"a" in c` **False → True**
- `c.update("aab")` **TypeError → counts**, incl. through a variant parameter
- already right and still right: the **list** arm `Counter(["a","a","b"])`, the
  int-list arm, `Counter()` + `c[k] += 1`, `len`, `items`, `keys`,
  `most_common`, `Counter(str.split())` (multi-char keys)
- unaffected: every NilPy-level route to a character — `s[i]`, `for ch in s`,
  `max`/`min`/`sorted`/`list`/`set` of a string, `chr()`, `split()[0]` — all
  already produced VT_STRING and all still match CPython.

### Anything for Track A?

**No.** The whole fix is in `compiler/builtin/pylib.pas` plus two comments in
`compiler/pyparser.inc`. No AST node, IR op, symtab field, backend, `lexer.inc`,
`ir*.inc`, `symtab.inc` or `defs.inc` was touched.

### Filed rather than fixed

- [[bug-n-a-char-key-and-a-string-key-are-equal-everywhere-except-in-a-dict]]
  (prio 40) — `PyVarEq`/`PyVarHashKey` are the only two of eight VT_CHAR/VT_STRING
  sites that do *not* normalise, which is why this bug was silent instead of a
  KeyError. **No NilPy-reachable repro today** (probed: nothing user-level
  produces a VT_CHAR), so it is a trap for the next pylib author rather than a
  live defect — and the fork (normalise vs. refuse-loudly) is close to a design
  call. Deliberately not folded in: different mechanism, and changing dict
  hashing with no repro is risk without measurement.
- [[feature-nilpy-counter-api-beyond-the-constructor]] (prio 35) —
  `Counter({...})`, `.elements()`, `c1 - c2` are all absent. All three wall
  **loudly** (compile error / AttributeError / TypeError), so they are a feature
  gap and not this ticket's silent-value class.

### Known remaining divergence (not filed)

Plain `dict.update("aab")` raises `TypeError` where CPython raises `ValueError`.
Pre-existing, unchanged by this fix, walls loudly either way, and error-*reporting*
parity is low prio by the project's own call (*"we seek LANGUAGE compliance, not
error-handling compliance"*). Noted here rather than minted as a ticket. It is
deliberately kept out of the regression test's `.expected`.

### The OrderedDict half

Unchanged and correct: `from collections import OrderedDict` still says
`undefined variable (OrderedDict)` at the use site. The ticket's own framing
agrees — that is the consume rule keeping its promise, and only the Counter half
was breaking it.

### Test

`test/test_nilpy_counter_from_a_string.npy` + `.expected`, wired into
**`test-core`** (native tier). The `.expected` is CPython's own stdout,
generated. It is a **witness**, not a smoke test — at the broken sha it fails
with three wrong-value rows and then dies:

```
-sub-str  2 1 0        +sub-str  0 0 0
-get-str  2 1 -1       +get-str  -1 -1 -1
-in-str   True True False   +in-str   False False False
                       +Unhandled exception: TypeError: dict.update expects ...
```

The list-arm rows sit next to each str-arm row and were *correct* at the broken
sha; the two arms disagreeing is what a reintroduced char key looks like.

### Gate

`make compiler/pascal26` — converged after 1 round (byte-identical self-host
fixedpoint). `tools/gate.sh quick` — **GREEN** (self-host fixedpoint, testmgr
quick tier, pinned-builds-lib/rtl, FPC seed canary).

## Log
- 2026-08-26 — resolved, commit 5d3d349a3.
