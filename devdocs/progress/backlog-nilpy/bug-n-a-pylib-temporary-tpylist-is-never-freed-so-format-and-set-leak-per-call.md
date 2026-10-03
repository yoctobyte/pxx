---
slug: bug-n-a-pylib-temporary-tpylist-is-never-freed-so-format-and-set-leak-per-call
title: a pylib temporary TPyList is never freed, so .format() and set() leak on every call
summary: >
  `"{}".format(x)` leaks ~200 bytes per call and `set(seq)` ~583 bytes per call,
  both perfectly linear across repeated passes, both zero under CPython. The
  mechanism is one shape: a pylib function builds a TPyList as a LOCAL
  TEMPORARY, passes it somewhere that only reads it, and drops it. pxx objects
  ARE refcounted (PXXObjRetain/Release, finalizer on zero) -- but a PASCAL LOCAL
  does not participate: the frontend emits retain/release for NilPy locals, and
  pylib.pas is Pascal, so nothing ever releases these. FOUR SITES FIXED
  (pystr_format/2/n, pyset_of); roughly 28 more temporaries remain unaudited.
  NOT the cause of lekkerzeilen's measured 800 kB/s leak -- see "what this is
  NOT" -- but the same class, and a frame loop touching either call leaks.
status-note: the two measured sites are fixed and regression-tested; the ticket
  stays OPEN for the remaining temporaries.
track: N
type: bug
prio: 75
owner: unassigned
status: open
---

## Measured

Compiler at 06e40fb95, pin v410. Instrument is `/proc/self/statm` resident
pages read from inside the NilPy program; CPython run as the oracle on the
identical source. Every phase runs TWICE -- a first pass may move the number
for one-off reasons, a second pass must not.

`retain` is the positive control and it is not decoration: every other row
reads 0, and a probe whose rows all read zero cannot tell "nothing leaks" from
"the instrument is dead".

| phase | pxx bytes/call | CPython |
| --- | --- | --- |
| `"{}".format(i)` | **199 / 200** | 0 / 0 |
| `"{} {} {}".format(a,b,c)` | **200 / 200** | 0 / 0 |
| `"constant".format()` (no args) | **69 / 64** | 0 / 0 |
| `set(L)`, L 32 elements | **583 / 583** | 0 / 0 |
| `"%d %s" % (i, s)` | 0 / 0 | 0 / 0 |
| `str(i) + " " + str(j)` | 0 / 0 | 0 / 0 |
| list / dict / tuple / object construction | 0 / 0 | 0 / 0 |
| slices, concat, closures, exceptions, nested dicts | 0 / 0 | 0 / 0 |
| `items` `keys` `enumerate` `zip` `sorted` `kwargs` `listcomp` `min/max/sum` | 0 / 0 | 0 / 0 |
| `retain` (control -- MUST move) | 380 | 207 |

ARGUMENT COUNT DOES NOT SCALE IT: one argument and three cost the same 200
bytes, which is what says the leak is a fixed per-call allocation rather than
per-argument work.

## The mechanism, both sites

`pystr_format` / `pystr_format2` / `pystr_formatn` (pylib.pas ~16717-16770):

    args := TPyList.Create;
    args.append(a);
    pystr_format := PyFormatApply(fmt, args);

`PyFormatApply` returns an AnsiString and retains nothing. `args` is
unreachable the moment it returns, and nothing frees it.

`pyset_of` (pylib.pas ~8469):

    kl := pyseq_of_obj(o);
    for i := 0 to kl.count - 1 do r.add(kl.at(i));

and `pyseq_of_obj` for a list arm is `Result := list(TPyList(o))` -- a full
COPY. So a 32-element input allocates a 32-element throwaway: 32 Variants at 16
bytes plus header, which is the 583 measured.

## The fix, and why it is `PXXObjRelease` and not `Free`

`Free` would be wrong: it runs `TObject.Destroy` and bypasses the refcount and
the type finalizer. The right call is `PXXObjRelease`, which decrements, runs
`PXXObjFinalizeHook` (releasing the Variants the list holds, recursively) and
frees the block at zero. pylib already used exactly this for exactly this shape
-- `if snap <> nil then PXXObjRelease(Pointer(snap))` -- so the fix follows
existing precedent rather than inventing a convention.

