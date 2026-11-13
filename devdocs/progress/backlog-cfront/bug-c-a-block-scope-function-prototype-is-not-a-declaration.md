---
track: B
tags: [C, cfront]
prio: 30
type: bug
blocked-by: []
summary: "A function prototype at block scope (`int main(void) { extern int f(void); ... f(); }`) does not declare f: the call fails with \"call to undeclared function: f\". This is valid C99 (6.2.1, 6.7.1), and gcc takes it with or without `extern`. Found writing test/c_extern_array_reserves_no_bss_use.c on 2026-11-13; the test declares at file scope instead."
status: backlog
owner: unassigned
---

# A block-scope function prototype is not a declaration

    int main(void) { extern int check_def(void); return check_def(); }

pxx reports `call to undeclared function: check_def`. The block-scope
`extern` VARIABLE form works (c_block_scope_extern_with_no_file_scope_declaration).
The function form needs the same route. The prototype should register the
function's signature (scoped to the block, or file-wide, as gcc in effect
does), so the call is typed.
