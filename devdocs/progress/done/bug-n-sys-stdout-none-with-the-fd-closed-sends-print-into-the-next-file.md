---
summary: "RESOLVED 2026-11-25: `sys.stdout = None` points fd 1 at /dev/null with open + dup3 + close. When fd 1 was already closed (`prog >&-`), open() returned 1 itself, dup3(1, 1) failed with EINVAL, and the close shut fd 1 again. The next open() then took fd 1 and print() wrote into that file. The descriptor open() returns is now kept when it is the target fd."
type: bug
track: N
prio: 40
status: done
created: 2026-11-25
found-by: a local /code-review of pin v455
owner: claude-dupwt
tags: [nilpy, sys, stdio, fd]
blocked-by: []
---

compiler/builtin/pylib.pas, pysys_stream_to_none: `if nul = fd then Exit`.

Test: test_nilpy_stdout_none_with_fd_1_closed_keeps_print_out_of_files
(test-nilpy). The Makefile row runs it with `>&-` and compares stderr with
CPython's, `file holds: 'only this\n'`. Latest before the fix put the print()
line into the file.
