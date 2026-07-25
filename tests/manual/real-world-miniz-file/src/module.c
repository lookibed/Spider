#include "../../real-world-miniz/upstream/miniz.h"
#include "../../real-world-miniz/upstream/miniz_zip.h"

typedef unsigned int u32;

void reset_heap(void);
void spider_vfs_reset(void);
int spider_vfs_seed_file(const char *path, const void *data, size_t size);
const unsigned char *spider_vfs_get_file_data(const char *path);
int spider_vfs_get_file_size(const char *path);

static unsigned char alpha_data[257];
static unsigned char beta_data[1024];
static unsigned char gamma_data[1536];
static unsigned char extra_data[321];

static const char source_alpha_path[] = "src/alpha.bin";
static const char source_beta_path[] = "src/beta.bin";
static const char source_gamma_path[] = "src/gamma.bin";
static const char archive_path[] = "out/archive.zip";
static const char extract_alpha_path[] = "extract/alpha.bin";
static const char extract_beta_path[] = "extract/beta.bin";
static const char extract_gamma_path[] = "extract/gamma.bin";

static const char alpha_name[] = "docs/alpha.bin";
static const char beta_name[] = "bin/beta.bin";
static const char gamma_name[] = "gamma.bin";
static const char extra_name[] = "extra/mem.bin";

static void fill_alpha(void) {
    u32 i = 0;
    for (i = 0; i < (u32)sizeof(alpha_data); i++) {
        unsigned char value = (unsigned char)(((i * 29u) ^ (i >> 1) ^ 0x35u) & 0xFFu);
        if ((i & 7u) == 0u) {
            value = (unsigned char)(value ^ 0xA3u);
        }
        alpha_data[i] = value;
    }
}

static void fill_beta(void) {
    u32 i = 0;
    for (i = 0; i < (u32)sizeof(beta_data); i++) {
        unsigned char value = (unsigned char)(((i * i) + (i * 11u) + (i >> 2)) & 0xFFu);
        if ((i & 31u) < 11u) {
            value = (unsigned char)(value + 19u);
        } else {
            value = (unsigned char)(value ^ 0x5Cu);
        }
        beta_data[i] = value;
    }
}

static void fill_gamma(void) {
    u32 i = 0;
    for (i = 0; i < (u32)sizeof(gamma_data); i++) {
        unsigned char value = (unsigned char)(((i * 7u) ^ (i * 13u) ^ (i >> 3) ^ 0xC1u) & 0xFFu);
        if ((i % 9u) == 4u) {
            value = (unsigned char)(value ^ (unsigned char)(i & 0xFFu));
        }
        gamma_data[i] = value;
    }
}

static void fill_extra(void) {
    u32 i = 0;
    for (i = 0; i < (u32)sizeof(extra_data); i++) {
        unsigned char value = (unsigned char)(((i * 5u) ^ (i * 17u) ^ 0x6Du) & 0xFFu);
        if ((i & 15u) > 8u) {
            value = (unsigned char)(value + (unsigned char)(i & 0x1Fu));
        }
        extra_data[i] = value;
    }
}

static void seed_vfs(void) {
    fill_alpha();
    fill_beta();
    fill_gamma();
    fill_extra();

    spider_vfs_seed_file(source_alpha_path, alpha_data, sizeof(alpha_data));
    spider_vfs_seed_file(source_beta_path, beta_data, sizeof(beta_data));
    spider_vfs_seed_file(source_gamma_path, gamma_data, sizeof(gamma_data));
}

static int fold_bytes(const unsigned char *data, size_t size, u32 seed) {
    u32 hash = seed;
    size_t i = 0;

    for (i = 0; i < size; i++) {
        hash ^= data[i];
        hash *= 16777619u;
        hash = (hash << 7) | (hash >> 25);
        hash += 0x9E3779B9u;
    }

    return (int)hash;
}

static int fold_text(const char *text, u32 seed) {
    u32 hash = seed;
    size_t i = 0;
    while (text[i] != '\0') {
        hash ^= (unsigned char)text[i];
        hash *= 2166136261u;
        hash = (hash << 3) | (hash >> 29);
        i++;
    }
    return (int)hash;
}

