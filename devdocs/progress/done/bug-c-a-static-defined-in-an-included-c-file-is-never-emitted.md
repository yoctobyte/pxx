---
slug: bug-c-a-static-defined-in-an-included-c-file-is-never-emitted
track: C
prio: 70
type: bug
status: done
created: 2026-11-14
found-by: claude-opus (toybox port)
tags: [c-frontend, toybox]
blocked-by: []
summary: "A `static` function prototyped in a .h and DEFINED in a .c that another .c #includes was never emitted: CPEnclosingCModule stopped at the first .c on the include stack, so the included .c's body was treated as belonging to a different module. It now walks outward past user .c files (only crtl paths end the walk). Reported by pixx-f2 for busybox (BZ2_*, xz_dec_*)."
---

# C: static defined in an #included .c

`cpreproc.inc` CPEnclosingCModule keeps walking past non-crtl `.c` frames;
`clexer.inc` checks the enclosing module before CPathIsCModule(path). Test:
`test/c_static_proto_in_header{.c,.h,_impl.c}` -- exe mode and
`--emit-obj` + `--link` both print 42.
