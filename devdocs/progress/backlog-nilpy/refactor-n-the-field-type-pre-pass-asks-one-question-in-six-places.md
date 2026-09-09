---
track: N
prio: 45
type: refactor
blocked-by: []
summary: "MEASURED, not asserted: PyInferFieldDecl is 13 decision arms, and six of them -- 341 lines across PyHeaderParamType, PyModuleGlobalLiteralType, PyModuleGlobalCtorClass, PyModuleGlobalIsDef, PyMethodBindsLocal and PyRhsOnlyNamesThisMethodBinds -- ask ONE question in three scopes: where is this NAME bound and what is its initialiser. Three of them (the module-global trio) carried a BYTE-IDENTICAL copy of one scan differing only in the pattern matched at a statement head and the return type; those are now collapsed to one scan with no answer changed. The remaining duplication is the same question in the PARAMETER and METHOD-LOCAL scopes. Root cause: the pre-pass has no name environment because PyLocals is one FLAT table with a linear name scan and no scope field, and seeding it early was tried and reverted."
status: backlog
owner: —
---

# The field pre-pass asks one question in six places

## What was counted

`PyInferFieldDecl`, 269 lines, 13 arms. They are **three** questions, not
thirteen:

| question | arms | notes |
| --- | --- | --- |
| what does this EXPRESSION evaluate to | `PyInferExprType`, `PyTypeFromTokenIndex` (x2), the qualified-construction reader | already carries class IDENTITY via `PyInferLastCi` |
| where is this NAME bound, and to what | **six readers, three scopes** | the duplication |
| what to do when nothing types it | None / not-in-ctor / int-accumulator / `ErrorAt` | policy, correctly separate |

The identity point is measured, not assumed: `self.k = K()` has no dot, so the
qualified-construction arm cannot fire, and `PyBlkRhsEndsAt` is false, so the
single-token readers cannot either. It prints `9`. `PyInferExprType` answered
it *with* the class identity.

## What collapsed, and what it cost

The three module-global readers were one loop written three times — same depth
counter, same `atStart` predicate, same `PyScanLo..MainProgramTokCount`
bounds — differing only in the statement-head pattern and the return type.
`PyModuleBindingsOf` is now that scan once; the three are thin callers.
**No answer changed**, asserted by every rung's probe before and after.

**The hazard found while collapsing is the part to keep.** The three readers
DISAGREE about a global rebound at module level: the literal reader lets the
LAST binding win, the constructor reader scans past bindings that do not match
its shape, and today's answer is an accident of the order they are consulted
in. A resolver that returned "the first binding" — the obvious collapse — would
type `RB2 = J(); RB2 = 7` as a `J` holding a `7`. A wrong LAYOUT, which
compiles and prints a plausible number. Guarded now by the last two rows of
`test/test_nilpy_field_from_a_module_global_expression.npy`.

## What did NOT collapse, and why that is a real answer

`PyHeaderParamType` reads an ANNOTATION, not an initialiser — a parameter has
no initialiser to infer from, so it is genuinely a different read. The
annotation arm is a DECLARATION. The policy arms are policy. Those four stay.

## The root cause, and the shape of the rest

The pre-pass runs before anything knows a name's type, so each scope grew its
own token-scanner. `PyLocals` is a **flat array with a linear name scan and no
scope field** (`pyparser.inc:76`), which is why seeding module globals into it
before this pre-pass — the obvious fix, and the first one tried — made a
def-local loop target inherit a same-named module global's type.
`test_nilpy_loop_target_in_a_def_is_local.npy` exists because it caught that.

So the remaining work is a `name -> binding-site` resolver per scope feeding
the one expression scanner, which would delete the two method-local readers and
fix a shape that is refused today for free: `FN = named` then `self.fn = FN`
(the direct `self.fn = named` works). **That is the tell this rule predicts** —
of several paths for one concept, the one nobody extended is the one that
stays broken.

Same rule, same evening, different subsystem:
`bug-n-a-chained-assignment-to-two-attributes-does-not-parse`.
