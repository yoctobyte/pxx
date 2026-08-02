/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CPYEXT_TRACEBACK_H
#define PXX_CPYEXT_TRACEBACK_H 1

/* pxx's stand-in for CPython's <traceback.h>. Included by name from generated
 * extension source; exists so the include resolves.
 *
 * Declares nothing. Tracebacks in this runtime are NilPy's own, raised by the
 * bridge from the extension's pending error (see PyErr_SetString and
 * __pxx_PyErr_Message in Python.h) — there is no PyTracebackObject to append
 * a frame to, so PyTraceBack_Here has nothing to be. */

#endif /* PXX_CPYEXT_TRACEBACK_H */
