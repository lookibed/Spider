//! Wasmtime-backed host runner for fixture-specific manual workflows.

use core::error::Error;
use std::env;
use std::ffi::OsString;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use wasmtime::{Engine, Instance, Memory, Module, Store, TypedFunc};

type DynError = Box<dyn Error>;
type RunnerResult<T> = Result<T, DynError>;

#[derive(Clone, Copy, Eq, PartialEq)]
enum FixtureKind {
	Plmpeg,
	Binjgb,
	LibjpegTurboMjpeg,
	H264Mp4,
	Cgltf,
}

#[derive(Clone, Copy, Eq, PartialEq)]
enum RunnerMode {
	Baseline,
	Stream,
}

struct Args {
	fixture: FixtureKind,
	mode: RunnerMode,
	wasm_path: PathBuf,
	input_path: PathBuf,
	max_frames: usize,
	output_dir: Option<PathBuf>,
}

struct Summary {
	decoded_frames: usize,
	width: i32,
	height: i32,
	rgb_size: i32,
}

struct WasmExports {
	fixture: FixtureKind,
	memory: Memory,
	host_alloc: TypedFunc<i32, i32>,
	host_load: TypedFunc<(i32, i32), i32>,
	host_decode_frame: TypedFunc<i32, i32>,
	host_get_width: TypedFunc<(), i32>,
	host_get_height: TypedFunc<(), i32>,
	host_reset: Option<TypedFunc<(), i32>>,
	host_get_rgb_ptr: Option<TypedFunc<(), i32>>,
	host_get_rgb_size: Option<TypedFunc<(), i32>>,
	host_get_framebuffer_ptr: Option<TypedFunc<(), i32>>,
	host_get_framebuffer_size: Option<TypedFunc<(), i32>>,
	host_get_y_ptr: Option<TypedFunc<(), i32>>,
	host_get_u_ptr: Option<TypedFunc<(), i32>>,
	host_get_v_ptr: Option<TypedFunc<(), i32>>,
	host_get_y_size: Option<TypedFunc<(), i32>>,
	host_get_u_size: Option<TypedFunc<(), i32>>,
	host_get_v_size: Option<TypedFunc<(), i32>>,
	host_stream_begin: Option<TypedFunc<(), i32>>,
	host_stream_decode_next: Option<TypedFunc<(), i32>>,
	host_stream_end: Option<TypedFunc<(), i32>>,
	host_stream_get_frame_index: Option<TypedFunc<(), i32>>,
}

struct CgltfExports {
	memory: Memory,
	host_alloc: TypedFunc<i32, i32>,
	host_load: TypedFunc<(i32, i32), i32>,
	host_parse: TypedFunc<(), i32>,
	host_free: TypedFunc<(), i32>,
	get_mesh_count: TypedFunc<(), i32>,
	get_animation_count: TypedFunc<(), i32>,
	get_node_count: TypedFunc<(), i32>,
	get_skin_count: TypedFunc<(), i32>,
	get_scene_count: TypedFunc<(), i32>,
	get_anim_chan_count: TypedFunc<i32, i32>,
	get_node_has_mesh: TypedFunc<i32, i32>,
	get_node_has_skin: TypedFunc<i32, i32>,
	get_mesh_name_len: TypedFunc<i32, i32>,
	get_mesh_name: TypedFunc<(i32, i32, i32), i32>,
	get_node_name_len: TypedFunc<i32, i32>,
	get_node_name: TypedFunc<(i32, i32, i32), i32>,
	compute_hash: TypedFunc<(i32, i32), i32>,
}

struct FrameData {
	frame_index: usize,
	width: i32,
	height: i32,
	rgb_size: i32,
	rgb_bytes: Vec<u8>,
}

fn main() -> RunnerResult<()> {
	let arguments: Vec<OsString> = env::args_os().skip(1).collect();
	let args = parse_args(&arguments)?;
	let summary = run(&args)?;

	println!("Decoded Frames: {}", summary.decoded_frames);
	println!("Width: {}", summary.width);
	println!("Height: {}", summary.height);
	println!("RGB Size: {}", summary.rgb_size);
	Ok(())
}

fn parse_args(args: &[OsString]) -> RunnerResult<Args> {
	let mut fixture = FixtureKind::Plmpeg;
	let mut mode = None;
	let mut wasm_path = None;
	let mut input_path = None;
	let mut max_frames = 240_usize;
	let mut output_dir = None;
	let mut index = 0_usize;

	while index < args.len() {
		let current = args[index].to_str().ok_or_else(|| {
			io::Error::new(
				io::ErrorKind::InvalidInput,
				"arguments should be valid UTF-8",
			)
		})?;

		match current {
			"--fixture" => {
				let value = next_arg(args, index, "--fixture")?;
				fixture = parse_fixture(value)?;
				index += 2;
			}
			"--mode" => {
				let value = next_arg(args, index, "--mode")?;
				mode = Some(parse_mode(value)?);
				index += 2;
			}
			"--wasm" => {
				let value = next_arg(args, index, "--wasm")?;
				wasm_path = Some(PathBuf::from(value));
				index += 2;
			}
			"--input" => {
				let value = next_arg(args, index, "--input")?;
				input_path = Some(PathBuf::from(value));
				index += 2;
			}
			"--frames" => {
				let value = next_arg(args, index, "--frames")?;
				max_frames = value.parse::<usize>()?;
				index += 2;
			}
			"--output-dir" => {
				let value = next_arg(args, index, "--output-dir")?;
				output_dir = Some(PathBuf::from(value));
				index += 2;
			}
			"--help" | "-h" => {
				print_help();
				std::process::exit(0);
			}
			_ => {
				return Err(io::Error::new(
					io::ErrorKind::InvalidInput,
					format!("unknown argument: {current}"),
				)
				.into());
			}
		}
	}

	let parsed_mode = if fixture == FixtureKind::Cgltf {
		RunnerMode::Baseline
	} else {
		mode.ok_or_else(|| {
			io::Error::new(
				io::ErrorKind::InvalidInput,
				"missing required argument: --mode baseline|stream",
			)
		})?
	};
	let parsed_wasm_path = wasm_path.ok_or_else(|| {
		io::Error::new(
			io::ErrorKind::InvalidInput,
			"missing required argument: --wasm <path>",
		)
	})?;
	let parsed_input_path = input_path.ok_or_else(|| {
		io::Error::new(
			io::ErrorKind::InvalidInput,
			"missing required argument: --input <path>",
		)
	})?;

	if (fixture == FixtureKind::H264Mp4 || fixture == FixtureKind::LibjpegTurboMjpeg)
		&& parsed_mode == RunnerMode::Stream
	{
		return Err(io::Error::new(
			io::ErrorKind::InvalidInput,
			"fixture currently supports only --mode baseline",
		)
		.into());
	}

	Ok(Args {
		fixture,
		mode: parsed_mode,
		wasm_path: parsed_wasm_path,
		input_path: parsed_input_path,
		max_frames,
		output_dir,
	})
}

