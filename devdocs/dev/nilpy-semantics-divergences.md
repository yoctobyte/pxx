# NilPy: where the language deliberately differs from CPython

Divergences that are **chosen**, not bugs. Each one here has been measured
against CPython and left as it is on purpose. Anything not in this file that
differs from CPython is a bug — file it.

The rule this list is written against: **a program CPython accepts must behave
the same under pxx.** Every entry below is allowed to differ only for programs
CPython itself rejects, or in a way no accepting program can observe.

> **There is a THIRD category this file does not hold** (owner, 2026-08-17):
> a divergence that an accepting program CAN observe and that **static
> compilation cannot express**. Those are permanent, and they belong in
> `devdocs/dev/frontend-compat-philosophy.md` rather than here or in the bug
> backlog — a permanent limit filed as an ordinary bug sits open forever and gets
> re-diagnosed by every new session. The bar for claiming one is high: show the
> workaround space is genuinely EMPTY, not that the obvious approach failed.
> "Most have sane workarounds" is the owner's framing, so assume one exists until
> proven otherwise. Declaring a permanent limit is a Track U escalation, never a
> worker's call.

---

## Mutating a dict while iterating it is not detected

*Decided 2026-08-04 (Rene). See `decide-nilpy-dict-mutation-during-iteration`.*

`for k in d` iterates a **snapshot of the keys** taken at loop entry (the
lowering rewrites it to iterate `d.keylist()`), so the loop cannot observe a
concurrent mutation at all. CPython raises
`RuntimeError: dictionary changed size during iteration`.

Measured, all three shapes:

| the loop body… | pxx | CPython |
| --- | --- | --- |
| **inserts** a key | completes, iterating the entry-time keys | `RuntimeError` |
| **deletes** a key, never reads it again | completes; the deleted key is still VISITED | `RuntimeError` |
| **deletes** a key, then reads it | `KeyError` | `RuntimeError` |

Only the third row is "the same failure with a different message". The first two
complete silently, and the second can hand the body a key that no longer exists —
so do not describe this as "you still get an error".

**Why this is acceptable:** every program that can tell the difference is one
CPython rejects outright. No working Python program is affected. And the failure
that does occur (row three) is a catchable `KeyError` at the point of use — not
garbage, not memory unsafety, not a wrong value silently returned.

**The cost of matching CPython** is a modification counter on `TPyDict` bumped on
every insert and delete and checked once per iteration — i.e. a per-iteration
cost on every dict loop in every program, paid to reject programs that are
already relying on undefined-ish behaviour.

**A `--strict-python` mode that raises is a recorded future option**, not a
rejected one: the cost above is only acceptable because it is opt-out, so making
it opt-IN is the natural shape if the differential sweeps ever want parity.

### Precedent, stated accurately

Permissive map iteration is a normal language choice, but **no one else
snapshots**, and that is where pxx is most permissive:

- **Go** — the spec explicitly permits mutation during `range` over a map: an
  entry removed before being reached **will not be produced**, and an entry added
  may or may not be. Deliberate and documented; the closest philosophical match.
- **JavaScript `Map`** — iteration is **live**: entries added during iteration
  are visited, deleted ones are not.
- **C# `Dictionary`** and **Java `HashMap`** are the strict ones — they throw
  (`InvalidOperationException` / `ConcurrentModificationException`). C# is
  therefore *not* an example of the permissive camp, despite being an easy one to
  reach for.

pxx differs from Go and JS in the same direction for the same reason: because it
snapshots, it **does** produce a removed key. That is the one behaviour worth
naming explicitly when explaining this to anyone.

---

## Iterating a LIST is live — and this is NOT a divergence

Worth stating precisely because the dict rule above invites the wrong
generalisation: **list iteration matches CPython exactly.** Both are index-based
and live. Measured:

| the loop body… | pxx | CPython |
| --- | --- | --- |
| `append`s | 7 iterations, final len 7 | 7 iterations, final len 7 |
| `pop`s | 2 iterations, final len 2 | 2 iterations, final len 2 |

So CPython is itself asymmetric — live lists, raising dicts — and pxx matches it
on the list half. Do not "fix" the list to be a snapshot for consistency with the
dict; that would introduce a divergence where there is none.

