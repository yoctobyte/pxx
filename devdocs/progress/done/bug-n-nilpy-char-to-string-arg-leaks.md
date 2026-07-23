---
track: N
prio: 40
type: bug
---

# NilPy tyChar arg to a string parameter leaks one handle per call

A `tyChar` value passed to a `tyAnsiString` / `tyString` parameter is
converted to a 1-character managed string **in per-backend codegen**
(`AnsiStrFromLiteralAddr`) with **no owner**, so it leaks one ~32-byte
handle per call. The SHAPE-BLINDSPOT family
([[project_string_conversion_shape_blindspot_pattern]]).

## Minimal repro (`/tmp/r3.npy` shape)

```python
s = "abcdefgh"
i = 0
n = 0
while i < 5000:
    c = s[3]          # pystr_at -> tyChar (scalar, no leak)
    n = n + len(c)    # len(<tyChar>) -> pystr_len(const AnsiString):
                      #   char->string coercion allocates, never freed
    i = i + 1
print(n)
```

`-dPXX_LIBC_HEAP` + valgrind: **160,000 B / 5,000 blocks** definitely lost
(1 per iter). Narrowing (all `s = "abcdefgh"` in a 5000-loop):
- `c = s[i]; len(c)`  → LEAK (this bug)
- `c = s[i]; c == "d"` → clean (tyChar compared as char, no string coercion)
- `c = s[i]; ord(c)`   → clean
- `c = s[i]; c + "y"`  → clean (concat path already owns/releases)
- `len("x")` (real str) → clean

So the trigger is specifically **a tyChar VALUE reaching a string
parameter** (here via `len`), not subscript itself and not string len.

## Root cause

IR types `s[i]` as `tyChar` (`pystr_at` returns `Char`; pyparser.inc
~2388 `ASTTk[callNode] := Ord(tyChar)`). `len(c)` lowers to a direct call
of the AnsiString-taking helper with the raw `arg tk=3` (tyChar). The
char→string materialisation is done at **arg-emit time** in each backend:
ir_codegen.inc has the tyChar→string emit duplicated at ~2669, ~3289,
~4453, ~4511, ~4636 (`push rax` char code; `mov rdi,1`;
`IREmitCodeCall(AnsiStrFromLiteralAddr)`). None release the result after
the call → leak. Per-backend, so aarch64/arm/etc. leak the same way.

## Fix direction (preferred: IR-level, all backends)

Wrap the tyChar arg as `pystr_ofchar(char)` at the IR level (an
`AN_CALL` yielding `tyAnsiString`) so it becomes a materialised managed
string that flows through the owning-arg-temp path (fixed in 5d3693bb)
and is released at scope exit — the same trick the for-in string desugar
uses (pyparser.inc ~5364) and the WideChar→UTF8 arg wrap (ir.inc ~1948).
Gate `isNilPy` so Pascal/C char→string args keep their lowering and
self-host stays byte-identical.

**ATTEMPTED and FAILED 2026-07-23** (reverted): adding that wrap in
`IRLowerCallArg` right after the WideChar block **DOUBLED** the leak
(160 KB → 320 KB, 5000 → 10,000 blocks) while output stayed correct
(prints 5000). So `len()` (and likely other intrinsic-lowered string
builtins) does **NOT** route its arg through the standard
`argIsManagedTemp` owning-temp path that would release the wrapped
string — the `pystr_ofchar` rc=1 result leaks IN ADDITION to whatever
already leaked. Next attempt must first find how `len`/string-builtins
lower their args (they may special-case, bypassing IRLowerCallArg's
managed-temp block), and either route them through it or release the
materialised string there. Do NOT re-try the bare wrap without fixing
that path first. Dump IR of the repro (`--dump-ir`) and inspect the
`len` call's arg chain before/after.

## Impact

Pervasive in uforth (`chr(...)`, `s[i]` char handling), part of the
residual doloop RSS in [[bug-n-pyeval-per-exec-leaks]]. Not correctness —
pure leak; memcheck reports 0 errors on these.