**The trap, and it is worth writing down because a blanket sweep hits it:**
`pyseq_of_obj` had to be checked arm by arm before `kl` could be released. Had
any arm returned an ALIAS rather than a copy -- the obvious candidate being the
dict arm, `TPyDict(o).keylist` -- releasing it would have been a use-after-free
inside the dict, which is a worse defect than the leak. Every arm was read: the
list, bytes and range arms copy through `list()`, `keylist` constructs a new
list, and the iter and user-object arms drain into a new one. All fresh, so the
release is safe. **The remaining ~28 temporaries each need that same
per-site answer; do not sweep them.**

## Fixed and verified

| | before | after |
| --- | --- | --- |
| `"{}".format(i)` | 199 B/call | 0 |
| `"{} {} {}".format(...)` | 200 B/call | 0 |
| `set(L)` | 583 B/call | 0 |
| `retain` (control) | moves | still moves |

Regression: `test/test_nilpy_format_and_set_do_not_leak_a_temporary_list_per_call.npy`.
POSITIVE CONTROL, with only the four `PXXObjRelease` calls removed:
`format1 LEAKS 199 bytes/call / format3 LEAKS 199 / set LEAKS 583 / PYLEAK FAIL`.
The threshold is 50 bytes per call -- deliberately BELOW the smallest real
defect (199) and well above noise, because asserting 0 would flap and asserting
200 would pass on the unfixed compiler.

## What this is NOT

**It is not lekkerzeilen's 800 kB/s leak**, and it would have been easy to
claim it was. The demo calls `.format()` thirteen times and ALL THIRTEEN are in
`tests/`, so its runtime never executes the path. It does call `set()` 37 times
in runtime code, but none of those has been shown to be per-frame. The demo's
leak (measured by lekkerzeilen-c8: 800 kB/s, linear over 11 minutes, no
plateau, one merged anonymous region) is still unattributed, and this ticket
must not be closed as though it explained it.

The one thing that IS shared is the region: pxx's heap is mmap-backed with
`HEAP_ARENA = 268435456` (256 MiB), and adjacent anonymous mappings MERGE in
/proc/maps -- measured, a bare pxx binary retaining 600 MB shows one region
going 256 -> 512 -> 768 MB with the mapping count never moving off 9. So a flat
mapping count does NOT rule the pxx heap out; it is the signature.

## Repro

`/tmp` fixtures were used to find this; the rows above reproduce from any NilPy
program that calls the named function in a loop and reads
`/proc/self/statm`. A wired regression test should assert a RELATION (bytes per
call below a threshold, second pass equal to first) and never an absolute RSS,
and must carry a retain-style positive control or it cannot fail.

## 2026-09-22 — censused the shape, seven more sites fixed, one residual and one unreachable

The ticket stayed open for "roughly 28 more temporaries remain unaudited".
Censused rather than sampled: routines in `pylib.pas` with a local **declared in
the routine's own `var` block**, assigned `T*.Create`, and neither released nor
assigned to the result.

**What the census enumerates, and what it cannot see.** A first pass answered
**58** and was nearly all false positives — a local literally named `Result`
IS the return value, and `F`-prefixed names are class fields. Restricting to
the routine's own `var` block gives **5**. It is still blind to a temporary
handed to something that does not retain, and its "returned" test was wrong for
METHODS: `function TPyDict.itemlist` gave the regex the CLASS name, so
`itemlist := r` did not look like a return. **Five is a candidate list, not a
population.**

| candidate | verdict |
| --- | --- |
| `TPyDict.most_common` — `pair` | **LEAK, fixed** |
| `pylist_setslice` — `keep` | **LEAK, fixed** |
| `TPyDict.itemlist` — `r` | false positive, returned (census mis-named the method) |
| `pyexc_setargs` — `cargs` | not a leak, ownership passes to the exception's `argsv` |
| `TPyDeque.Compact` — `nb` | **real defect, UNREACHABLE — see below** |

### 1. `most_common` — the open question, answered

