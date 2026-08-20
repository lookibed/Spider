#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define CGLTF_MALLOC(size) malloc(size)
#define CGLTF_FREE(ptr) free(ptr)
#define CGLTF_ATOI(str) atoi(str)
#define CGLTF_ATOF(str) atof(str)
#define CGLTF_ATOLL(str) ((long long)atof(str))
#define CGLTF_IMPLEMENTATION
#include "../upstream/cgltf.h"

void shim_reset_heap(void);

static cgltf_data *host_data = 0;
static uint8_t *host_bytes = 0;
static int host_length = 0;

int32_t cgltf_host_alloc(int32_t size) {
	if (size <= 0) {
		return 0;
	}

	return (int32_t)(intptr_t)malloc((size_t)size);
}

int32_t cgltf_host_load(int32_t bytes_ptr, int32_t bytes_len) {
	if (bytes_ptr == 0 || bytes_len <= 0) {
		return 0;
	}

	if (host_data) {
		cgltf_free(host_data);
		host_data = 0;
	}

	host_bytes = (uint8_t *)(intptr_t)bytes_ptr;
	host_length = bytes_len;
	return 1;
}

int32_t cgltf_host_parse(void) {
	cgltf_options options;

	if (!host_bytes || host_length <= 0) {
		return 0;
	}

	if (host_data) {
		cgltf_free(host_data);
		host_data = 0;
	}

	memset(&options, 0, sizeof(options));

	if (cgltf_parse(&options, host_bytes, (cgltf_size)host_length, &host_data) != cgltf_result_success) {
		return 0;
	}

	return 1;
}

int32_t cgltf_host_free(void) {
	if (host_data) {
		cgltf_free(host_data);
		host_data = 0;
	}

	host_bytes = 0;
	host_length = 0;
	return 1;
}

int32_t cgltf_host_get_mesh_count(void) {
	return host_data ? (int32_t)host_data->meshes_count : -1;
}

int32_t cgltf_host_get_animation_count(void) {
	return host_data ? (int32_t)host_data->animations_count : -1;
}

int32_t cgltf_host_get_node_count(void) {
	return host_data ? (int32_t)host_data->nodes_count : -1;
}

int32_t cgltf_host_get_skin_count(void) {
	return host_data ? (int32_t)host_data->skins_count : -1;
}

int32_t cgltf_host_get_scene_count(void) {
	return host_data ? (int32_t)host_data->scenes_count : -1;
}

int32_t cgltf_host_get_animation_name_len(int32_t index) {
	if (host_data && index >= 0 && (cgltf_size)index < host_data->animations_count) {
		const char *name = host_data->animations[index].name;
		return name ? (int32_t)strlen(name) : 0;
	}

	return -1;
}

int32_t cgltf_host_get_animation_name(int32_t index, int32_t out_ptr, int32_t out_cap) {
	if (host_data && index >= 0 && (cgltf_size)index < host_data->animations_count && out_ptr != 0) {
		const char *name = host_data->animations[index].name;
		char *out = (char *)(intptr_t)out_ptr;

		if (!name) {
			out[0] = 0;
			return 0;
		}

		size_t len = strlen(name);
		size_t copy = (size_t)out_cap < len + 1 ? (size_t)out_cap - 1 : len;

		memcpy(out, name, copy);
		out[copy < len ? copy : len] = 0;
		return (int32_t)len;
	}

	return -1;
}

int32_t cgltf_host_get_animation_channel_count(int32_t index) {
	if (host_data && index >= 0 && (cgltf_size)index < host_data->animations_count) {
		return (int32_t)host_data->animations[index].channels_count;
	}

	return -1;
}

int32_t cgltf_host_get_mesh_name_len(int32_t index) {
	if (host_data && index >= 0 && (cgltf_size)index < host_data->meshes_count) {
		const char *name = host_data->meshes[index].name;
		return name ? (int32_t)strlen(name) : 0;
	}

	return -1;
}

int32_t cgltf_host_get_mesh_name(int32_t index, int32_t out_ptr, int32_t out_cap) {
	if (host_data && index >= 0 && (cgltf_size)index < host_data->meshes_count && out_ptr != 0) {
		const char *name = host_data->meshes[index].name;
		char *out = (char *)(intptr_t)out_ptr;

		if (!name) {
			out[0] = 0;
			return 0;
		}

		size_t len = strlen(name);
		size_t copy = (size_t)out_cap < len + 1 ? (size_t)out_cap - 1 : len;

		memcpy(out, name, copy);
		out[copy < len ? copy : len] = 0;
		return (int32_t)len;
	}

	return -1;
}

int32_t cgltf_host_get_node_name_len(int32_t index) {
	if (host_data && index >= 0 && (cgltf_size)index < host_data->nodes_count) {
		const char *name = host_data->nodes[index].name;
		return name ? (int32_t)strlen(name) : 0;
	}

	return -1;
}

int32_t cgltf_host_get_node_name(int32_t index, int32_t out_ptr, int32_t out_cap) {
	if (host_data && index >= 0 && (cgltf_size)index < host_data->nodes_count && out_ptr != 0) {
		const char *name = host_data->nodes[index].name;
		char *out = (char *)(intptr_t)out_ptr;

		if (!name) {
			out[0] = 0;
			return 0;
		}

		size_t len = strlen(name);
		size_t copy = (size_t)out_cap < len + 1 ? (size_t)out_cap - 1 : len;

		memcpy(out, name, copy);
		out[copy < len ? copy : len] = 0;
		return (int32_t)len;
	}

	return -1;
}

int32_t cgltf_host_get_node_has_mesh(int32_t index) {
	if (host_data && index >= 0 && (cgltf_size)index < host_data->nodes_count) {
		return host_data->nodes[index].mesh ? 1 : 0;
	}

	return -1;
}

int32_t cgltf_host_get_node_has_skin(int32_t index) {
	if (host_data && index >= 0 && (cgltf_size)index < host_data->nodes_count) {
		return host_data->nodes[index].skin ? 1 : 0;
	}

	return -1;
}

int32_t cgltf_host_get_node_local_transform(int32_t index, int32_t out_ptr) {
	if (host_data && index >= 0 && (cgltf_size)index < host_data->nodes_count && out_ptr != 0) {
		cgltf_float *out = (cgltf_float *)(intptr_t)out_ptr;
		cgltf_node_transform_local(&host_data->nodes[index], out);
		return 1;
	}

	return -1;
}

int32_t cgltf_host_get_node_world_transform(int32_t index, int32_t out_ptr) {
	if (host_data && index >= 0 && (cgltf_size)index < host_data->nodes_count && out_ptr != 0) {
		cgltf_float *out = (cgltf_float *)(intptr_t)out_ptr;
		cgltf_node_transform_world(&host_data->nodes[index], out);
		return 1;
	}

	return -1;
}

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

int32_t cgltf_compute_hash(int32_t data_ptr, int32_t data_len) {
	cgltf_options options;
	cgltf_data *data = 0;
	const uint8_t *bytes = 0;
	uint32_t hash = 0x811C9DC5u;

	if (data_ptr == 0 || data_len <= 0) {
		return -1;
	}

	bytes = (const uint8_t *)(intptr_t)data_ptr;
	memset(&options, 0, sizeof(options));

	if (cgltf_parse(&options, bytes, (cgltf_size)data_len, &data) != cgltf_result_success) {
		return -2;
	}

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

	cgltf_free(data);
	return (int32_t)hash;
}
