#include "../../real-world-miniz/upstream/miniz.h"
#include "../../real-world-miniz/upstream/miniz_zip.h"

typedef unsigned int u32;

void reset_heap(void);

static unsigned char alpha_data[257];
static unsigned char beta_data[1024];
static unsigned char gamma_data[1536];
static unsigned char extract_alpha[257];
static unsigned char extract_beta[1024];
static unsigned char extract_gamma[1536];

static const char alpha_name[] = "docs/alpha.txt";
static const char beta_name[] = "bin/beta.bin";
static const char gamma_name[] = "gamma.dat";

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

static void fill_inputs(void) {
    fill_alpha();
    fill_beta();
    fill_gamma();
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

static int build_archive(
    int level,
    void **archive_buffer,
    size_t *archive_size,
    mz_zip_archive *writer
) {
    mz_bool ok = MZ_FALSE;

    *archive_buffer = 0;
    *archive_size = 0;
    mz_zip_zero_struct(writer);

    if (!mz_zip_writer_init_heap(writer, 0, 0)) {
        return -1001;
    }

    ok = mz_zip_writer_add_mem(
        writer,
        alpha_name,
        alpha_data,
        sizeof(alpha_data),
        (mz_uint)level
    );
    if (!ok) {
        mz_zip_writer_end(writer);
        return -1002 - (int)mz_zip_get_last_error(writer);
    }

    ok = mz_zip_writer_add_mem(
        writer,
        beta_name,
        beta_data,
        sizeof(beta_data),
        (mz_uint)level
    );
    if (!ok) {
        mz_zip_writer_end(writer);
        return -1003 - (int)mz_zip_get_last_error(writer);
    }

    ok = mz_zip_writer_add_mem(
        writer,
        gamma_name,
        gamma_data,
        sizeof(gamma_data),
        (mz_uint)level
    );
    if (!ok) {
        mz_zip_writer_end(writer);
        return -1004 - (int)mz_zip_get_last_error(writer);
    }

    if (!mz_zip_writer_finalize_heap_archive(writer, archive_buffer, archive_size)) {
        mz_zip_writer_end(writer);
        return -1005 - (int)mz_zip_get_last_error(writer);
    }

    return 0;
}

static int validate_archive(
    int level,
    int *out_hash,
    int *out_num_files,
    int *out_archive_size,
    int *out_locate_mix,
    int *out_extract_hash,
    int *out_validate
) {
    void *archive_buffer = 0;
    size_t archive_size = 0;
    mz_zip_archive writer;
    mz_zip_archive reader;
    mz_zip_archive_file_stat stat;
    mz_bool ok = MZ_FALSE;
    mz_uint num_files = 0;
    int alpha_index = -1;
    int beta_index = -1;
    int gamma_index = -1;
    int hash = 0;
    int build_status = 0;

    reset_heap();
    fill_inputs();

    build_status = build_archive(level, &archive_buffer, &archive_size, &writer);
    if (build_status != 0) {
        return build_status;
    }

    mz_zip_zero_struct(&reader);
    if (!mz_zip_reader_init_mem(&reader, archive_buffer, archive_size, 0)) {
        mz_zip_writer_end(&writer);
        return -2001 - (int)mz_zip_get_last_error(&reader);
    }

    num_files = mz_zip_reader_get_num_files(&reader);
    if (num_files != 3u) {
        mz_zip_reader_end(&reader);
        mz_zip_writer_end(&writer);
        return -2002 - (int)num_files;
    }

    alpha_index = mz_zip_reader_locate_file(&reader, alpha_name, 0, 0);
    beta_index = mz_zip_reader_locate_file(&reader, beta_name, 0, 0);
    gamma_index = mz_zip_reader_locate_file(&reader, gamma_name, 0, 0);
    if ((alpha_index < 0) || (beta_index < 0) || (gamma_index < 0)) {
        mz_zip_reader_end(&reader);
        mz_zip_writer_end(&writer);
        return -2003;
    }

    ok = mz_zip_reader_file_stat(&reader, (mz_uint)alpha_index, &stat);
    if ((!ok) || (stat.m_uncomp_size != sizeof(alpha_data))) {
        mz_zip_reader_end(&reader);
        mz_zip_writer_end(&writer);
        return -2004;
    }

    ok = mz_zip_reader_extract_to_mem(&reader, (mz_uint)alpha_index, extract_alpha, sizeof(extract_alpha), 0);
    if ((!ok) || (memcmp(extract_alpha, alpha_data, sizeof(alpha_data)) != 0)) {
        mz_zip_reader_end(&reader);
        mz_zip_writer_end(&writer);
        return -2005;
    }

    ok = mz_zip_reader_extract_to_mem(&reader, (mz_uint)beta_index, extract_beta, sizeof(extract_beta), 0);
    if ((!ok) || (memcmp(extract_beta, beta_data, sizeof(beta_data)) != 0)) {
        mz_zip_reader_end(&reader);
        mz_zip_writer_end(&writer);
        return -2006;
    }

    ok = mz_zip_reader_extract_to_mem(&reader, (mz_uint)gamma_index, extract_gamma, sizeof(extract_gamma), 0);
    if ((!ok) || (memcmp(extract_gamma, gamma_data, sizeof(gamma_data)) != 0)) {
        mz_zip_reader_end(&reader);
        mz_zip_writer_end(&writer);
        return -2007;
    }

    ok = mz_zip_validate_archive(&reader, MZ_ZIP_FLAG_VALIDATE_LOCATE_FILE_FLAG);
    if (!ok) {
        mz_zip_reader_end(&reader);
        mz_zip_writer_end(&writer);
        return -2008 - (int)mz_zip_get_last_error(&reader);
    }

    hash = fold_bytes((const unsigned char *)archive_buffer, archive_size, 0x811C9DC5u);
    hash = fold_text(alpha_name, (u32)hash);
    hash = fold_text(beta_name, (u32)hash);
    hash = fold_text(gamma_name, (u32)hash);
    hash ^= fold_bytes(extract_alpha, sizeof(extract_alpha), 0x12345678u);
    hash ^= fold_bytes(extract_beta, sizeof(extract_beta), 0x9ABCDEF0u);
    hash ^= fold_bytes(extract_gamma, sizeof(extract_gamma), 0x0F1E2D3Cu);
    hash ^= (int)mz_crc32(MZ_CRC32_INIT, (const mz_uint8 *)archive_buffer, archive_size);
    hash ^= (int)mz_adler32(MZ_ADLER32_INIT, (const mz_uint8 *)archive_buffer, archive_size);
    hash ^= (int)mz_zip_get_central_dir_size(&reader);
    hash ^= ((alpha_index & 0xFF) << 16) ^ ((beta_index & 0xFF) << 8) ^ (gamma_index & 0xFF);
    hash ^= (int)num_files;

    *out_hash = hash;
    *out_num_files = (int)num_files;
    *out_archive_size = (int)archive_size;
    *out_locate_mix = ((alpha_index & 0xFF) << 16) | ((beta_index & 0xFF) << 8) | (gamma_index & 0xFF);
    *out_extract_hash =
        fold_bytes(extract_alpha, sizeof(extract_alpha), 0xCAFEBABEu) ^
        fold_bytes(extract_beta, sizeof(extract_beta), 0x13579BDFu) ^
        fold_bytes(extract_gamma, sizeof(extract_gamma), 0x2468ACE0u);
    *out_validate = 1;

    mz_zip_reader_end(&reader);
    mz_zip_writer_end(&writer);
    return 0;
}

int miniz_full_hash(int level) {
    int hash = 0;
    int num_files = 0;
    int archive_size = 0;
    int locate_mix = 0;
    int extract_hash = 0;
    int validate = 0;
    int status = validate_archive(level, &hash, &num_files, &archive_size, &locate_mix, &extract_hash, &validate);
    if (status != 0) {
        return status;
    }
    return hash;
}

int miniz_full_probe_num_files(int level) {
    int hash = 0;
    int num_files = 0;
    int archive_size = 0;
    int locate_mix = 0;
    int extract_hash = 0;
    int validate = 0;
    int status = validate_archive(level, &hash, &num_files, &archive_size, &locate_mix, &extract_hash, &validate);
    if (status != 0) {
        return status;
    }
    return num_files;
}

int miniz_full_probe_archive_size(int level) {
    int hash = 0;
    int num_files = 0;
    int archive_size = 0;
    int locate_mix = 0;
    int extract_hash = 0;
    int validate = 0;
    int status = validate_archive(level, &hash, &num_files, &archive_size, &locate_mix, &extract_hash, &validate);
    if (status != 0) {
        return status;
    }
    return archive_size;
}

int miniz_full_probe_locate_mix(int level) {
    int hash = 0;
    int num_files = 0;
    int archive_size = 0;
    int locate_mix = 0;
    int extract_hash = 0;
    int validate = 0;
    int status = validate_archive(level, &hash, &num_files, &archive_size, &locate_mix, &extract_hash, &validate);
    if (status != 0) {
        return status;
    }
    return locate_mix;
}

int miniz_full_probe_extract_hash(int level) {
    int hash = 0;
    int num_files = 0;
    int archive_size = 0;
    int locate_mix = 0;
    int extract_hash = 0;
    int validate = 0;
    int status = validate_archive(level, &hash, &num_files, &archive_size, &locate_mix, &extract_hash, &validate);
    if (status != 0) {
        return status;
    }
    return extract_hash;
}

int miniz_full_probe_validate(int level) {
    int hash = 0;
    int num_files = 0;
    int archive_size = 0;
    int locate_mix = 0;
    int extract_hash = 0;
    int validate = 0;
    int status = validate_archive(level, &hash, &num_files, &archive_size, &locate_mix, &extract_hash, &validate);
    if (status != 0) {
        return status;
    }
    return validate;
}
