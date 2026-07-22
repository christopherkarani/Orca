/* Thin C helpers around PCRE2 for Zig shell_engine pack matching. */
#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    pcre2_code *code;
} orca_regex;

orca_regex *orca_regex_compile(const char *pattern, size_t len, int *err_code, size_t *err_offset) {
    int ec = 0;
    PCRE2_SIZE eo = 0;
    /* DOTALL so `.` matches newlines (heredoc bodies). UTF off (byte patterns). */
    uint32_t options = PCRE2_DOTALL;
    pcre2_code *code = pcre2_compile((PCRE2_SPTR)pattern, (PCRE2_SIZE)len, options, &ec, &eo, NULL);
    if (!code) {
        if (err_code) *err_code = ec;
        if (err_offset) *err_offset = (size_t)eo;
        return NULL;
    }
    orca_regex *re = (orca_regex *)malloc(sizeof(orca_regex));
    if (!re) {
        pcre2_code_free(code);
        return NULL;
    }
    re->code = code;
    return re;
}

void orca_regex_free(orca_regex *re) {
    if (!re) return;
    pcre2_code_free(re->code);
    free(re);
}

int orca_regex_is_match(orca_regex *re, const char *text, size_t len) {
    if (!re || !re->code) return 0;
    pcre2_match_data *md = pcre2_match_data_create_from_pattern(re->code, NULL);
    if (!md) return 0;
    int rc = pcre2_match(re->code, (PCRE2_SPTR)text, (PCRE2_SIZE)len, 0, 0, md, NULL);
    pcre2_match_data_free(md);
    return rc >= 0 ? 1 : 0;
}
