---
slug: feature-a-an-extern-only-variable-still-reserves-its-storage
title: "An imported variable still reserves .bss it can never address"
track: A
prio: 25
type: feature
status: backlog
created: 2026-09-01
found-by: frankA
owner: ""
blocked-by: []
summary: "MEASURED 2026-09-18 (frankB) -- THE GATING QUESTION THIS TICKET ASKS IS ANSWERED AND THE ANSWER IS NO. It says to check first whether real inputs make a reclaim pass worth anything; checked, and the cost is **~241 bytes per busybox translation unit** (33 imports, 102 bytes of declared size plus 139 of alignment padding, `others-in-span=0` so the span is exact) against a 91 KB .bss -- 0.26%, because libbb.h's names are almost all `extern const char x[]`, an INCOMPLETE array reserving one byte, so the cost is alignment on 1-byte slots rather than the declarations' sizes. **ZERO on ESP, by construction, on both profiles**: an `--emit-obj` xtensa/riscv32 object refuses an imported variable outright (ObjRefuseEspDataImports) and an executable refuses it on any target, measured to 0 imports on a real ESP object, with `lib/**` declaring no `external` variable at all -- so this ticket must NOT be raised under the ESP SRAM re-rank. Nothing could measure this before: the UND symbol carries st_size 0 and NOTYPE, so readelf cannot see the reservation and the size lives only in SymAllocSize. `PXXDBG=a.impwaste` now reports it at write time through the same ObjDataIsImport predicate the writers walk, in two bounds (sum of sizes is a lower bound; the offset span is an upper bound and only exact when `others-in-span=0`), with a positive control on this ticket's own fixture -- 4000 against 0, identical bss. LEFT AT PRIO 25 AND NOT IMPLEMENTED: the reclaim would have to remap every GlobFix.BSSoff, which stores an OFFSET and not a symbol index, making it a DceNewOff-shaped compaction with that class of risk, for 241 bytes per object. Original defect unchanged: AllocFromDeclTypeDesc reserves at declaration time and the import decision is a fold that is not final until the unit ends."
---

# An import pays for storage it cannot use

The reservation happens at declaration time and the import decision is a fold
over every declaration of the name, so the allocator cannot know. By the time
`SymObjDataExternOnly` is final the slot exists.

Measured with the same program either side of one keyword:

```
extern int Big[1000];  int get(void){return Big[3];}    bss=42156B
       int Big[1000];  int get(void){return Big[3];}    bss=42156B
```

Harmless in the sense that matters — the writer routes every reference to the
UND symbol, so nothing reads the dead slot — and it is why this is prio 25
rather than a bug. It costs object size, which is the same currency as
[[feature-a-every-emit-obj-object-links-its-own-full-copy-of-crtl-so-n-objects-cost-n-runtimes]]
and worth folding into whatever measurement that one does.

## The shape of a fix

