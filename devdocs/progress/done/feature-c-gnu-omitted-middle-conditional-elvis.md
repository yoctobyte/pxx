---
slug: feature-c-gnu-omitted-middle-conditional-elvis
title: "GNU omitted-middle conditional `x ?: y` is not parsed"
track: C
prio: 50
type: feature
blocked-by: []
status: done
owner: opus5-frank1
created: 2026-08-26
summary: "`x ?: y` — the GNU elvis operator — died as `expected C expression` because ParseCExpr's `?` arm always called ParseCCommaExpr for the middle. The value is x when x is true, and x is evaluated EXACTLY ONCE, so the then-arm cannot be a second copy of the condition node: bind it to a hidden temp, make the ASSIGNMENT the condition (an assign yields the stored value) and read the temp back as the then-arm. busybox editors/vi.c:791."
---

# `x ?: y`

Found compiling busybox 1.37.0, one of a four-file `expected C expression`
cluster. The other three are the `_IOW`/`_IOR` ioctl macro family — a
different cause; the shared symptom string is not a shared bug. Sibling
findings from the same sweep:
[[bug-c-a-ternary-cannot-be-the-callee-of-a-call]],
[[bug-c-logical-not-is-not-folded-in-a-constant-expression]],
[[feature-c-gcc-extended-inline-asm]].

## Repro

`editors/vi.c:791`:

```c
return col - ((col % tabstop) ?: tabstop);
```

Reduced:

```c
int printf(const char *, ...);
static int calls;
static int side(int v) { calls++; return v; }
int main(void) {
  int a = 0, b = 7;
  printf("%d %d\n", a ?: b, b ?: a);
  printf("%d\n", side(3) ?: 5);
  printf("%d\n", calls);
  return 0;
}
```

```
pascal26:6: error: expected C expression
```

gcc -O0 prints `7 7` / `3` / `1`.

## Cause

`ParseCExpr` (compiler/cparser.inc) handled `?` by unconditionally parsing a
middle operand:

```pascal
if CurTok.Kind = tkQuestion then
begin
  Next;
  thenE := ParseCCommaExpr();   { middle }
  Expect(tkColon, ':');
```

With the middle omitted, `CurTok` is already `:` and `ParseCCommaExpr` has
nothing to parse.

## Why the obvious fix is wrong

The tempting one-liner is `thenE := left` — reuse the condition node as the
then-arm. That is wrong on **evaluation count**: gcc evaluates the left
operand exactly once, and `calls` above proves it (0 -> 1 per `side()` call,
not 2). Duplicating the node makes the AST evaluate it twice, so
`side(3) ?: 5` would call `side` twice and any `f() ?: d` with a side effect
would silently run it again.

## Fix

Bind the condition to a hidden temp and let the **assignment** be the
condition — an `AN_ASSIGN` yields the stored value, so the truth test sees it
without a second evaluation — then read the temp back as the then-arm.
Everything downstream sees an ordinary `AN_TERNARY`, so `CTernaryResultTk`,
the `CNodeDecaysToPointer` pointer-result path and the ir.inc short-circuit
lowering all apply unchanged. `Syms[tmp].PtrElemRec` is carried over from the
condition so `(np ?: pp)->field` still resolves.

## Outcome

Landed in `ParseCExpr` (compiler/cparser.inc). `test/cternary_elvis.c`, wired
into `test-core`, oracled byte-for-byte against `gcc -O0`: int arms, the
once-only evaluation count, pointer arms with `->field` through the result,
char promotion, float arms, nesting, the busybox `vi.c` shape, and the else
arm's side effect.

One test row had to be split across two `printf`s: reading the side-effect
counter in the same call as the expression that bumps it tests the compiler's
argument evaluation order, which C leaves unspecified — the same trap that bit
[[bug-c-a-ternary-cannot-be-the-callee-of-a-call]].

Gates: c-conformance 220/0 (unchanged), `gate.sh quick` GREEN.

busybox: `editors/vi.c` clears line 791 and now reaches line 2446, where it
stops on `strncasecmp` — a crtl gap, not a compiler one. The four-file
`expected C expression` cluster is down to three, all of them the
`_IOW`/`_IOR` family, which measurement shows is *also* a crtl header gap
(pxx's `<sys/ioctl.h>` never defines the `_IO*` macros; busybox spells
`FDGETPRM` itself as `_IOR(2, 0x04, struct floppy_struct)` and expects the
header to supply the macro). Filed separately — not a compiler defect.


## Log
- 2026-08-26 — resolved, commit a08822ab3.
