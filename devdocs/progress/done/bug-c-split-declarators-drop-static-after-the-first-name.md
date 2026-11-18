---
track: C
tags: [cfront, declarations, storage-class, linkage, pathb, expat]
prio: 80
type: bug
blocked-by: []
summary: "`static HANDLER h0, h1;` (HANDLER a function typedef) split into `static HANDLER h0; HANDLER h1;`: every name after the first lost `static`, so its body was a second, local row and references stayed undefined externals. expat's xmlrole.c (41 PROLOG_HANDLERs) failed to link in the pxx X-client build."
status: done
owner: pxx2
---

# Split declarators dropped `static` after the first name

cparser.inc CSplitDeclarators: each split copy now repeats the storage-class
words in front of the type (the same CIsTopLevelSkipIdent walk the caller
consumed), so `static T a, b;` becomes `static T a; static T b;`.

Test: test/c_static_split_declarators.c (row c_ssdecl26) against gcc, x86-64
and i386, plus an --emit-obj object with no undefined h0..h2.
