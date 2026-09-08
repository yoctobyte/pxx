---
slug: bug-p-a-for-in-enumerator-whose-movenext-takes-arguments-is-accepted
track: P
prio: 45
type: bug
blocked-by: []
status: done
owner: frankS
created: 2026-09-08
found-by: frankS
summary: "FIXED 2026-09-08. A class whose `MoveNext` takes arguments was accepted as a for-in enumerator on BOTH arms -- through an `operator enumerator` and through `GetEnumerator` -- and the lowering then called it with none, so the parameter slot was never written and the loop ran on whatever was in it. fpc 3.2.2 refuses both (`Cannot find a \"MoveNext\" method in enumerator \"T\"`). Silent: compiled clean, exit 0. The rule now lives in EnumeratorMoveNextMeth, the single resolver both arms already go through -- its own header says both the check and the lowering must ask the same question, and a rule at either call site would have left the other arm accepting. FOUND BY A GREEN ROW GOING RED: tforin22.pp is a `%FAIL` conformance row that had been PASSING, and not because of this check -- its container is the literal `1`, which the for-in dispatch refused at an unrelated tkIdent gate. Removing that gate is what exposed it, so the row had been green for a reason with nothing to do with what it asserts."
---

# A for-in enumerator whose MoveNext takes arguments is accepted, on both arms

Measured 2026-09-08, compiler `70dffa8a0e51`, against fpc 3.2.2 `-Mobjfpc`.

```pascal
type
  TBad = class
    F: Integer;
    function MoveNext(a: Integer): Boolean;   { NOT the protocol's MoveNext }
    property Current: Integer read F;
  end;
operator enumerator(a: Integer): TBad; ...
var i, v: Integer;
begin v := 1; for i in v do WriteLn(i); end.
```

| arm | pxx before | fpc |
| --- | --- | --- |
| `operator enumerator` returning TBad | compiles, exit 0 | `Cannot find a "MoveNext" method in enumerator "TBad"` + `Impossible operator overload`, at the operator DECLARATION |
| `GetEnumerator` returning TBad | compiles, exit 0 | same, at the loop |

`GenMakeMethodCallM` passes the instance and no argument list, so the call was
built for a parameterless method and the parameter slot was simply never
written.

# Why it was invisible, and it is not the usual reason

It is not that nobody wrote a test. `tforin22.pp` is exactly this program, is a
`%FAIL` row, and **was passing** — because pxx refused it at a for-in gate that
required the container's first token to be `tkIdent`, and its container is the
literal `1`. The row asserted "this must be rejected", pxx rejected it, and the
rejection had nothing to do with the enumerator.

So the conformance suite reported a green that was correct about something else.
Closing [[bug-p-a-for-in-container-must-start-with-an-identifier-token]] turned
that row red in the same run, which is the only reason this was found.

**A `%FAIL` row cannot tell you WHY the compiler refused**, and that is
structural rather than a gap in this one test: it asserts a non-zero exit, and
every refusal produces one. Any `%FAIL` row whose program would also be refused
for an unrelated reason is carrying the same risk, and there is no instrument in
the harness that would distinguish them.

# The fix, and why it is in the resolver

`EnumeratorMoveNextMeth` (pasparser_stmt.inc) answers -1 when the method it
resolves takes more than one parameter. Its own header already stated the
governing rule — *"Both the check and the lowering must ask the same question,
or a loop is accepted by one rule and lowered by another"* — and both readers
(`ParseForInEnumeratorAST`, `BuildForInOpEnumeratorLoop`) already `Error` on -1,
so both arms refuse with one edit and one message.

`ParamCount > 1`, not `<> 1`, and the direction is deliberate: `ParamCount`
counts Self for a class method (the interface-signature check in
`pasparser_decl.inc` prints `ParamCount - 1` as the user-visible arity), while an
interface method's row need not carry the Self slot — `tforin9.pp`'s
`IMyIterator`, which nominates its MoveNext through the `enumerator MoveNext`
directive, is that shape and still compiles. Erring toward accepting is right
here: the failure being closed is ACCEPTING a malformed enumerator, so a missed
interface case leaves it exactly where it was rather than refusing a loop that
works.

# Verification

`test/test_a_for_in_enumerator_needs_a_parameterless_movenext_operator.pas` and
`..._getenumerator.pas`, both MUST-NOT-COMPILE, both wired into `test-core`.
**Two files because there are two arms and one resolver** — a fix at either call
site would leave the other accepting, and these two rows are what says the rule
is in the resolver rather than beside one caller.

Positive controls, all green after the change: the seven `test/test_for_in_*`
fixtures and `tforin9.pp`.

## Log
- 2026-09-08 — fixed and closed, commit PENDING-COMMIT.