fn next_arg<'args>(args: &'args [OsString], index: usize, flag: &str) -> RunnerResult<&'args str> {
	args.get(index + 1)
		.ok_or_else(|| {
			io::Error::new(
				io::ErrorKind::InvalidInput,
				format!("missing value after {flag}"),
			)
		})?
		.to_str()
		.ok_or_else(|| {
			io::Error::new(
				io::ErrorKind::InvalidInput,
				format!("{flag} value should be valid UTF-8"),
			)
			.into()
		})
}

fn parse_fixture(fixture: &str) -> RunnerResult<FixtureKind> {
	match fixture {
		"plmpeg" => Ok(FixtureKind::Plmpeg),
		"binjgb" | "gbc" => Ok(FixtureKind::Binjgb),
		"libjpeg-turbo-mjpeg" | "libjpegturbo-mjpeg" | "mjpeg" => {
			Ok(FixtureKind::LibjpegTurboMjpeg)
		}
		"h264mp4" => Ok(FixtureKind::H264Mp4),
		"cgltf" => Ok(FixtureKind::Cgltf),
		_ => Err(io::Error::new(
			io::ErrorKind::InvalidInput,
			format!("unsupported fixture: {fixture}"),
		)
		.into()),
	}
}

fn parse_mode(mode: &str) -> RunnerResult<RunnerMode> {
	match mode {
		"baseline" => Ok(RunnerMode::Baseline),
		"stream" => Ok(RunnerMode::Stream),
		_ => Err(io::Error::new(
			io::ErrorKind::InvalidInput,
			format!("unsupported mode: {mode}"),
		)
		.into()),
	}
}

fn print_help() {
	println!("Usage:");
	println!(
		"  cargo run -p wasmtime-host-runner -- --fixture plmpeg --mode baseline --wasm <path> --input <path> --frames 100"
	);
	println!(
		"  cargo run -p wasmtime-host-runner -- --fixture plmpeg --mode stream --wasm <path> --input <path> --frames 100"
	);
	println!(
		"  cargo run -p wasmtime-host-runner -- --fixture binjgb --mode baseline --wasm <path> --input <path> --frames 16"
	);
	println!(
		"  cargo run -p wasmtime-host-runner -- --fixture libjpeg-turbo-mjpeg --mode baseline --wasm <path> --input <path> --frames 12"
	);
	println!(
		"  cargo run -p wasmtime-host-runner -- --fixture h264mp4 --mode baseline --wasm <path> --input <path> --frames 12"
	);
	println!("Optional:");
	println!("  --output-dir <path>   Write decoded PPM frames for visual inspection");
}

fn run(args: &Args) -> RunnerResult<Summary> {
	if args.fixture == FixtureKind::Cgltf {
		return run_cgltf(args);
	}

	let engine = Engine::default();
	let module = Module::from_file(&engine, &args.wasm_path)?;
	let mut store = Store::new(&engine, ());
	let instance = Instance::new(&mut store, &module, &[])?;
	let exports = load_exports(&mut store, &instance, args.fixture)?;
	let input_bytes = fs::read(&args.input_path)?;

	match args.mode {
		RunnerMode::Baseline => run_baseline(
			&mut store,
			&exports,
			&args.input_path,
			&input_bytes,
			args.max_frames,
			args.output_dir.as_deref(),
		),
		RunnerMode::Stream => run_stream(
			&mut store,
			&exports,
			&args.input_path,
			&input_bytes,
			args.max_frames,
			args.output_dir.as_deref(),
		),
	}
}

fn load_exports(
	store: &mut Store<()>,
	instance: &Instance,
	fixture: FixtureKind,
) -> RunnerResult<WasmExports> {
	let memory = instance
		.get_memory(&mut *store, "memory")
		.ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "missing exported memory"))?;

	match fixture {
		FixtureKind::Plmpeg => load_plmpeg_exports(store, instance, memory),
		FixtureKind::LibjpegTurboMjpeg => load_libjpeg_turbo_mjpeg_exports(store, instance, memory),
		FixtureKind::Binjgb => load_binjgb_exports(store, instance, memory),
		FixtureKind::H264Mp4 => load_h264mp4_exports(store, instance, memory),
		FixtureKind::Cgltf => {
			Err(io::Error::other("cgltf is handled separately in run_cgltf").into())
		}
	}
}

