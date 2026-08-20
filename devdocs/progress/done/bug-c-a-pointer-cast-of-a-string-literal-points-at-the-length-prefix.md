---
track: C
prio: 80
type: bug
blocked-by: []
summary: "`(char*)\"abc\"` pointed 8 bytes low -- at the frozen string's LENGTH WORD, not its data -- so b[0] was 3 and printf(\"%s\", b) printed nothing. Silent, and `(char*)\"lit\"` is everywhere in real C. The uncast literal was correct, so the two spellings of one address disagreed."
status: done
owner: frank1-ACP
---

# A pointer cast of a string literal points at the length prefix

- **Track C** (`compiler/cparser.inc`, the cast path).
- Found 2026-08-20 by a gcc differential probe over C storage classes and
  qualifiers.

## The measurement

`gcc -O0` vs pxx at `df17e58d7`:

```c
const char *a = "abc";
char       *b = (char*)"abc";
char       *c = (char*)(void*)"abc";
```

| expression | gcc | pxx |
| --- | --- | --- |
| `b - a` | 0 | **-8** |
| `c - a` | 0 | **-8** |
| `b[0]` | 97 (`'a'`) | **3** — the length word |
| `strlen(b)` | 3 | **1** |
| `printf("%s", b)` | `abc` | **(empty)** |
| `((char*)"xyz")[1]` | `y` | **(a NUL)** |
| `a[0]` (uncast) | 97 | 97 |

Nothing crashed and nothing warned: the pointer was valid, just eight bytes
early, so the program read the length prefix as characters.

The probe reached it through `char * const p = (char*)"s2";`, which made it
look like a `const`-qualifier bug. It is not — `const` is irrelevant, and
chasing it was a detour worth recording: the narrowing that mattered was
printing the two POINTERS and diffing them, not trying more qualifier
spellings.

## Root cause — the skip lives at the consumers, not the producer

A string literal's IR value is the frozen string's **handle**, which points at
an 8-byte length prefix followed by the char data. Every place that needs a C
`char *` adds 8 itself, keyed on the node kind of its own operand:

- the assign path (`ir.inc`): `if CProgramMode and (ASTKind[ASTRight[node]] = AN_STR_LIT) and (lhsTk = tyPointer)`
- the return path: the same test on `ASTLeft[node]` with a pointer return type
- the call-argument marshalling: the same idea again

Three copies of one rule, each asking "is my operand literally an AN_STR_LIT?".
An `AN_PTR_CAST` in between is not one, so **all three missed simultaneously** —
which is why assignment, return and argument passing were wrong together and
looked like a single deep bug.

`devdocs/dev/normalise-dont-special-case.md` calls this exactly: a concept
reachable through two shapes, where the second path is the one that stays
broken. And `root-cause-over-microfix.md`'s counting rule applies — *two is a
smell, three is a design flaw*.

## The fix, and the one that should follow

In C a string literal already **is** a `char *` (C99 6.3.2.1p3), so a pointer
cast of one is an identity. The cast now yields the literal unchanged when the
target is a pointer, which removes a shape rather than adding a fourth copy of
the skip, and makes `(char*)"abc"` and `"abc"` the same node again — as the
language says they are.

The proper normalisation is one level deeper: lower a C string literal to its
DATA pointer at the producer and delete all three consumer skips. That is filed
as `refactor-c-string-literal-decay-belongs-at-the-producer` rather than done
here, because it touches every C string path at once and this session gates at
`--tier quick`; the C corpora (zlib, sqlite, quickjs, tcc, lua) are what would
actually judge it, and they run on Track T.

## Test

`test/cstring_literal_cast.c`, gcc-oracled: pointer identity against the uncast
literal for `(char*)`, `(char*)(void*)`, `(const char*)` and
`(unsigned char*)`; the bytes, the length and the rendering; a global
initialised through a cast; indexing a cast literal directly; a cast literal
returned from a function; passed as an argument; compared with `strcmp`; the
empty literal; and the uncast and adjacent-concatenation spellings that already
worked. The pinned binary prints `same -8 -8 -8 -8` / `bytes 3 0 0 0`.

## Gate

`make compiler/pascal26` fixedpoint converged after 1 round; `tools/gate.sh
quick` GREEN.