`test/test_nilpy_iterate_live_list.npy` pins the list half;
`test/test_nilpy_dict_mutation_during_iteration.npy` pins the dict half.

---

## A tuple is mutable

*Decided 2026-08-06 (Rene), while triaging what was almost filed as a bug.*

A NilPy tuple is built as a `TPyList` and nothing marks it read-only, so every
mutating operation CPython refuses on a tuple succeeds here:

| expression | CPython | pxx |
| --- | --- | --- |
| `t[0] = 9` | `TypeError` | succeeds |
| `t.append(4)` | `AttributeError` | succeeds |
| `del t[0]` | `TypeError` | succeeds |

Everything else about a tuple is already CPython-exact: `type(t).__name__`,
`isinstance(t, tuple)`, indexing, slicing, iteration, `len`, `==`, `+`,
unpacking, and use as a dict key.

**This is not a bug**, and the reasoning generalises past tuples:

> If code works on CPython, it must work on NilPy. NilPy is *upward compatible*
> with the reference implementation. Doing something you shouldn't do, and
> having it still work under NilPy, is a language feature — not a defect.
>
> — Rene, 2026-08-06

No working CPython program mutates a tuple, so no working CPython program can
observe this. Enforcing immutability would reject nothing anyone legitimately
writes and would put a check on every store. The same call was made in the
Pascal dialect for restrictions that were historic rather than necessary — see
`../progress/backlog/meta-dialect-extensions-and-fpc-strict.md`, which is the
Pascal-side charter for exactly this trade.

**The half that IS a bug** is the TYPE tag, because a program CPython accepts
*can* observe it: `isinstance(t, list)` answers True for a tuple (and for a
set), so `flatten([[1,2], (3,4), 5])` returns `[1, 2, (3, 4), 5]` under CPython
and `[1, 2, 3, 4, 5]` here. Filed as
`bug-nilpy-list-tuple-and-set-are-indistinguishable-to-isinstance`. The split
between these two halves — lax mutation is fine, a wrong type answer is not — is
the cleanest worked example of the rule on this page.

---

## Set ITERATION ORDER is insertion order — and this is NOT a divergence

*Measured 2026-08-06, after a set started printing with braces and its order
became visible.*

pxx iterates and prints a set in **insertion** order, so `{3, 1, 2}` prints
`{3, 1, 2}` where CPython prints `{1, 2, 3}`. That looks like a divergence and
is not one, for a reason worth writing down rather than re-deriving:

**The language does not specify an order.** A `set` is defined as an *unordered*
collection of distinct hashable objects; iteration order is an implementation
detail of the hash table, not part of the contract.

**And CPython is not even self-consistent.** String hashing is randomised per
process by default (PEP 456, on since 3.3), so CPython's own set order changes
between runs of the same program:

```
$ PYTHONHASHSEED=0 python3 -c 'print({"alpha","beta","gamma","delta"})'
{'alpha', 'delta', 'beta', 'gamma'}
$ PYTHONHASHSEED=1 python3 -c 'print({"alpha","beta","gamma","delta"})'
{'beta', 'delta', 'gamma', 'alpha'}
$ PYTHONHASHSEED=2 python3 -c 'print({"alpha","beta","gamma","delta"})'
{'delta', 'gamma', 'alpha', 'beta'}
```

Small integers only look stable because CPython's `hash(n)` **is** `n` — an
artifact of the hash function, not a promise.

So a working CPython program **cannot** depend on set order; one that did would
already be broken under CPython. Under the upward-compatibility rule at the top
of this page, insertion order is therefore fully conforming, and pxx's answer is
if anything the more useful one (deterministic, reproducible across runs).

**Do not "fix" this to match CPython's output.** Chasing it would mean
reproducing CPython's hash function and its per-process randomisation — copying
an implementation detail that CPython itself does not guarantee, to make a
diff-based comparison look tidier. Any test that pins a set's order must sort it
(`sorted(s)`), exactly as it must under CPython.

The genuinely open set questions — whether `[1] - [2]` should raise — remain in
`../progress/backlog/decide-nilpy-set-as-a-distinct-type-or-a-list.md`. Ordering
is not among them.

## Keyword-only parameters are not enforced (decided 2026-08-08)

