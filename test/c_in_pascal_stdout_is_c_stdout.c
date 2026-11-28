/* C's stdout/stderr inside a Pascal program are C's FILE pointers, not
   textfile.pas's `StdOut`/`StdErr: Text`: FindSym folds case and C's
   `extern FILE *stdout` was merged into the Pascal record, so `fp = stdout`
   stored the record (segfault at the first fprintf; refused as a struct
   operand since e17b4497b4). pdfgen's pdf_save(pdf, NULL) is this.
   bug-c-stdout-inside-a-pascal-program-binds-to-pascals-stdout-text */
#include <stdio.h>

static FILE *pick(int k) { FILE *fp; if (k) fp = stdout; else fp = stderr; return fp; }

int cso_run(void)
{
	FILE *o = pick(1), *e = pick(0);
	fprintf(o, "via fp: %d\n", 1);
	fflush(o);
	fprintf(e, "to stderr\n");
	return (o == stdout) * 10 + (e == stderr);
}
