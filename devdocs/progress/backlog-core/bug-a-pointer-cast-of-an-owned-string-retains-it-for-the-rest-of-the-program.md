---
slug: bug-a-pointer-cast-of-an-owned-string-retains-it-for-the-rest-of-the-program
track: A
prio: 70
type: bug
blocked-by: []
status: backlog
found: 2026-09-01
found-by: frankZ
owner: unassigned
summary: "`p := Pointer(s)` on an already-owned AnsiString adds +1 to its refcount that is released only at the ENCLOSING SCOPE's exit — so in a routine it is balanced and merely wasteful, and in the main program body it is held for the program's life. Six lines reproduce it. This is what turned test_threadsafe_refcount_lockfree red (3 of its rows assert rc=1); Track T's bisect window holds exactly one buildable commit, b788c5865, and the behaviour it describes is this one. NOT unbounded: a loop adds +1 per SITE, not per iteration, and the payload is intact."
---

# A pointer cast of an already-owned string retains it for the rest of the program

Measured 2026-09-01 by frankZ at `db706c2da`, binary `59699dc0833f8110`.

## Six lines

```pascal
program rc3;
var s: AnsiString; p: Pointer; k: Integer;
function Cnt: Int64; begin Cnt := PWord(Int64(PChar(s)) - 16)^; end;
begin
  s := '';
  for k := 1 to 44 do s := s + Chr(65 + (k mod 26));
  WriteLn('after build              = ', Cnt);   { 2 }
  p := Pointer(s);  WriteLn('after p := Pointer(s)    = ', Cnt);   { 3 }
  p := Pointer(s);  WriteLn('after p := Pointer(s) #2 = ', Cnt);   { 4 }
  p := Pointer(s);  WriteLn('after p := Pointer(s) #3 = ', Cnt);   { 5 }
end.
```

Each `Pointer(s)` site in the MAIN BODY adds one and never gives it back.
`PChar(s)` reads are stable, so the generic pointer cast is the spelling that
does it.

## What it is NOT — three things I checked before writing this down

- **Not unbounded.** The same three sites inside a `for i := 1 to 70000` loop
  add **+1 in total, not 70000**: the retain is per SITE, not per execution.
  The 16-bit count does not wrap and the payload survives (`Copy(s,1,8)` still
  reads `BCDEFGHI`).
- **Not a leak in a routine.** Wrapped in a procedure, the count returns to its
  starting value on return — 2 before, 2 after 1000 iterations, 2 after 72000.
  The release IS emitted; it is parked at the enclosing scope's exit. The main
  program body's scope exit is program exit, which is why only the main body
  shows it.
- **Not `const`-parameter passing.** A `procedure JustPass(const v: AnsiString)`
  that does nothing costs zero. I initially read a `+1` there and it was the
  next statement's own pointer cast; the reading was wrong, not the compiler.

So the severity is **an owned string that cannot be freed while `main` runs**,
plus every refcount assertion in the corpus reading one too many.

## What it broke

`test-threads#src:test/test_threadsafe_refcount_lockfree.pas`, deterministic
5/5, `fail=3`:

```
FAIL heap handle starts at rc=1
FAIL heap handle back to rc=1 after the parallel hammer
FAIL heap handle back to rc=1 after the array dropped it
```

All three read the count through the test's own
`RC(v) = PWord(Int64(Pointer(v)) - 16)^` helper — i.e. **through the very cast
that does the retaining**, which is why exactly the rc=1 rows fail and the
saturation rows pass.

## Where it came from

Track T's bisect: last good `645259ff18c0`, bad `1e37a55f6748`, and the ONE
buildable commit in that range is `b788c5865` *"one helper for the
string-to-pointer ownership seam, and the three that were still leaking"* —
the eighth instance of that shape, which introduced `IRParkManagedStr` and
made all eight sites call it.

That commit's own header says the mechanism: `IR_STORE_SYM` *"MOVES a fresh
call result and RETAINS anything else, so an already-owned value gains a
balanced retain/release rather than a second free."* **The retain is by
design; where its release is parked is the defect.** For a fresh temp the pair
is invisible. For an already-owned variable the retain lands now and the
release lands at scope exit, which is correct in a routine and wrong in the
main body.

Two directions worth weighing, and I do not have a recommendation between them:
skip the park entirely when the operand is already an owned symbol (nothing
needs parking — the symbol's own scope owns it), or keep it and release at the
end of the STATEMENT rather than the scope.

## Not claimed

The string-to-pointer seam is under active work by whoever landed
`b788c5865` — eight instances of one shape, deliberately being generalised.
Filed rather than fixed so the ninth instance is not me, working the same
question from the other end. It blocks
[[umbrella-one-full-tier-run-with-no-red-tier]].
