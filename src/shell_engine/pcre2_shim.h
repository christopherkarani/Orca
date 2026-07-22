#pragma once
#include <stddef.h>

typedef struct orca_regex orca_regex;

orca_regex *orca_regex_compile(const char *pattern, size_t len, int *err_code, size_t *err_offset);
void orca_regex_free(orca_regex *re);
int orca_regex_is_match(orca_regex *re, const char *text, size_t len);
