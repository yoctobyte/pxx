---
track: C
tags: [c, initialiser, function-pointer, rump, netbsd, silent-miscompile]
prio: 10
type: bug
blocked-by: []
summary: "`void (*f)(struct proc *) = (void *)nullop;` left f zero, hosted and freestanding alike. The scalar function-pointer global arm knew only `func` and `&func`, and skipped anything else to the zero default. rump's rump_proc_vfs_init is exactly this, and the first lwproc_newproc at boot called through nil. A leading cast is now skipped when a function name ends the declarator."
status: done
owner: claude-dupwt
---

# A cast function name does not initialise a function-pointer global

The function-pointer path of `ParseCGlobalVarDecl` records a scalar
initialiser only when it is `func` or `&func`. Anything else goes to the skip,
which leaves the pointer at its zero default. With a cast in front of the
name, `= (void *)nullop;` or `= (fn_t)f;`, the pointer was 0 with no
diagnostic. `void *p = (void *)f`, `fp = f`, and every braced form (struct
tables, arrays, designated fields) were already correct.

Found booting a pxx-built librump: `rump.c` has
`rump_proc_vfs_init_fn rump_proc_vfs_init = (void *)nullop;`, and
`lwproc_newproc` called it during `rump_init`. pxx's nil check stopped it with
runtime error 216.

## Fix

If the initialiser starts with `(`, the arm finds the matching `)`. When an
identifier (optionally `&`) follows, and then `;` or `,`, it advances to the
identifier. If that identifier is a function, the existing arm binds it;
otherwise the parser rewinds. `(f)(x)` and `(void *)f + 1` still reach the
skip.

## Proof

`test/c_fnptr_global_cast_init.c`: four globals (a typedef'd function pointer
and a plain one, both via `(void *)`; a bare name; a `void *`), compared
against a gcc main. All four now hold `nullop`, hosted and freestanding
(previously `0 0 1 1`). Rows: c_fpcast26, c_fpcast26_f.