static int run_full_file_cycle(int level, int *out_hash, int *out_files, int *out_archive_size, int *out_extract_hash, int *out_in_place) {
    mz_zip_archive archive;
    mz_zip_archive reader;
    mz_bool ok = MZ_FALSE;
    void *extra_heap = 0;
    size_t extra_size = 0;
    const unsigned char *archive_bytes = 0;
    const unsigned char *extract_alpha = 0;
    const unsigned char *extract_beta = 0;
    const unsigned char *extract_gamma = 0;
    int archive_size = 0;
    int hash = 0;
    mz_uint num_files = 0;

    reset_heap();
    spider_vfs_reset();
    seed_vfs();

    mz_zip_zero_struct(&archive);
    ok = mz_zip_writer_init_file(&archive, archive_path, 0);
    if (!ok) {
        return -1001 - (int)mz_zip_get_last_error(&archive);
    }

    ok = mz_zip_writer_add_file(&archive, alpha_name, source_alpha_path, 0, 0, (mz_uint)level);
    if (!ok) {
        mz_zip_writer_end(&archive);
        return -1002 - (int)mz_zip_get_last_error(&archive);
    }

    ok = mz_zip_writer_add_file(&archive, beta_name, source_beta_path, 0, 0, (mz_uint)level);
    if (!ok) {
        mz_zip_writer_end(&archive);
        return -1003 - (int)mz_zip_get_last_error(&archive);
    }

    ok = mz_zip_writer_add_file(&archive, gamma_name, source_gamma_path, 0, 0, (mz_uint)level);
    if (!ok) {
        mz_zip_writer_end(&archive);
        return -1004 - (int)mz_zip_get_last_error(&archive);
    }

    ok = mz_zip_writer_finalize_archive(&archive);
    if (!ok) {
        mz_zip_writer_end(&archive);
        return -1005 - (int)mz_zip_get_last_error(&archive);
    }

    mz_zip_writer_end(&archive);

    ok = mz_zip_add_mem_to_archive_file_in_place(
        archive_path,
        extra_name,
        extra_data,
        sizeof(extra_data),
        0,
        0,
        (mz_uint)level
    );
    if (!ok) {
        return -1006;
    }

    mz_zip_zero_struct(&reader);
    ok = mz_zip_reader_init_file(&reader, archive_path, 0);
    if (!ok) {
        return -2001 - (int)mz_zip_get_last_error(&reader);
    }

    num_files = mz_zip_reader_get_num_files(&reader);
    if (num_files != 4u) {
        mz_zip_reader_end(&reader);
        return -2002 - (int)num_files;
    }

    ok = mz_zip_validate_archive(&reader, MZ_ZIP_FLAG_VALIDATE_LOCATE_FILE_FLAG);
    if (!ok) {
        mz_zip_reader_end(&reader);
        return -2003 - (int)mz_zip_get_last_error(&reader);
    }

    ok = mz_zip_reader_extract_file_to_file(&reader, alpha_name, extract_alpha_path, 0);
    if (!ok) {
        mz_zip_reader_end(&reader);
        return -2004 - (int)mz_zip_get_last_error(&reader);
    }

    ok = mz_zip_reader_extract_file_to_file(&reader, beta_name, extract_beta_path, 0);
    if (!ok) {
        mz_zip_reader_end(&reader);
        return -2005 - (int)mz_zip_get_last_error(&reader);
    }

    ok = mz_zip_reader_extract_file_to_file(&reader, gamma_name, extract_gamma_path, 0);
    if (!ok) {
        mz_zip_reader_end(&reader);
        return -2006 - (int)mz_zip_get_last_error(&reader);
    }

    mz_zip_reader_end(&reader);

    extra_heap = mz_zip_extract_archive_file_to_heap(archive_path, extra_name, &extra_size, 0);
    if ((!extra_heap) || (extra_size != sizeof(extra_data)) || (memcmp(extra_heap, extra_data, sizeof(extra_data)) != 0)) {
        if (extra_heap) {
            mz_free(extra_heap);
        }
        return -2007;
    }

    archive_bytes = spider_vfs_get_file_data(archive_path);
    archive_size = spider_vfs_get_file_size(archive_path);
    extract_alpha = spider_vfs_get_file_data(extract_alpha_path);
    extract_beta = spider_vfs_get_file_data(extract_beta_path);
    extract_gamma = spider_vfs_get_file_data(extract_gamma_path);

    if ((!archive_bytes) || (!extract_alpha) || (!extract_beta) || (!extract_gamma)) {
        mz_free(extra_heap);
        return -2008;
    }

    if ((spider_vfs_get_file_size(extract_alpha_path) != (int)sizeof(alpha_data)) ||
        (spider_vfs_get_file_size(extract_beta_path) != (int)sizeof(beta_data)) ||
        (spider_vfs_get_file_size(extract_gamma_path) != (int)sizeof(gamma_data)) ||
        (memcmp(extract_alpha, alpha_data, sizeof(alpha_data)) != 0) ||
        (memcmp(extract_beta, beta_data, sizeof(beta_data)) != 0) ||
        (memcmp(extract_gamma, gamma_data, sizeof(gamma_data)) != 0)) {
        mz_free(extra_heap);
        return -2009;
    }

    hash = fold_bytes(archive_bytes, (size_t)archive_size, 0x811C9DC5u);
    hash = fold_text(alpha_name, (u32)hash);
    hash = fold_text(beta_name, (u32)hash);
    hash = fold_text(gamma_name, (u32)hash);
    hash = fold_text(extra_name, (u32)hash);
    hash ^= fold_bytes(extract_alpha, sizeof(alpha_data), 0x12345678u);
    hash ^= fold_bytes(extract_beta, sizeof(beta_data), 0x9ABCDEF0u);
    hash ^= fold_bytes(extract_gamma, sizeof(gamma_data), 0x0F1E2D3Cu);
    hash ^= fold_bytes((const unsigned char *)extra_heap, extra_size, 0xCAFEBABEu);
    hash ^= (int)mz_crc32(MZ_CRC32_INIT, archive_bytes, (size_t)archive_size);
    hash ^= (int)mz_adler32(MZ_ADLER32_INIT, archive_bytes, (size_t)archive_size);
    hash ^= archive_size;
    hash ^= (int)num_files;

    *out_hash = hash;
    *out_files = (int)num_files;
    *out_archive_size = archive_size;
    *out_extract_hash =
        fold_bytes(extract_alpha, sizeof(alpha_data), 0x13579BDFu) ^
        fold_bytes(extract_beta, sizeof(beta_data), 0x2468ACE0u) ^
        fold_bytes(extract_gamma, sizeof(gamma_data), 0xDEADBEEFu) ^
        fold_bytes((const unsigned char *)extra_heap, extra_size, 0x31415926u);
    *out_in_place = 1;

    mz_free(extra_heap);
    return 0;
}

