/* crtl's read buffer (fopen/fdopen/popen streams) must be invisible: every
   position, seek, write-after-read and direct fd use behaves as unbuffered.
   gcc-compared against glibc's stdio. feature-c-crtl-stdio-read-buffer */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>

static char path[64];

static void mkfile(int n) {
    FILE *f = fopen(path, "w");
    int i;
    for (i = 0; i < n; i++) fprintf(f, "line %05d abcdefghijklmnopqrstuvwxyz\n", i);
    fclose(f);
}

int main(void) {
    FILE *f;
    char buf[200], *big;
    int c, i, n;
    long pos;
    unsigned long sum;

    sprintf(path, "/tmp/pxx_c_crtl_read_buffer.%d", (int)getpid());
    mkfile(2000);   /* 74 KB: many buffer refills */

    /* fgetc over the whole file, checksum + count */
    f = fopen(path, "r");
    sum = 0; n = 0;
    while ((c = fgetc(f)) != EOF) { sum = sum * 31 + (unsigned)c; n++; }
    printf("fgetc n=%d sum=%lu eof=%d\n", n, sum, feof(f) != 0);

    /* ftell after partial reads; fseek SEEK_CUR relative to the logical spot */
    rewind(f);
    for (i = 0; i < 100; i++) fgetc(f);
    printf("ftell %ld\n", ftell(f));
    fseek(f, 10, SEEK_CUR);
    pos = ftell(f);
    c = fgetc(f);
    printf("after SEEK_CUR+10 ftell %ld c=%c\n", pos, c);
    fseek(f, -50, SEEK_CUR);
    fgets(buf, sizeof buf, f);
    printf("after SEEK_CUR-50 line [%s", buf);
    fseek(f, -5, SEEK_END);
    printf("SEEK_END-5 ftell %ld rest [", ftell(f));
    while ((c = fgetc(f)) != EOF) putchar(c == '\n' ? '|' : c);
    printf("]\n");

    /* ungetc on top of the buffer, and ftell with it */
    fseek(f, 37 * 3, SEEK_SET);
    c = fgetc(f);
    ungetc('X', f);
    pos = ftell(f);
    c = fgetc(f);
    i = fgetc(f);
    printf("ungetc ftell %ld got %c then %c\n", pos, c, i);

    /* fread: small pieces, then a large one straight past the buffer */
    rewind(f);
    n = (int)fread(buf, 1, 7, f);
    buf[n] = 0;
    printf("fread7 [%s] ftell %ld\n", buf, ftell(f));
    big = malloc(20000);
    n = (int)fread(big, 1, 20000, f);
    printf("fread20000 n=%d first=%c ftell %ld\n", n, big[0], ftell(f));
    n = (int)fread(big, 37, 3, f);
    printf("fread 37x3 n=%d [%.12s]\n", n, big);
    fseek(f, -10, SEEK_END);
    n = (int)fread(big, 1, 100, f);
    printf("fread past end n=%d eof=%d\n", n, feof(f) != 0);
    fclose(f);

    /* r+: read some, then write: the write lands at the logical position */
    f = fopen(path, "r+");
    fgets(buf, sizeof buf, f);
    fputs("LINE", f);
    fflush(f);
    fseek(f, 0, SEEK_SET);
    fgets(buf, sizeof buf, f);
    printf("r+ line0 [%s", buf);
    fgets(buf, sizeof buf, f);
    printf("r+ line1 [%s", buf);
    fgetc(f);
    fprintf(f, "%s", "##");
    fseek(f, 37 * 2, SEEK_SET);
    fgets(buf, sizeof buf, f);
    printf("r+ line2 [%s", buf);
    fclose(f);

    /* fflush on an input stream hands the fd back at the logical spot */
    f = fopen(path, "r");
    fgets(buf, sizeof buf, f);
    fflush(f);
    pos = lseek(fileno(f), 0, SEEK_CUR);
    printf("fflush: fd at %ld\n", pos);
    n = (int)read(fileno(f), buf, 10);
    buf[n] = 0;
    printf("read after fflush [%s]\n", buf);
    fclose(f);

    /* setvbuf(_IONBF): unbuffered from then on, fd follows each read */
    f = fopen(path, "r");
    printf("setvbuf IONBF %d\n", setvbuf(f, NULL, _IONBF, 0));
    fgetc(f); fgetc(f);
    printf("unbuffered fd at %ld\n", (long)lseek(fileno(f), 0, SEEK_CUR));
    fclose(f);

    /* fdopen on a descriptor, and popen (a pipe: no seeking) */
    f = fdopen(open(path, O_RDONLY), "r");
    n = 0;
    while (fgets(buf, sizeof buf, f)) n++;
    printf("fdopen lines %d\n", n);
    fclose(f);
    f = popen("printf 'a\\nbb\\nccc\\n'", "r");
    n = 0;
    while ((c = fgetc(f)) != EOF) n += c == '\n';
    printf("popen lines %d\n", n);
    pclose(f);

    remove(path);
    free(big);
    return 0;
}
