---
slug: feature-crtl-pthread-types-in-sys-types-h
track: crtl
prio: 55
type: feature
status: done
owner: pxx2
created: 2026-11-28
closed: 2026-11-28
found-by: pxx2 (umbrella-pxx-compiles-systemd slice 1: pthread_mutex_t / pthread_t in a struct, 39 units)
tags: [crtl, pthread, systemd]
summary: "POSIX puts the pthread_*_t types in <sys/types.h>, and glibc does (bits/pthreadtypes.h); crtl had them only in <pthread.h>. systemd declares structs holding a pthread_mutex_t with only <sys/types.h> in scope. The twelve typedefs and their pad macros moved unchanged to a types-only <pxx/pthreadtypes.h>, included by <pthread.h> and <sys/types.h>; the functions, and the auto-pull of src/pthread.c, stay with <pthread.h>. Test c_ptty26: a struct of eight pthread types from <sys/types.h> alone, sizes against gcc."
---

# pthread types in <sys/types.h>
