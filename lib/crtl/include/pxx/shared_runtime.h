/* SPDX-License-Identifier: Zlib */
/*
 * pxx: forced into every translation unit compiled with --shared-runtime.
 *
 * The object then carries one undefined reference to __PXXRT_MARKER
 * (__pxxrt_needed_<target>[_ts], predefined by the compiler), which only the
 * runtime object defines. pxx --link sees it and adds the runtime itself;
 * ld or gcc without the runtime fail with "undefined reference to
 * __pxxrt_needed_x86_64", which names what is missing.
 * decide-a-is-a-pxx-object-a-self-contained-runtime-or-a-translation-unit
 */
#ifndef PXX_CRTL_PXX_SHARED_RUNTIME_H
#define PXX_CRTL_PXX_SHARED_RUNTIME_H 1

extern char __PXXRT_MARKER;
static char *const __pxxrt_marker_ref __attribute__((used)) = &__PXXRT_MARKER;

#endif
