---
track: P
prio: 40
type: bug
blocked-by: []
status: open
owner: frankS
---

# A constructor reached through an INSTANCE is typed Integer, so its value is wrong

`R.Create(...)` on an existing variable — FPC re-runs the constructor on that
instance and the expression's VALUE is the instance. pxx builds the call
correctly and then types the result from `Procs[mpi].RetType`, which for a
constructor is `tyInteger`: `ParseRecordMethodDecl` sets `isFunc := False` for
`isCtor` (pasparser_decl.inc:4923), so no return type is ever recorded. The
metaclass and type-name arms both override this by hand — `outTk := tyClass;
outRec := REC_UCLASS_BASE + ci` (pasparser_lval.inc ~6080, ~1735) — and the
INSTANCE arm does not.

**MEASURED 2026-09-07** against fpc 3.2.2, compiler `83302cc339b5`. Four
spellings of the same construct, four different behaviours, and the second one
is the reason this is a bug and not a compat row:

| spelling | pxx | fpc |
| --- | --- | --- |
| `R.Create(false);` statement | `10 20` — correct | `10 20` |
| `R2 := R.Create(false);` | **`20 20`** | `10 20` |
| `Writeln(R.Create(false).X)` | `IR_UNSUPPORTED: ... AST node (kind 8)` | `10` |
| `Show(R.Create(false))` | `no overload of Show matches these arguments / argument types: (Integer)` | `10 20` |

Row 2 **compiles clean and prints the wrong value**. Rows 3 and 4 refuse, and
row 4's diagnostic is actively misleading — it names the CALLEE's overload set
for a defect in the ARGUMENT, so a reader goes looking at `Show`.

**Both arms are broken identically.** `class` behaves exactly as `record` does
here, which is unusual for this area: the record/class split is normally where
one arm was fixed and the sibling was not
(`devdocs/dev/normalise-dont-special-case.md`). Here neither was, which points
at the shared instance-method arm rather than at either type's own path.

## Where

`compiler/pasparser_lval.inc`, the instance-method `else` arm at ~3495 and the
`tk := Procs[mpi].RetType` at ~3707. The fix is the one the two sibling arms
already make: when `UMthIsCtor[mmi]`, the expression's type is the RECEIVER's
and its value is the receiver — an `(call, receiver)` comma, so the receiver is
evaluated once and the constructed state is what the consumer reads.

**Not yet attempted, and one thing to settle first:** the receiver node is
already consumed as `mselfArg`, so yielding it as the value means either
reusing the node (double evaluation for a non-trivial receiver) or
materialising a temp. FPC only accepts an lvalue receiver here, which bounds
the problem but does not remove it.

## Why it is ranked 40 and not higher

Real code does not call a constructor on an already-constructed instance —
terecs15.pp's own comment says *"delphi has an internal error here"*, i.e.
Delphi ICEs on the same line. So the wrong value is real but the population
that can reach it is small. What keeps it out of `low-prio/` is that it is
SILENT: nothing about row 2 tells the programmer the answer is wrong.

## Where it was found

`test/pascal-conformance/pxx.skip`'s `terecs15.pp` row. That row's overload
half was fixed on 2026-09-07 (test/test_record_constructor_overload.pas); this
is the whole of what is left of it, at line 71.