CPython marks some builtin parameters keyword-only — the bare `*` in
`list.sort(*, key=None, reverse=False)`, `sorted(iterable, /, *, key=None,
reverse=False)`, `min(arg, *args, key=None)`. Those may be passed by name and
only by name.

pxx implements these as ordinary Pascal routines with defaulted parameters, and a
Pascal parameter list has no notion of keyword-only, so the positional spelling
is **accepted**:

```python
sorted(xs, len)        # pxx: works.  CPython: TypeError
min(words, len)        # pxx: 'a'.    CPython: TypeError
```

**This is a divergence, not a defect.** The NilPy rule is forward compatibility
only: everything CPython accepts must work here, and accepting more is a
language feature. A pxx-only spelling fails loudly on CPython, so the cost is
deferred discovery of a portability issue, never a wrong answer.

### Why it does not endanger forward compatibility

`min`/`max` are the case worth knowing, because their second POSITIONAL slot is
another value (`*args`), not `key`. Binding it to `key` would silently change the
meaning of `min(a, b)` — valid, ordinary CPython. It does not: pxx disambiguates
on **callability**, so a callable second argument is `key` and anything else is
another value.

Verified at HEAD against the CPython oracle: `min(3, 5)`, `min(3, 5, 1)`,
`min([1,2], [1,3])`, `max([1,2], [1,3])`, `min("apple", "banana")` and
`min(words, key=len)` all agree. Only `min(words, len)` differs, and CPython
refuses that outright.

Limit of the heuristic, for the record: an object that is both callable and
orderable, passed as a second value, would take the `key` reading here and the
value reading in CPython.

### If portability checking is ever wanted

It becomes a `--strict-python`-style per-feature flag, like `--strict-case` and
`--strict-overload`. The default stays lax; see
`decide-nilpy-builtin-keyword-only-parameters`.

---

## `__file__` names the EXECUTABLE, not the source (decided 2026-08-13)

*Decided 2026-08-13 (Rene). See `decide-nilpy-dunder-file-for-a-compiled-program`
for the full reasoning and the rejected options; implementation is
`feature-nilpy-file-dunder-from-the-executable`; the user-facing write-up is
`docs-nilpy-file-dunder-and-data-files` (Track D).*

CPython's `__file__` is the path of the **source file** a module was loaded
from. A compiled NilPy program performs no module load at run time, so the name
has to mean something else. It is derived from the **resolved executable path**:

| | value |
| --- | --- |
| main module | the executable's own path (`os.path.exists(__file__)` is True) |
| imported module | `<exe_dir>/<original module basename>` — a VIRTUAL path; no file is there |
| `sys.executable` | the same resolved executable path |

Resolved via `/proc/self/exe` on hosted Linux, not raw `argv[0]` — `argv[0]` can
be a PATH lookup, a relative path, or whatever an `exec` caller passed.

**What this makes work:** the dominant idiom
`os.path.dirname(os.path.abspath(__file__))` yields the **executable's
directory** for every module, i.e. where a shipped app's data files sit.

**What an accepting program can observe, and why it is acceptable:**

- `open(__file__)` on an imported module fails — nothing is at that path. This
  is the third-most-common use of `__file__`, after locating sibling data and
  logging, and **frozen Python behaves the same** once its temp directory is
  gone. pxx is a freezer; PyInstaller/cx_Freeze is the right family to compare
  against, not CPython running source.
- A program that ships data beside its SOURCE and is run from elsewhere finds
  nothing, where CPython finds it. This is a **trade, not a strict win**: it
  works when you ship the binary next to its data instead. uforth is the worked
  example — run from `tests/`, it locates `STD.UFO` only if the binary sits
  beside it.

**Why the two rejected alternatives are worse:** baking the compile-time source
path leaks the build machine's absolute paths into every shipped binary (even
with debug info off) and breaks the moment the binary moves; a compile-time path
with a run-time fallback makes the same binary answer differently on two
machines, and a silent fallback is the pattern this codebase refuses elsewhere.

**If a program needs data somewhere else** (a distro installing to
`/usr/share/<app>`), the answer is an application-level data root —
`--data-root=<path>` setting the base directory those virtual paths hang off,
default the executable's directory. Deliberately NOT built yet: it waits for the
first program that needs it, so that `__file__` does not acquire two meanings
speculatively.

