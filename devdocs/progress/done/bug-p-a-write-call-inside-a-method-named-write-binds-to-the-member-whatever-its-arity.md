---
slug: bug-p-a-write-call-inside-a-method-named-write-binds-to-the-member-whatever-its-arity
track: P
prio: 70
type: bug
status: done
created: 2026-09-02
found: 2026-09-02
found-by: frankC
owner: frankC
commit: PENDING-COMMIT
blocked-by: []
summary: "An unqualified Write/Read call inside a class that has a member of that name bound to the member on the NAME ALONE -- no arity check, no type check. `Write(f, 'payload')` inside a method named write therefore became a 3-argument call to a 2-parameter method: i386/arm32/aarch64 refuse it, x86-64 has no such guard and emitted it, and the file came out EMPTY while the function returned True. lib/rtl/configparser.pas is written in exactly that shape. FIXED: the branch now asks the arity/type-aware finders the tkIdent twin it claims to mirror was already asking."
---

# `Write(f, x)` inside a method named `write` bound to the member whatever its arity

## How it was found

Not by looking for it. `examples/tk/uses_tkinter_and_configparser` was the one
example in the tree that failed on every cross target
(`umbrella-cross-target-codegen-is-correct`, second attempt), on four different
causes. Three named unwritten features; aarch64's said

```
pascal26:399: error: target aarch64: call argument count mismatch
  in: ./compiler/../lib/rtl/configparser.pas
```

**A refusal that reports a count mismatch is describing a state the compiler
believes is impossible.** That is what made it worth opening ahead of the other
two, which were both larger and both honest.

## What it was

`pasparser_stmt.inc`, the `tkwriteln, tkwrite, tkReadln, tkRead` statement arm.
An unqualified `Write(` inside a class that has a `Write` member binds to the
member rather than the intrinsic — right, deliberate, and citing FPC
(`bug-bare-read-write-in-method-hits-intrinsic`). But the guard and the
selection both asked `FindUMeth`, **which answers on the name alone**:

```pascal
(FindUMeth(SelfMemberCi(CurTok.SVal), CurTok.SVal) >= 0)   { guard }
smmii := FindUMeth(smci, CurTok.SVal);                     { selection }
```

So `Write(f, 'payload')` — the intrinsic, two arguments, a `Text` file — bound
to `write(const path: AnsiString)` and emitted a **three**-argument call
(Self, f, str) to a **two**-parameter method.

The `tkIdent` twin that this branch's own comment says it mirrors was already
asking both questions (`FindUMethOverloadAhead(..., CountCallArgsAhead)`). This
was the copy that did not — the second path that stays broken,
`normalise-dont-special-case.md` exactly.

## Why only one target saw it

i386, arm32 and aarch64 carry a `call argument count mismatch` guard. **x86-64
does not.** So on the target everything is developed on, the bad call was
emitted and:

```
x86-64 before the fix:  TRUE TRUE      <- the function reported success
                        wr.out: 0 bytes
x86-64 after:           TRUE TRUE
                        wr.out: 7 bytes = 'payload'
```

A file created, left empty, and reported written. With the file *read back*
rather than the result trusted, the pre-fix binary **segfaults**.

## FPC rejects the same source

```
wr.pas(24,24) Error: Wrong number of parameters specified for call to "write"
wr.pas(8,16)  Error: Found declaration: write(LongInt):Boolean;
wr.pas(13,16) Error: Found declaration: write(const AnsiString):Boolean;
```

So `lib/rtl/configparser.pas` is written in a shape FPC will not build at all
and pxx built wrong — the worst of both. We take the permissive reading on
purpose: the source plainly MEANS the intrinsic (`Write(f, to_string)` with a
`Text`), no overload of the member can accept it, and accepting what FPC
rejects is not a defect here. What is not acceptable is emitting a call no
signature matches.

## The fix

`FindUMethArityStrict` (symtab.inc) — `FindUMethArity` **without** its final
fall back to the first name match, so it can answer *no*. The fallback is right
for a SELECTOR, which has already decided it is a method call; it is wrong for a
caller still deciding WHETHER this is one, which reads it as yes and then binds
a call nothing accepts. The statement arm now gates on it and selects with
`FindUMethOverloadAhead`, so same-arity overloads are chosen by type too.

## Verification, both directions

`test/test_method_read_write_unqualified.pas` was extended rather than
duplicated — it already asserted the binding, and **a test that only asserts
the binding cannot fail when the binding becomes unconditional.** The new
`spill` case asserts the fall-through, and reads the file back rather than
trusting the return value, because the defect reported success.

- new compiler: `data=42 / r=43 / spill=OK`, and all six targets build it
- pinned compiler: builds, then **segfaults** — a two-directional control
- the original binding control is byte-identical before and after
- `tools/gate.sh quick` GREEN with the tree dirty
- `examples/tk/uses_tkinter_and_configparser` builds for aarch64 now