fn load_plmpeg_exports(
	store: &mut Store<()>,
	instance: &Instance,
	memory: Memory,
) -> RunnerResult<WasmExports> {
	Ok(WasmExports {
		fixture: FixtureKind::Plmpeg,
		memory,
		host_alloc: instance.get_typed_func::<i32, i32>(&mut *store, "plmpeg_host_alloc")?,
		host_load: instance.get_typed_func::<(i32, i32), i32>(&mut *store, "plmpeg_host_load")?,
		host_decode_frame: instance
			.get_typed_func::<i32, i32>(&mut *store, "plmpeg_host_decode_frame")?,
		host_get_width: instance.get_typed_func::<(), i32>(&mut *store, "plmpeg_host_get_width")?,
		host_get_height: instance
			.get_typed_func::<(), i32>(&mut *store, "plmpeg_host_get_height")?,
		host_reset: instance
			.get_typed_func::<(), i32>(&mut *store, "plmpeg_host_reset")
			.ok(),
		host_get_rgb_ptr: instance
			.get_typed_func::<(), i32>(&mut *store, "plmpeg_host_get_rgb_ptr")
			.ok(),
		host_get_rgb_size: instance
			.get_typed_func::<(), i32>(&mut *store, "plmpeg_host_get_rgb_size")
			.ok(),
		host_get_framebuffer_ptr: None,
		host_get_framebuffer_size: None,
		host_get_y_ptr: None,
		host_get_u_ptr: None,
		host_get_v_ptr: None,
		host_get_y_size: None,
		host_get_u_size: None,
		host_get_v_size: None,
		host_stream_begin: instance
			.get_typed_func::<(), i32>(&mut *store, "plmpeg_host_stream_begin")
			.ok(),
		host_stream_decode_next: instance
			.get_typed_func::<(), i32>(&mut *store, "plmpeg_host_stream_decode_next")
			.ok(),
		host_stream_end: instance
			.get_typed_func::<(), i32>(&mut *store, "plmpeg_host_stream_end")
			.ok(),
		host_stream_get_frame_index: instance
			.get_typed_func::<(), i32>(&mut *store, "plmpeg_host_stream_get_frame_index")
			.ok(),
	})
}

fn load_libjpeg_turbo_mjpeg_exports(
	store: &mut Store<()>,
	instance: &Instance,
	memory: Memory,
) -> RunnerResult<WasmExports> {
	Ok(WasmExports {
		fixture: FixtureKind::LibjpegTurboMjpeg,
		memory,
		host_alloc: instance
			.get_typed_func::<i32, i32>(&mut *store, "libjpeg_turbo_mjpeg_host_alloc")?,
		host_load: instance
			.get_typed_func::<(i32, i32), i32>(&mut *store, "libjpeg_turbo_mjpeg_host_load")?,
		host_decode_frame: instance
			.get_typed_func::<i32, i32>(&mut *store, "libjpeg_turbo_mjpeg_host_decode_frame")?,
		host_get_width: instance
			.get_typed_func::<(), i32>(&mut *store, "libjpeg_turbo_mjpeg_host_get_width")?,
		host_get_height: instance
			.get_typed_func::<(), i32>(&mut *store, "libjpeg_turbo_mjpeg_host_get_height")?,
		host_reset: instance
			.get_typed_func::<(), i32>(&mut *store, "libjpeg_turbo_mjpeg_host_reset")
			.ok(),
		host_get_rgb_ptr: instance
			.get_typed_func::<(), i32>(&mut *store, "libjpeg_turbo_mjpeg_host_get_rgb_ptr")
			.ok(),
		host_get_rgb_size: instance
			.get_typed_func::<(), i32>(&mut *store, "libjpeg_turbo_mjpeg_host_get_rgb_size")
			.ok(),
		host_get_framebuffer_ptr: None,
		host_get_framebuffer_size: None,
		host_get_y_ptr: None,
		host_get_u_ptr: None,
		host_get_v_ptr: None,
		host_get_y_size: None,
		host_get_u_size: None,
		host_get_v_size: None,
		host_stream_begin: None,
		host_stream_decode_next: None,
		host_stream_end: None,
		host_stream_get_frame_index: None,
	})
}

fn load_binjgb_exports(
	store: &mut Store<()>,
	instance: &Instance,
	memory: Memory,
) -> RunnerResult<WasmExports> {
	Ok(WasmExports {
		fixture: FixtureKind::Binjgb,
		memory,
		host_alloc: instance.get_typed_func::<i32, i32>(&mut *store, "binjgb_host_alloc")?,
		host_load: instance
			.get_typed_func::<(i32, i32), i32>(&mut *store, "binjgb_host_load_rom")?,
		host_decode_frame: instance
			.get_typed_func::<i32, i32>(&mut *store, "binjgb_host_run_frame")?,
		host_get_width: instance.get_typed_func::<(), i32>(&mut *store, "binjgb_host_get_width")?,
		host_get_height: instance
			.get_typed_func::<(), i32>(&mut *store, "binjgb_host_get_height")?,
		host_reset: instance
			.get_typed_func::<(), i32>(&mut *store, "binjgb_host_reset")
			.ok(),
		host_get_rgb_ptr: None,
		host_get_rgb_size: None,
		host_get_framebuffer_ptr: instance
			.get_typed_func::<(), i32>(&mut *store, "binjgb_host_get_framebuffer_ptr")
			.ok(),
		host_get_framebuffer_size: instance
			.get_typed_func::<(), i32>(&mut *store, "binjgb_host_get_framebuffer_size")
			.ok(),
		host_get_y_ptr: None,
		host_get_u_ptr: None,
		host_get_v_ptr: None,
		host_get_y_size: None,
		host_get_u_size: None,
		host_get_v_size: None,
		host_stream_begin: None,
		host_stream_decode_next: None,
		host_stream_end: None,
		host_stream_get_frame_index: None,
	})
}

