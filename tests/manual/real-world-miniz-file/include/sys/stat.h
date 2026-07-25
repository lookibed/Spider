#pragma once

struct stat {
    long long st_size;
};

int stat(const char *path, struct stat *buffer);
