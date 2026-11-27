---
title: "C preprocessor: an empty include file was reported \"not found\""
status: done
owner: claude-dupwt
prio: 70
area: cfront
---

Every include lookup (CPSearchInclude: an absolute path, the including
file's directory, -I, the system fallback) treated a hit as a non-empty
buffer. So a 0-byte header counted as not found, both for #include and for
__has_include and -include, which share the search. FreeBSD's LinuxKPI
ships its placeholder headers as empty files
(compat/linuxkpi/dummy/include/linux/kgdb.h and about forty more).
drm-kmod's DRM core includes them, so about 900 of 2100 GPU-driver compiles
failed on them in the first pxx census of Rainyday's drivers/gpu
(feature-nodisx-linux-gpu-drivers-built-by-pxx).

Fix (compiler/cpreproc.inc, CPLoadInclude): when the load comes back empty,
the file is opened and read for one byte. If it opens and reads 0 bytes (a
directory opens but its read fails), the slot holds a single newline,
which means the same thing to the preprocessor. Test row c_emptyhdr26.
