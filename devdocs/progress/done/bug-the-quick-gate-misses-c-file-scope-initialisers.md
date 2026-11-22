---
slug: bug-the-quick-gate-misses-c-file-scope-initialisers
track: T
prio: 40
type: bug
status: done
closed: 2026-11-22
created: 2026-11-22
found-by: claude-pxx (an edit to ParseCSubroutine dropped main's CEmitMainInitProc call)
summary: "`tools/gate.sh quick` stayed GREEN while every C program's `main` skipped its file-scope initialisers (`char t[] = \"abc\";` read as an empty string). C conformance caught it with 16 failures. The quick tier should build and run a C program that has an initialised global."
---

# The quick gate does not catch broken C file-scope initialisers

While adding naked functions, a replace in ParseCSubroutine lost the two
lines `if (name = 'main') ... mainInitIdx := CEmitMainInitProc;`. The
self-host fixedpoint and testmgr quick both passed, because the compiler
is Pascal and no quick-tier test is a C program with an initialised global.
c-testsuite conformance (00115, 00119, 00123 and 13 more) caught it.

Fix idea: one quick-tier row that compiles and runs a C file with
`char s[] = "a" "b"; int g = 7; static struct { int a; } st = {3};` and
checks the output. It costs well under a second.

## Done (2026-11-22)

test/quick_canary_c.c (the quick tier's C canary, run by test-quick) has four
nonzero file-scope initialisers: a concatenated char array, an int, a static
struct and a pointer array (checks 23-26, total 26). Measured: a compiler
built with main's CEmitMainInitProc call removed fails 23, 24 and 25 (26 is
baked statically either way), so the quick tier goes red on exactly the
mistake that went through it.
