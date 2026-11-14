---
track: B
tags: [C, cfront]
prio: 30
type: bug
blocked-by: []
summary: "A function prototype at block scope (`int main(void) { extern int f(void); ... f(); }`) does not declare f: the call fails with \"call to undeclared function: f\". This is valid C99 (6.2.1, 6.7.1), and gcc takes it with or without `extern`. Found writing test/c_extern_array_reserves_no_bss_use.c on 2026-11-13; the test declares at file scope instead."
status: done
owner: unassigned
---

# A block-scope function prototype is not a declaration

    int main(void) { extern int check_def(void); return check_def(); }

pxx reports `call to undeclared function: check_def`. The block-scope
`extern` VARIABLE form works (c_block_scope_extern_with_no_file_scope_declaration).
The function form needs the same route. The prototype should register the
function's signature (scoped to the block, or file-wide, as gcc in effect
does), so the call is typed.

## Resolved 2026-11-14

Fixed: CHoistBlockScopeExterns (pass 1, at a body's opening brace) also
registers a block-scope function prototype, `[extern] T name(params);` or the
first declarator of `T name(params), x;`, through ParseCSubroutine, as the
same line at file scope would be. A name already known as a routine is left
alone (CHoistBlockProto, cparser.inc).

Tests: test/c_block_scope_prototype.c, linked by gcc against
test/c_block_scope_prototype_other.c (row c_bsproto: `extern int f(int);`,
`int g(void), y = 2;`, a three-parameter prototype); and the `proto` line of
test/c_declarator_and_sizeof_shapes.c.

Found beside it, not fixed here: a function returning a struct by value
called across a pxx/gcc object boundary crashes, in both directions:
bug-c-a-struct-returned-by-value-across-a-gcc-object-boundary-crashes.
