/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CPYEXT_COMPILE_H
#define PXX_CPYEXT_COMPILE_H 1

/* pxx's stand-in for CPython's <compile.h>. Included by name from generated
 * extension source; exists so the include resolves.
 *
 * Declares nothing. There is no Python compiler in this runtime — an
 * extension is compiled ahead of time by cfront — so PyCode_*,
 * Py_CompileString and the CO_* code-object flags have no meaning here.
 * Source that reaches for them fails at compile with its own name, which is
 * the honest answer; a stub PyCodeObject would let it build and then be
 * wrong at run time. */

#endif /* PXX_CPYEXT_COMPILE_H */
