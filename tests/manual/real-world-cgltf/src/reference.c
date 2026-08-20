#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CGLTF_MALLOC(size) malloc(size)
#define CGLTF_FREE(ptr) free(ptr)
#define CGLTF_ATOI(str) atoi(str)
#define CGLTF_ATOF(str) atof(str)
#define CGLTF_ATOLL(str) ((long long)atof(str))
#define CGLTF_IMPLEMENTATION
#include "../upstream/cgltf.h"

static uint32_t rotl32(uint32_t value, unsigned int shift) {
	return (value << shift) | (value >> (32u - shift));
}

static uint32_t hash_bytes(const uint8_t *bytes, size_t length) {
	uint32_t hash = 0x811C9DC5u;

	for (size_t i = 0; i < length; i++) {
		hash ^= bytes[i];
		hash *= 16777619u;
		hash = rotl32(hash, 5u);
	}

	return hash;
}

static uint32_t hash_string(const char *str) {
	if (!str) {
		return 0xDEADC0DEu;
	}

	return hash_bytes((const uint8_t *)str, strlen(str));
}

int main(int argc, char **argv) {
	if (argc < 2) {
		fprintf(stderr, "usage: %s <file.glb>\n", argv[0]);
		return 1;
	}

	FILE *file = fopen(argv[1], "rb");
	if (!file) {
		fprintf(stderr, "failed to open %s\n", argv[1]);
		return 1;
	}

	fseek(file, 0, SEEK_END);
	long size = ftell(file);
	fseek(file, 0, SEEK_SET);

	uint8_t *bytes = (uint8_t *)malloc((size_t)size);
	if (!bytes) {
		fprintf(stderr, "failed to allocate %ld bytes\n", size);
		fclose(file);
		return 1;
	}

	if (fread(bytes, 1, (size_t)size, file) != (size_t)size) {
		fprintf(stderr, "failed to read file\n");
		free(bytes);
		fclose(file);
		return 1;
	}

	fclose(file);

	cgltf_options options;
	memset(&options, 0, sizeof(options));

	cgltf_data *data = 0;
	cgltf_result result = cgltf_parse(&options, bytes, (cgltf_size)size, &data);

	if (result != cgltf_result_success) {
		fprintf(stderr, "failed to parse glb\n");
		free(bytes);
		return 1;
	}

	uint32_t hash = 0x811C9DC5u;

	hash ^= (uint32_t)data->meshes_count;
	hash = rotl32(hash, 3u);
	hash ^= (uint32_t)data->animations_count;
	hash = rotl32(hash, 3u);
	hash ^= (uint32_t)data->nodes_count;
	hash = rotl32(hash, 3u);
	hash ^= (uint32_t)data->skins_count;
	hash = rotl32(hash, 3u);
	hash ^= (uint32_t)data->scenes_count;
	hash = rotl32(hash, 3u);

	for (cgltf_size i = 0; i < data->meshes_count; i++) {
		uint32_t name_hash = hash_string(data->meshes[i].name);
		hash ^= name_hash + (uint32_t)(i * 0x9E3779B9u);
		hash = rotl32(hash, 7u);
	}

	for (cgltf_size i = 0; i < data->animations_count; i++) {
		uint32_t name_hash = hash_string(data->animations[i].name);
		hash ^= name_hash + (uint32_t)(i * 0x9E3779B9u);
		hash = rotl32(hash, 7u);
		hash ^= (uint32_t)data->animations[i].channels_count;
		hash = rotl32(hash, 3u);
	}

	for (cgltf_size i = 0; i < data->nodes_count; i++) {
		uint32_t name_hash = hash_string(data->nodes[i].name);
		hash ^= name_hash + (uint32_t)(i * 0x9E3779B9u);
		hash = rotl32(hash, 7u);
		if (data->nodes[i].mesh) {
			hash ^= 0x4D455348u;
			hash = rotl32(hash, 3u);
		}
		if (data->nodes[i].skin) {
			hash ^= 0x534B494Eu;
			hash = rotl32(hash, 3u);
		}
	}

	printf("Result (MeshCount): %d\n", (int)data->meshes_count);
	printf("Result (AnimationCount): %d\n", (int)data->animations_count);
	printf("Result (NodeCount): %d\n", (int)data->nodes_count);
	printf("Result (SkinCount): %d\n", (int)data->skins_count);
	printf("Result (SceneCount): %d\n", (int)data->scenes_count);

	for (cgltf_size i = 0; i < data->animations_count; i++) {
		printf("Result (AnimationChannelCount%u): %d\n", (unsigned)i, (int)data->animations[i].channels_count);
	}

	for (cgltf_size i = 0; i < data->meshes_count; i++) {
		const char *name = data->meshes[i].name;
		printf("Result (MeshName%u): %s\n", (unsigned)i, name ? name : "");
	}

	for (cgltf_size i = 0; i < data->nodes_count; i++) {
		const char *name = data->nodes[i].name;
		const char *mesh_flag = data->nodes[i].mesh ? " MESH" : "";
		const char *skin_flag = data->nodes[i].skin ? " SKIN" : "";
		printf("Result (Node%u): %s%s%s\n", (unsigned)i, name ? name : "", mesh_flag, skin_flag);
	}

	int32_t hash_signed = (int32_t)hash;
	printf("Result (Hash): %ld\n", (long)hash_signed);

	cgltf_free(data);
	free(bytes);
	return 0;
}
