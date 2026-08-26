---
track: N
prio: 80
type: bug
blocked-by: []
summary: "A class base which is a NAME bound to a type, or a call, does not compile: `B = object; class P(B)` fails where `class P(object)` and `class P(SomeClass)` both work. Blocks six.with_metaclass, which html5lib's parser spells as `class Phase(with_metaclass(...))` — the single remaining wall on html5parser.py."
status: done
owner: agent-abd00f67be57fcf38
---

# A class base that is an expression does not compile

- **Type:** bug (frontend) — **Track N**. Found from Track B, which cannot fix it.
- **Found:** 2026-08-17 by frank3, building `lib/rtl/mimic_six.py`
  ([[feature-nilpy-six-and-warnings-shims]]).
- **Measured against:** `pinned` **v345**. Not re-checked at HEAD.

## Repro — three cells, one variable

```python
class P(object):        # OK
    def hi(self): return "hi"
print(P().hi())
```

```python
class A:                # OK
    def hi(self): return "hi"
class P(A):
    pass
print(P().hi())
```

```python
B = object               # FAILS
class P(B):
    def hi(self): return "hi"
print(P().hi())
```

```
pascal26: error, near: B  object >>>   P
```

CPython runs all three. So a base which is a **class name** resolves, and a base
which is a **name bound to a type** does not — the same distinction that
`bug-n-a-type-name-is-not-a-first-class-value` fixed for ordinary value
positions, not yet extended to the base-class position.

A base which is a **call** fails the same way, which is the shape that matters
in practice:

```python
def wm(meta):
    return object
class P(wm(type)):      # FAILS
    pass
```

## Why it is worth more than it looks

It is the last wall on **`six.with_metaclass`**, and therefore on html5lib's
parser. `html5parser.py:426` reads:

```python
class Phase(with_metaclass(getMetaclass(debug, log))):
```

and `getMetaclass` (line 419) returns **plain `type`** unless the `debug` flag is
set. So the real, default path asks for *no metaclass at all* — semantically
just `class Phase(object)`, which this dialect can already express. The only
thing stopping it is that the base is written as an expression.

That is worth stating plainly because it changes the cost: supporting
`with_metaclass` here does **not** require metaclasses. It requires evaluating
the base expression. Metaclass support is only needed for html5lib's debug mode,
which the corpus scan does not exercise.

`lib/rtl/mimic_six.py` therefore refuses `with_metaclass` with a message naming
this ticket, rather than returning `object` — because returning `object` would be
semantically correct for the `meta is type` case and *still* would not compile at
the call site. The wall is the base expression, not the shim's answer.

## Gate

The third and fourth cells above compile and print `hi`. Then `mimic_six`'s
`with_metaclass` can return `object` for `meta is type` (and keep refusing
anything else, which genuinely does need metaclasses), and `html5parser.py`
advances past line 426.


---

## RE-MEASURED at HEAD 2026-08-19 — not fruit, and the ticket's own repro misdiagnoses it

Re-measured because the ticket said "Measured against pinned v345, not
re-checked at HEAD". Still reproduces, but it is **three separate defects**, and
the headline repro is not an instance of the bug the title names.

| shape | result | what it actually is |
| --- | --- | --- |
| `B = object` then `class P(B)` | `undefined variable (object)` **at line 1** | fails in the ASSIGNMENT — `object` is not a first-class value. Nothing to do with the base position. |
| `B = A` then `class P(B)` | `unknown base class B` | the real base-position bug |
| `class P(pick())` | `unknown base class pick` | base is an arbitrary call |
| `class P(A)` | OK | control |

Two controls that decide the sizing:

```python
B = A ; print(B().hi())                       # WORKS
B = A if len(sys.argv) > 99 else C            # a RUNTIME-chosen alias
print(B().hi())                               # WORKS -- prints C, like CPython
```

A class held in a variable is a genuine **run-time** value (a metaclass blob),
resolved when it is called. There is therefore **no compile-time record that
`B` means class `A`** — and a base class is needed at compile time, because it
determines the layout and the vtable.

So the fix is not an extra arm in the base-name chain
(`pyparser.inc:32370-32403`, which is pure name lookup: Exception, qualified,
FindUClassNonRecord, PyBuiltinBaseCi, error). It is either:

- **(a)** a new compile-time constant-alias analysis — "this module-level name is
  bound once, to a class literal, and never rebound"; or
- **(b)** run-time class creation, for the general case.

Both are mechanisms. Parking rather than starting one.

## The corpus argument in the summary does not hold

The frontmatter says this "blocks six.with_metaclass, which html5lib's parser
spells as `class Phase(with_metaclass(...))` — the single remaining wall on
html5parser.py". Checked:

```python
# html5lib/html5parser.py:426
class Phase(with_metaclass(getMetaclass(debug, log))):
```

That is the **call** shape, and its argument depends on a run-time flag, so it
needs (b) — the harder half. Option (a), the tractable half, would not move
html5parser.py at all. `lib/rtl/mimic_six.py:97` already reaches the same
conclusion and deliberately raises rather than pretending.

Also worth recording so it is not re-derived: **html5parser.py's current first
wall is not this at all.** At HEAD it stops on `decode has no parameter named
'final'` ([[bug-nilpy-a-callable-in-a-variable-loses-to-a-def-of-the-same-name]]),
which is upstream of the base-class question. So even (b) would not make
html5parser.py compile today, and the "single remaining wall" claim is stale.