fn load_h264mp4_exports(
	store: &mut Store<()>,
	instance: &Instance,
	memory: Memory,
) -> RunnerResult<WasmExports> {
	Ok(WasmExports {
		fixture: FixtureKind::H264Mp4,
		memory,
		host_alloc: instance.get_typed_func::<i32, i32>(&mut *store, "h264mp4_host_alloc")?,
		host_load: instance.get_typed_func::<(i32, i32), i32>(&mut *store, "h264mp4_host_load")?,
		host_decode_frame: instance
			.get_typed_func::<i32, i32>(&mut *store, "h264mp4_host_decode_frame")?,
		host_get_width: instance
			.get_typed_func::<(), i32>(&mut *store, "h264mp4_host_get_width")?,
		host_get_height: instance
			.get_typed_func::<(), i32>(&mut *store, "h264mp4_host_get_height")?,
		host_reset: instance
			.get_typed_func::<(), i32>(&mut *store, "h264mp4_host_reset")
			.ok(),
		host_get_rgb_ptr: None,
		host_get_rgb_size: None,
		host_get_framebuffer_ptr: None,
		host_get_framebuffer_size: None,
		host_get_y_ptr: instance
			.get_typed_func::<(), i32>(&mut *store, "h264mp4_host_get_y_ptr")
			.ok(),
		host_get_u_ptr: instance
			.get_typed_func::<(), i32>(&mut *store, "h264mp4_host_get_u_ptr")
			.ok(),
		host_get_v_ptr: instance
			.get_typed_func::<(), i32>(&mut *store, "h264mp4_host_get_v_ptr")
			.ok(),
		host_get_y_size: instance
			.get_typed_func::<(), i32>(&mut *store, "h264mp4_host_get_y_size")
			.ok(),
		host_get_u_size: instance
			.get_typed_func::<(), i32>(&mut *store, "h264mp4_host_get_u_size")
			.ok(),
		host_get_v_size: instance
			.get_typed_func::<(), i32>(&mut *store, "h264mp4_host_get_v_size")
			.ok(),
		host_stream_begin: None,
		host_stream_decode_next: None,
		host_stream_end: None,
		host_stream_get_frame_index: None,
	})
}

fn run_baseline(
	store: &mut Store<()>,
	exports: &WasmExports,
	input_path: &Path,
	input_bytes: &[u8],
	max_frames: usize,
	output_dir: Option<&Path>,
) -> RunnerResult<Summary> {
	let mut decoded_frames = 0_usize;
	let mut width = 0_i32;
	let mut height = 0_i32;
	let mut rgb_size = 0_i32;
	let output_base = basename_without_extension(input_path);

	if let Some(path) = output_dir {
		fs::create_dir_all(path)?;
	}

	while decoded_frames < max_frames {
		let Some(frame) = decode_baseline_frame(store, exports, input_bytes, decoded_frames)?
		else {
			break;
		};

		if decoded_frames == 0 {
			width = frame.width;
			height = frame.height;
			rgb_size = frame.rgb_size;
		}

		if let Some(path) = output_dir {
			write_ppm_frame(
				path,
				&output_base,
				frame.frame_index,
				frame.width,
				frame.height,
				&frame.rgb_bytes,
				false,
			)?;
		}

		decoded_frames += 1;
	}

	Ok(Summary {
		decoded_frames,
		width,
		height,
		rgb_size,
	})
}

fn run_stream(
	store: &mut Store<()>,
	exports: &WasmExports,
	input_path: &Path,
	input_bytes: &[u8],
	max_frames: usize,
	output_dir: Option<&Path>,
) -> RunnerResult<Summary> {
	let stream_begin = exports.host_stream_begin.as_ref().ok_or_else(|| {
		io::Error::new(
			io::ErrorKind::NotFound,
			"stream mode requires exported function plmpeg_host_stream_begin",
		)
	})?;
	let stream_decode_next = exports.host_stream_decode_next.as_ref().ok_or_else(|| {
		io::Error::new(
			io::ErrorKind::NotFound,
			"stream mode requires exported function plmpeg_host_stream_decode_next",
		)
	})?;
	let stream_end = exports.host_stream_end.as_ref().ok_or_else(|| {
		io::Error::new(
			io::ErrorKind::NotFound,
			"stream mode requires exported function plmpeg_host_stream_end",
		)
	})?;
	let stream_get_frame_index = exports
		.host_stream_get_frame_index
		.as_ref()
		.ok_or_else(|| {
			io::Error::new(
				io::ErrorKind::NotFound,
				"stream mode requires exported function plmpeg_host_stream_get_frame_index",
			)
		})?;
	let mut decoded_frames = 0_usize;
	let mut width = 0_i32;
	let mut height = 0_i32;
	let mut rgb_size = 0_i32;
	let output_base = basename_without_extension(input_path);

	if let Some(path) = output_dir {
		fs::create_dir_all(path)?;
	}

	load_host_bytes(store, exports, input_bytes)?;
	ensure_success(stream_begin.call(&mut *store, ())?, "stream begin failed")?;

	while decoded_frames < max_frames {
		if stream_decode_next.call(&mut *store, ())? != 1_i32 {
			break;
		}

		let frame_index =
			usize::try_from(stream_get_frame_index.call(&mut *store, ())?).map_err(|error| {
				io::Error::other(format!(
					"negative frame index returned from stream decode: {error}"
				))
			})?;
		let frame = read_current_frame(store, exports, frame_index)?;

		if decoded_frames == 0 {
			width = frame.width;
			height = frame.height;
			rgb_size = frame.rgb_size;
		}

		if let Some(path) = output_dir {
			write_ppm_frame(
				path,
				&output_base,
				frame.frame_index,
				frame.width,
				frame.height,
				&frame.rgb_bytes,
				true,
			)?;
		}

		decoded_frames += 1;
	}

	ensure_success(stream_end.call(&mut *store, ())?, "stream end failed")?;

	Ok(Summary {
		decoded_frames,
		width,
		height,
		rgb_size,
	})
}

