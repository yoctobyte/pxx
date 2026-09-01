---
slug: bug-a-an-object-neither-exports-nor-imports-data-symbols-and-links-silently-wrong
track: A
prio: 75
type: bug
status: done
blocked-by: []
created: 2026-09-01
found-by: frankD
owner: frankA
summary: "RESOLVED: the SILENT wrong link is gone on every route that could produce it. C exports and imports data symbols on x86-64 and i386 (72000d1e1); a Pascal global marked `cvar`/`public` exports (d402147d6) and the import direction REFUSES rather than reading its own zeroed .bss. Two scoped successors, both filed and neither silent: Pascal data import, and the ESP writer, which exports only `app_main` and has never named a cdecl routine either."
status: working
blocked-by: []
created: 2026-09-01
found-by: frankD
owner: frankA
summary: "--emit-obj emits NO data symbols. A global defined in a .c gets no OBJECT symbol, and `extern int x;` is relocated into the object's OWN .bss instead of becoming an undefined import -- so two pxx objects sharing a global LINK CLEANLY and read different memory. Measured: gcc links the pair and prints 0 where 99 is correct. No diagnostic anywhere. Blocks separate compilation of any real C project (busybox's libbb/ptr_to_globals.c is one global pointer and cannot even be emitted)."
---

# An object neither exports nor imports data symbols, and links silently wrong

Found attempting busybox's own build model — 52 translation units compiled as
separate objects rather than as a unity — for
[[feature-c-corpus-busybox-multi-applet]]. Compiler binary sha256
`0e1ed8c673bc`, at commit `d86bb32fe`.

## The measurement

```c
/* extref.c */              /* extmain.c */
extern int somebody_elses_global;      int somebody_elses_global = 99;
int read_it(void) {                    int read_it(void);
  return somebody_elses_global;        int main(void){ printf("%d\n", read_it()); }
}
```

```
pascal26 --emit-obj extref.c extref.o      # succeeds, no warning
gcc -O2 extmain.c extref.o -o link         # succeeds, no warning
./link
0                                          # gcc-only build prints 99
```

Nothing anywhere reports a problem. This is the repo's expensive shape: no
crash, a plausible wrong value, far from the cause.

## What the object actually contains

```
$ readelf -sW extref.o | awk '$4=="OBJECT"'
                                        (nothing — not one OBJECT symbol)
$ readelf -rW extref.o | grep 18377
0000000000018377  R_X86_64_PC32   .bss + 9504
```

So the two halves are one missing concept:

- **A defined global is not exported.** `ObjPlanHostedSymbols`
  (`elfwriter.inc:2948`) walks `Procs` only; there is no data pass. Its
  `numExportProcs = 0` refusal is the visible consequence — busybox's
  `libbb/ptr_to_globals.c`, whose entire content is `struct globals
  *ptr_to_globals;`, is refused with *"this object would define no linkable
  symbol"*. That message is correct about the object and wrong about the
  program: a translation unit of pure data is ordinary C.
- **An extern global is not imported.** `extern int x;` becomes a *local
  tentative definition* in this object's own `.bss`, with a section-relative
  relocation. There is no undefined symbol for the linker to resolve, which is
  exactly why the link is silent.

The second half is the dangerous one. The first fails loudly; the second
produces a running program that reads the wrong memory.

## Why it has not bitten before

Every C program pxx has built has been a single translation unit, where a
global is just a local. `--emit-obj` exists for ESP-IDF and for the ABI-parity
links, and those pass and return values in registers — they never share a
variable. The first thing to share one was busybox.

## Acceptance

- A global defined in a `.c` appears as `OBJECT GLOBAL` in the object's
  `.symtab`, in `.data` or `.bss` with its real size.
- `extern int x;` with no definition in this TU becomes `UND` plus a symbol
  relocation, and a link against another object's definition reads THAT
  variable — the two-file case above must print `99`.
- The `numExportProcs = 0` refusal counts data symbols too, so a data-only TU
  emits. Keep the refusal for a genuinely empty object.
