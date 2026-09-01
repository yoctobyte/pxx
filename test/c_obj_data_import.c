/* THE BUG THIS TICKET IS NAMED FOR, as a linkable object. `extern` used to be
   discarded at parse time, so this compiled to a private slot in THIS object's
   own .bss: the link succeeded and read the wrong memory, with no diagnostic
   anywhere. The caller defines the variable as 99. */
extern int somebody_elses_global;
int read_it(void) { return somebody_elses_global; }