fn decode_baseline_frame(
	store: &mut Store<()>,
	exports: &WasmExports,
	input_bytes: &[u8],
	frame_index: usize,
) -> RunnerResult<Option<FrameData>> {
	if let Some(host_reset) = exports.host_reset.as_ref() {
		ensure_success(host_reset.call(&mut *store, ())?, "host reset failed")?;
	}

	load_host_bytes(store, exports, input_bytes)?;

	let target_frame_index = i32::try_from(frame_index).map_err(|error| {
		io::Error::new(
			io::ErrorKind::InvalidInput,
			format!("frame index exceeds i32 range: {error}"),
		)
	})?;

	if exports
		.host_decode_frame
		.call(&mut *store, target_frame_index)?
		!= 1_i32
	{
		return Ok(None);
	}

	read_current_frame(store, exports, frame_index).map(Some)
}

fn load_host_bytes(
	store: &mut Store<()>,
	exports: &WasmExports,
	input_bytes: &[u8],
) -> RunnerResult<()> {
	let size = i32::try_from(input_bytes.len()).map_err(|error| {
		io::Error::new(
			io::ErrorKind::InvalidInput,
			format!("input file exceeds i32 range: {error}"),
		)
	})?;
	let input_ptr = exports.host_alloc.call(&mut *store, size)?;

	if input_ptr == 0_i32 {
		return Err(io::Error::other("input allocation failed").into());
	}

	let offset = usize::try_from(input_ptr).map_err(|error| {
		io::Error::other(format!(
			"negative input pointer returned from wasm: {error}"
		))
	})?;

	exports.memory.write(&mut *store, offset, input_bytes)?;
	ensure_success(
		exports.host_load.call(&mut *store, (input_ptr, size))?,
		"host load failed",
	)?;
	Ok(())
}

fn read_current_frame(
	store: &mut Store<()>,
	exports: &WasmExports,
	frame_index: usize,
) -> RunnerResult<FrameData> {
	match exports.fixture {
		FixtureKind::Plmpeg | FixtureKind::LibjpegTurboMjpeg => {
			read_current_rgb_frame(store, exports, frame_index)
		}
		FixtureKind::Binjgb => read_current_binjgb_frame(store, exports, frame_index),
		FixtureKind::H264Mp4 => read_current_h264_frame(store, exports, frame_index),
		FixtureKind::Cgltf => {
			Err(io::Error::other("cgltf uses run_cgltf, not read_current_frame").into())
		}
	}
}

fn read_current_rgb_frame(
	store: &mut Store<()>,
	exports: &WasmExports,
	frame_index: usize,
) -> RunnerResult<FrameData> {
	let width = exports.host_get_width.call(&mut *store, ())?;
	let height = exports.host_get_height.call(&mut *store, ())?;
	let rgb_ptr = required_func(
		exports.host_get_rgb_ptr.as_ref(),
		"missing RGB pointer export",
	)?
	.call(&mut *store, ())?;
	let rgb_size = required_func(
		exports.host_get_rgb_size.as_ref(),
		"missing RGB size export",
	)?
	.call(&mut *store, ())?;

	if width <= 0_i32 || height <= 0_i32 || rgb_ptr <= 0_i32 || rgb_size <= 0_i32 {
		return Err(io::Error::other("wasm returned invalid frame metadata").into());
	}

	let rgb_offset = usize::try_from(rgb_ptr).map_err(|error| {
		io::Error::other(format!("negative RGB pointer returned from wasm: {error}"))
	})?;
	let rgb_length = usize::try_from(rgb_size).map_err(|error| {
		io::Error::other(format!("negative RGB size returned from wasm: {error}"))
	})?;
	let mut rgb_bytes = vec![0_u8; rgb_length];

	exports
		.memory
		.read(&mut *store, rgb_offset, &mut rgb_bytes)?;

	Ok(FrameData {
		frame_index,
		width,
		height,
		rgb_size,
		rgb_bytes,
	})
}

