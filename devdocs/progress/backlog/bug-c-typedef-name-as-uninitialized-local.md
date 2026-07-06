# C: uninitialized local named same as an in-scope typedef mis-parses

- **Type:** bug (cfront parser — declaration vs typedef disambiguation). Track C.
- **Priority:** HIGH — blocks the entire zlib bring-up; a common real-world C
  shadow (gcc/clang accept it silently).
- **Found:** 2026-07-06, zlib bring-up (feature-c-corpus-expansion step 2).

## Minimal repro (gcc exit 0; pxx `pascal26:2: error: expected C expression`)
```c
typedef struct { unsigned char op, bits; unsigned short val; } code;
static int h(void){ int code; int n=0; for(code=0;code<16;code++){ n+=code; } return n; }
int main(void){ return h()-120; }
```

## Exact trigger
A **local variable declaration `T code;` with NO initializer**, where `code` is
an in-scope `typedef` name, in an inner (block) scope. Legal C: the declarator
`code` reintroduces the identifier as an ordinary object, shadowing the typedef
for the rest of the block. pxx's C parser, after the type-specifier `int`, sees
the typedef-name `code` and treats it as (part of) the type / a non-declarator,
then hits `;` and reports "expected C expression".

Disambiguating cases that ALREADY parse (narrow the fix):
- `int code = 7;` (WITH initializer) — parses fine.
- `unsigned code` as a function PARAMETER — parses fine.
- `code global;` (using `code` AS the type) — parses fine.
So only the bare, initializer-less block-scope declaration is broken. Fix likely
in the C statement/declaration parser: when a type-specifier is already in hand,
an identifier that happens to be a typedef-name must be accepted as the
declarator (object name), same as the initialized path does.

## How it surfaced (real code)
zlib `inftrees.h`: `typedef struct {...} code;`. zlib `trees.c` (pulled after
inftrees.h in the amalgam) declares `int code;` and loops `for(code=0; ...)`.
Whole zlib runner fails to compile. See [[feature-c-corpus-zlib]].

## Gate
Repro compiles + runs exit 0 under pxx; zlib runner advances past trees.c.
