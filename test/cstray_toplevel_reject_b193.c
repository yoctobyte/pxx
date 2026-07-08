/* Regression (bug-c-comment-terminator-greedy): a block comment ends at the
 * FIRST `*/ /* ` so the words after it are real top-level tokens. gcc errors on
 * them; pxx used to silently skip unknown top-level tokens (ParseCProgram's
 * `else Next`), swallowing stray code between two comments. Now pxx must reject
 * an unknown identifier at top level. Expected: compile error
 * "stray token at top level". */
/* comment ends here void*/ stray tokens here */
int main(void) { return 0; }