fn read_current_h264_frame(
	store: &mut Store<()>,
	exports: &WasmExports,
	frame_index: usize,
) -> RunnerResult<FrameData> {
	let width = exports.host_get_width.call(&mut *store, ())?;
	let height = exports.host_get_height.call(&mut *store, ())?;
	let y_ptr = required_func(
		exports.host_get_y_ptr.as_ref(),
		"missing h264mp4_host_get_y_ptr",
	)?
	.call(&mut *store, ())?;
	let u_ptr = required_func(
		exports.host_get_u_ptr.as_ref(),
		"missing h264mp4_host_get_u_ptr",
	)?
	.call(&mut *store, ())?;
	let v_ptr = required_func(
		exports.host_get_v_ptr.as_ref(),
		"missing h264mp4_host_get_v_ptr",
	)?
	.call(&mut *store, ())?;
	let y_size = required_func(
		exports.host_get_y_size.as_ref(),
		"missing h264mp4_host_get_y_size",
	)?
	.call(&mut *store, ())?;
	let u_size = required_func(
		exports.host_get_u_size.as_ref(),
		"missing h264mp4_host_get_u_size",
	)?
	.call(&mut *store, ())?;
	let v_size = required_func(
		exports.host_get_v_size.as_ref(),
		"missing h264mp4_host_get_v_size",
	)?
	.call(&mut *store, ())?;

	if width <= 0_i32
		|| height <= 0_i32
		|| y_ptr <= 0_i32
		|| u_ptr <= 0_i32
		|| v_ptr <= 0_i32
		|| y_size <= 0_i32
		|| u_size <= 0_i32
		|| v_size <= 0_i32
	{
		return Err(io::Error::other("wasm returned invalid YUV frame metadata").into());
	}

	let y_length = usize::try_from(y_size).map_err(|error| {
		io::Error::other(format!("negative Y size returned from wasm: {error}"))
	})?;
	let u_length = usize::try_from(u_size).map_err(|error| {
		io::Error::other(format!("negative U size returned from wasm: {error}"))
	})?;
	let v_length = usize::try_from(v_size).map_err(|error| {
		io::Error::other(format!("negative V size returned from wasm: {error}"))
	})?;
	let mut y_bytes = vec![0_u8; y_length];
	let mut u_bytes = vec![0_u8; u_length];
	let mut v_bytes = vec![0_u8; v_length];

	let y_offset = usize::try_from(y_ptr).map_err(|error| {
		io::Error::other(format!("negative Y pointer returned from wasm: {error}"))
	})?;
	let u_offset = usize::try_from(u_ptr).map_err(|error| {
		io::Error::other(format!("negative U pointer returned from wasm: {error}"))
	})?;
	let v_offset = usize::try_from(v_ptr).map_err(|error| {
		io::Error::other(format!("negative V pointer returned from wasm: {error}"))
	})?;

	exports.memory.read(&mut *store, y_offset, &mut y_bytes)?;
	exports.memory.read(&mut *store, u_offset, &mut u_bytes)?;
	exports.memory.read(&mut *store, v_offset, &mut v_bytes)?;

	let rgb_bytes = yuv420_to_rgb_bytes(width, height, &y_bytes, &u_bytes, &v_bytes)?;
	let rgb_size = i32::try_from(rgb_bytes.len())
		.map_err(|error| io::Error::other(format!("RGB output size exceeds i32 range: {error}")))?;

	Ok(FrameData {
		frame_index,
		width,
		height,
		rgb_size,
		rgb_bytes,
	})
}

fn read_current_binjgb_frame(
	store: &mut Store<()>,
	exports: &WasmExports,
	frame_index: usize,
) -> RunnerResult<FrameData> {
	let width = exports.host_get_width.call(&mut *store, ())?;
	let height = exports.host_get_height.call(&mut *store, ())?;
	let framebuffer_ptr = required_func(
		exports.host_get_framebuffer_ptr.as_ref(),
		"missing binjgb framebuffer pointer export",
	)?
	.call(&mut *store, ())?;
	let framebuffer_size = required_func(
		exports.host_get_framebuffer_size.as_ref(),
		"missing binjgb framebuffer size export",
	)?
	.call(&mut *store, ())?;

	if width <= 0_i32 || height <= 0_i32 || framebuffer_ptr <= 0_i32 || framebuffer_size <= 0_i32 {
		return Err(io::Error::other("wasm returned invalid binjgb frame metadata").into());
	}

	let framebuffer_offset = usize::try_from(framebuffer_ptr).map_err(|error| {
		io::Error::other(format!(
			"negative framebuffer pointer returned from wasm: {error}"
		))
	})?;
	let framebuffer_length = usize::try_from(framebuffer_size).map_err(|error| {
		io::Error::other(format!(
			"negative framebuffer size returned from wasm: {error}"
		))
	})?;
	let mut framebuffer_bytes = vec![0_u8; framebuffer_length];
	let mut rgb_bytes = Vec::with_capacity(framebuffer_length / 2 * 3);

	exports
		.memory
		.read(&mut *store, framebuffer_offset, &mut framebuffer_bytes)?;

	for chunk in framebuffer_bytes.as_chunks::<2>().0 {
		let pixel = u16::from_le_bytes(*chunk);
		let r5 = ((pixel >> 10_i32) & 0x1f) as u8;
		let g5 = ((pixel >> 5_i32) & 0x1f) as u8;
		let b5 = (pixel & 0x1f) as u8;
		rgb_bytes.push((r5 << 3_i32) | (r5 >> 2_i32));
		rgb_bytes.push((g5 << 3_i32) | (g5 >> 2_i32));
		rgb_bytes.push((b5 << 3_i32) | (b5 >> 2_i32));
	}

	Ok(FrameData {
		frame_index,
		width,
		height,
		rgb_size: i32::try_from(rgb_bytes.len())
			.map_err(|error| io::Error::other(format!("RGB output exceeds i32 range: {error}")))?,
		rgb_bytes,
	})
}

fn yuv420_to_rgb_bytes(
	width: i32,
	height: i32,
	y_bytes: &[u8],
	u_bytes: &[u8],
	v_bytes: &[u8],
) -> RunnerResult<Vec<u8>> {
	let width_usize = usize::try_from(width)
		.map_err(|error| io::Error::other(format!("negative width returned from wasm: {error}")))?;
	let height_usize = usize::try_from(height).map_err(|error| {
		io::Error::other(format!("negative height returned from wasm: {error}"))
	})?;
	let uv_width = width_usize / 2;
	let mut rgb = Vec::with_capacity(width_usize * height_usize * 3);

	for y in 0..height_usize {
		let y_row = y * width_usize;
		let uv_row = (y / 2) * uv_width;

		for x in 0..width_usize {
			let y_value = f32::from(y_bytes[y_row + x]);
			let uv_index = uv_row + (x / 2);
			let cb = f32::from(u_bytes[uv_index]) - 128.0;
			let cr = f32::from(v_bytes[uv_index]) - 128.0;
			let r = clamp_byte(y_value + 1.402 * cr);
			let g = clamp_byte(y_value - 0.344_136 * cb - 0.714_136 * cr);
			let b = clamp_byte(y_value + 1.772 * cb);

			rgb.push(r);
			rgb.push(g);
			rgb.push(b);
		}
	}

	Ok(rgb)
}