### Why this surfaced only on 2026-08-13

Worth knowing because it hides a whole class: programs probe the CWD first
(uforth: `if not os.path.exists("STD.UFO"): ...__file__...`), and our corpus
habit compiles a program in its source directory and runs it there — so "the
CWD" and "where the source lives" coincide and any `__file__`-based resolution
silently agrees with the CWD-based one. Finding one needs a program that BOTH
reaches the fallback AND runs from somewhere else.


---

## A `Protocol` subclass can be instantiated (2026-08-14)

`typing.Protocol` and `typing.Generic` are ERASED where they appear in a base
list — NilPy erases generics, so the base contributes nothing to the layout, the
method table or `super()`, and the class is registered exactly as `class C:` is
(the same call `object` in a base list already gets). A side effect:

| | CPython | pxx |
| --- | --- | --- |
| `class R(Protocol): ...` then `R()` | `TypeError: Protocols cannot be instantiated` | succeeds |
| an explicit subclass `class F(R)`, then `F()` | succeeds | succeeds |

**Not a bug, by the upward-compatibility rule**: a program CPython *accepts and
runs* cannot observe it, because in CPython that program never instantiates the
Protocol. The divergence is a refusal we do not make, which is the same shape as
the mutable tuple above.

Erasure is also what makes `class Bus(Service, Generic[T])` legal here at all:
the header names exactly one REAL base, so it is single inheritance, and the
multiple-inheritance refusal correctly does not fire. It still fires for
`class C(A, B)` where both are real. bug-n-typevar-call-is-an-undefined-variable

## A bad name in a `from` import is caught at the USE site, not the import (2026-08-18)

`from sys import nosuch` does not fail. The name simply binds nothing, and the
wall arrives when something reads it:

| | CPython | pxx |
| --- | --- | --- |
| `from sys import nosuch` then `print(1)` | `ImportError` at the import | compiles, prints 1 |
| `from sys import nosuch` then `print(nosuch)` | `ImportError` at the import | `error: undefined variable (nosuch)` |

**Not a bug, by the upward-compatibility rule**: a program CPython accepts and
runs contains no such import, so nothing that works there can observe the
difference. It is a refusal we do not make — the same shape as the mutable tuple
and the instantiable `Protocol` above.

Recorded because it is easy to describe imprecisely. The from-import binding
work (bug-n-a-from-import-of-a-compiler-provided-module-binds-no-names)
deliberately keeps an unprovided name OFF the qualified any-attribute arm, so
that reading it is a compile-time `undefined variable` rather than a weaker
runtime AttributeError — and I first wrote that up as "still walls at compile
time", which reads as though the IMPORT fails. It does not; the USE does. The
design point is real, the wall is one statement later than that phrasing
implies, and the coordinator caught it by measuring the unused case.

## `exec` binds, but injects no `__builtins__` key (2026-08-14)

`exec(src, g, l)` now really does bind into `l` — it used to run and publish
nothing at all, which was a bug and is fixed
(bug-n-exec-builtin-is-a-silent-no-op-and-eval-is-absent). Two differences
remain, and they are different in kind.

**A divergence.** CPython injects a `__builtins__` key into the globals dict;
NilPy does not, having no module object to put there.

| | CPython | pxx |
| --- | --- | --- |
| `d={}; exec("x=1", d, d); sorted(d.keys())` | `['__builtins__', 'x']` | `['x']` |
| `d["x"]` | `1` | `1` |

Only a program that ENUMERATES the namespace can see it; reading a bound name
agrees.

**DECIDED 2026-08-19 (user): leave it out, permanently for now.** Not because
the key is hard to produce — CPython's value is `builtins.__dict__`, a plain
dict by identity, and pxx could hand back a populated copy cheaply. Because
neither shape is honest:

- **A copy** is inert. `d["__builtins__"]["len"] = f` mutates a snapshot and
  changes nothing, where CPython would have rebound `len` program-wide.
