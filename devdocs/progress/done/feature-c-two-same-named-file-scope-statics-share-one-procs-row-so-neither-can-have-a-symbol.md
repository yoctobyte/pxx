---
slug: feature-c-two-same-named-file-scope-statics-share-one-procs-row-so-neither-can-have-a-symbol
track: C
prio: 45
type: feature
blocked-by: []
status: done
found: 2026-09-02
found-by: frankA
owner: unassigned
summary: "C gives a file-scope `static` INTERNAL linkage, so `static int sysret` in fcntl.c and `static int sysret` in unistd.c are two distinct functions — but both landed in ONE Procs[] row and the later body overwrote BodyAddr. FIXED: a `static` definition whose bound row is a static DEFINED IN ANOTHER C MODULE no longer seizes that row, and C name resolution now prefers the asking module's own static (calls and address-taking both). CORRECTION TO THIS TICKET'S ORIGINAL READING: it was not only a representation problem. Calls were indeed safe — each site keeps a CallFixTarget snapshot and stays BAKED — but TAKING THE ADDRESS of a static never went through that snapshot, so a module's own function pointer called the OTHER module's body and returned its value. Measured by ablation at 47618f77c240. The object half is fixed too: `--emit-obj --function-sections` on a TU whose only libc reference is printf goes from `pinned-target 6` (all six `sysret`) to 0, with every other family already at zero, so per-function sections is no longer blocked."
---

# Two same-named file-scope statics share one Procs row, so neither can have a symbol

## What was measured

`--emit-obj --function-sections` on a C translation unit that includes
`<stdio.h>`, `<stdlib.h>` and `<string.h>` and calls `snprintf`, `strlen` and
`atoi`:

```
function-sections: CallFix 1089  relocated 1083  pinned-target 6  undefined 0  no-symbol 0  (pinned: sysret sysret sysret sysret sysret sysret)
function-sections: ProcAddrFix 0  relocated 0  baked 0
function-sections: MethodFix 5  relocated 5  baked 0
```

Six call SITES, one callee. A translation unit with no crtl pull at all
(`int f(int x) { return x + 1; }`) is at `pinned-target 0`, and so is a Pascal
object — so this is specific to two crtl modules being preprocessed into one
buffer.

## Why it is not a bug today

`ObjCallFixIsRelocatable` refuses exactly the shape where `CallFixTarget[i]`
(the snapshot of `BodyAddr` taken when the site was recorded) disagrees with
the row's current `BodyAddr`. Refusing is right: relocating against the one
symbol would aim a call at the SECOND body, which is how
`test/cstatic_same_module_dup.c` once went from `2 11` to `11 11`. The baked
displacement uses the snapshot and reaches the correct body.

## Why it blocks the goal

`feature-a-every-emit-obj-object-links-its-own-full-copy-of-crtl-so-n-objects-cost-n-runtimes`
step 2 wants real per-function sections. A baked displacement is computed for
this object's own copy of the callee, so a linker that moves, drops or replaces
that copy leaves the jump pointing at whatever moves in. Six sites is six
opportunities for a silent wrong call, and there is no symbol to relocate
against because **the first body does not have one** — one row, one
`ObjProcSymIdx`.

Everything else is already at zero. `.rela.text`, `.rela.data`,
`.rela.init_array` and `.rela.fini_array` name the `.text` section symbol
**zero** times in both a Pascal and a C object as of `f15ea507e`. This is what
is left.

## The shape of the fix

A file-scope `static` needs a Procs row per (C module, name), not per name.
`ProcCModule[procIdx]` already records which module a body came from — it is
the term the duplicate-definition warning uses to stay quiet about exactly this
pair (`cparser.inc`, "a FOURTH term: both bodies must come from the SAME C
module"). So the attribution exists; what does not is a second row to hang it
on.

**Check before designing:** `CProcHasLocalDef`, `ProcCStaticLink`,
`ProcObjRuntimeCopy` and `ProcUnitIdx` are all per-row too, so today the second
body's attributes silently overwrite the first's. Splitting the row fixes those
as a side effect — which also means a reader should not assume the current
values are right for the first body.

**Do not "fix" this by renaming.** The two functions are legally distinct and
gcc compiles them; mangling the name to make them unique would be a
compiler-appeasement workaround in the frontend, and the symbol the object
exports must stay LOCAL either way.

## RESOLVED 2026-09-05 — and this ticket's own reading needed correcting

Fixed by a Procs row per (C module, name) for file-scope statics, plus
module-aware C name resolution (`CFindProcFromModule`) so calls, address-taking
and redeclaration all reach the asking module's own body. `FindProc` itself is
untouched: its "representative of a same-named set" contract is load-bearing
for pyparser and the Pascal parser.

**The "not a wrong-answer bug today" claim was true of CALLS and false of
FUNCTION POINTERS.** Calls were safe because each site keeps a `CallFixTarget`
snapshot and stays BAKED. Taking a static's ADDRESS never goes through that
snapshot. Ablated at `47618f77c240` on a probe whose two module bodies return
1 and 2 (crtl's real pair are byte-identical and cannot discriminate):

```
  1 1 / 2 2 / 3 2 / 4 2 / 5 0     pre-fix
  1 1 / 2 2 / 3 1 / 4 2 / 5 1     fixed, and gcc's multi-TU answer
```

Row 3: module A's own function pointer called module B's body. A correct
premise with an unstated boundary, which is why re-reading the ticket kept
confirming it and only the ablation found it.

**The object half, which is what was filed.** `pinned-target 6` -> 0 on the
census, every other family already at zero, and two LOCAL `who` symbols at
different addresses where there was one. Per-function sections is unblocked.

**Corpora, all on binary `10492cae86d8`:** c-testsuite conformance 220/220;
`c_corpus_probe.sh` 3/3 identical; lua 6/6; sqlite amalgamation (unity build,
one TU, hundreds of file-scope statics) compiles and its output matches
external libsqlite3 byte-for-byte.

**The SIBLING ARM IS NOT FIXED and is filed separately** as
`bug-c-two-same-named-file-scope-static-variables-share-one-syms-row-and-alias`:
static VARIABLES have no `SymCModule` at all, so two in different modules are
ONE variable — pxx `1 2 / 2 2 / 3 70 / 4 70` against gcc's `1 1 / 2 2 / 3 70 /
4 2`, i.e. writing module A's copy changes module B's. Zero instances in crtl
today. Not widened into this fix because variables resolve through `FindSym`,
which cparser calls 28 times against `FindProc`'s 3.

## Log
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 3f427655e.
