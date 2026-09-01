/* SPDX-License-Identifier: GPL-2.0 */
/*
 * busybox `cat` as ONE pxx translation unit -- the subject of
 * feature-c-corpus-busybox-applet, driven by tools/busybox_diff.sh.
 *
 * TWO JOBS NOW, and the second is why this file is not merely historical.
 * tools/busybox_diff.sh generates its unity from busybox_unstripped.map, so the
 * include list below is no longer the only copy -- but the PREAMBLE is. That
 * script reads everything down to and including the appletlib.c include out of
 * THIS file, verbatim, because the three facts recorded there (BB_GLOBAL_CONST,
 * NDEBUG/BB_VER provenance, and appletlib.c's load-bearing position) are the
 * hard-won part and a second copy would be the one that goes stale. It also
 * asserts, on every single-applet run, that the generated list equals the 24
 * members listed below -- the POSITIVE CONTROL that keeps the generator honest
 * against the translation unit rung 1's byte-identical claim was measured over.
 * So: edit the preamble here and the generator follows; edit the include list
 * here and the control will tell you whether you were right.
 *
 * This file is OURS; busybox's source is not vendored (library_candidates/ is
 * gitignored and gate.sh asserts nothing third-party is tracked). All it does
 * is #include the archive members a real single-applet link pulls, read off
 * busybox_unstripped.map: 25 of them, no more and no less. There is no harness
 * main -- appletlib.c's own main plus SINGLE_APPLET_MAIN cat_main is exactly
 * what the upstream busybox_CAT binary runs, so the comparison is between two
 * builds of the same program rather than between a program and a wrapper.
 *
 * pxx has no separate compilation yet, which is why this is a unity build. Two
 * things about busybox are load-bearing in that mode and are NOT in a real
 * link; both are handled below rather than by patching upstream.
 */
#define _GNU_SOURCE 1
/* Upstream's own documented knob (include/libbb.h:379): "set
   -DBB_GLOBAL_CONST='' in CONFIG_EXTRA_CFLAGS to disable". libbb.h declares
   ptr_to_globals const and libbb/ptr_to_globals.c re-declares it WRITABLE,
   which only works when they are separate translation units. In one TU the
   const declaration wins and the object lands in rodata -- gcc rejects the
   combination outright ("conflicting type qualifiers"), and we accepted it
   silently and then jumped into hyperspace when lbb_prepare wrote through it.
   Emptying BB_GLOBAL_CONST gives the whole unity the writable object a real
   link produces, using upstream's supported switch rather than a patch. */
#define BB_GLOBAL_CONST
#define NDEBUG 1
/* Overridable so the harness can pass the tree's real version; the fallback
   is the pinned tag. Nothing cat prints contains it -- BB_VER reaches only
   the usage/version text SHOW_USAGE builds -- so it is provenance, not
   output. */
#ifndef BB_VER
#define BB_VER "1.36.1"
#endif
#define BB_BT "0"
/* The version banner is "BusyBox v" BB_VER BB_EXTRA_VERSION (libbb/messages.c:14),
   and BB_EXTRA_VERSION defaults to " ("AUTOCONF_TIMESTAMP")" -- a string stamped
   into include/autoconf.h when the tree is CONFIGURED. Unpinned it makes the
   banner change on every reconfigure with identical sources, and it will not
   match the separately-linked upstream binary, because busybox deliberately
   does not rebuild the world when only that timestamp moves. Measured:
   autoconf.h stamped 19:09:43 and busybox relinked at 19:09:53, while
   libbb/messages.o stayed at 18:59:14 and kept the OLDER banner. Pinning it
   makes the comparison about the program rather than about when it was
   configured. `busybox --help' prints this string, so it is compared output,
   not decoration. */
#define BB_EXTRA_VERSION " (pxx-diff)"
#define KBUILD_BASENAME "busybox"
#define KBUILD_MODNAME "busybox"
#include "include/autoconf.h"
/* appletlib.c MUST come first. Its line 30 says why: "Define this accessor
   before we #define 'errno' our way" -- get_perrno() has to be compiled while
   errno is still the LIBC's, because libbb.h then redefines errno to
   (*bb_errno) and lbb_prepare fills bb_errno in from get_perrno(). Include
   any other libbb TU first and &errno is already &(*bb_errno), so get_perrno
   returns bb_errno itself: NULL, and the first bb_perror_msg segfaults. A
   real link never hits this because each .o is its own TU; a unity build is
   the one place the ordering is load-bearing.
   (pxx is immune either way: crtl's errno is a plain "extern int", not a
   macro, so libbb.h's "#if defined(errno)" is false, bb_errno never exists
   and every errno reference is the real variable -- the same path busybox
   takes on any libc that does not macro-define errno.) */
#include "libbb/appletlib.c"
#include "coreutils/cat.c"
#include "libbb/bb_cat.c"
#include "libbb/bb_strtonum.c"
#include "libbb/compare_string_array.c"
#include "libbb/copyfd.c"
#include "libbb/default_error_retval.c"
#include "libbb/full_write.c"
#include "libbb/getopt32.c"
#include "libbb/llist.c"
#include "libbb/messages.c"
#include "libbb/perror_msg.c"
#include "libbb/ptr_to_globals.c"
#include "libbb/read.c"
#include "libbb/safe_strncpy.c"
#include "libbb/safe_write.c"
#include "libbb/signals.c"
#include "libbb/time.c"
#include "libbb/verror_msg.c"
#include "libbb/wfopen.c"
#include "libbb/wfopen_input.c"
#include "libbb/xatonum.c"
#include "libbb/xfunc_die.c"
#include "libbb/xfuncs.c"
#include "libbb/xfuncs_printf.c"