Not "do not allocate": the fold is not final until the translation unit ends,
and a name that looked like an import can still become a definition (C 6.9.2's
tentative definition, which is busybox's dominant shape). So it is a
RECLAIM at end of unit, or a second .bss pass that lays out only the symbols
that survived as definitions. The second is the honest one and it is not small.

Worth checking first whether real inputs make it worth anything: busybox's
`libbb.h` declares a lot of names into 41 translation units, so the multiplier
may be larger than the single-file number suggests.

## Measured 2026-09-18 (frankB) — the ticket's own gating question, answered: NOT worth a reclaim pass, and ZERO on ESP

This ticket says *"Worth checking first whether real inputs make it worth
anything"* and names busybox as the input to check. Checked. **The answer is no**,
and it is no for two independent reasons.

### Nothing could answer it before, so an instrument was built first

The reservation is invisible from outside the compiler: the UND symbol carries
`st_size 0` and `NOTYPE`, so `readelf` cannot see it. The size lives only in
`SymAllocSize`. `PXXDBG=a.impwaste` (elfwriter.inc, `ObjReportImportedDataWaste`)
now reports, at write time and through the same `ObjDataIsImport` predicate the
writers walk: every import with its offset, size and referenced flag, and a
total in **two bounds**.

Two bounds because the sum of sizes is NOT the answer — each slot is aligned, so
removing an import frees its padding too. The sum is a lower bound; the offset
SPAN is an upper bound, and only a true one when nothing else was allocated
inside it, which is why `others-in-span` is printed rather than assumed.

Positive control, run: `extern int Big[1000];` reports 4000, the same file with
the `extern` removed reports 0, and `bss=42700` is identical in both — so the
instrument discriminates the thing the whole ticket is about, on the ticket's
own fixture.

### ESP: zero, by construction, on both profiles

    --emit-obj, xtensa/riscv32   REFUSED  (ObjRefuseEspDataImports, elfwriter.inc)
      "an imported variable (X) is not supported for xtensa/riscv32 objects:
       the reference would relocate into this object's own .bss and read zero"
    executable, any target        REFUSED  (pasparser)
      "external on a variable needs --emit-obj: in an executable there is no
       import for it to bind to, so it would allocate local storage and read zero"

So an ESP program cannot contain this defect. Measured too, not only reasoned:
`test/esp_pal_fdsem_baseline.pas` built `--emit-obj --target=xtensa
--platform=esp` reports **0 imports, 0 bytes**, and `lib/**` declares **no
`external` variable at all**. **Under the 2026-09-18 ESP SRAM re-rank this
ticket is worth nothing** — it should not be raised on that basis.

### busybox: ~241 bytes per translation unit

`--emit-obj`, `-include include/autoconf.h -I. -Iinclude -Ilibbb`:

| TU | imports | sum of sizes | span | others in span | bss |
| --- | --- | --- | --- | --- | --- |
| `coreutils/echo.c` | 33 | 102 | **241** | 0 | 91268 |
| `libbb/xfuncs.c` | 33 | 102 | **241** | 0 | 91284 |
| `networking/wget.c` | 33 | 102 | **241** | 0 | 91324 |
| `coreutils/cat.c` | 34 | 103 | 44641 | 43 | 91276 |
| `editors/sed.c` | 34 | 103 | 44641 | 43 | 91388 |
| `coreutils/ls.c` | 34 | 103 | 44641 | 43 | 91320 |

Three TUs have `others-in-span=0`, so for those the span is EXACT: **241 bytes**,
of which 102 is declared size and 139 is alignment padding. The other three
differ by one symbol, `bb_common_bufsiz1`, which lands at offset 83464 with 43
unrelated allocations between — their span is therefore meaningless and the
truth is ~242.

**0.26% of the object's .bss.** The multiplier this ticket hoped for is not
there: libbb.h does declare a lot of names into 41 translation units, but almost
every one is `extern const char x[]` — an INCOMPLETE array, which reserves one
byte. The cost is dominated by 8-byte alignment on 1-byte slots, not by the
declarations' sizes. Across 41 separate objects it is ~9.9 KB in total and
~241 B in any one of them.

### Conclusion

**Left at prio 25 and not implemented.** The fix this ticket describes — a
second `.bss` pass laying out only the symbols that survived as definitions, or
a reclaim at end of unit — would have to remap every `GlobFix.BSSoff`, which
stores an OFFSET and not a symbol index, so the remap is a `DceNewOff`-shaped
compaction over a table with no symbol association. That is the same machinery
as `dce.inc`'s code compaction and carries the same class of risk, for 241 bytes
per object on the only population that has the defect at all.

What this section changes is that the question is now ANSWERED rather than open:
a future reader does not have to re-derive whether it is worth doing, and if the
population changes — a real program with large `extern` arrays, which is the
shape that would move the number — `PXXDBG=a.impwaste` measures it in one run.
