# bug: "Unsupported linear node Kind=10" — AN_CALL in lvalue-address position

- **Type:** bug (Track A — AST→IR lowering / codegen)
- **Status:** DONE 2026-06-23 (no longer reproduces; resolved by prior work)
- **Found:** 2026-06-23, building the Eliah IDE (full apps/ide/eliah/main.pas)
- **Severity:** high (blocks compiling a real GTK application)

## Resolution (2026-06-23) — verified no longer reproduces

The whole-program interaction no longer triggers IR_UNSUPPORTED. Verified clean
(exit 0, no "Unsupported linear node" / "Kind=10"):

- the ticket fixture
  `docs/progress/fixtures/bug-ir-unsupported-call-lvalue-eliah.pas`
- **and the real, now-larger** `apps/ide/eliah/main.pas` (more panes than the
  fixture: 661 procs / 226 KB code vs the fixture's 593 / 164 KB)

both on **current HEAD and on the pinned stable v41**. Since v41 (which predates
this session) already compiles them, the fix landed in the Track A work batched
into that pin — most likely the nested-routines lambda-lifting and the
PChar-empty / managed-string lowering fixes (`40569f9` and siblings), which
changed exactly the call-result / address-materialisation paths the IDE's
five-pane assembly exercised. The lvalue-address `IR_UNSUPPORTED` fallthrough at
`ir.inc:744` is still the correct guard for genuinely unlowerable nodes; nothing
hits it for this program now.

No code change this session — closed after confirming the high-severity repro is
gone. Track B can build the full Eliah `main.pas` (the trimmed-structure
workaround noted below is no longer required).

## Symptom

A full assembled program fails codegen:

```
Unsupported linear node in IR codegen! Kind=10 node=389 IRA=8 IRB=369 IRC=-1 IRIVal=374
pascal26: error: Unsupported linear node in IR codegen
```

`Kind=10` is `IR_UNSUPPORTED` (defs.inc:185): the AST→IR lowering hit a node it
could not lower and emitted a placeholder, which codegen then rejects. The
placeholder is produced at `ir.inc:744` (the **lvalue-address** path —
IR_FIELD / AN_DEREF / AN_PTR_CAST / AN_AS_CAST else-branch). `IRA = 8 = AN_CALL`
(defs.inc:80): a **function call result is being used where an address (lvalue)
is required** and the address-of-call-result case is unhandled.

## Repro

`docs/progress/fixtures/bug-ir-unsupported-call-lvalue-eliah.pas` — the IDE's
`main.pas` (build with `-Fulib/pcl -Fulib/rtl -Fuapps/ide/garin`). Fails reliably.

## Minimization — INCONCLUSIVE (honest note)

Could not reduce to a small repro. Every isolated candidate compiles:
`f(g(x))` with `const string` params; `IntToStr(method())`; record/array field
access in loops; handler+listbox+OnClick; `GetDirectoryContents` loops;
`RunCapture` (open-array param) calls. A trimmed variant (tree + open-file +
Compile + Run + buttons, no Output/Props/smoke panes) **compiles**; the full
five-pane version does not. So it is a whole-program interaction, not one line —
Track A likely needs to instrument which proc (`IRIVal=374`) / call node 389 is.

## Workaround status

None applied (policy). The shipped Eliah IDE uses the trimmed structure that
compiles; the extra panes/feature that crosses into the failing combination wait
on this fix.
