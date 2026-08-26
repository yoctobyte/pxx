---
track: N
prio: 80
type: bug
blocked-by: []
summary: "`hasattr(x, name)` returns False for EVERYTHING when x is a parameter with no static type — `hasattr(a_dict, 'keys')` and `hasattr(a_list, 'append')` are both False. Silently wrong, never an error, and it is how CPython code dispatches on duck type."
status: done
owner: agent-a34da8ba
---

# `hasattr` through an untyped parameter is always False

Filed 2026-08-19 from [[feature-b-mimic-collections-abc-mapping-and-mutablemapping]],
where it made `MutableMapping.update({'x': 1})` take the pairs branch and index a
one-character string.

Measured on **pinned v356** (`2bb09afb0cff`):

```python
def probe(x):
    return hasattr(x, 'keys')
class C:
    def take(self, other):
        return hasattr(other, 'keys')
print(probe({'a': 1}), probe([1]), probe('s'))
print(C().take({'a': 1}), C().take([1]))
```

| | |
| --- | --- |
| CPython | `True False False` / `True False` |
| pxx (pinned v356) | `False False False` / `False False` |

Not dict-specific and not container-specific: through a dynamic receiver `hasattr`
answers False **uniformly**, including `hasattr(a_list, 'append')`. Written
against a local whose static type is known it answers correctly, so the resolution
is happening at compile time against the declared type and there is no runtime
fallback for the unknown case.

The failure mode is the expensive kind — no error, a plausible wrong value, and a
crash somewhere else entirely. `hasattr`-based duck-typing is how a large fraction
of real Python dispatches, so this will keep resurfacing under different symptoms.

Track B workaround: `lib/rtl/mimic_collections_abc.py`'s `update()` discriminates
with `isinstance(other, dict) or isinstance(other, Mapping)` instead of
`hasattr(other, 'keys')`. Registered in `devdocs/dev/track-b-workarounds.md`;
that workaround is narrower than CPython (a non-Mapping object exposing `keys()`
takes the wrong branch) and should be reverted when this closes.

## Resolution (2026-08-26)

**The predicate was asking a STATIC-TYPE question of a receiver that has no
static type.** Not "no runtime fallback" as the ticket guessed — a runtime
fallback was there and doing half the job — and not "answers False uniformly",
which measurement contradicted before any code changed.

### What it was actually consulting

`hasattr(<variant>, "lit")` lowered to
`pydynattr_has_any_v(v, name) OR PyHasAttrClassChain(v, name)`, plus a
compile-time `PyAttrExists` short-circuit before either. Three consultations,
and each was blind in a different way:

| consultation | what it can see | what it misses |
| --- | --- | --- |
| `PyAttrExists` (compile time) | the receiver's STATIC type's str/int tables | a variant has no static type — except its int arm asked `PyIsIntMethodBaseTk`, whose variant clause is a statement about the PROGRAM (`not PyAnyClassDeclares(nm)`) and so was constant **True** |
| `PyHasAttrClassChain` (run time) | user classes declaring the name as a **field** | methods, properties, and every pylib method reached under a Python ALIAS |
| `pydynattr_has_any_v` (run time, pylib) | the dynamic store, declared fields, properties, RTTI methods, `__getattr__` — **object tags only** | the alias (RTTI knows `keylist`, the user wrote `keys`) and every scalar tag: `Exit`s outright when `pyvartag(v) <> 7` |

So the answer was wrong in **both** directions, which is why "always False" did
not survive contact with a wider probe:

- **wrongly False** — every str method, every float method, `dict.keys/values/
  items`, `set.update`, and the `__len__`/`__getitem__` family.
- **wrongly True** — `bit_length` / `to_bytes` / `bit_count` on *anything*:
  `hasattr(a_dict, "bit_length")` and `hasattr(None, "to_bytes")` were True.

`hasattr(a_list, "append")` was already True at v376, contrary to the ticket's
"answers False uniformly, including hasattr(a_list, 'append')" — that arm rides
the RTTI lookup, and `append` happens to be spelled the same in Pascal. The
ticket was filed against v356 and the builtin-receiver work landed in between.

### How many sites shared the rule, and how many were already right

`PyParseVariantMethod` lowers the **CALL** on the identical receiver and it was
right on every row: it has an object-tag arm over the candidate classes (through
`PyMethNameFor`, so it sees the alias), a `pyvar_is_strtag` arm, and a
`pyvar_is_floattag` arm with an int-tag branch for the three shared names. Every
one of `x.upper()`, `x.is_integer()`, `x.hex()`, `x.keys()`, `x.__len__()` ran
correctly on an untyped parameter **while `hasattr` said the name did not
exist.** One question, two mechanisms, and only one of them looking at the
receiver.

