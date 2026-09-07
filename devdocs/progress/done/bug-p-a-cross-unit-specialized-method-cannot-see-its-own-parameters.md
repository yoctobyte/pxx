---
prio: 70
track: P
status: done
summary: "FIXED 2026-09-07 at compiler 4fcc6478fb08. A generic method body is re-parsed AS ITS DECLARING UNIT (deliberately, so a template reaches its own unit's private helpers), but its PARAMETERS, its Result and its Self are allocated by the header path BEFORE that switch and therefore carry the SPECIALIZING unit. When a UNIT specializes another UNIT's template -- a library wrapping a generic, the ordinary direction -- the declaring unit does not `uses` the specializing one, so the cross-unit visibility test refused the method its own arguments: `undefined variable (a)`, `undefined variable (Result)`, `undefined variable (Self)`. Fixed in SymBindableHere: a routine's own parameters and locals are exempt from unit/section visibility, which is a question that cannot apply to them -- IsBlockVisible is their whole scope. Fixture test_xunitparams26; new PXXDBG channel p.specunit."
owner: frankS
resolved: PENDING-COMMIT
---

## What was wrong

`ParseSubroutine` sets `CurrentUnitIdx := tmplDeclUnit` around `ParseBlockAST`
for a specialized method, and the comment there says exactly why: *"this body is
the unit's code no matter where its tokens were pasted."* Correct — and the
switch is placed **after** the parameters and `Result` have been allocated, so
those symbols are stamped with the unit the specialization was written in.

`SymBindableHere` then asks `DeclVisibleSect` about them, and for a library
shape it says no:

```pascal
unit ugxpbase;  generic TBox<T> = class procedure SetIt(a: T); ... end;
unit ugxpwrap;  uses ugxpbase;  type TIntBox = specialize TBox<LongInt>;
```

`ugxpbase` does not `uses` `ugxpwrap` — it must not; that is the direction a
library runs — so `VisibilityAllows(ugxpbase, ugxpwrap)` is false and every
routine-scoped name in the body disappears.

## Why it read as a `Self` bug for as long as it did

Three separate accidents pointed away from the cause, and each one is a named
trap:

1. **Method bodies are spliced at the cursor, so they are parsed in REVERSE
   declaration order.** Whichever method mentions `Self` is usually reached
   first and the compile stops there — so `Self` looked special and parameters
   looked fine. Delete the `Self` method and `undefined variable (a)` and
   `undefined variable (Result)` appear immediately.
2. **A LOCAL declared inside the body works**, because it is allocated *after*
   the switch. So the obvious "is this about scope at all" probe says no.
3. **It works from a PROGRAM**, which is where every reduction starts. A program
   is not a unit, the two identities never disagree, and the whole defect is
   invisible. Only a UNIT specializing another UNIT's template reaches it.

The `tgeneric91.pp` skip row had recorded this as *"Self in class procedure of a
generic class specialized cross-unit"* — the symptom exactly, and three wrong
things about the cause: it is not `Self`, not `class procedure`, and not
cross-unit on its own.

## Measured

`PXXDBG=p.specunit` (added here) prints a specialized method's two unit
identities side by side, before a single body token is read:

```
PXXDBG p.specunit TGL.UsesSelf body-unit=61 spec-host=60 param-unit=60 FindSym(Self)=-1
PXXDBG p.specunit TGL.ITest    body-unit=60 spec-host=-1 param-unit=-1 FindSym(Self)=296
```

The first is the failing arrangement, the second the same template specialized
from a program. `FindSym` answers -1 while the parameter exists and is correct —
which is why no error message could name the cause.

`PXXDBG=p.implleak` is what found the gate, and it is worth recording that it
was *nearly* misleading: it reported `LEAK var Self in=qb decl-unit=qa` and,
with the report on, the program STILL did not compile — because the report only
bypasses the `ImplPrivateApplies` arm, not the `VisibilityAllows` return one
line further down. A probe that disables half of a two-part gate looks like an
exoneration.

## The fix

`SymBindableHere`, `compiler/symtab.inc`:

```pascal
SymBindableHere :=
  ((Syms[i].Kind = skParam) or (Syms[i].Kind = skLocal) or
   DeclVisibleSect(SymUnitIdx[i], SymDeclImpl[i], IMPLTAB_SYM, i))
  and not (DeclOrderStrict and ...);
```

**Unit and section visibility decides which of ANOTHER unit's names this one may
reach.** A parameter or routine-local is reachable only from inside its own
routine, and `IsBlockVisible` — plus `SymRollbackTo` unhashing the chain when the
routine exits — is the whole of that decision. Asking `DeclVisibleSect` about
them is a category error; it simply had no victim until a body was parsed under
a borrowed unit identity.

**Re-stamping the parameters instead was the alternative and is weaker**: it
repairs one producer and leaves the invariant unstated, so the next body parsed
under a borrowed unit identity breaks the same way.

## Verified at `4fcc6478fb08`

- `test_xunitparams26` — ten rows identical to fpc 3.2.2, one routine-scoped
  name per method (parameter, `Result`, a local, `Self` by value, `Self`
  reaching a `TObject` method) plus a field read as the control that always
  worked. **Both sections of the wrapping unit specialize**, because the
  interface and the implementation reach the splice by different paths. The
  pinned compiler refuses it with `undefined variable (a)`.
- The `Self` rows assert a VALUE and a PREDICATE, never the class-name spelling:
  pxx calls the specialization `TIntBox` where fpc calls it
  `TBox<System.LongInt>`, and printing it would make this fixture assert one
  compiler's naming scheme instead of the thing it is about.
- gate quick GREEN; self-host fixedpoint converged.
- fgl corpus 7/7 against the FPC oracle on real `fgl.pp`; fcl-passrc's
  `pparser.pp` still compiles clean.
- **`SymBindableHere` is every frontend's every name lookup**, and the
  fixedpoint proves only the Pascal one, so one probe per uncovered frontend:
  C, NilPy, Rust and Zig each compile and run, and the Rust and Zig outputs are
  byte-identical to the pinned compiler's.

## What this does NOT fix

`tgeneric91.pp` itself. Its arrangement adds **mutually recursive
implementation-section `uses`** — a and b each specialize the other's template —
and the wall has moved to a second, unrelated defect: the specialized body is
spliced somewhere the parser will not take a method implementation
(`expected 'begin' before '.'`, `near: ; end ; class procedure TSomeGeneric1LongInt >>> . Test ;`).
Filed as
[[bug-p-a-specialized-method-body-splices-into-an-illegal-place-under-circular-uses]].
Its skip reason is corrected in this commit rather than left naming a cause that
was wrong.
