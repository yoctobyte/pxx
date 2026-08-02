/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CPYEXT_COMPILE_H
#define PXX_CPYEXT_COMPILE_H 1

/* pxx's stand-in for CPython's <compile.h>. Included by name from generated
 * extension source; exists so the include resolves.
 *
 * There is no Python compiler in this runtime — an extension is compiled ahead
 * of time by cfront — so PyCode_*, Py_CompileString and the code object itself
 * have no meaning here and are NOT declared. Source that reaches for them
 * fails with its own name, which is the honest answer; a stub PyCodeObject
 * would let it build and then be wrong at run time.
 *
 * The CO_* flags ARE defined, because they are not machinery: they are fixed,
 * published constants and their values are part of the source-level API.
 * Python.h defines them too (and must, since generated code tests for them
 * long before it includes this file — see the note there); the #ifndef keeps
 * the two from fighting. */

#ifndef CO_OPTIMIZED
#define CO_OPTIMIZED            0x0001
#define CO_NEWLOCALS            0x0002
#define CO_VARARGS              0x0004
#define CO_VARKEYWORDS          0x0008
#define CO_NESTED               0x0010
#define CO_GENERATOR            0x0020
#define CO_NOFREE               0x0040
#define CO_COROUTINE            0x0080
#define CO_ITERABLE_COROUTINE   0x0100
#define CO_ASYNC_GENERATOR      0x0200
#endif

#endif /* PXX_CPYEXT_COMPILE_H */
