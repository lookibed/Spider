# `real-world-smollm2` Open Problem

Current state:

- `tests/manual/real-world-smollm2/` now exists as the first LLM fixture scaffold
- upstream `llama.cpp` is vendored into the fixture
- prompt fixture, Lua harness contracts, generated policy, and a narrow native reference runner are in place
- vendored `gguf` now has a local `gguf_init_from_buffer(const void * data, size_t size, ...)` path
- a tiny native `gguf_buffer_probe.cpp` exists to validate memory-backed metadata parsing on a real GGUF blob

Current blocker:

- Spider `lua-no-ffi` fixtures expect a standalone non-WASI wasm module
- the missing piece is no longer metadata parsing
- the remaining gap is the full in-memory model load path on top of `llama_model_init_from_user()`
- the fixture still needs a tensor-data callback that maps tensor names and offsets back into the owned GGUF byte blob

Why this matters:

- embedding a GGUF model into C bytes is still not enough if tensor payloads are not wired into the model structs
- `lua-no-ffi` cannot solve this by giving the wasm module a native filesystem path
- `llama-model-loader` already has a `files.empty()` path, so the next work should target that path directly instead of reworking file I/O again

Recommended next implementation target:

1. add a fixture-side owner for model bytes plus parsed `gguf_context`
2. implement `set_tensor_data(tensor, userdata)` using `gguf_find_tensor`, `gguf_get_data_offset`, `gguf_get_tensor_offset`, and `gguf_get_tensor_size`
3. validate full native `llama_model_init_from_user()` on a tiny `SmolLM 135M` GGUF first
4. only then move the same slice into standalone wasm and Spider

Recommended first model policy:

- start with `SmolLM 135M` base
- freeze one exact `GGUF` quantization for parity
- define parity on token ids, not decoded text