/// Clamps a color channel into a byte, rounding it to the nearest integer.
///
/// Values below one, including `NaN`, become zero and values of `255.0` or more
/// become `255`, matching the saturating behaviour of the decoder output.
fn clamp_byte(value: f32) -> u8 {
	let rounded = value.round();

	if rounded >= 255.0 {
		return 255_u8;
	}

	if rounded >= 1.0 {
		return whole_f32_to_byte(rounded);
	}

	0_u8
}

/// Reads back the value of an `f32` that holds a whole number between one and
/// `254`.
///
/// Adding `2^23` lines the number up with the mantissa of the sum, so the low
/// mantissa bits spell out the integer exactly and no lossy cast is needed.
fn whole_f32_to_byte(value: f32) -> u8 {
	const MANTISSA_OFFSET: f32 = 8_388_608.0;
	const MANTISSA_MASK: u32 = 0x007f_ffff;

	let bits = (value + MANTISSA_OFFSET).to_bits() & MANTISSA_MASK;

	u8::try_from(bits).expect("a whole number below 255 should fit in a byte")
}

fn required_func<'func, T>(value: Option<&'func T>, message: &str) -> RunnerResult<&'func T> {
	value.ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, message).into())
}

fn ensure_success(value: i32, message: &str) -> RunnerResult<()> {
	if value == 1_i32 {
		return Ok(());
	}

	Err(io::Error::other(message.to_owned()).into())
}

fn basename_without_extension(path: &Path) -> String {
	path.file_stem()
		.and_then(std::ffi::OsStr::to_str)
		.map_or_else(|| String::from("output"), str::to_owned)
}

fn write_ppm_frame(
	output_dir: &Path,
	output_base: &str,
	frame_index: usize,
	width: i32,
	height: i32,
	rgb_bytes: &[u8],
	is_stream: bool,
) -> RunnerResult<()> {
	let suffix = if is_stream { "_stream" } else { "" };
	let file_name = format!("{output_base}{suffix}_frame{frame_index:03}.ppm");
	let path = output_dir.join(file_name);
	let header = format!("P6\n{width} {height}\n255\n");
	let mut bytes = header.into_bytes();

	bytes.extend_from_slice(rgb_bytes);
	fs::write(path, bytes)?;
	Ok(())
}

fn run_cgltf(args: &Args) -> RunnerResult<Summary> {
	let engine = Engine::default();
	let module = Module::from_file(&engine, &args.wasm_path)?;
	let mut store = Store::new(&engine, ());
	let instance = Instance::new(&mut store, &module, &[])?;
	let exports = load_cgltf_exports(&mut store, &instance)?;
	let input_bytes = fs::read(&args.input_path)?;
	let (input_ptr, input_size) = load_cgltf_input(&mut store, &exports, &input_bytes)?;

	let hash_value = exports
		.compute_hash
		.call(&mut store, (input_ptr, input_size))?;
	println!("Result (Hash): {hash_value}");

	ensure_success(
		exports.host_parse.call(&mut store, ())?,
		"host parse failed",
	)?;

	let mesh_count = exports.get_mesh_count.call(&mut store, ())?;
	let anim_count = exports.get_animation_count.call(&mut store, ())?;
	let node_count = exports.get_node_count.call(&mut store, ())?;
	let skin_count = exports.get_skin_count.call(&mut store, ())?;
	let scene_count = exports.get_scene_count.call(&mut store, ())?;

	println!("Result (MeshCount): {mesh_count}");
	println!("Result (AnimationCount): {anim_count}");
	println!("Result (NodeCount): {node_count}");
	println!("Result (SkinCount): {skin_count}");
	println!("Result (SceneCount): {scene_count}");

	print_cgltf_animation_channels(&mut store, &exports, anim_count)?;
	print_cgltf_mesh_names(&mut store, &exports, mesh_count)?;
	print_cgltf_nodes(&mut store, &exports, node_count)?;

	exports.host_free.call(&mut store, ())?;
	Ok(Summary {
		decoded_frames: 0,
		width: 0,
		height: 0,
		rgb_size: 0,
	})
}