- **A live pointer** is worse, because it half-works. pxx has TWO name
  resolution paths where CPython has one: compiled NilPy resolves `len` at
  COMPILE time into a direct call and consults no dict at run time, while only
  code inside the `pyeval` tree-walker resolves against `g`/`l`. So a mutation
  through a live builtins dict would be honoured by exec'd source and silently
  ignored by every compiled call site — a divergence that LOOKS like CPython
  semantics, which is the expensive kind.

Making it genuinely live means routing every compiled builtin call through a
run-time dict lookup — turning `len(x)` into a hash probe across the whole
language, for a feature no corpus file has asked for.

So: a documented incompatibility beats silently wrong behaviour. Revisit only
if a real consumer needs it AND someone has a third shape; the ticket is parked
in `rainy-day/`, not rejected.

**Not a divergence — a refusal.** The AMBIENT form `exec(src)` with no
namespace, which writes into the caller's own locals, is a COMPILE ERROR here
and names itself:

```
exec(src) with no namespace is not supported — it would bind into the
caller's own locals, which are compiled stack slots with no run-time name
table. Use the explicit form Python also has: d = {}; exec(src, d, d)
```

Loud, at compile time, with the working spelling in the message. That is the
opposite of the failure this whole area just came out of, and it is why it is
refused rather than accepted-and-ignored.

`eval(src)` has no such restriction — an expression only READS, so a name it
cannot see is a run-time error naming the name, never a silent wrong value.

## `@overload` with no implementation fails at COMPILE time (2026-08-15)

`@overload`-decorated stubs are dropped, header and body, because CPython
replaces them with the implementation def that follows
(bug-n-overload-decorator-is-refused). If no implementation follows:

| | result |
| --- | --- |
| CPython | runs, and the call raises `NotImplementedError` — *"A series of @overload-decorated functions ... should always be followed by an implementation"* |
| pxx | `error: undefined variable (only)` at compile time |

Both refuse the program; pxx refuses it earlier. **Not a divergence under the
upward-compatibility rule** — CPython does not accept-and-run such a program
either, so nothing that works there breaks here. The message names the call
rather than the missing implementation, which is worse than CPython's; improving
it would mean carrying the dropped stub names, and no real code has needed it.

## Codecs: the supported set is a SUBSET, refused by name (2026-08-15)

`str.encode` / `bytes.decode` honour their encoding argument
(bug-n-str-encode-and-bytes-decode-ignore-the-encoding). Supported: `utf-8`,
`ascii`, `latin-1`/`iso-8859-1`, `utf-16le`/`be`, `utf-32le`/`be`, and
`utf-16`/`utf-32` with a BOM — with CPython's alias spellings and its
`-`/`_`/space normalisation, and `errors=` as `strict` / `replace` / `ignore`.

Anything else raises `LookupError` **by name**. CPython ships dozens more
(`big5`, `gb18030`, `shift_jis`, the other `iso-8859-*` …), so:

| | CPython | pxx |
| --- | --- | --- |
| `"hé".encode("big5")` | `UnicodeEncodeError` (big5 exists; é is not in it) | `LookupError: unknown encoding: big5` |
| `"ab".encode("big5")` | `b'ab'` | `LookupError` |
| `"ab".encode("no-such-codec")` | `LookupError` | `LookupError` |

**A missing feature, deliberately, not an approximation.** Returning UTF-8 bytes
labelled `big5` would be a wrong answer that no caller could detect; refusing is
one a caller can. Row 2 is the honest cost: a program that only ever passes
ASCII through an unimplemented codec worked in CPython and is refused here. Add
a codec when a real target needs it — each is a table, and the one place that
decides what an encoding NAME means is `PyEncCode`, so a future `codecs.lookup`
delegates there rather than becoming a second mechanism.

## Multiple inheritance is FLATTENED, and three shapes are refused (2026-08-15)

`class D(B, C):` compiles. The first base is a real parent; every further base
is **flattened** — its body span is replayed against the derived class, so its
methods compile with `self` = the derived object, which is exactly what a mixin
means in Python. Conflicts resolve C3 left-to-right: the derived class wins,
then the first base and its ancestors, then each further base in order.

What is the SAME as CPython: mixin methods, a mixin method reading an attribute
the derived class supplies, class attributes carried over from a flattened base,
and every conflict resolution above. `test/test_nilpy_multiple_inheritance.npy`
diffs all of it.

Three things differ, all of them loud:

