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