fn load_cgltf_exports(store: &mut Store<()>, instance: &Instance) -> RunnerResult<CgltfExports> {
	let memory = instance
		.get_memory(&mut *store, "memory")
		.ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "missing exported memory"))?;

	let host_alloc = instance.get_typed_func::<i32, i32>(&mut *store, "cgltf_host_alloc")?;
	let host_load = instance.get_typed_func::<(i32, i32), i32>(&mut *store, "cgltf_host_load")?;
	let host_parse = instance.get_typed_func::<(), i32>(&mut *store, "cgltf_host_parse")?;
	let host_free = instance.get_typed_func::<(), i32>(&mut *store, "cgltf_host_free")?;

	let get_mesh_count =
		instance.get_typed_func::<(), i32>(&mut *store, "cgltf_host_get_mesh_count")?;
	let get_animation_count =
		instance.get_typed_func::<(), i32>(&mut *store, "cgltf_host_get_animation_count")?;
	let get_node_count =
		instance.get_typed_func::<(), i32>(&mut *store, "cgltf_host_get_node_count")?;
	let get_skin_count =
		instance.get_typed_func::<(), i32>(&mut *store, "cgltf_host_get_skin_count")?;
	let get_scene_count =
		instance.get_typed_func::<(), i32>(&mut *store, "cgltf_host_get_scene_count")?;
	let get_anim_chan_count = instance
		.get_typed_func::<i32, i32>(&mut *store, "cgltf_host_get_animation_channel_count")?;
	let get_node_has_mesh =
		instance.get_typed_func::<i32, i32>(&mut *store, "cgltf_host_get_node_has_mesh")?;
	let get_node_has_skin =
		instance.get_typed_func::<i32, i32>(&mut *store, "cgltf_host_get_node_has_skin")?;

	let _get_anim_name_len =
		instance.get_typed_func::<i32, i32>(&mut *store, "cgltf_host_get_animation_name_len")?;
	let _get_anim_name = instance
		.get_typed_func::<(i32, i32, i32), i32>(&mut *store, "cgltf_host_get_animation_name")?;
	let get_mesh_name_len =
		instance.get_typed_func::<i32, i32>(&mut *store, "cgltf_host_get_mesh_name_len")?;
	let get_mesh_name =
		instance.get_typed_func::<(i32, i32, i32), i32>(&mut *store, "cgltf_host_get_mesh_name")?;
	let get_node_name_len =
		instance.get_typed_func::<i32, i32>(&mut *store, "cgltf_host_get_node_name_len")?;
	let get_node_name =
		instance.get_typed_func::<(i32, i32, i32), i32>(&mut *store, "cgltf_host_get_node_name")?;
	let compute_hash =
		instance.get_typed_func::<(i32, i32), i32>(&mut *store, "cgltf_compute_hash")?;

	Ok(CgltfExports {
		memory,
		host_alloc,
		host_load,
		host_parse,
		host_free,
		get_mesh_count,
		get_animation_count,
		get_node_count,
		get_skin_count,
		get_scene_count,
		get_anim_chan_count,
		get_node_has_mesh,
		get_node_has_skin,
		get_mesh_name_len,
		get_mesh_name,
		get_node_name_len,
		get_node_name,
		compute_hash,
	})
}

fn load_cgltf_input(
	store: &mut Store<()>,
	exports: &CgltfExports,
	input_bytes: &[u8],
) -> RunnerResult<(i32, i32)> {
	let size = i32::try_from(input_bytes.len()).map_err(|error| {
		io::Error::new(
			io::ErrorKind::InvalidInput,
			format!("input file exceeds i32 range: {error}"),
		)
	})?;
	let input_ptr = exports.host_alloc.call(&mut *store, size)?;

	if input_ptr == 0_i32 {
		return Err(io::Error::other("input allocation failed").into());
	}

	let offset = usize::try_from(input_ptr).map_err(|error| {
		io::Error::other(format!(
			"negative input pointer returned from wasm: {error}"
		))
	})?;

	exports.memory.write(&mut *store, offset, input_bytes)?;
	ensure_success(
		exports.host_load.call(&mut *store, (input_ptr, size))?,
		"host load failed",
	)?;

	Ok((input_ptr, size))
}

fn print_cgltf_animation_channels(
	store: &mut Store<()>,
	exports: &CgltfExports,
	anim_count: i32,
) -> RunnerResult<()> {
	for i in 0_i32..anim_count {
		let channels = exports.get_anim_chan_count.call(&mut *store, i)?;
		println!("Result (AnimationChannelCount{i}): {channels}");
	}

	Ok(())
}

fn print_cgltf_mesh_names(
	store: &mut Store<()>,
	exports: &CgltfExports,
	mesh_count: i32,
) -> RunnerResult<()> {
	for i in 0_i32..mesh_count {
		let name_len = exports.get_mesh_name_len.call(&mut *store, i)?;

		if let Some(name) = read_cgltf_name(store, exports, &exports.get_mesh_name, i, name_len)? {
			println!("Result (MeshName{i}): {name}");
		}
	}

	Ok(())
}

fn print_cgltf_nodes(
	store: &mut Store<()>,
	exports: &CgltfExports,
	node_count: i32,
) -> RunnerResult<()> {
	for i in 0_i32..node_count {
		let name_len = exports.get_node_name_len.call(&mut *store, i)?;
		let name = read_cgltf_name(store, exports, &exports.get_node_name, i, name_len)?
			.unwrap_or_default();
		let has_mesh = exports.get_node_has_mesh.call(&mut *store, i)? == 1_i32;
		let has_skin = exports.get_node_has_skin.call(&mut *store, i)? == 1_i32;
		let mut flags = String::new();

		if has_mesh {
			flags.push_str(" MESH");
		}

		if has_skin {
			flags.push_str(" SKIN");
		}

		println!("Result (Node{i}): {name}{flags}");
	}

	Ok(())
}

fn read_cgltf_name(
	store: &mut Store<()>,
	exports: &CgltfExports,
	name_getter: &TypedFunc<(i32, i32, i32), i32>,
	index: i32,
	name_len: i32,
) -> RunnerResult<Option<String>> {
	if name_len <= 0_i32 {
		return Ok(None);
	}

	let buffer = exports.host_alloc.call(&mut *store, name_len + 1_i32)?;

	if buffer == 0_i32 {
		return Ok(None);
	}

	name_getter.call(&mut *store, (index, buffer, name_len + 1_i32))?;

	let buffer_offset = usize::try_from(buffer)
		.map_err(|error| io::Error::other(format!("negative buffer pointer: {error}")))?;
	let length = usize::try_from(name_len)
		.map_err(|error| io::Error::other(format!("negative name length: {error}")))?;
	let mut name_bytes = vec![0_u8; length];

	exports
		.memory
		.read(&mut *store, buffer_offset, &mut name_bytes)?;

	Ok(Some(
		String::from_utf8(name_bytes).unwrap_or_else(|_| String::from("<invalid utf8>")),
	))
}
