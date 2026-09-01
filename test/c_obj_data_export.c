/* The other direction: a global this object DEFINES must be visible to a
   foreign linker, and its initialiser must have run by the time a gcc-built
   main reads it (the .init_array path, asserted separately above). */
int shared_counter = 42;
int bump(void) { return ++shared_counter; }
