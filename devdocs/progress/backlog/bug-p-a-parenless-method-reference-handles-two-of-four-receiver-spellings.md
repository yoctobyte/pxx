---
slug: bug-p-a-parenless-method-reference-handles-two-of-four-receiver-spellings
track: P
prio: 45
type: bug
status: backlog
blocked-by: []
summary: "`TryParseParenlessMethodRef` (pasparser_call.inc:723) reads `obj.M` with no `@` and no argument list as a method REFERENCE, and is the single place that decision lives. It handles two receiver spellings — a class NAME and an instance VARIABLE — and there are four. A BARE name inside the class's own method (`TSel(Pick)`) and a METACLASS VARIABLE receiver (`mc: class of TSvc; TSel(mc.Pick)`) both fall through to the call path and are rejected with `wrong number of parameters in call to TSvc.Pick`. FPC accepts both. Same on pinned faf762981c3c and HEAD a9a4818ab6c8, so neither is a regression. The corpus does not need them — all 24 rtl-generics sites use the working class-name spelling — which is why this is filed rather than folded into the ticket that found it."
owner: unassigned
---

# A parenless method reference handles two of four receiver spellings

Found while verifying
[[bug-p-the-address-of-a-virtual-class-method-cannot-be-lowered]], whose own
defect turned out to be already fixed. These two arms are what the sibling check
turned up.

## Measured — binary `a9a4818ab6c8`, and identically on `pinned faf762981c3c`

| arm | receiver spelling | pxx | FPC 3.2.2 |
| --- | --- | --- | --- |
| B | class NAME — `TMethod(TSel(TSvc.Pick)).Code` | compiles, runs | ✓ |
| D | instance VARIABLE — `TMethod(TSel(s.Pick)).Code` | compiles, runs | ✓ |
| **A** | **bare name**, inside the class's own method — `TMethod(TSel(Pick)).Code` | `wrong number of parameters in call to TSvc.Pick` | ✓ |
| **C** | **metaclass VARIABLE** — `mc: class of TSvc;` then `TMethod(TSel(mc.Pick)).Code` | same error | ✓ |

Neither is a regression — both fail on the current pin too.

## Why they fall through

`TryParseParenlessMethodRef` (`compiler/pasparser_call.inc:723`) is deliberately
the ONE place this decision lives; its own comment says writing a fifth
construction site is what `root-cause-over-microfix.md` tells you to stop and
count instead of doing. Two guards keep A and C out:

```pascal
  if Tokens[TokPos].Kind <> tkDot then Exit;        { arm A has no receiver at all }
  ...
  if (rsym >= 0) and (Syms[rsym].RecName >= REC_UCLASS_BASE) and ... then
    rci := ...                                      { instance variable }
  else if (rsym < 0) and (FindUClass(...) >= 0) ... { class name }
  else
    Exit;                                           { arm C lands here }
```

A metaclass variable is a `tyPointer` whose pointee is a class, not a symbol
whose `RecName` is a class, so it misses both arms.

## The design fork — this is why it is filed rather than written

`NodeMetaclassCi` (`symtab.inc:12876`) already exists and is exactly the right
predicate. Its own comment records that the metaclass receiver was taught one
spelling per ticket as four copies of the same test, and that it exists so *"the
next spelling is added once"*. This is the next spelling.

But it takes a **node**, and at this point in `TryParseParenlessMethodRef` no
node has been built — the function is careful to allocate nothing before it is
committed, because it must be able to `Exit` without consuming tokens. So there
are three options and the choice is not the parser's to make alone:

1. **Allocate the `AN_IDENT` receiver node early** and pass it to
   `NodeMetaclassCi`. Cleanest, reuses the predicate — but it orphans one AST
   node on every `something.field` in Delphi mode that turns out not to be a
   method reference, which on a large unit is thousands of wasted nodes.
2. **Split a sym-level `SymMetaclassCi(si)` out of `NodeMetaclassCi`'s
   `AN_IDENT` arm** and call that here, with `NodeMetaclassCi` delegating to it.
   No waste, no duplication, one predicate still. **This edits `symtab.inc`,
   which is Track A ground** — so it is an A change, filed here and handed over
   rather than reached into.
3. Duplicate the three-line `tyPointer` / `PtrElemTk = tyClass` test inline.
   Cheapest, and precisely the duplication `NodeMetaclassCi` was created to end.
   Recommended against.

**Recommendation: (2).** It keeps the "added once" property the predicate was
built for, and the split is mechanical. Arm A needs no such decision — the
receiver is the enclosing method's implicit `Self`, and that fix is contained in
`pasparser_call.inc`.

## Gate

