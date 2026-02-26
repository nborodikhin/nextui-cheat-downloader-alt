#include <stdio.h>
#include <string.h>
#include "miniz.h"

static int list_archive(const char *path) {
    mz_zip_archive zip = {0};
    if (!mz_zip_reader_init_file(&zip, path, 0)) {
        fprintf(stderr, "Failed to open %s\n", path);
        return 1;
    }

    int n = (int)mz_zip_reader_get_num_files(&zip);
    for (int i = 0; i < n; i++) {
        mz_zip_archive_file_stat stat;
        mz_zip_reader_file_stat(&zip, i, &stat);
        printf("%s\n", stat.m_filename);
    }

    mz_zip_reader_end(&zip);
    return 0;
}

static int extract_file(const char *archive, const char *inner, const char *output) {
    mz_zip_archive zip = {0};
    if (!mz_zip_reader_init_file(&zip, archive, 0)) {
        fprintf(stderr, "Failed to open %s\n", archive);
        return 1;
    }

    int index = mz_zip_reader_locate_file(&zip, inner, NULL, 0);
    if (index < 0) {
        fprintf(stderr, "File not found in archive: %s\n", inner);
        mz_zip_reader_end(&zip);
        return 1;
    }

    if (!mz_zip_reader_extract_to_file(&zip, index, output, 0)) {
        fprintf(stderr, "Failed to extract to %s\n", output);
        mz_zip_reader_end(&zip);
        return 1;
    }

    mz_zip_reader_end(&zip);
    return 0;
}

int main(int argc, char *argv[]) {
    if (argc >= 3 && strcmp(argv[1], "-l") == 0)
        return list_archive(argv[2]);

    if (argc >= 5 && strcmp(argv[1], "-x") == 0)
        return extract_file(argv[2], argv[3], argv[4]);

    fprintf(stderr, "Usage:\n");
    fprintf(stderr, "  %s -l <archive.zip>\n", argv[0]);
    fprintf(stderr, "  %s -x <archive.zip> <path/in/zip> <output_file>\n", argv[0]);
    return 1;
}
