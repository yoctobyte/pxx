---
title: "C: a block-scope VLA typedef (`typedef char T[n];`)"
status: done
owner: claude-dupwt
prio: 80
area: cfront
---

A typedef with a run-time extent was folded with the variable read as 0. The
result was a silent miscompile: in `int n = argc + 4; typedef int row[n];
row r;`, sizeof(row) was 0 and r had no storage, so writing r[i] overwrote
the stack (gcc: 20 and a working array). When the fold came out negative, the
declaration was refused instead. LinuxKPI's BUILD_BUG_ON is
`while (0) { typedef char __assert_line_N[(x) ? 1 : -1]; ... }`, and i915's
__platform_mask_index passes it a run-time `pbits`. That was 222 refused
compiles in the sixth GPU-driver census
(feature-nodisx-linux-gpu-drivers-built-by-pxx), all at that one site.

C evaluates the extent at the typedef, once (6.7.8p3). In a block, the typedef
statement now reads the extent as an expression into a hidden Int64 local
(CTypedefReadDims, CTypedefVlaSym). A variable of the type takes the existing
alloca VLA path with that local as its extent, and sizeof(T) multiplies by it
at run time. Changing n after the typedef does not resize later variables,
and the test checks that. Only 1-D is supported, as for VLA variables. A
pointer to a VLA typedef is refused, not given the wrong stride. At file scope,
where a VLA typedef is invalid C anyway, nothing changed.

Test row c_vlatd26 (test/c_block_scope_vla_typedef.c), whose expected output
is gcc's.
