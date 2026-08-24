---
track: A
prio: 35
type: bug
blocked-by: []
status: done
owner: claude-A
summary: "A .bas program with a string literal and no `uses` emits a call to PXXStrFromLit whose body is never emitted — the helper only arrives with builtinheap, which a unit-free BASIC program never pulls. Invisible today because nothing resolves this driver's forward calls: the call keeps its placeholder. Adding ApplyCallFixups to the BASIC driver turns it into `unresolved forward: PXXStrFromLit` at compile time, which is why that pass could not be added along with the entry-stub fix."
---

# A unit-free BASIC program calls `PXXStrFromLit` and never emits it

Found 2026-08-24 while fixing
[[bug-a-a-basic-program-is-an-illegal-instruction-on-aarch64-and-arm32]].

## Repro

```
$ cat > t.bas <<'X'
10 PRINT "hello"
X
$ compiler/pascal26 t.bas /tmp/t       # compiles, runs, prints hello
```

Now add the one line every other driver has at the end of its program
(`ApplyCallFixups;` after `EmitFinalizerRunnerBody;` in `ParseBProgram`) and the
same file fails:

```
pascal26:1: error: unresolved forward: PXXStrFromLit
```

`--debug` shows the row: `Proc 5: PXXStrFromLit at CodePos -1`. There is exactly
one such row, so this is not the two-registration-sites case — the body simply
never arrives.

## Why the body never arrives

`PXXStrFromLit` has two possible providers, and a unit-free `.bas` program gets
neither:

- **builtinheap's Pascal body** — pulled only when the program pulls the unit.
  `DetectPascalRuntimeNeeds` decides that by scanning for `uses` / `array` /
  `class` / a float token, which are Pascal questions a BASIC source never
  answers yes to.
- **the emitted x86-64 shims** (`EmitAnsiStringRuntime`) — gated on the same
  pre-scan's `needsAnsiRuntime`, which is `tkUses` or the
  `PXX_MANAGED_STRING` define. Also no.

Meanwhile BASIC's own string-literal codegen reaches the managed-string path and
emits the call. Calling `EmitAnsiStringRuntime` unconditionally on x86-64 does
NOT fix it — measured — so the missing provider is the builtinheap body, not the
shim set.

## Why it has never been visible

Nothing resolves the BASIC driver's forward calls. `ApplyCallFixups` is called
by the Pascal, C, NilPy, Rust, Zig and Erlang drivers and by `DceRun`; `DceRun`
is off unless `--dce` **and** x86-64 **and** the Pascal frontend, and `bparser`
never called the pass itself. So the call site keeps its placeholder for the
whole compile, and on x86-64 a placeholder is `call rel32=0`, which falls
through. The one program that emits this call happens not to execute it.

That placeholder is now a NOP on every target
([[bug-a-a-basic-program-is-an-illegal-instruction-on-aarch64-and-arm32]]), so
the fall-through is deliberate rather than accidental — but it is still a call
that silently does not happen.

## The fix is a scoping question, not a patch

Three candidates, and the right one is not obvious:

1. **Teach the pre-scan the frontend's own needs.** `DetectPascalRuntimeNeeds`
   is asked by three drivers and answers in Pascal tokens. A `needsAnsiRuntime`
   that also fires on "this frontend emits managed string literals" would fix
   BASIC and is honest about what the flag means.
