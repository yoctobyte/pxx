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

