/* pxx cJSON test-suite runner (used by `make test-cjson`, NOT the base gate).
 * Amalgamates crtl + cJSON from library_candidates/cjson/src (gitignored 3rd-party
 * scratch) and round-trips a JSON document: read the file at PXX_CJSON_INPUT,
 * cJSON_Parse it, then cJSON_PrintUnformatted the result back to stdout. The
 * input document path is argv[1] (the Makefile passes each test/cjson/*.json case
 * directly); it falls back to the legacy fixed PXX_CJSON_INPUT when run with no
 * arg. Passing the path avoids a shared /tmp input file that races when the suite
 * runs under parallel test execution. Output diffed against the *.expected oracle.
 *
 * The round-trip is the free oracle: parse + canonical re-serialize exercises the
 * parser, object/array structs, heap (malloc/realloc/free), string handling, and
 * the number print path. Float number output additionally needs sscanf in crtl
 * (cJSON re-parses its own %g output to check round-trip precision); the first
 * fixtures stay integer/string/bool/null to isolate the frontend from that gap.
 *
 * Distinct from `make test`: the base gate carries no 3rd-party dependency, and
 * test-cjson skips gracefully when the cJSON tree is absent. */
#include "ctype.c"
#include "string.c"
#include "stdlib.c"
#include "stdio.c"
#include "math.c"
#include "locale.c"
#include "cJSON.c"

#define PXX_CJSON_INPUT "/tmp/pxx_cjson_input.json"
#define PXX_CJSON_MAX   (256 * 1024)

extern long __pxx_write(int, const void *, unsigned long);
static unsigned long slen(const char *s){ unsigned long n=0; while(s[n]) n++; return n; }
static void out(const char *s){ __pxx_write(1, s, slen(s)); }
static void err(const char *s){ __pxx_write(2, s, slen(s)); }

static char input[PXX_CJSON_MAX];

int main(int argc, char **argv) {
  const char *inpath = (argc > 1) ? argv[1] : PXX_CJSON_INPUT;
  FILE *f = fopen(inpath, "rb");
  size_t n;
  cJSON *root;
  char *printed;

  if (f == NULL) { err("OPEN-ERR\n"); return 2; }
  n = fread(input, 1, PXX_CJSON_MAX - 1, f);
  fclose(f);
  input[n] = '\0';

  root = cJSON_Parse(input);
  if (root == NULL) {
    err("PARSE-ERR\n");
    return 3;
  }

  printed = cJSON_PrintUnformatted(root);
  if (printed == NULL) {
    err("PRINT-ERR\n");
    cJSON_Delete(root);
    return 4;
  }

  out(printed);
  out("\n");

  cJSON_free(printed);
  cJSON_Delete(root);
  return 0;
}