Its own comment said the pairs reach `res` through `res.append(pair)` and that
*"whether that retains is not established here and is not patched on an
assumption."* That was the right call and the answer is **yes**:
`append -> append_self -> PyVarSlotSet`, which does
`if PyVarSlotIsObj(src^.VType) then PXXObjRetain(...)`. The result list takes
its own reference and the constructor's was dropped by nothing.

    most_common(4)                800 bytes/call     CPython 0
    most_common() over 16 keys   3200 bytes/call     CPython 0

**200 bytes per emitted pair, linear in the pair count** — which is what says
one leaked list per pair rather than a per-call cost, and it is the same
200 bytes/entry `itemlist` measured before its own fix.

### 2. `pylist_setslice` — the temporary AND a dropped band

`keep` (prefix + src + suffix) was copied back element by element and dropped:
**584 bytes/call** on a 32-element list, **1096** when the assignment grew it
past 32. The number tracks `keep`'s CAPACITY, not its length, which identifies
one leaked list object per call.

Separately, `FLen := 0` does not release the slots being dropped. It does not
have to for indices below the new length — `append -> PyVarSlotSet` clears each
destination — but the band ABOVE it is revisited by nothing, so a **shrinking**
slice assignment over managed elements stranded their references. Now cleared
with the finalizer's own spelling. **Int elements cannot expose this**; the
measurement that found it used strings.

### 3. The `pyiter_drain(pyiter_of_*(...))` family — seven sites, found by grep

`list(r: TPyRange)` was `Result := pyiter_drain(pyiter_of_range(r))`. The cursor
is built inline, drained, and dropped. **`pyiter_drain` cannot take ownership of
its argument** — `list(it: TPyIter)` hands it a cursor the CALLER owns, so
releasing there would over-release — hence each site must release its own.

Grepping the shape found **seven**, and the four aggregates leaked TWICE,
because `sum`/`tuple`/`any`/`all` only READ the drained list:

    list(range)                384 bytes/call    cursor only; list is the result
    sum/tuple/any/all(range)   968 = 384 cursor + 584 drained list

**The arithmetic is the corroboration**: 384 is FLAT across `range(8)` through
`range(128)` (a per-call object), and 584 is a 32-slot list — the same 584
`keep` leaked. All five now measure 0.

### Residual, measured and NOT fixed

`list(<user iterable>)` went 447 -> **63 bytes/call** and is not zero. The
remainder is in `pyiter_of_userobj`, not at the seven sites: the `itv: Variant`
holding `__iter__`'s result is retained and never dropped. Isolated — the
instance alone leaks 0, and binding it to a named local does not change the 63.
**No fixture row for it, deliberately**: at 63 against a LEAK_LIMIT of 50 it
would be red on arrival.

### Verification

Eight new fixture rows, each shown to FAIL on the unfixed compiler (799, 3200,
583, 384, 967, 968, 968, 967 bytes/call) and pass on the fixed one — the
positive control run before the result, not after. Slice assignment checked
against CPython across same-length, shrink, grow, full-replace, insert, append,
empty, delete and nested-list shapes, plus repeated shrink, identical under
`-dPXX_HEAP_DEBUG`. **527 NilPy tests: 515 ok on both sides, one row moved and
it was `select_stdin_ready`, which my runner does not feed stdin** — five runs
give rc=217 without it and rc=0 with it, matching `.expected`. Zero regressions.

### INERT UNTIL THE NEXT PIN

All of this is `compiler/builtin/pylib.pas`, and the pin carries its **own** copy
(`stable_linux_amd64/default/builtin/pylib.pas`, a different sha). Anything built
with `$(PXX_STABLE)` — Track B and E demos — does not get these fixes until
someone pins.

### The ticket stays open

The census is a candidate list and not a population; `TPyDeque.Compact` is a
real defect nobody can reach yet; and `pyiter_of_userobj` has a measured
residual with a named mechanism and no fix.


## 2026-10-02 — the pyiter_of_userobj residual, found to be much larger and fixed (frankuser)

The "63 bytes/call" residual above was the visible tip of a wider defect.
The census showed objects, not bytes:

