#pragma once
#include <stddef.h>

typedef struct orca_regex orca_regex;

orca_regex *orca_regex_compile(const char *pattern, size_t len, int *err_code, size_t *err_offset);
void orca_regex_free(orca_regex *re);

/* Match result contract (security-sensitive — must not collapse errors to no-match):
 *   1  = match
 *   0  = no match (PCRE2_ERROR_NOMATCH only)
 *  <0  = infrastructure / match error (caller must fail closed)
 */
int orca_regex_is_match(orca_regex *re, const char *text, size_t len);
