#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "../upstream/wasm3.h"

void shim_reset_heap(void);

static IM3Environment env = 0;
static IM3Runtime runtime = 0;
static IM3Module module = 0;
static uint8_t *host_wasm_bytes = 0;
static int host_wasm_len = 0;
static int32_t host_result = 0;
static int host_has_result = 0;
static char host_error[256];

#define STACK_SIZE (64 * 1024)

int32_t wasm3_host_alloc(int32_t size) {
	if (size <= 0) return 0;
	return (int32_t)(intptr_t)malloc((size_t)size);
}

int32_t wasm3_host_load_wasm(int32_t ptr, int32_t len) {
	if (ptr == 0 || len <= 0) return 0;
	host_wasm_bytes = (uint8_t *)(intptr_t)ptr;
	host_wasm_len = len;
	return 1;
}

int32_t wasm3_host_run(int32_t name_ptr, int32_t name_len) {
	M3Result result;

	if (!host_wasm_bytes || host_wasm_len <= 0) return -1;
	if (!name_ptr || name_len <= 0) return -1;

	host_result = 0;
	host_has_result = 0;
	host_error[0] = 0;

	if (runtime) { m3_FreeRuntime(runtime); runtime = 0; }
	if (env) { m3_FreeEnvironment(env); env = 0; }
	module = 0;

	env = m3_NewEnvironment();
	if (!env) return -2;

	runtime = m3_NewRuntime(env, STACK_SIZE, 0);
	if (!runtime) { m3_FreeEnvironment(env); env = 0; return -3; }

	result = m3_ParseModule(env, &module, host_wasm_bytes, host_wasm_len);
	if (result) {
		size_t len = strlen(result);
		if (len > 255) len = 255;
		memcpy(host_error, result, len);
		host_error[len] = 0;
		m3_FreeRuntime(runtime); runtime = 0;
		m3_FreeEnvironment(env); env = 0;
		return -4;
	}

	result = m3_LoadModule(runtime, module);
	if (result) {
		size_t len = strlen(result);
		if (len > 255) len = 255;
		memcpy(host_error, result, len);
		host_error[len] = 0;
		m3_FreeRuntime(runtime); runtime = 0;
		m3_FreeEnvironment(env); env = 0;
		return -5;
	}

	char *name = (char *)(intptr_t)name_ptr;
	char func_name[256];
	size_t copy_len = (size_t)name_len < 255 ? (size_t)name_len : 255;
	memcpy(func_name, name, copy_len);
	func_name[copy_len] = 0;

	IM3Function func;
	result = m3_FindFunction(&func, runtime, func_name);
	if (result) {
		m3_FreeRuntime(runtime); runtime = 0;
		m3_FreeEnvironment(env); env = 0;
		return -6;
	}

	result = m3_CallV(func);
	if (result) {
		m3_FreeRuntime(runtime); runtime = 0;
		m3_FreeEnvironment(env); env = 0;
		return -7;
	}

	uint32_t ret_count = m3_GetRetCount(func);
	if (ret_count > 0) {
		M3ValueType ret_type = m3_GetRetType(func, 0);
		if (ret_type == c_m3Type_i32) {
			uint32_t value = 0;
			m3_GetResultsV(func, &value);
			host_result = (int32_t)value;
			host_has_result = 1;
		}
	} else {
		host_has_result = 0;
	}

	return 1;
}

int32_t wasm3_host_get_result(void) {
	return host_has_result ? host_result : 0;
}

int32_t wasm3_host_has_result(void) {
	return host_has_result;
}

int32_t wasm3_host_get_error(int32_t out_ptr, int32_t out_cap) {
	if (!out_ptr || out_cap <= 0) return -1;
	char *out = (char *)(intptr_t)out_ptr;
	size_t len = strlen(host_error);
	size_t copy = len < (size_t)out_cap - 1 ? len : (size_t)out_cap - 1;
	memcpy(out, host_error, copy);
	out[copy] = 0;
	return (int32_t)len;
}

int32_t wasm3_host_free(void) {
	if (runtime) { m3_FreeRuntime(runtime); runtime = 0; }
	if (env) { m3_FreeEnvironment(env); env = 0; }
	module = 0;
	host_wasm_bytes = 0;
	host_wasm_len = 0;
	host_result = 0;
	host_has_result = 0;
	return 1;
}