Four programs, one per row of the table, each **calling through** the taken
address rather than only asserting it is non-nil — a wrong pointer is non-nil
too. Compare against FPC; `tools/fpc_diff_probe.sh` is the oracle. Arms B and D
must stay green.


---

# ARM A DONE. Arm C is what is left, and the table above needs two corrections.

Binary `490a2cfd83a2`, `gate.sh quick` GREEN. Test:
`test/test_method_pointer_bare_receiver_and_call_reading.pas` (+ `.expected`),
wired into `test-core`, fails on `pinned` with the recorded error and matches
FPC at HEAD.

## What landed

**Arm A — bare receiver.** `TryParseParenlessMethodRef` gained a no-receiver arm
that resolves the implicit `Self` as the ordinary symbol it is and then joins the
instance-variable path unchanged, so it is one more spelling of the same node
rather than a fourth construction site. Two guards keep it safe and run BEFORE
the dot test: a name that IS a symbol in scope is a variable and shadows the
method (so a local named after a method still reads as the local), and a
following `(` is an argument list.

**...and the site that had to be fixed twice, which is the real find.** The
ticket says the decision "lives in one place". It did not. The ASSIGNMENT context
(`p := obj.M`, `pasparser_stmt.inc`) carried its own hand-written copies of the
instance-variable and class-name arms — two more of the four AN_METHODREF
construction sites the helper's own comment says to stop and count. Adding arm A
to the helper therefore fixed only the CAST context; the assignment context still
rejected `t := Pick`. Both copies are now deleted and that site asks the helper,
which is why every row of the new test is exercised in **both** contexts.

**A SEGFAULT fell out of the unification, and it is the more serious half.**
Folding the arms together exposed that neither site had Delphi's
call-vs-reference rule:

```pascal
  function TSvc.Handler: TSel;   { parameterless, RETURNS a method pointer }
  t := Self.Handler;             { FPC CALLS Handler }
```

pxx took Handler's **address**, stored a `{Code, Data}` pair built from the wrong
routine, compiled clean, and **SIGSEGV'd on the first call through `t`** —
measured on `pinned`, so pre-existing and not a regression. Same failure shape as
`bug-p-a-class-method-cast-to-a-method-pointer-inline-segfaults`, one construct
further on. The rule now lives in `MethodResultSatisfiesTarget`, **inside the
helper**, so all three receiver spellings get it rather than the one arm that
happened to need it: every caller has already established that a method pointer
is wanted, so "the result fits the target" is exactly "the result IS a method
pointer", and no other result type changes the reading.

## Two corrections to the table at the top of this ticket

Both found by trying to write the gate this ticket specifies.

1. **`TMethod(TSel(X)).Code` does not compile — for ANY receiver spelling, and
   never did.** `expected ')' before '.'` on `pinned` and at HEAD. So rows B and
   D were not measured in the spelling they are written in; they were measured
   through a variable (`f := TSel(s.Pick); m := TMethod(f)`), which does work.
   Filed as [[bug-p-a-field-selection-on-a-record-cast-is-not-parsed]].
2. **Row B is not a valid FPC program as written.** `TSel(TSvc.Pick)` on an
   INSTANCE method is rejected by FPC — *"Only class methods, class properties
   and class variables can be referred with class references"*. A class-name
   receiver has to be exercised against a CLASS method. The class-name arm itself
   is fine; the row's example is not.

The lesson is small and cheap: **a ticket's example is not measured just because
its verdict was.** Both rows' verdicts are right about the receiver arms; the
spellings printed beside them had never been run.

## A third axis, found the same way and NOT part of this ticket

`Result := s.Pick` is refused for **every** receiver spelling, while
`t := s.Pick; Result := t` works — the implicit `Result` symbol is allocated as a
plain var with no recorded procedural signature, so the LHS never looks like a
method-pointer lvalue. That is the LHS spelling, orthogonal to the receiver
spellings this ticket enumerates, and it lives in result-symbol setup that every
function in every mode goes through. Filed as
[[bug-p-result-is-not-a-method-pointer-lvalue]]; the new test uses locals
throughout and says so in its header.

## Arm C — unchanged, and the recommendation stands

Metaclass VARIABLE receiver (`mc: class of TSvc; TSel(mc.Pick)`). Option (2) from
the fork above: split a sym-level `SymMetaclassCi(si)` out of `NodeMetaclassCi`'s
`AN_IDENT` arm in `symtab.inc` and have `NodeMetaclassCi` delegate to it. frankA
has cleared it with two conditions: `git pull --rebase` immediately before
writing (that file is under repeated concurrent edit), and verify the `AN_IDENT`
arm reads nothing off the node but the sym index. Arm A needed no such clearance
and is done.