| loop body (5000 passes) | at pin v452 | fixed |
| --- | --- | --- |
| `list(o)`, `__iter__` returns `self` | 0 per pass, but the instance itself never dies | 0 |
| `o = Sel(4); list(o)`, fresh each pass | 1 object per pass (the instance) | 0 |
| `__iter__` returns a separate iterator object | 1 per pass | 0 |
| `__iter__` returns `iter(self.xs)` | 3 per pass | 0 |
| a `__next__` that yields fresh objects | 1 per yielded value | 0 |

**Mechanism.** `PyUserObjNoArgMeth` (pylib.pas) added an EXTRA reference to
every object a no-argument dunder returned, in both object arms (RetKind 6 and
22). The reason given was that callers keep the raw pointer after `res` dies.
On top of that, a NilPy def already hands back an OWNED reference: the objtrace
of the separate-iterator case read `A1 R2 R3 R4 r3 r2`, ending at rc=2. Nothing
dropped either reference.

**Fix.** There is now one contract: `res` holds the caller's only reference.
- The RetKind 6 arm releases the def's owned reference after `res` takes its
  own, but ONLY for a NilPy def. A Pascal method returns a borrowed pointer
  (`TWaveFile.__enter__` is `Result := Self`), and releasing that would free a
  live object. The test is `RTTI_METH_FLAG_HASSIG`, which rtti_emit.inc sets
  from `PyProcIsNilPyDef`, so it is exactly "a NilPy def". It also holds for
  the generated `__pxx_gen_iter__`, which returns a fresh cursor.
- The RetKind 22 arm takes no extra reference any more.
- `pyiter_of_userobj`, the one caller that kept the pointer, retains the
  cursor it returns.

**Verified.** Values match CPython under `-dPXX_HEAP_DEBUG` for every shape:
object-yielding `__next__`, generator `__iter__`, `-> Any` returning
`iter(xs)`, a field-held iterator iterated twice, a mixin base `__iter__`,
`sum`/`zip`/`in`/`for`. Regression test:
`test/test_nilpy_iterating_a_user_class_does_not_leak.npy`, wired into
test-nilpy. It reads live=89206 against a bound of 300 on the unfixed pylib,
and 48 fixed. Its `keep` control trips the bound.

**Still open in this ticket:** `TPyDeque.Compact` (unreachable), and the census
remains a candidate list rather than a population.

## 2026-10-02 (later) — measured instead of censused: a probe over ~180 builtins

Each expression ran in a loop under `-dPXX_ALLOC_CENSUS` at N=10 and
N=4010; a growth above 400 live objects flags it. Of ~180 expressions
(string, list, dict, set, bytes, comprehension, map/filter/zip, min/max/sum,
sorted with keys, class construction), these leaked, all fixed:

| expression | at v452 | mechanism |
| --- | --- | --- |
| `dict(zip(a, b))`, `dict(<iterator>)` | 10 objects/call | drained pair list dropped (both `dict` arms) |
| `dict.fromkeys(xs[, v])` | ~2/call | `pylist_v` copy dropped |
| `min/max(xs, default=d)` | ~2/call | same |
| `min/max(xs, key=f)` held in a variable | same | same (PyMinMaxByKey) |
| `sorted(s)`, `min(s)`, `max(s)` over a str | ~2/call | `pystr_charlist` dropped |
| `s.rsplit(sep, n)`, `s.rsplit(None, n)` | ~4/call | backward scratch list |
| `reversed(range(...))` | 1/call | the reversed TPyRange; the cursor copies it |
| `iter(bytes)`, `pyiter_v` over bytes/file, `reversed(<user iterable>)` | 1/call | `pyiter_of_list` / `pyiter_rev_list` RETAIN, so a fresh list passed straight in sat at rc 2 -- new `PyIterAdoptList` |
| `math.prod/fsum/dist`, `random.choice` over a variant | 1-2/call | `pylist_v` copy |

`pylist_v` answers a fresh list on every arm; every caller in pylib was
checked and the remaining ones already release. Regression test:
test/test_nilpy_builtins_release_the_temporary_list_they_read.npy (112673
live at v452, 45 now; HEAP_DEBUG and i386 rows diff against CPython).

Not covered by the probe: statements (with/try/class bodies), the stdlib
mimic units under lib/rtl, and anything needing I/O.

## 2026-10-03 — statement probe: del, exceptions, and three crashes found on the way