| shape | CPython | here |
| --- | --- | --- |
| `isinstance(d, C)` for a flattened base `C` | True | **False** — `C` is not in the object model's parent chain |
| a class used BOTH standalone and as a second base | works | compile error at the standalone call (`C has no method m`) |
| a diamond, or `super()` inside a flattened body | works | refused by name, with its own message |

The first is the known v1 cost and is fixed later by synthesising an interface
per flattened base (the RTTI interface table already carries what that needs).

The second follows from the first: a class that is flattened somewhere is
flattened *everywhere*, and its body is not compiled standalone at all — the
canonical mixin reads members it does not declare, which only resolves against a
host. It is not a silent wrong answer, and it is new ground: a program with a
second base did not compile at all before.

The third is deliberate. A diamond gives the shared ancestor one copy under C3
and two under flattening, after which the two copies' state diverges silently.
`super()` in a flattened body would reach the derived class's own parent instead
of the next class in the MRO. Both are refused with a message naming the shared
ancestor / the calling base, rather than answered wrongly.

## A hand-written `__lt__` under `@dataclass(order=True)` is allowed (2026-08-15)

CPython refuses the combination outright:

```
TypeError: Cannot overwrite attribute __lt__ in class Rev.
Consider using functools.total_ordering
```

NilPy accepts it, and the hand-written method wins — the same rule
`__eq__` and `__repr__` already follow for the generated pair. Divergence in
the permitted direction: no program CPython *runs* can observe it, because
CPython never gets past the decorator. Recorded rather than "fixed", since
refusing it would buy nothing a working program can see.

Everything else about `order=True` is parity: the four comparisons are
generated over the field tuple in declaration order, the first differing field
decides, and `sorted`/`min`/`max` use them.
`test/test_nilpy_dataclass_order.npy` pins it.

## `float.as_integer_ratio()` raises where CPython answers a big int (2026-08-15)

NilPy's ints are 64-bit; CPython's are arbitrary precision. That difference is
program-wide and pre-existing, but `as_integer_ratio` is the first place where
the *exact* answer is routinely outside the 64-bit range, so it is worth naming:

```python
(1e300).as_integer_ratio()   # CPython: a 1000-bit numerator over 1
                             # NilPy:   OverflowError
(5e-324).as_integer_ratio()  # CPython: (1, 2**1074)
                             # NilPy:   OverflowError (subnormal denominator)
```

The whole normal range answers exactly and matches CPython bit for bit —
`(3.5)` is `(7, 2)`, `(0.1)` is `(3602879701896397, 36028797018963968)`.
Outside it the choice was between a truncated pair and a raise, and a silently
wrong ratio is the worse of the two. This is a symptom of the 64-bit int
decision rather than a rule of its own: it goes away for free if NilPy ever
grows big ints.

Same statement, no divergence, for the other three: `is_integer`, `hex` and
`conjugate` are exact over every double including the infinities, NaN and the
subnormals.

## A SLICE of a builtin subclass does not call `__getitem__` (2026-08-18)

A subclass of `list`/`dict` that overrides `__getitem__` gets the override for
every scalar subscript — `c[k]`, `c[k] = v`, `del c[k]`, `len(c)`, `k in c` —
but **not** for a slice:

```python
class L(list):
    def __getitem__(self, i):
        print("mine")
        return list.__getitem__(self, i)

l = L([1, 2, 3])
l[0]      # CPython: "mine"   NilPy: "mine"
l[0:2]    # CPython: "mine"   NilPy: silent, base slice
```

CPython passes a **slice object** to `__getitem__`; this frontend has no such
value, so there is nothing to hand the method. The alternatives were to refuse
slicing on any class with an override (breaking working code, including
`test/test_nilpy_subclass_a_builtin_type.npy`) or to call the override with the
start index alone (a wrong value dressed as a right one). Taking the base
lowering means the slice does what the un-overridden container would — which is
what a class overriding *scalar* indexing means anyway, and it is the answer
that cannot be silently wrong about a value it invented.

Direction: NilPy accepts and runs the program, and answers what the base class
would. Observable by a CPython program whose override changes slice results, so
it is a genuine divergence and not laxity — recorded here rather than filed
because closing it needs a slice VALUE, which is a language-level addition.
Landed with `bug-n-a-builtin-subclass-subscript-operator-skips-the-override`.