- `static` file-scope data stays LOCAL and must NOT become an export.
- A tentative definition (`int x;` at file scope with no initialiser,
  C 6.9.2) is a definition here, not an import — the distinction from
  `extern int x;` is the whole bug. It is emitted in `.bss` as `GLOBAL OBJECT`,
  **not** as `SHN_COMMON`: `-fno-common` semantics, matching gcc 10+.
- **POSITIVE CONTROL, asserted:** two TUs each containing a bare `int x;` must
  **fail** to link, with a duplicate-definition diagnostic. This is a case the
  export pass must REJECT, and it is the counterpart of the `file_local` row —
  one guards against exporting too much, this one against exporting too little
  or reviving `-fcommon` by accident. gcc's exit status for the same pair is 1;
  measured, not recalled.
- Both frontends, since Pascal `cdecl` units have the same exposure, and every
  target `--emit-obj` supports (x86-64, i386, xtensa, riscv32).

## `-fno-common` IS THE SEMANTICS, and the duplicate-definition failure is REQUIRED

An earlier cut of this section listed "export half alone makes a link that used
to succeed start failing" as a **risk to mitigate**. That was right about the
mechanism and **wrong about its sign** (frankA, 2026-09-01; re-measured here
with the exit status his own reading did not capture):

```
$ gcc --version | head -1
gcc (Ubuntu 15.2.0-16ubuntu1) 15.2.0

$ cat ta.c            $ cat tb.c
int x;                int x;
int a(void){return x;}      int b(void){return x;}

$ gcc -c ta.c && readelf -sW ta.o | awk '$8=="x"'
     3: 0000000000000000     4 OBJECT  GLOBAL DEFAULT    4 x      <- section 4 (.bss), NOT COM

$ gcc ta.o tb.o tm.c -o /dev/null
ld.bfd: tb.o:(.bss+0x0): multiple definition of `x'; ta.o:(.bss+0x0): first defined here
link exit=1

$ gcc -fcommon -c ta.c && readelf -sW tac.o | awk '$8=="x"'
     3: 0000000000000004     4 OBJECT  GLOBAL DEFAULT  COM x      <- COMMON, and the link SUCCEEDS
