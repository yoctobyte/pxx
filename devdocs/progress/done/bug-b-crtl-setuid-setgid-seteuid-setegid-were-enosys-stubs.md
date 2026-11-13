---
track: B
tags: [c, crtl, security, dropbear]
prio: 70
type: bug
blocked-by: []
summary: "crtl's setuid/setgid/seteuid/setegid were ENOSYS stubs, so a pxx-built server started as root could not drop to the logged-in user. They now go through the raw syscall bridge (the *32 numbers on i386/arm32), and setresuid/setresgid/setreuid/setregid/getresuid/getresgid were added. Per-thread semantics: there is no setxid broadcast."
status: done
owner: claude
---

# setuid and friends were ENOSYS stubs

Found building dropbear 2026.94 ([[feature-c-dropbear-builds-with-pxx]]). A
dropbear started as root (Gibux runs it that way) has to call setgid,
initgroups and setuid before it execs the user's shell.
lib/crtl/src/unistd.c had all four id setters as `errno = ENOSYS; return -1`.
dropbear checks the result and refuses the session. A program that does not
check would have run the user's shell as root.

They are now real, through `syscall()` as chroot already was:
setuid/setgid, and seteuid/setegid as setresuid/setresgid with -1 for the ids
that stay. Also added: setresuid, setresgid, setreuid, setregid, getresuid,
getresgid. On i386 and arm32 the *32 syscall numbers are used, because the
plain numbers there are the 16-bit-uid legacy calls.

**One thread only.** Linux applies these to the calling thread. glibc and musl
signal every other thread to repeat the call (setxid), which crtl does not do.
Every caller so far is single-threaded when it changes ids. Written in the
code comment so it is not rediscovered.

Test: test/c_crtl_dropbear_surface.c. Its rows are getresuid agreeing with
getuid/geteuid, setuid(own uid) == 0, and setuid(0) as non-root failing with
EPERM (it was ENOSYS).
