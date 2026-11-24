---
slug: feature-c-ffile-prefix-map
track: C
prio: 50
type: feature
status: done
owner: pxx2
created: 2026-11-24
closed: 2026-11-24
found-by: pxx2, Path B on site (Nodisx): a build's bytes must not depend on its directory
tags: [cfront, preprocessor, reproducible]
summary: "gcc's -ffile-prefix-map=OLD=NEW and -fmacro-prefix-map=OLD=NEW: __FILE__ that starts with OLD reads NEW instead. Ordering as gcc 15.2: a matching -ffile- map beats every -fmacro- one, and within one kind the last given wins. pxx writes no debug info that names a directory, so __FILE__ is the one place a build path entered an object; the same source built from two directories with the same map now gives byte-identical objects and executables. test/c_file_prefix_map.c (c_fpmap26)."
---

# -ffile-prefix-map / -fmacro-prefix-map

Path B's on-site recipe (tools/pathb/onsite.sh) compiles on the target in
whatever directory the installer uses; the host records in another. With
every compile mapping the work dir to `/usr/src/pathb`, the bundle's bytes
do not depend on either.

Implementation: compiler.pas parses the options into CPrefixMap* (defs.inc,
16 at most); cpreproc.inc's CPMapPrefix rewrites CPCurPath when `__FILE__`
expands. Checked against gcc 15.2 for seven orders of overlapping maps.