The same probe, with each case as a loop body instead of an expression. Leaks
found and fixed (each with a regression test and census + keep control):

| shape | at v452 | mechanism |
| --- | --- | --- |
| `del l[i]`, `del l[a:b]` | 18317 live / 5000 passes (test mix) | the shift left the vacated top slots holding references |
| `del d[k]`, `d.pop(k)` | same test | the removed key and value were never released |
| `Exception(a, b)` | use-after-free + leak | `pyexc_setargs` stored the args tuple without retaining it |
| `repr(KeyError(k))`, `str(KeyError(k))` | 1/call | `GetArgs` returns an owned reference; the renderer dropped it |

Correctness bugs met on the way, fixed in the same batch: a Variant-typed
`__eq__` (`return isinstance(o, P) and ...`) was ignored by dict/set/`in`;
repr of a multi-argument exception used its message, not its args; a
`nonlocal` list or str in an escaping closure crashed; a class passed as the
function of `map()` or as a `key=` crashed.

Still leaking, left alone: `repr(P(1))` -- `repr(o: TObject)` boxes its
argument into a local Variant, so ParamStays cannot prove it borrows and a
construction at position 0 is not spilled (widening that spill to every free
function over-released inside the generator, iterator and exception helpers:
measured, reverted). Frame cells (`pycell_new`) are still never freed.

## 2026-10-03 (later) -- receivers: a construction or a fresh result in position 0

The probe's next family was not in pylib at all but in who owns a method's
RECEIVER. The IR spills an owned argument to a releasing temp from position 1
on, and an owned call result at position 0, but not a construction there (the
receiver guard), and a dunder's result followed by `.` / `[` was not bound the
way a method chain's link is. Fixed in the parser, in PyCallMeth1 (every
desugared dunder goes through it): a construction receiver is bound to an ARC
local and the binding FOLDED into the expression, so it survives the hoist
queue the len()/f-string trial parses park. Covered: `V(1) + w`, `-V(k)`,
`V(1)[i]`, `len(V(1))`, `1 in V(1)`, `str(P(1))`, `f"{P(1)}"`, `(V(1) + w).x`,
`w[i].x`, `io.StringIO(s).read()` (the module-qualified construction lacked
the `.` hoist its bare twin has). test_nilpy_a_construction_or_result_as_a_
dunder_receiver_is_released: pin v452 38547 live after 5000 passes, now 33.

Probed clean afterwards (~110 more shapes): try/finally, nested try, return
from finally, sort(key=), extend/update/insert/pop/remove, set union of
instances, dict views, nested comprehensions, property chains, BST insert and
recursive walk, global containers, exceptions carrying objects, f-string
format specs, class attributes, divmod/hex/chr.

Still open: `repr(P(1))` (see the 2026-10-03 note above in this file's
history: repr(o: TObject) boxes into a local Variant, so ParamStays cannot
prove it borrows); and the compatibility gaps the probe met, which are not
leaks -- module-qualified `itertools.*` and `collections.OrderedDict()` /
`defaultdict(list)` / `namedtuple(..)` calls do not compile.

## 2026-10-03 (evening) -- renderers, and a generator's argument cells

`repr(P(1))`, the one left above, is fixed (e0516eb180), with the rest of
its family: `str(Q())` of a class with no dunders, `f"{Q()}"`,
`str([P(1)])` and `print()` of a fresh object all handed the construction
to a pylib renderer as argument 0. The renderer calls built in the parser
(PyReprContainer, both f-string twins) now bind an owned argument and fold
the binding into the expression (PyRenderCallOwned). `repr()` goes through
the ordinary overload set, so there the IR's position-0 spill names pylib's
repr overloads instead (IRCalleeIsLibraryRepr): they only borrow, which
ProcParamStays cannot prove for `repr(o: TObject)`. Pin v452: 18309 live
after 5000 passes; now 35.

A generator's VARIANT argument cell (`pycell_new`, one per variant argument
per call) is now freed when the generator is done or closed
(SLReleaseLocalsAtDone calls pycell_free_at on each such parameter slot).
Pin v452, every argument spelled out: 64113 live after 5000 passes; now 39.
The `nonlocal` frame cells were fixed earlier (aafccd97bb), so no
`pycell_new` cell is left unowned on these paths.

