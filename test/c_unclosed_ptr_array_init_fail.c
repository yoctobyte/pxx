/* Same bug, deferred pointer-array arm: an element the flat pre-scan cannot
   fold (a cast) routes to the defer path, whose brace skip exited on EOF with
   the braces still open and said nothing. */
int g;
void *p[] = { (void*)0, &g
int main(void){ return 0; }
