/* --shared from a C translation unit, and specifically one with NO main.
   feature-a-shared-library-output-for-compiled-sources.

   This file exists because the Pascal test cannot see the defect it covers.
   When --shared first worked for compiled sources it reused --emit-obj's
   export surface but not --emit-obj's entry-stub guard, so the C frontend
   still demanded a `main` and refused a translation unit meant to BE a
   library:

       pascal26 --shared lib.c lib.so
       error: main function not found

   --emit-obj on the identical file succeeded, which is what named the bug: a
   shared library has no ELF entry point either, so the two modes had to agree
   and only one of them had been told.

   There is deliberately no main below. Adding one would make this file pass
   against the broken compiler, which is the whole thing it is here to
   prevent. */

int shared_c_addup(int n) { return n + 36; }

const char *shared_c_tag(void) { return "pxx-c-shared"; }

/* A file-scope pointer initialised to a string literal: an absolute pointer
   stored in .data, so it needs an R_X86_64_RELATIVE like the Pascal ones. Read
   through a function rather than exported directly, because a data symbol and
   a code symbol are relocated by different paths and this file is asserting
   the data one. */
static const char *shared_c_name = "pxx-c-data";

const char *shared_c_from_data(void) { return shared_c_name; }