Correctness bugs found in the same generator probe, fixed in the same batch:
`for v in g(5)` over `def g(n, step=2)` seeded the omitted defaults as 0
(step 0 looped forever) while `list(g(5))` was refused; a generator METHOD
anywhere but `for v in name.gen(..)` ran its step routine once and answered
its Boolean (`list(C(1).items(6, 2))` was []); a six-parameter generator
used as a value segfaulted on x86-64, whose call puts all seven step words
on the stack while the cursor passed one in a register. A generator with
`*args`, and a generator method on a receiver of unknown type, are now
refused by name instead of crashing.

## 2026-10-03 (night) -- stdlib probe: one leak, in deque

The probe over the stdlib mimic units and I/O, the family the 10-02 note
left uncovered: json dumps/loads (nested, indent, sort_keys), Counter
(most_common, +=, values, dict()), deque, struct pack/unpack/calcsize,
io.StringIO/BytesIO, re sub/split/finditer/findall, os.path, time,
str.format and %, sorted with a key, `with open(..)` write/read/readlines/
line iteration, a plain open/close, context managers with and without an
exception. 50 shapes, N=10 against N=4010. All flat but one:

- `collections.deque`: TPyDeque.Compact replaced FBuf by a raw field store
  and never released the old list, so every deque leaked one list on its
  first appendleft, and another on each compaction after a run of popleft.
  164588 live after 2000 passes of the test's loop; 66 now. A deque held in
  a variant (back through a tuple) could not be indexed, assigned or
  iterated; pyvar_getitem / pyvar_setitem / pyseq_of_obj grew a TPyDeque
  arm. test_nilpy_a_deque_releases_its_old_buffer_and_indexes_through_a_variant.

Compile gaps the probe met (compatibility, not leaks; no tickets filed):
`deque(maxlen=n)`, `StringIO.readlines()`, iterating a StringIO,
`match.groups()`, `re.sub` with a callable, `collections.defaultdict(..)`,
`collections.OrderedDict()`, `str(b, "utf-8")`.

Four older leak tickets were re-measured on the way and found flat at HEAD,
closed with test_nilpy_a_discarded_or_variant_routed_result_is_released.

## 2026-10-03 (late) -- a static audit of the remaining temporaries

A walk over pylib.pas for `TPyList.Create` / `pyseq_of_obj` / `list(..)`
results bound to a Pascal local and never released, each hit census-checked
(N=300 against N=3000) before it was touched:

- TPyList.setintersect (`&=`, intersection_update): the Self snapshot.
- TPyList.setsymdiff (`^=`, symmetric_difference_update): BOTH snapshots.
- TPyList.setdiff (`-=`, difference_update): the other-side snapshot.
- TPyList.isdisjoint: built pyset_and's whole intersection to read its
  count; now a membership walk that allocates nothing (298 vs 2783 live).
- min()/max() of a DICT (pyeval): `max(d.keylist, key)` passed the fresh key
  list straight into the list overload; 555 vs 5862 live. The other 23
  keylist/vallist/itemlist locals in pylib and pyeval were checked: all
  released.
- TPyFile.writelines: the materialised argument (pyseq_of_obj is fresh on
  every arm, a copy even for a list).

`s &= t` went from 555 to 5861 live (300 vs 3000 calls), `^=` from 1181 to
11120, the three *_update methods together from 2401 to 22551, writelines
from 554 to 5860; all flat now. test_nilpy_a_pylib_temporary_list_is_released_
after_the_call: 124492 live after 5000 passes of its
loop on the old compiler, 69 now; its HEAP_DEBUG row covers `s ^= s` and
`s -= s` on the same object, which is what the snapshots are for.

Found earlier the same day and fixed with the collections batch: the
type-call builtins `set()`/`tuple()`/`frozenset()` (pybtype_call0) and
`list(x)`/`dict(x)`/`set(x)` reached through a type value (pybtype_call1)
kept the construction's reference after PyObjAsVar had taken its own.

Measured flat and left alone: `sort(key=..)` (keys.Free), `sorted(t, key=..)`
over a tuple (13 vs 24 at N=300/3000, constant).
