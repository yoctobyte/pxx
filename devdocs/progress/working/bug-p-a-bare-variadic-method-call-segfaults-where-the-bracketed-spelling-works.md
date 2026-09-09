---
track: P
prio: 40
type: bug
status: working
owner: frankH
created: 2026-09-09
found-by: frankS
tags: [array-of-const, methods, variadic]
blocked-by: []
summary: "`Desc('a', 1)` — variadic bracket-elision against `Desc(const a: array of const)` — SEGFAULTS when written bare inside the class that declares it, while the bracketed spelling `Desc(['a', 1])` of the same call runs correctly in the same program. Measured 2026-09-09 at 1180aa627: `Desc(['a',1])` prints `n=2: chr=a int=1`, then `Desc('a', 1)` crashes. The elision is a pxx extension (feature-writeln-as-library) and fpc refuses the source, so there is no oracle for the ACCEPTED behaviour — the defect is that we accept it and then crash, which is the one outcome nobody can act on. AbsorbVariadicTailArgs hooks ExpectCallRParen; the bare implicit-Self site hand-rolls its own argument loop and never reaches it, which is the same structural cause the BRACKET DOOR comment already records at that loop. NOT the arity bug fixed in bug-p-a-bare-method-call-inside-its-own-class-ignores-arity: that fix deliberately carves this shape OUT rather than converting the crash into a diagnostic, because a fix aimed elsewhere must not hide it."
---

# A bare variadic method call segfaults where the bracketed spelling works

- **Type:** bug — **Track P** (`compiler/pasparser_stmt.inc`, the implicit-Self
  call site's hand-rolled argument loop).

## The repro

```pascal
type TC = class
  procedure Desc(const a: array of const);
  procedure Go;
end;
procedure TC.Go;
begin
  Desc(['a', 1]);   { prints  desc n=2: chr=a int=1 }
  Desc('a', 1);     { SEGFAULT }
end;
```

Both are the same call. The bracketed one is built correctly; the elided one
crashes at run time, having compiled clean.

## Why it is here rather than in AbsorbVariadicTailArgs

`AbsorbVariadicTailArgs` is called from `ExpectCallRParen`. The bare
implicit-Self statement path does not go through it — it hand-rolls its
argument loop, which is the **same structural cause** the `THE BRACKET DOOR`
comment already sitting in that loop records: *"Every other call path asks;
this one hand-rolled its loop and asked nothing."* That comment fixed the
bracket case at this site; the elision case is the next one along.

## Relationship to the arity fix

[[bug-p-a-bare-method-call-inside-its-own-class-ignores-arity]] closed the loose
arity fallback at this exact site, and **deliberately carves this shape out**
(`UMethNameCanAbsorbVarRecTail`). Refusing it would have turned a segfault into
a compile error, which reads as a fix and is not one — the extension is
supposed to work here, and the bracketed spelling proves the machinery exists.

## No oracle for the accepted behaviour

fpc refuses `Desc('a', 1)` outright ("Wrong number of parameters"), so this is
`us accepting what FPC rejects`, which **is not a defect** — the defect is the
crash. The expected output is the bracketed spelling's, which is measured and
in the ticket above.

---

## Fixed 2026-09-09 (frankH)

### The mechanism

The bare implicit-Self **statement** site (`compiler/pasparser_stmt.inc`, the
`CurSelfClass >= REC_UCLASS_BASE` arm of the `tkIdent` dispatch) ran

```pascal
while CurTok.Kind <> tkRParen do begin ParseExpr; …append AN_ARG…; if CurTok.Kind = tkComma then Next; end;
Expect(tkRParen, ')');
```

Unbounded. For a call whose arity already matched, that is the same thing as a
bounded loop. For a call whose arity did not, the strict check above it has
already errored. **Exactly one shape lives in between:** variadic
bracket-elision, which the arity check deliberately carves out
(`UMethNameCanAbsorbVarRecTail`) *because the extension is supposed to pass
more arguments than the signature has*. Those surplus arguments were appended
as separate `AN_ARG` slots, so the callee's open-array descriptor was whatever
the second one happened to be — `Length(a)` segfaulted, having compiled clean.

The fix bounds the loop at `Procs[smpii].ParamCount`, leaves the comma in place
once the declared slots are full, and routes the tail through the shared
`ExpectCallRParen`, which is where the other seven argument loops absorb an
elided `array of const` tail.

### Three things that were not obvious

1. **`Desc('a')` crashed by the OTHER route.** Arity MATCHES, so nothing is
   carved out and nothing is surplus — a scalar was handed to a slot that wants
   a vector. This is why `ExpectCallRParen` calls `AbsorbVariadicTailArgs`
   unconditionally rather than only when a comma is in sight, and why the test
   pairs a single-element row with a multi-element one.

2. **Leaving the comma is load-bearing, not tidy.** Bounding the loop alone
   would have exited with `CurTok` on the first *surplus expression*, and
   `AbsorbVariadicTailArgs` reads `while CurTok.Kind = tkComma`. It would then
   have wrapped element 0 only and reported an arity error for the one call
   shape the extension exists to accept.

3. **`smLastArg` still being `smselfArg` means empty parens, and handing THAT
   to the absorber wraps the implicit Self pointer.** `Desc()` printed `n=1`
   with a garbage element. Passing `-1` (the absorber's own "no meaningful last
   argument" convention) leaves the empty-parens shape exactly as it was rather
   than giving it a new and more confident wrong answer. It is still wrong and
   is now filed separately:
   [[bug-p-empty-parens-at-a-bare-method-call-reads-a-garbage-argument]]
   (`n=8`, identical on HEAD and on the pin, so not a regression).

### The duplicate diagnostic the bounded loop created, and why the pre-check won

Bounding the loop left the surplus in the token stream, so
`test_p_a_bare_method_call_ignores_arity_fail` began reporting each bad call
twice — once from this site's pre-check (`call to Plain`) and once from
`ExpectCallRParen`'s tail (`call to TC.Plain`).

Which one to keep is settled by **what each can see**: the tail fires only on a
surplus, because a call that is SHORT of arguments leaves `CurTok` on `)` and
is invisible to it. The pre-check catches both directions. Handing the surplus
direction to the tail would have split one site's arity reporting across two
wordings depending on which way the count was wrong. So the pre-check stays the
site's single arity authority, and all that is owed at the tail is the resync —
`SkipSurplusCallArgTail`, lifted out of `ExpectCallRParen` in this commit so
the two callers share it rather than growing an eighth copy of that loop.

### Verification

- New test `test/test_p_a_bare_variadic_method_call.pas`, wired into
  `test-core`. Every elided row is **paired with its bracketed twin** and the
  two must agree — the bracketed spelling always worked, so an unpaired row
  could be green against a wrong-but-stable descriptor.
- **Positive control:** pin v399 SEGFAULTS on the very first row of that file.
- `test_p_a_bare_method_call_ignores_arity_fail` back to exactly four
  diagnostics on lines 42-45, `rc=1`, no binary.
- `test_p_a_bare_method_call_arity_still_valid`,
  `test_an_array_of_const_literal_at_a_bare_self_method_call`,
  `test_variadic_bracket_elision`, `test_variadic_elision_methods` and
  `test_variadic_elision_method_refusal` all unchanged.
- Self-host `converged after 1 round(s)`; `tools/gate.sh quick` GREEN with the
  FPC seed canary active (committed from a dirty tree, so the canary ran).