Leaving prio at 45. Suggest splitting out the `object`-as-a-value defect, which
is unrelated to this title and may be much cheaper.

---

## RESOLVED 2026-08-26 — option (a), and it needed no new mechanism

Re-measured at `dev` HEAD first (endpoint measurement before anything else):
still broken, exactly the three-way split the 2026-08-19 pass recorded. Not
already-fixed fruit.

### The mechanism was already there, with one arm missing

The 2026-08-19 note concluded there is "**no compile-time record that `B` means
class `A`**" and sized the work as a new constant-alias analysis. That is the
one part of the diagnosis that was wrong, and it is why the ticket sat: the
record exists. `UClsAlias*` (`symtab.inc`) is a compile-time
name→class-row table, and **`FindUClassNonRecord` — the very function the base
position already calls — resolves through it.**

So the base-name chain at `PyParseClass` needed **no new arm at all**. The whole
fix is a pre-pass that puts a module-level `B = A` into the table that four
other spellings of "this name means that class" already use:

| spelling | registered before? |
| --- | --- |
| `from m import C as D` | yes |
| `import m as mm` (qualified base) | yes |
| Pascal `T = TList` alias | yes |
| a builtin base (`dict`, `list`) | yes, own path |
| **`B = A`** | **no — the one that stayed broken** |

Five mechanisms served one concept and one was missing, which is the
normalise-dont-special-case shape exactly. Registering it means every
alias-aware consumer starts answering at once — `PyIsExactCtorName`,
`PyIsClassTypeExact`, `IsClassType`, the construction intercept in
`pasparser_lval.inc` — rather than the base position alone. Verified: isinstance
through the alias, `B is A`, `B(...)` construction, and a **chained** alias
(`C = B` after `B = A`) all work, and none of them were touched directly.

### Rebinding is the whole difficulty, and it is why this is narrow

The table is flat and global with no notion of a program point, so a name bound
more than once **cannot be represented in it**:

```python
B = A ; B = C ; class P(B)      # CPython: C.  "First binding wins": A.
```

A wrong base is a wrong layout and a wrong vtable, and nothing downstream would
say so — the exact silent-wrong-value failure the playbook is built around. So
the pass registers a name only when the module binds it **exactly once**,
counting every binding form (assignment, augmented assignment, `as`, a `for`
target, a `def`/`class` of that name) at **every** depth. Anything else is left
as it was: still a compile error, which is a refusal rather than a wrong answer.

### Boundary — what varying the shape showed

| shape | before | after | note |
| --- | --- | --- | --- |
| `class P(A)` | OK | OK | control |
| `B = A` → `class P(B)` | **FAIL** | **OK** | the ticket |
| `B = A` → `C = B` → `class P(C)` | FAIL | **OK** | chain, free |
| `B = A` → `B = C` → `class P(B)` | FAIL | refused | CPython says C; refusing beats guessing |
| `B = A` at module level, `B = 5` in a def | FAIL | refused | conservative: name bound twice |
| `B = A if … else C` → `B()` | OK | **OK** | control, must not become compile-time |
| `B = A` → `B()`, `isinstance(x, B)`, `B is A` | OK | OK | controls |
| `class P(pick())` | FAIL | FAIL | a **call** — genuinely needs run-time class creation |
| `B = object` | FAIL | FAIL | fails in the ASSIGNMENT — split out, see below |

### Filed rather than fixed

- **[[bug-n-object-is-the-one-builtin-type-name-that-is-not-a-value]]** — the
  split this ticket's own re-measurement asked for. Sharp boundary: `t = str`,
  `u = int`, `v = dict` all bind and call; `object` alone is `undefined
  variable`, because it is *erased* rather than resolved everywhere it appears
  and so has no row to hand back in value position.
- **The call shape (`class P(wm(type))`) is NOT fixed and stays open.** It needs
  run-time class creation, option (b) — unchanged from the 2026-08-19 sizing.
  Per that same note it would still not move `html5parser.py`, whose first wall
  is elsewhere. If the call shape alone is wanted later, it deserves its own
  ticket rather than reopening this one.
- Not filed, already known: `super()` in expression position blew up several of
  my probe programs with `annotate the type / too dynamic [a=22 b=8]` at line 1.
  Reproduces identically with a **direct** base on the pinned binary, so it is
  independent of this ticket — it is
  [[bug-n-super-as-an-expression-fails-with-a-misleading-diagnostic]].

### Regression test — a witness, in test-core

`test/test_nilpy_class_base_is_an_alias.npy` + `.expected` (generated by
CPython, not written by hand), and
`test/test_nilpy_class_base_alias_rebound_refused.npy` for the refusal half.
Wired into **test-core**, not test-nilpy: test-core runs in the NATIVE tier (the
fast watcher verdict) while test-nilpy is limited/full only.

Witness, not smoke: at the broken sha the first file does not compile at all
(`unknown base class Base` at line 30), so no row in it could have passed by
accident. The rebound file guards the dangerous direction — it must never start
compiling to the *first* binding.

### Gate

`make compiler/pascal26` self-host fixedpoint byte-identical (converged in 1
round); both new test-core recipe lines pass; `tools/gate.sh quick` GREEN.
No Track A file was modified — `RegisterUClassAlias` / `FindUClassNonRecord`
are called, not changed.

## Log
- 2026-08-26 — resolved, commit 10a186faa.