So the fix delegates rather than adding a third list:

- `PyHasAttrClassChain` → **`PyHasAttrRuntimeChain`**, now the whole run-time
  question and built arm-for-arm from the *call's own* tables. Its class arm
  asks the new `PyHasAttrAnsweredBy` — field OR property OR
  `FindUMeth(ci, PyMethNameFor(ci, attr))` — which is one predicate used by both
  the scan and its introducer check, so the two cannot disagree about what
  "answers it" means. Then scalar arms: `VT_STRING`/`VT_CHAR` when
  `PyStrMethodInfo` has a row, `VT_DOUBLE` when `PyIsFloatMethodName`,
  `VT_INT`/`VT_INT64`/`VT_BOOL` when `PyIsIntMethodName` or
  `PyIsIntFloatSharedMethodName`. `VT_BOOL` is in deliberately: bool is an int in
  Python, `True.bit_length()` already evaluates to 1 here, and the predicate must
  not disagree with its own call. (`pyvar_is_inttag` excludes VT_BOOL for a
  reason that does not apply to a presence check, so the arm is spelled with
  tags rather than borrowed from it.)
- `PyAttrExists` int arm: `PyIsIntMethodBaseTk` → `PyIsIntBaseTk`. That is the
  same substitution [[bug-nilpy-hasattr-on-a-builtin-container-or-str-answers-false]]
  made one level in (a dispatch predicate asked an existence question); it fixed
  the NAME half and left the RECEIVER half, which is the wrong-True above.

No pylib change, so nothing here waits on a pin: everything is emitted from
tables the frontend already owns.

### The trade, stated plainly

`list` and `set` are **both `TPyList`**, so an `is`-test chain cannot separate
them. `hasattr([1], "add")` was already True before this (wrong); routing the
alias through `PyMethNameFor` adds `hasattr([1], "update")` to that list, in
exchange for `set.update` and the dict views going right. That is one defect —
one Pascal class serving two Python types — not a new one, and hiding it behind
a per-name exclusion in `hasattr` would be the compiler-appeasement workaround
CLAUDE.md forbids. Filed with the measured rows as
[[bug-n-a-list-and-a-set-share-one-class-so-introspection-cannot-tell-them-apart]].

### What stays False on purpose

`hasattr('s', '__len__')` and `hasattr(b'ab', '__getitem__')` — because
`'s'.__len__()` raises here and `b'ab'.__getitem__(0)` returns empty. Answering
True would be a claim the call cannot honour, the rule the float arm was held to
last time. Both become right for free when
[[bug-n-bytes-getitem-returns-empty-instead-of-the-byte-value]] lands, since the
predicate reads those same tables.

### Filed rather than fixed

- [[bug-n-hasattr-with-a-computed-name-cannot-see-a-builtin-method]] — `hasattr(x, n)`
  with the name in a variable is a genuinely different mechanism (pure pylib, no
  compile-time half) and has all the same holes. N p55.
- [[bug-n-a-list-and-a-set-share-one-class-so-introspection-cannot-tell-them-apart]] — N p45.
- [[bug-n-bytes-getitem-returns-empty-instead-of-the-byte-value]] — N p60, silent wrong value.
- [[bug-n-an-int-method-on-a-none-receiver-returns-0-instead-of-raising]] — the CALL half
  of the wrong-True this ticket fixed on the predicate side. N p50.

Nothing here is Track A's: no AST node, IR op, symtab field or backend was
touched. The `VT_*` constants are read from `defs.inc`, not edited.

### Gate

`test/test_nilpy_hasattr_untyped_parameter.npy`, `.expected` generated by
CPython, wired into **test-core** (native tier). It is a witness: at pinned v376
**ten** of its rows are wrong — in both directions — and the `describe()` duck
dispatch at the end returns `scalar scalar sequence scalar` instead of
`mapping text sequence scalar`, which is the wrong-branch failure mode in one
line. Every wrong row sits beside an already-correct sibling, and the `call *`
rows assert the calls that worked all along, so the predicate disagreeing with
its own call is what fails.

`make compiler/pascal26` byte-identical self-host fixedpoint green. The ten
attribute-related NilPy tests re-run individually and all match
(`hasattr_builtin_receivers`, `hasattr_variant_receiver`,
`hasattr_getattr_property`, `getattr_dunder`, `getattr_computed_name`, `attrs`,
`dynattr`, `dynattr_class`, `missing_attribute_raises`, `setattr`).

## Log
- 2026-08-26 — resolved.
- 2026-08-26 — resolved, commit PENDING-COMMIT.