int miniz_file_hash(int level) {
    int hash = 0;
    int files = 0;
    int archive_size = 0;
    int extract_hash = 0;
    int in_place = 0;
    int status = run_full_file_cycle(level, &hash, &files, &archive_size, &extract_hash, &in_place);
    if (status != 0) {
        return status;
    }
    return hash;
}

int miniz_file_probe_num_files(int level) {
    int hash = 0;
    int files = 0;
    int archive_size = 0;
    int extract_hash = 0;
    int in_place = 0;
    int status = run_full_file_cycle(level, &hash, &files, &archive_size, &extract_hash, &in_place);
    if (status != 0) {
        return status;
    }
    return files;
}

int miniz_file_probe_archive_size(int level) {
    int hash = 0;
    int files = 0;
    int archive_size = 0;
    int extract_hash = 0;
    int in_place = 0;
    int status = run_full_file_cycle(level, &hash, &files, &archive_size, &extract_hash, &in_place);
    if (status != 0) {
        return status;
    }
    return archive_size;
}

int miniz_file_probe_extract_hash(int level) {
    int hash = 0;
    int files = 0;
    int archive_size = 0;
    int extract_hash = 0;
    int in_place = 0;
    int status = run_full_file_cycle(level, &hash, &files, &archive_size, &extract_hash, &in_place);
    if (status != 0) {
        return status;
    }
    return extract_hash;
}

int miniz_file_probe_in_place(int level) {
    int hash = 0;
    int files = 0;
    int archive_size = 0;
    int extract_hash = 0;
    int in_place = 0;
    int status = run_full_file_cycle(level, &hash, &files, &archive_size, &extract_hash, &in_place);
    if (status != 0) {
        return status;
    }
    return in_place;
}
