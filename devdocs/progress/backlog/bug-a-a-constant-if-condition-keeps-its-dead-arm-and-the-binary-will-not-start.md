---
track: A
prio: 70
type: bug
status: open
found: 2026-08-30
found-by: frankC
---

# A constant `if` condition keeps its dead arm, and the binary will not start

`jump_if_false` on a `const_int` is never folded, and the block it guards is
never pruned. The dead arm reaches codegen, so a call inside it becomes a real
external reference — and if that symbol is only ever *declared*, the program
gcc builds and runs fine becomes one that **fails at load**:

```
symbol lookup error: ./a.out: undefined symbol: NEVER_DEFINED_marker
```

Not a warning-level nuisance: the compiler does warn (`crtl does not define
...`), links anyway, and the binary dies before `main`.

## Repro

```c
int NEVER_DEFINED_marker(void);              /* declared, never defined */
static int pick(unsigned x) {
  if (1) return (int)x + 1;                  /* always taken */
  return NEVER_DEFINED_marker();             /* unreachable */
}
int main(void) { printf("%d\n", pick(41)); return 0; }
```

gcc prints `42`. pxx (default *and* `-O2`) emits the call and the binary will
not start.

## It is the IR, not a frontend

`PXXDBG=a.ir:pick` shows the condition is already a literal:

```
0: const_int ival=1
1: jump_if_false a=0            <- operand is a constant; never taken
...
BB4: 20: call a=394             <- survives to codegen anyway
```

The Pascal frontend reproduces it exactly (`if True then ... Exit;` then a call
to an `external name` that does not exist → same load failure), so this is
shared-IR ground and one fix covers every frontend.

## The boundary, measured

| shape | dead call emitted? |
| --- | --- |
| `return A; return NEVER();` | **no** — statement-level unreachable IS pruned |
| `if (1) return A; return NEVER();` | yes |
| `if (0) return NEVER(); return A;` | yes |
| `if (sizeof(unsigned) == 4) return A; return NEVER();` | yes |

So there is unreachable-code elimination, it just does not run after constant
folding: even a literal `if (1)` keeps both arms.

## Why it is worth 70

This is the pre-C11 static-assert idiom, and it is everywhere in real C.
busybox's `include/xatonum.h` uses it verbatim:

```c
uint32_t BUG_bb_strtou32_unimplemented(void);      /* never defined, anywhere */
static ALWAYS_INLINE uint32_t bb_strtou32(...) {
	if (sizeof(uint32_t) == sizeof(unsigned)) return bb_strtou(...);
	if (sizeof(uint32_t) == sizeof(unsigned long)) return bb_strtoul(...);
	return BUG_bb_strtou32_unimplemented();        /* the assert */
}
```

The first condition is true on every target we have, so gcc never references
the symbol. We do, and `busybox cat` therefore cannot start — found while
closing the TU set for `feature-c-corpus-busybox-applet`, which it blocks.
Defining the symbol in crtl would be the wrong fix twice over: it is busybox's
private assert, and the next corpus brings its own spelling.