## `sys.path` cannot work, and that is PERMANENT — the answer is `-Fu` (2026-08-17)

**Not a bug, and not fixable.** `sys.path.insert(0, "/path/to/pkg")` before an
import is how CPython finds a third-party package. Under NilPy it does nothing
to imports, because **`sys.path` is a RUNTIME list and pxx resolves imports at
COMPILE time**. No amount of work makes a compile-time resolver honour a list
the program mutates while running.

The NilPy answer is the unit search path:

```sh
./compiler/pascal26 -Fu/abs/path/to/library_candidates/webencodings drv.npy drv
```

`-Fu` takes the directory *containing* the package directory — the same "parent
of the package" convention Python's own path entries use.

**Why this is written down rather than left obvious:** without `-Fu` the failure
is `error: import: no unit named webencodings and no shim mimic_webencodings`,
which reads as *"this feature does not exist"* for a feature that does — and
`-Fu` is absent from the compiler's usage line, so nothing points at it. That
combination produced a wrong first diagnosis on the first third-party corpus
attempt ("pxx cannot resolve third-party packages at all") and sent the next
move to `sys.path`, which silently does nothing. See
[[doc-n-fu-is-how-a-python-package-is-found]] for the message and usage-line
fixes.

This entry exists so a future session does not try to "fix" `sys.path`.
Assigning to it is legal and harmless — it just has no effect on imports, the
same way it has no effect in any AOT-compiled Python.

## The `--strict-python` flag (shipped 2026-08-13, no rules wired yet)

Every divergence on this page is a **laxity**: NilPy accepts something CPython
refuses. That direction is deliberate and is the rule of the frontend — *if code
works on CPython it must work on NilPy*, one direction only — so the default
dialect will not grow these checks.

But a program that must stay portable wants to be told, and so does a program
using a dialect EXTENSION (`parallel for` and friends) that CPython has no
notion of. `--strict-python` is that switch, the peer of `--strict-fpc`.

**It was shipped deliberately empty** (user, 2026-08-13: *"we want and/or should
implement strict-python even if we don't use it today"*). The reason is
structural rather than tidy-minded: if the flag arrives with its first rule,
then that rule's author also has to invent the flag, the diagnostic wording, and
the place rules are listed — and the second rule copies whatever the first one
guessed. Shipping the frame first makes every rule a small, uniform change.

What exists today:

| piece | where |
| --- | --- |
| `StrictPython` global, default False, always | `defs.inc`, reset in `PasInitDefines` |
| `--strict-python` option | `compiler.pas`, listed in the usage line |
| `PyStrictRefuse(feature, cpythonSays)` | `pyparser.inc` — the ONE diagnostic shape |

`PyStrictRefuse` checks the flag itself, so a rule cannot accidentally refuse
something for everybody, and its message always names three things: the
construct, what CPython does, and that the default dialect accepts it.

### Adding a rule

1. Find the single site where the construct is accepted.
2. Call `PyStrictRefuse('a mutable tuple', 'raises TypeError')` there.
3. Add a `.npy` test that passes by default and is refused under the flag —
   both directions, or the rule is not tested.
4. Add a row to this page.

**Do not half-wire a rule.** If a construct is reachable through several sites
(argument binding, for one, has separate paths for plain calls, methods and
constructors), refusing it at one of them is worse than not refusing it at all:
the flag would then mean "sometimes". Either cover every site or file the rule
and leave it unwired.

### Candidate rules, in the order they are worth doing

- **keyword-only parameters passed positionally** — the bare `*` marker is
  currently consumed and dropped, so nothing records the boundary; needs a
  parallel array plus a check at each argument-binding path
  ([[decide-nilpy-builtin-keyword-only-parameters]]).
- **a mutable tuple** — `t[0] = 9`, `t.append(4)`, `del t[0]`; needs the store
  paths to see the receiver's `FKind`, which is a run-time tag, so this one is
  probably a runtime check the flag has to reach.
- **dict mutated while iterating** — runtime, same problem.
- **dialect extensions** (`parallel for`) — the cheapest of the four, because
  each extension has exactly one parse site.
