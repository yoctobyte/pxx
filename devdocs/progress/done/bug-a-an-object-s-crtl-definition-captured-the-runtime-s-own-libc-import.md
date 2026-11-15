---
slug: bug-a-an-object-s-crtl-definition-captured-the-runtime-s-own-libc-import
track: A
prio: 80
type: bug
status: done
created: 2026-11-15
found-by: pxx (Gibux seat), rump-pxx s13: nbdkeeper's NBD_DO_IT thread never started in the pxx-built usbhid
tags: [emit-obj, threadsafe, crtl, link]
blocked-by: []
summary: "pthread_create from a --threadsafe --emit-obj object never ran a thread. Four defects, in the order the repro peeled them: (1) crtl's body was exported as `pthread_create` while palthread's weak libc import has the same name, so every linker bound the import to crtl's own body, which re-entered PalThreadCreate and deadlocked on its registry lock. crtl's pthread.h now renames the pair to __pxx_crtl_pthread_create/_join, which keeps the family's one shared registry; ObjProcShadowsAnImport keeps any remaining same-named definition LOCAL (the dl* trio under -dPXX_DYNLIB_LIBC). (2) The thread then segfaulted: both the clone leg and PxxPthreadStart read the creator's TLS init image through gs, and nothing installs a main block in an object (gs = 0). Objects now size the user TLS area at 0, which TLSREFUSE_NOINSTALL already made unusable. (3) PxxPthreadStart is cdecl, so it was a STRONG global in every object and gcc refused two of them; palthread is now weak runtime like builtinheap. (4) pxx --link took that duplicate silently and kept one; it now refuses `multiple definition` as ld does. Test: test/c_obj_thread_{a,b}.c, rows c_objth (pxx --link, clone route) and c_objth_g (gcc, glibc's pthread_create)."
---

# An object's crtl definition captured the runtime's own libc import

Repro: `~/gibux/docs/rump-pxx/repros/s13_pthread_create_second_object/`.
`two_b.c` calls `pthread_create`; `two_a.c` holds `main`. Each was compiled
with `--emit-obj --threadsafe` and linked with `pxx --link` or gcc. It hung.
A single object linked by gcc hung the same way. Only a plain executable
worked.

## 1. The hang

In the object, `readelf -s` showed:

    WEAK  DEFAULT 1   pthread_create      <- crtl's body (lib/crtl/src/pthread.c)
    WEAK  DEFAULT UND pthread_create      <- palthread's c_pthread_create import

The linker binds the UND to the definition. The backtrace was
`pthread_create -> __pxx_pthread_create -> PalThreadCreate -> pthread_create
-> __pxx_pmutex_lock -> PalFutexWait`: crtl's own registry lock, already held
by the outer call. In an executable the import is a dynamic relocation and
crtl's body is internal, so the two never meet.

Making crtl's body LOCAL fixes the hang but splits the family. create and
join would be per object while detach and the rest stay merged, each with a
different static registry. A thread made in one object could then not be
joined from another. A `name@GLIBC_2.2.5` reference does not help either: ld
binds it to an unversioned definition in a regular object, and the
measurement recursed. The fix is in `lib/crtl/include/pthread.h`: crtl's link
names become `__pxx_crtl_pthread_create` and `__pxx_crtl_pthread_join`.
Every pxx C caller, `&pthread_create` included, is renamed with them.
gcc-compiled objects reach glibc's `pthread_create`, as they would anyway.

`ObjProcShadowsAnImport` (elfwriter.inc) is the guard for the general shape.
A routine whose name the same object imports from a library is not exported.
Today that covers crtl's dlopen/dlsym/dlclose against palthread's
`-dPXX_DYNLIB_LIBC` imports.

## 2. The segfault

With the import reaching glibc, the new thread faulted at
`PxxPthreadStart+96: mov %gs:0x0,%rax`, which reads the creator's init-image
slot. The clone route faulted the same way in its child leg (`mov r12,
gs:[8*TLS_SLOT_INIT_IMAGE]`). Nothing installs a main TLS block in an object,
because the entry is the host's crt. That is why every threadvar is refused
there (TLSREFUSE_NOINSTALL), and the main thread's gs base is 0. The area was
still sized at the default, though, so both readers copied an image through
a null base. `ApplyTlsUserBytesOption` now zeroes the area under
`--emit-obj`. `--shared` is unchanged, because a pxx host's threads do use
the area there.

## 3 and 4. The duplicate

`PxxPthreadStart` is `cdecl`, so `ObjProcIsExported` made it a STRONG global
in every object that reached it. gcc refused the pair with "multiple
definition". `palthread` now joins builtinheap, platform, platform_backend
and pxxcio in `ObjProcIsBuiltinRtl`: weak, not DCE-rooted, and one copy wins.
pxx `--link` had counted duplicates since the merge dump was written, but
only the dump reported them. `ElfLnkWriteExe` now refuses them, naming the
symbol and the first object that defined it.

## Not covered

A gcc link of `--shared-runtime` objects still needs the runtime object, as
before. Only pxx `--link` adds it.