```

**gcc has defaulted to `-fno-common` since GCC 10**, so `int x;` in two
translation units is a genuine duplicate definition and gcc's own toolchain
refuses to link it. Producing that failure is **conformance, not collateral
damage** — and the link succeeding today is the defect, not a property to
preserve: two TUs are silently getting private slots for what the C source says
is one object.

**So it belongs in the acceptance list as required behaviour with a test that
asserts the failure**, and that is the positive control this ticket was missing.
`file_local` staying `LOCAL` guards against exporting too MUCH; nothing pinned
that the loud failure appears when it should.

**Decide it explicitly rather than inherit it:** pxx implements `-fno-common`
semantics. The old merge-into-one-slot behaviour is `-fcommon`, which is a
different symbol type (`SHN_COMMON`), not a variation on this one. Saying so
here is what stops the next person reading `multiple definition` as a bug in
the new pass.

## Still land both halves together — for a different reason than first written

Not because export-only regresses (it does not; see above), but:

- **Import half alone** makes every `extern int x;` an `UND` with nothing
  exporting it, so **every** existing object build fails to link. Unusable.
- **Export half alone** looks like progress while leaving the dangerous
  behaviour entirely intact: an `extern` reference is still a private `.bss`
  slot, so the silent wrong READ — the thing this ticket is named for — is
  untouched. The half that gets fixed is the half that was already loud.

The precedent for the general worry is frankA's own afternoon: a descriptor
field written as 0 made both the retain and release halves decline, so it merely
leaked; widening the field woke release alone and turned the leak into a double
free, and had to be reverted. Symmetric defect, asymmetric repair.

## THE INSTRUMENT, AND ITS "BEFORE" — measured 2026-09-01, not remembered

frankA's other point, from the same afternoon: an object that links cleanly and
reads the wrong memory has a detection problem, because a probe that reads
values back can print OK against a live defect. His first useful instrument was
an allocation census, not an assertion. The equivalent here is a **symbol-table
diff against gcc for the same translation unit**, and it exists now so the
"before" is a recorded measurement:

```c
int defined_initialised = 7;      /* .data, GLOBAL OBJECT */
int defined_tentative;            /* tentative definition (C 6.9.2) */
static int file_local = 3;        /* must stay LOCAL */
extern int imported_elsewhere;    /* must become UND */
int a_function(void) { return defined_initialised + defined_tentative + file_local + imported_elsewhere; }
```

`readelf -sW`, OBJECT/NOTYPE/FUNC rows only, at compiler binary sha256
`73a9d172409b`:

```
gcc -c -O0                        pxx --emit-obj
FUNC    GLOBAL 1   a_function     FUNC GLOBAL 1 a_function
OBJECT  GLOBAL 3   defined_initialised          (nothing)
OBJECT  GLOBAL 4   defined_tentative            (nothing)
OBJECT  LOCAL  3   file_local                   (nothing)
NOTYPE  GLOBAL UND imported_elsewhere           (nothing)
```

Five rows to one. **The fix is done when those two columns match** — including
`file_local` staying `LOCAL`, which is the control that catches an export pass
that simply exports everything.

## Coordination

**Not frankA** — he confirmed on 2026-09-01 that he has not touched
`elfwriter.inc`; his day was `ir_codegen.inc`, `rtti_emit.inc`,
`builtinheap.pas` and `symtab.inc`. An earlier version of this section named
him, wrongly: I read the **lane tags** on the object-writer commits (`feat(A)`,
`fix(A,C)`) as agent names, which they are not.

What is true is about the FILE, measured: `compiler/elfwriter.inc` has ten
recent commits on `origin/master` — i386 PC-relative data loads, `R_386_PC32`,
`--emit-obj` initialisers, hardened PIE objects (`ca4197115`, `b64341130`,
`6ab85feb8`, `3dd98fe32`). It is actively moving. Ask on the channel who is in
it now rather than inferring an owner from a commit tag.

**And there is no way to read the author off the log, which is why the tag is
so tempting.** Measured over the last 200 commits on `origin/master`: **200 of
200 have the same `%an`**, and only **89** carry a `Claude-Session:` trailer,
across **7** distinct sessions. So the trailer is the only discriminator that
exists, it is present on well under half the history, and **its absence means
UNKNOWN, not "someone else"** (frankA, 2026-09-01). Attribute from a message or
from that trailer, or do not attribute.

## The two halves are in DIFFERENT layers — the import half never reaches the writer

Reproduced the filed measurement first, unchanged: pxx object prints `0`, the
gcc-only build of the same two sources prints `99`, both links clean. Symbol
tables, same TU:

    gcc  -c -O0   3: FUNC   GLOBAL  1  read_it
                  4: NOTYPE GLOBAL UND somebody_elses_global
    pxx --emit-obj  408: FUNC GLOBAL 1 read_it        (and nothing else)

**The export half is where this ticket says it is** — `ObjPlanHostedSymbols`
walks `Procs` only, and the symbol table it plans is `null + 3 section syms +
local procs + exported procs + externals`. `ExternalProc[]` is indexed by
**procIdx**, so the existing externals group is function-only and cannot carry a
data symbol at all: a new group is needed, not a widening of that one.

**The import half is NOT a writer problem, and this is the part that changes the
work.** The `extern` storage class is discarded at parse time. It is consumed
and thrown away in two independent places — the declaration-specifier loop
(`cparser.inc:4874`, whose own comment says "consume without affecting the
type") and the top-level dispatch (`CIsTopLevelSkipIdent`, `:9986`). Nothing
downstream records that a declaration was `extern`, so the writer could not emit
`UND` even if it wanted to: by then the fact does not exist.

Measured rather than read, with a positive control:

    pxx:  `extern int x; int get(void){return x;}`
          `int x;        int get(void){return x;}`   -> objects BYTE-IDENTICAL
    gcc:  same two TUs                                -> objects DIFFER
          extern -> NOTYPE GLOBAL UND
          plain  -> OBJECT GLOBAL 4

So the keyword currently has **zero** effect on pxx's output. That is the
cleanest statement of the import half, and it means the fix starts in the C
frontend (carry the storage class, the way `CTypeLong`/`CTypeLongLong` already
carry facts `TTypeKind` cannot), not in `elfwriter.inc`.

Consequence for sequencing, which sharpens the "land both halves together" note:
the two halves are not merely a symmetric pair, they are in different layers and
the frontend one gates the writer one. A writer-only session cannot deliver the
import half however carefully it is written.

### Two things the acceptance list should pin

- `static int y;` must stay **LOCAL**, which is the control against an export
  pass that exports everything — and note pxx currently discards `static` at the
  same two sites, so "LOCAL" is not something the writer can currently know
  either. Same layer problem, opposite sign.
- Two TUs each with a bare `int x;` must FAIL to link with a duplicate
  definition. That is gcc's own behaviour under its default `-fno-common`
  (verified here on gcc 15.2.0: `OBJECT GLOBAL 4`, and `ld` reports "multiple
  definition"; under `-fcommon` the same symbol becomes `COM` and the link
  succeeds). Producing that failure is conformance, not a regression.

## The decision is PER NAME over the whole TU, not per declaration

Track C supplied the corpus shapes; every row below was re-measured here with
`gcc -c -O0` + `readelf -sW`, and the linkage claim was checked with a negative
control rather than inferred from the symbol table.

| TU contents (one name) | gcc symbol | section | size |
| --- | --- | --- | --- |
| `extern const char *n;` then `const char *n;` | OBJECT GLOBAL | `.bss` | 8 |
| `extern const char *n;` + use only | NOTYPE GLOBAL **UND** | — | 0 |
| `extern char b[];` then `char b[4096] __attribute__((aligned(8)));` | OBJECT GLOBAL | `.bss` | **4096** |
| `extern char b[];` + use only | NOTYPE GLOBAL **UND** | — | 0 |
| `extern const char *m;` then `const char *m = "\n";` | OBJECT GLOBAL | **`.data.rel.local`** | 8 |
| `static int h = 7;` + use | OBJECT **LOCAL** | `.bss`/`.data` | 4 |

**Row 1 is the trap, and it is busybox's dominant shape** (`applet_name`,
declared in `include/libbb.h` and defined in `libbb/appletlib.c` with the header
included, so both lines are in one TU). An `extern` declaration followed by a
bare tentative definition **is a definition** — C 6.9.2, the tentative
definition wins and the `extern` only supplied linkage. Verified end to end:
linking that object against a use-only object prints the value, and dropping it
gives undefined-symbol diagnostics.

So the obvious implementation — *"`extern` seen for this name, therefore emit
UND"* — is wrong, and fails in the worst available way: **nothing in the entire
program would define `applet_name` while every busybox TU imports it.** A clean
compile, then one unresolved symbol at link, for the variable the applet
dispatcher needs. That is a rule you would write, ship, and only discover at the
last link of the corpus this ticket exists to build.

**The rule, stated so it cannot be implemented per-declaration.** For each
file-scope name, after the WHOLE translation unit is parsed:

1. any declaration carried an initialiser -> **definition**; section from the
   content (`.data`, `.data.rel.local` when it needs a relocation, `.rodata`),
   size and alignment from that declaration;
2. else any declaration omitted `extern` -> **tentative definition**, which is
   still a definition; `.bss`, size and alignment from the most complete
   declarator;
3. else every declaration said `extern` -> **UND import**, `NOTYPE`, size 0,
   emitted only if the name is referenced;
4. `static` anywhere -> internal linkage, `LOCAL`, and never UND.

Rules 2 and 3 differ only by a keyword that pxx currently discards, and rule 1
outranks both — which is why this has to be a per-name decision taken at emit
time, over accumulated state, rather than a branch at the point the declarator
is parsed.

**Two consequences for size and section that a declaration-time design gets
wrong.** The `extern char b[];` import carries no size and the definition
carries 4096: size must come from the definition, so an incomplete array type is
not an error at the declaration. And alignment travels with the definition too
(`aligned(8)`). Row 5 needs a third section — an initialised pointer-to-literal
is `.data.rel.local`, not `.data`, because it needs a relocation.

Not adopted: a `static` that is also `extern`-declared earlier. gcc rejects the
pair and the corpus does not contain it, so it would be an invented row.

Deferred, real but not on the rung-1/2 path: a tentative definition carrying an
explicit `__attribute__((section(".data")))` (busybox `common_bufsiz.c:71`,
under a different config).

## COMMON is out of scope, measured — and the simple case is on the critical path

Census by Track C/D over **busybox's own objects, built by gcc** (143 TUs across
libbb, coreutils, shell, editors):

    43 distinct GLOBAL OBJECT symbols defined across them
    46 of 143 TUs import at least one cross-TU DATA symbol
     0 symbols defined in MORE THAN ONE TU
     0 SHN_COMMON symbols anywhere

The last two lines decide the tentative-definition question for this corpus:
every tentative definition already resolves to exactly one owning TU under
gcc's default `-fno-common`, which is what a real build gets. So
`-fcommon`/`SHN_COMMON` support is a **separate ticket with no evidence behind
it yet**, and the duplicate-definition row stays in the acceptance list as a
case that must be REJECTED rather than a shape busybox will present.

46 of 143 also says the plain defined/undefined case is not a corner — a third
of the translation units need it before anything links.

**Scope of that number, kept attached to it:** it counts what GCC emits for
busybox's sources. It says nothing about what pxx emits for the same sources —
that is this ticket's own measurement, and the two must not be quoted as one.

## Writer half: the design, and the constraint that shapes it

The frontend half landed (`c29cd34f5`) and the linkage is now readable per name
via `PXXDBG=a.clink`. What remains is the writer.

**Symbol table layout.** ELF requires every LOCAL before every GLOBAL, with
`sh_info` naming the first global, so the two new definition groups slot around
the existing ones and one existing constant moves:

    0            null
    1,2,3        .text / .data / .bss section symbols
    4..          local procs                       numLocalProcs
    ..           local data (static)               numLocalData     NEW
    firstGlobal  = 4 + numLocalProcs + numLocalData
    ..           exported procs                    numExportProcs
    ..           exported data                     numExportData    NEW
    extSym0      = firstGlobal + numExportProcs + numExportData     CHANGED
    ..           external functions                ExternalCount
    impSym0      = extSym0 + ExternalCount
    ..           imported data (UND)               numImportData    NEW

`extSym0` is the only existing index arithmetic that moves; `writeRela64(...,
extSym0 + i, ...)` for the external GOT slots stays correct once it does.

**The constraint: `EmitGlobRef(bssOff)` takes an OFFSET, not a symbol**, and has
roughly 200 call sites. A reference to an imported global must relocate against
that symbol rather than against the `.bss` section, so the writer needs an
identity the emitter never passed it. Three options, and the first two are
traps:

- *Thread a symbol index through EmitGlobRef* — 200 call sites for a fact almost
  none of them have to hand.
- *Bias the offset the way `DATA_SYM_BIAS` does* — attractive because it matches
  an idiom already in the tree, and wrong: element and field offsets are folded
  into the same integer, so `buf[3]` would arrive as bias + ordinal + 3 with no
  way to separate the ordinal from the 3.
- **Map the offset back at write time.** Each imported global still owns a
  distinct `.bss` range, so the writer can hold `(base, size, importIdx)` per
  import and, for each `GlobFix`, ask which range its `BSSoff` falls in. The
  addend is then `BSSoff - base` (plus the usual `-4 - GlobFixTrail[i]` for
  PC32), which is exactly the element offset that the folding produced. No
  signature change and no new encoding.

**Open question that must be answered before writing it, not assumed:** an
`extern char buf[];` import has no size at its declaration — the size lives on
the definition, in another TU. If pxx allocates it a zero-length `.bss` range,
the lookup above has nothing to match and the relocation silently stays
section-relative, which is the current bug wearing a new hat. Check what
`AllocArray` reserves for an incomplete array before relying on ranges;
if it can be zero, the imports need their own ordinal table rather than a
range map.

Only `writeELFRelX64General` needs this: it refuses any target but x86-64, and
the ELF32 writer serves xtensa/riscv32 where the refusal stands.

## The open question is ANSWERED, and the answer corrects the option-2 rejection

Measured 2026-09-01 (frankA), compiler binary `70c62f7968b6` at `88e1ab536`,
x86-64 `--emit-obj`, C frontend. The question was whether an incomplete-array
import gets a zero-length `.bss` range, which would leave the range map nothing
to match.

**It does not: the reservation is ONE ELEMENT, never zero.** `arrLen` falls
through to `1` for a declarator with no size and no initialiser
(`cparser.inc`, the `else arrLen := 1` at the end of that chain), and
`CGrowGlobalArray` only ever grows it if a definition appears later in the same
TU. So every import owns a distinct base and no two can collide. `extern char
p[]; extern char q[];` land 8 bytes apart (9504, 950c) — one element plus
alignment padding.

**But the premise the option-2 rejection rests on is FALSE for C, and I checked
it because it was the reason a design was discarded.** The ticket says element
and field offsets are folded into the same integer, so `buf[3]` would arrive as
`bias + ordinal + 3`. Measured, every shape relocating to its symbol's BARE
BASE with no addend fold:

| expression | fold would give | actual addend |
| --- | --- | --- |
| `p[0]` / `p[3]` | base, base+3 | `.bss + 9504` both |
| `ia[0]` / `ia[5]` | base, base+20 | `.bss + 9514` both |
| `m2[i]` / `m2[1000]` | base, base+4000 | `.bss + 950c` both |
| `st.c` (field +8) | base+8 | `.bss + 9504` |
| `ta[4].y` (+36) | base+36 | `.bss + 9504` |
| `single.y` (+4) | base+4 | `.bss + 9514` |

The constant index and the field offset are computed in the instruction stream
after the `LEA`; the relocation carries the base only. So **an exact-match table
`base -> importIdx` is sufficient for the C half** — no range containment test,
no ordinal table, and option 2 was not disqualified for the reason given.

**The residual, which is why the range map does not simply disappear.** x86-64
DOES have call sites that fold: `EmitGlobRef(Syms[idx].Offset + 8)` in
`symtab.inc` (6743, 6762, 6930, 6932, 7263 — `EmitStringCharLoad` and the
string-header paths). Those are Pascal string/ShortString accesses skipping a
header word, and no C array indexing reaches them, which is why every row above
is clean. But this ticket's acceptance covers Pascal `cdecl` units too, and a
Pascal string global as an IMPORT would produce `base+8` against a reservation
that may be a single element — too small for a range check keyed on
`ArrLen * elemSize` to contain it.

**So: exact-match table, plus a positive control that makes the residual LOUD.**
Any `GlobFix` whose addend is not an exact import base but falls between one
import's base and the next symbol's base must be a hard compiler error, not a
fallback to a section-relative relocation. That is the case I could not
construct from C, and silently relocating it is the current bug wearing the new
hat that this section was written to look for. A guard that cannot fire is worth
nothing here; this one has a real case behind it and a reason it did not appear
in my rows.

Scope of these numbers, kept attached: x86-64, C frontend, `--emit-obj`, the
shapes tabulated. `writeELFRelX64General` is the only writer that needs this,
so that is the right scope — but the Pascal row is UNMEASURED, not clean.

## Writer half LANDED for the C frontend — 72000d1e1 (frankA, 2026-09-01)

The headline case prints `99` on x86-64 and on i386 under `gcc -m32`, matching
the gcc-only control. 18 acceptance rows across both targets: BEFORE 0/18,
AFTER 18/18, against a baseline built by reverting the hunks and rebuilding to
`converged` (8e853c4cba34 vs 4f594cf743f5).

Every item on this ticket's acceptance list is met FOR C, including the two the
list called out as controls: `static` stays LOCAL and is not also exported, and
two TUs each with a bare `int x;` are REJECTED at link with exit 1, the same as
gcc. A data-only TU emits.

**Three corrections this ticket's own design needs**, all measured:

1. The bias option was rejected here because element and field offsets are
   folded into the addend. For C they are NOT — every shape relocates to the
   symbol's bare base. An exact-match table is sufficient; the range containment
   test was designed around a premise that does not hold.
2. The open question is answered and its answer is benign: an incomplete array
   reserves ONE element, never zero, so imports cannot share a base.
3. **A third flag was needed that this ticket does not mention.** The linkage
   pair cannot express MEMBERSHIP — both default False and False means
   "defined, external linkage" — so there was no set to walk. `SymCFileScope`.

**And one failure mode the design did not anticipate, which is the most
transferable part.** crtl is compiled as C and bundled into every object, so its
file-scope variables are C file-scope variables: the first version exported
`errno`, `environ`, `optarg`, `optind`, `opterr`, `optopt`, `optreset`. The link
then failed outright — glibc's `errno` is TLS in `.tbss` and ours is not, so ld
refused the object. The export set is the USER's translation unit, not every C
source the compiler parses. See `CDeclIsFromCrtl`, and note it does NOT use
`CModuleOfTok < 0`: under `--emit-obj` the user's own `.c` has a module range,
so its declarations carry a real id, and the id is an interned PATH key.

## STILL OPEN: the Pascal frontend, and it is not covered by anything above

This ticket's acceptance says "both frontends". Only C is done. A Pascal `cdecl`
program's globals still produce no data symbol at all —
`nm --defined-only | grep -cE ' [BbDd] '` is 0 — measured independently by
Track B on a program whose AnsiString globals link, run and mutate correctly.
Split into
[[bug-a-a-pascal-cdecl-program-emits-no-data-symbols-either]] rather than left
implied here, because the C symbol tables now look complete.

**This ticket stays OPEN until that lands**, since its own acceptance names both
frontends. What is NOT open is the mechanism: the writer walks three data groups
and both writers emit them; the Pascal side needs only its own answer to "whose
declaration is this", and the `errno` incident above says what happens when that
answer is "everything".

Also recorded as a divergence rather than a bug: a name the user's own file
declares `extern` and crtl defines is now EXPORTED rather than invisible
(`environ` in `test_shared_lib.c` is the live instance). gcc emits UND there. It
links and runs correctly.


## RESOLVED — the named defect is gone on every route that could produce it

This ticket is named for a SILENT wrong link: an object that resolves cleanly
and reads different memory than the source says. That is what is closed.

| route | before | now |
| --- | --- | --- |
| C export, x86-64 / i386 | no `OBJECT` symbol at all | `GLOBAL`/`LOCAL` with real size, `-fno-common` semantics — `72000d1e1` |
| C import, x86-64 / i386 | relocated into this object's own `.bss` — the silent wrong read | `UND` + symbol relocation, reads the definition |
| Pascal export | 0 data symbols, and no spelling that could change it | `cvar` / `public` — `d402147d6` |
| Pascal import | not expressible | **refused**, naming its ticket. Loud, not silent |
| xtensa / riscv32 | one `GLOBAL` symbol, `app_main` | unchanged, and it was never silent — nothing is exported by name, including `cdecl` routines |

The acceptance row *"both frontends, and every target"* is therefore met for the
DEFECT and not for the FEATURE, which is why the two remainders are tickets
rather than an open parent:

- [[bug-a-a-pascal-global-cannot-import-a-c-global]] — the refusal above,
  with the writer work it needs (most of which exists, for C).
- [[bug-a-the-esp-object-writer-exports-only-app-main-so-no-cdecl-routine-or-global-is-linkable]]
  — measured, not assumed: a riscv32 object from a fixture with four `cdecl`
  routines and two `cvar` globals exports exactly `app_main`. That writer has a
  different symbol model, deliberately (LOCAL FUNC avoids collisions inside an
  IDF build), so it cannot be closed by extending the general writers.

Keeping this open for those would leave a ticket whose summary is no longer true
of anything a program can hit, and its summary is the only part everyone reads.

## Log
- 2026-09-01 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 9a6b936ec.
