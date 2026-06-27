#include "stdio.c"

int main(void) {
  const char *path = "/tmp/pxx_crtl_file_stdio_b87.txt";
  char buf[8];
  FILE *f;
  long pos;

  remove(path);
  f = fopen(path, "wb");
  if (!f) return 1;
  if (fwrite("abcdef", 1, 6, f) != 6) return 2;
  pos = ftell(f);
  if (pos != 6) return 3;
  if (fclose(f) != 0) return 4;

  f = fopen(path, "rb");
  if (!f) return 5;
  if (fseek(f, 2, SEEK_SET) != 0) return 6;
  if (fread(buf, 1, 3, f) != 3) return 7;
  if (buf[0] != 'c' || buf[1] != 'd' || buf[2] != 'e') return 8;
  pos = ftell(f);
  if (pos != 5) return 9;
  rewind(f);
  if (fgetc(f) != 'a') return 10;
  if (fclose(f) != 0) return 11;
  if (remove(path) != 0) return 12;
  return 42;
}
