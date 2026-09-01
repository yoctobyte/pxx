/* The C 6.9.2 linkage matrix for --emit-obj, one translation unit per row.
   Every name here is a different ANSWER to "does this become an exported
   OBJECT, a LOCAL one, or an UND import", and the object's symbol table is the
   observable. Before the data-symbol work this TU produced exactly one symbol
   (a_function) and none of the five below.
   bug-a-an-object-neither-exports-nor-imports-data-symbols-and-links-silently-wrong */
int defined_initialised = 7;   /* a definition, external linkage */
int defined_tentative;         /* tentative definition: STILL a definition */
static int file_local = 3;     /* internal linkage: LOCAL, never exported */
extern int imported_elsewhere; /* every declaration said extern: UND import */
extern char incomplete_arr[];  /* an import whose SIZE lives in another TU */

int a_function(void)
{
  return defined_initialised + defined_tentative + file_local
       + imported_elsewhere + incomplete_arr[0];
}
