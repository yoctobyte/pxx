---
slug: feature-c-two-same-named-file-scope-statics-share-one-procs-row-so-neither-can-have-a-symbol
track: C
prio: 45
type: feature
blocked-by: []
status: backlog
found: 2026-09-02
found-by: frankA
owner: unassigned
summary: "C gives a file-scope `static` INTERNAL linkage, so `static int sysret` in fcntl.c and `static int sysret` in unistd.c are two distinct functions — but both land in ONE Procs[] row and the later body overwrites BodyAddr. Calls still reach the right body (each site keeps a CallFixTarget snapshot and stays BAKED), so this is not a wrong-answer bug today. It is the last thing blocking per-function sections: a baked displacement cannot survive a linker moving either function, and there is no second symbol to relocate against. Measured on a C object whose only libc reference is printf: `CallFix 1089 relocated 1083 pinned-target 6`, and all six are `sysret`. Every other family is at zero."
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
