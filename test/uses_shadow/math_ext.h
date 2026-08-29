/* SPDX-License-Identifier: Zlib */
/* A SHADOW of lib/rtl/math_ext.h, reached only via -Futest/uses_shadow.

   It declares abs and deliberately omits labs, so "which file did the `uses`
   resolve to" is answerable from outside: a program calling labs compiles
   against the RTL header and fails against this one. That is the whole job.

   It exists because the ordering it pins has no other witness. A search root's
   C header must beat a compiler-anchored one (lib/rtl, lib/pcl) while losing
   to any Pascal unit anywhere — and when
   bug-a-a-c-include-path-captures-a-pascal-uses-and-emits-a-dynamic-import
   was first fixed, the first cut got the second half right and broke the
   first: -Futest/gtk3stock's gtk3_c.h started losing to lib/pcl/gtk3_c.h and
   the shadow was silently defeated. The gtk3stock test could not see it —
   both headers now include the installed GTK surface and produce
   byte-identical output — so it took a #error poison probe to find, which is
   exactly the kind of evidence a suite should not need a human to invent
   twice. */
int abs(int x);