2. **Pull builtinheap whenever a .bas program contains a string literal.** Costs
   every BASIC program the unit (test_basic_comprehensive already pulls it and
   is 105 KB against test_basic_lexer's 1.5 KB, so this is not free).
3. **Do not reach the managed-string path from BASIC at all** for a literal that
   is only printed — the driver has no managed variables to speak of.

Whichever is chosen, `ApplyCallFixups` should then be added to `ParseBProgram`
so the class cannot recur silently; that is
[[refactor-a-one-program-driver-prologue-for-every-frontend]]'s job anyway.

## Gate

Track A's, plus a unit-free `.bas` program with a string literal compiling with
`ApplyCallFixups` present in the BASIC driver, and the three existing `.bas`
tests unchanged on x86-64 / i386 / aarch64 / arm32.

## Resolved 2026-08-24 (claude-A) — the scoping question had a measured answer

The ticket says *"The fix is a scoping question, not a patch"* and lists three
candidates. Candidate 1 is right, and one measurement settles it — the ticket's
own framing was one step short of the cause.

### The predicate the drivers were using is a CONSTANT

`DetectPascalRuntimeNeeds` opens with

```pascal
  needsAnsiRuntime := PasDefineExists('PXX_MANAGED_STRING');
```

and `PasApplyDefaults` (`lexer.inc`) defines `PXX_MANAGED_STRING`
**unconditionally**, next to `PXX`, `CPU64`, `CPUX86_64` and `LINUX`. So
`needsAnsiRuntime` is `True` for every program ever compiled, in every frontend,
and the function's closing `if needsAnsiRuntime then needsHeap := True;` makes
`needsHeap` a constant too. Measured:

```
PROBE heap=TRUE ansi=TRUE div=FALSE    <- 10 PRINT "hello"
PROBE heap=TRUE ansi=TRUE div=FALSE    <- test_basic_comprehensive.bas
```

It is not a discriminator, it is a constant, and that is why a unit-free
`10 PRINT "hello"` got the AnsiString shims.

### And the shims are not self-contained

Every shim is a marshalling wrapper: `AnsiStrFromLiteralAddr` is nine pushes
around `EmitCallProc(FindProc('PXXStrFromLit'))`, and `PXXStrFromLit`'s BODY is
a **builtinheap** procedure. BASIC pulls builtinheap through exactly one door —
`USES <unit>` during the parse; unlike Pascal, C and NilPy it never calls
`ParseUsesUnitAmbient('builtinheap')` itself. So "may the shims be emitted" and
"does this source say USES" are the same question, and the second one is
answerable before the parse.

### The fix

`BSourceUsesAUnit` in `bparser.inc` — a scan of the driver's own token stream
for `tkUses` — is what feeds `wantAnsiRuntime`. That is candidate 1 (*"teach the
pre-scan the frontend's own needs"*) with the frontend answering for itself
rather than `DetectPascalRuntimeNeeds` being taught a new language.

With no dangling forward left to resolve, **`ApplyCallFixups` could finally be
added**, and the BASIC driver now takes the whole `EmitProgramEpilogue` like
every other driver — closing the last gap
[[refactor-a-one-program-driver-prologue-for-every-frontend]] recorded against
it.

### Measured

| program | before | after |
| --- | --- | --- |
| `10 PRINT "hello"` | 933 B | **559 B** |
| `test_basic_lexer.bas` | 1163 B | **789 B** |
| `test_basic_goto_gosub.bas` | 2708 B | **2334 B** |
| `test_basic_comprehensive.bas` (has USES) | 103935 B | 103935 B |

Output byte-identical to `pinned` on all three gated tests, on x86-64 and under
qemu on i386 / aarch64 / arm32. A unit-free program is *smaller* than before,
because it no longer carries shims it could never call.

### Test

`test/test_basic_unit_free_string_literal.bas`, wired into `test-core` natively
and on all three cross targets. The property is that it COMPILES; the file says
in its own header that adding a `USES` to it destroys the test.

### Two other BASIC bugs the same measurement turned up

Both reproduce on `pinned`, neither is caused by this change, both filed rather
than folded in:

- [[bug-a-basic-prints-a-string-variable-as-its-character-code]] — `DIM m = "x"`
  then `PRINT m` prints **120**. A silent wrong answer in a two-line program.
- [[bug-a-basic-string-concat-in-a-unit-free-program-is-a-compiler-error]] —
  `PRINT s + t` with no `USES` is `call to a runtime stub that was never
  emitted`. The sibling of this hole, one stub family over, and it needs the
  same decision this ticket just took — but it should wait on the one above,
  because BASIC's string-variable path may be mis-typed to begin with.

### Gate

`make compiler/pascal26` fixedpoint converged in one round; the three existing
`.bas` tests byte-identical to `pinned` on x86-64 / i386 / aarch64 / arm32; the
new test on all four; `tools/gate.sh quick` GREEN.

## Log
- 2026-08-24 — resolved, commit a95d75f89.
