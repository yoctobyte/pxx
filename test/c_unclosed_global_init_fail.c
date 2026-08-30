/* bug-c-an-unclosed-initializer-list-reports-the-next-error-instead-of-itself
   The aggregate arm: an unclosed global initializer used to CONSUME the rest of
   the file as initializer text, so main silently left the program and the error
   was "main function not found" -- naming a function that is right there on the
   next line. gcc: expected '}' before 'int'. */
int a[] = { 1, 2
int main(void){ return 0; }
