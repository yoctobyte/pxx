/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CPYEXT_FRAMEOBJECT_H
#define PXX_CPYEXT_FRAMEOBJECT_H 1

/* pxx's stand-in for CPython's <frameobject.h>. Included by name from
 * generated extension source; exists so the include resolves.
 *
 * Declares nothing. There are no Python frames here: an extension's functions
 * are native code with native stack frames, and pxx has no interpreter state
 * to hang a PyFrameObject off. Cython's profiling / line-tracing support and
 * its traceback-building helpers are what want this header, and both are
 * compiled out under the limited API. */

#endif /* PXX_CPYEXT_FRAMEOBJECT_H */
