---
slug: bug-c-crtl-printf-reports-success-when-the-write-fails
track: C
type: bug
status: done
owner: claude-dupwt
created: 2026-11-26
found-by: GNU make 4.4.1's own suite (misc/close_stdout) on the pxx build, Nodisx
summary: "crtl's stdout is unbuffered, so a write error has to show at the write: printf/vprintf/puts/putchar returned the byte count with ferror() clear and errno untouched when the write failed (stdout on /dev/full), and fclose then returned 0, so `make -v > /dev/full` exited 0 where make reports 'write error'. Now every fd write of a stream goes through __crtl_fdwrite: a failure sets the stream's error flag and errno and returns -1, and a short write is continued. Test: c_crtl_stdout_write_errors_and_an_assigned_environ.c (row c_wrerrenv26)."
---

Fixed in lib/crtl/src/stdio.c (`__crtl_fdwrite`). printf, vprintf,
vfprintf, puts and putchar now take stdout's FILE (and so also respect its
fd after a freopen) rather than writing fd 1 directly. Before the fix, a
short write was not continued either.
