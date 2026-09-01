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

/* environ, which is the symptom this bug was REPORTED as (frankC, measured
   against a gcc dlopen host). It is a different mechanism from the static
   pointer above and fails separately: that one needs the file-scope
   initialisers to run at all, this one needs the ENVIRONMENT, and a .so has no
   Linux initial stack for __pxx_run_initializers to read -- at DT_INIT time rsp
   is inside ld.so. The loader passes (argc, argv, envp) instead, so the init
   thunk hands rdx to __pxx_set_environ.

   Returns the COUNT rather than a string: the host cannot know which variables
   are set, but "more than zero, and environ is not NULL" is checkable anywhere,
   and it was exactly (nil) before. */
extern char **environ;

int shared_c_envcount(void) {
  int n = 0;
  if (!environ) return -1;
  while (environ[n]) n++;
  return n;
}
