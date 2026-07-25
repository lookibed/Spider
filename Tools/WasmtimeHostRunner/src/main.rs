//! Wasmtime-backed host runner for fixture-specific manual workflows.

use std::env;
use std::error::Error;
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

struct FrameData {
    frame_index: usize,
    width: i32,
    height: i32,
    rgb_size: i32,
    rgb_bytes: Vec<u8>,
}

fn main() -> RunnerResult<()> {
    let args = parse_args(env::args_os().skip(1).collect())?;
    let summary = run(args)?;

    println!("Decoded Frames: {}", summary.decoded_frames);
    println!("Width: {}", summary.width);
    println!("Height: {}", summary.height);
    println!("RGB Size: {}", summary.rgb_size);
    Ok(())
}

fn parse_args(args: Vec<OsString>) -> RunnerResult<Args> {
    let mut fixture = FixtureKind::Plmpeg;
    let mut mode = None;
    let mut wasm_path = None;
    let mut input_path = None;
    let mut max_frames = 240usize;
    let mut output_dir = None;
    let mut index = 0usize;

    while index < args.len() {
        let current = args[index]
            .to_str()
            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "arguments should be valid UTF-8"))?;

        match current {
            "--fixture" => {
                let value = next_arg(&args, index, "--fixture")?;
                fixture = parse_fixture(value)?;
                index += 2;
            }
            "--mode" => {
                let value = next_arg(&args, index, "--mode")?;
                mode = Some(parse_mode(value)?);
                index += 2;
            }
            "--wasm" => {
                let value = next_arg(&args, index, "--wasm")?;
                wasm_path = Some(PathBuf::from(value));
                index += 2;
            }
            "--input" => {
                let value = next_arg(&args, index, "--input")?;
                input_path = Some(PathBuf::from(value));
                index += 2;
            }
            "--frames" => {
                let value = next_arg(&args, index, "--frames")?;
                max_frames = value.parse::<usize>()?;
                index += 2;
            }
            "--output-dir" => {
                let value = next_arg(&args, index, "--output-dir")?;
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

    let parsed_mode = mode.ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            "missing required argument: --mode baseline|stream",
        )
    })?;
    let parsed_wasm_path = wasm_path
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "missing required argument: --wasm <path>"))?;
    let parsed_input_path = input_path
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "missing required argument: --input <path>"))?;

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

fn next_arg<'a>(args: &'a [OsString], index: usize, flag: &str) -> RunnerResult<&'a str> {
    args.get(index + 1)
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, format!("missing value after {flag}")))? 
        .to_str()
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, format!("{flag} value should be valid UTF-8")).into())
}

fn parse_fixture(fixture: &str) -> RunnerResult<FixtureKind> {
    match fixture {
        "plmpeg" => Ok(FixtureKind::Plmpeg),
        "binjgb" | "gbc" => Ok(FixtureKind::Binjgb),
        "libjpeg-turbo-mjpeg" | "libjpegturbo-mjpeg" | "mjpeg" => Ok(FixtureKind::LibjpegTurboMjpeg),
        "h264mp4" => Ok(FixtureKind::H264Mp4),
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
    println!("  cargo run -p wasmtime-host-runner -- --fixture plmpeg --mode baseline --wasm <path> --input <path> --frames 100");
    println!("  cargo run -p wasmtime-host-runner -- --fixture plmpeg --mode stream --wasm <path> --input <path> --frames 100");
    println!("  cargo run -p wasmtime-host-runner -- --fixture binjgb --mode baseline --wasm <path> --input <path> --frames 16");
    println!("  cargo run -p wasmtime-host-runner -- --fixture libjpeg-turbo-mjpeg --mode baseline --wasm <path> --input <path> --frames 12");
    println!("  cargo run -p wasmtime-host-runner -- --fixture h264mp4 --mode baseline --wasm <path> --input <path> --frames 12");
    println!("Optional:");
    println!("  --output-dir <path>   Write decoded PPM frames for visual inspection");
}

fn run(args: Args) -> RunnerResult<Summary> {
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

fn load_exports(store: &mut Store<()>, instance: &Instance, fixture: FixtureKind) -> RunnerResult<WasmExports> {
    let memory = instance
        .get_memory(&mut *store, "memory")
        .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "missing exported memory"))?;

    let exports = match fixture {
        FixtureKind::Plmpeg => WasmExports {
            fixture,
            memory,
            host_alloc: instance.get_typed_func::<i32, i32>(&mut *store, "plmpeg_host_alloc")?,
            host_load: instance.get_typed_func::<(i32, i32), i32>(&mut *store, "plmpeg_host_load")?,
            host_decode_frame: instance.get_typed_func::<i32, i32>(&mut *store, "plmpeg_host_decode_frame")?,
            host_get_width: instance.get_typed_func::<(), i32>(&mut *store, "plmpeg_host_get_width")?,
            host_get_height: instance.get_typed_func::<(), i32>(&mut *store, "plmpeg_host_get_height")?,
            host_reset: instance.get_typed_func::<(), i32>(&mut *store, "plmpeg_host_reset").ok(),
            host_get_rgb_ptr: instance.get_typed_func::<(), i32>(&mut *store, "plmpeg_host_get_rgb_ptr").ok(),
            host_get_rgb_size: instance.get_typed_func::<(), i32>(&mut *store, "plmpeg_host_get_rgb_size").ok(),
            host_get_framebuffer_ptr: None,
            host_get_framebuffer_size: None,
            host_get_y_ptr: None,
            host_get_u_ptr: None,
            host_get_v_ptr: None,
            host_get_y_size: None,
            host_get_u_size: None,
            host_get_v_size: None,
            host_stream_begin: instance.get_typed_func::<(), i32>(&mut *store, "plmpeg_host_stream_begin").ok(),
            host_stream_decode_next: instance
                .get_typed_func::<(), i32>(&mut *store, "plmpeg_host_stream_decode_next")
                .ok(),
            host_stream_end: instance.get_typed_func::<(), i32>(&mut *store, "plmpeg_host_stream_end").ok(),
            host_stream_get_frame_index: instance
                .get_typed_func::<(), i32>(&mut *store, "plmpeg_host_stream_get_frame_index")
                .ok(),
        },
        FixtureKind::LibjpegTurboMjpeg => WasmExports {
            fixture,
            memory,
            host_alloc: instance.get_typed_func::<i32, i32>(&mut *store, "libjpeg_turbo_mjpeg_host_alloc")?,
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
        },
        FixtureKind::Binjgb => WasmExports {
            fixture,
            memory,
            host_alloc: instance.get_typed_func::<i32, i32>(&mut *store, "binjgb_host_alloc")?,
            host_load: instance.get_typed_func::<(i32, i32), i32>(&mut *store, "binjgb_host_load_rom")?,
            host_decode_frame: instance.get_typed_func::<i32, i32>(&mut *store, "binjgb_host_run_frame")?,
            host_get_width: instance.get_typed_func::<(), i32>(&mut *store, "binjgb_host_get_width")?,
            host_get_height: instance.get_typed_func::<(), i32>(&mut *store, "binjgb_host_get_height")?,
            host_reset: instance.get_typed_func::<(), i32>(&mut *store, "binjgb_host_reset").ok(),
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
        },
        FixtureKind::H264Mp4 => WasmExports {
            fixture,
            memory,
            host_alloc: instance.get_typed_func::<i32, i32>(&mut *store, "h264mp4_host_alloc")?,
            host_load: instance.get_typed_func::<(i32, i32), i32>(&mut *store, "h264mp4_host_load")?,
            host_decode_frame: instance.get_typed_func::<i32, i32>(&mut *store, "h264mp4_host_decode_frame")?,
            host_get_width: instance.get_typed_func::<(), i32>(&mut *store, "h264mp4_host_get_width")?,
            host_get_height: instance.get_typed_func::<(), i32>(&mut *store, "h264mp4_host_get_height")?,
            host_reset: instance.get_typed_func::<(), i32>(&mut *store, "h264mp4_host_reset").ok(),
            host_get_rgb_ptr: None,
            host_get_rgb_size: None,
            host_get_framebuffer_ptr: None,
            host_get_framebuffer_size: None,
            host_get_y_ptr: instance.get_typed_func::<(), i32>(&mut *store, "h264mp4_host_get_y_ptr").ok(),
            host_get_u_ptr: instance.get_typed_func::<(), i32>(&mut *store, "h264mp4_host_get_u_ptr").ok(),
            host_get_v_ptr: instance.get_typed_func::<(), i32>(&mut *store, "h264mp4_host_get_v_ptr").ok(),
            host_get_y_size: instance.get_typed_func::<(), i32>(&mut *store, "h264mp4_host_get_y_size").ok(),
            host_get_u_size: instance.get_typed_func::<(), i32>(&mut *store, "h264mp4_host_get_u_size").ok(),
            host_get_v_size: instance.get_typed_func::<(), i32>(&mut *store, "h264mp4_host_get_v_size").ok(),
            host_stream_begin: None,
            host_stream_decode_next: None,
            host_stream_end: None,
            host_stream_get_frame_index: None,
        },
    };

    Ok(exports)
}

fn run_baseline(
    store: &mut Store<()>,
    exports: &WasmExports,
    input_path: &Path,
    input_bytes: &[u8],
    max_frames: usize,
    output_dir: Option<&Path>,
) -> RunnerResult<Summary> {
    let mut decoded_frames = 0usize;
    let mut width = 0i32;
    let mut height = 0i32;
    let mut rgb_size = 0i32;
    let output_base = basename_without_extension(input_path);

    if let Some(path) = output_dir {
        fs::create_dir_all(path)?;
    }

    while decoded_frames < max_frames {
        let maybe_frame = decode_baseline_frame(store, exports, input_bytes, decoded_frames)?;
        let frame = if let Some(frame) = maybe_frame {
            frame
        } else {
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
    let stream_get_frame_index = exports.host_stream_get_frame_index.as_ref().ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::NotFound,
            "stream mode requires exported function plmpeg_host_stream_get_frame_index",
        )
    })?;
    let mut decoded_frames = 0usize;
    let mut width = 0i32;
    let mut height = 0i32;
    let mut rgb_size = 0i32;
    let output_base = basename_without_extension(input_path);

    if let Some(path) = output_dir {
        fs::create_dir_all(path)?;
    }

    load_host_bytes(store, exports, input_bytes)?;
    ensure_success(stream_begin.call(&mut *store, ())?, "stream begin failed")?;

    while decoded_frames < max_frames {
        if stream_decode_next.call(&mut *store, ())? != 1 {
            break;
        }

        let frame_index = usize::try_from(stream_get_frame_index.call(&mut *store, ())?)
            .map_err(|_| io::Error::other("negative frame index returned from stream decode"))?;
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
    let target_frame_index = i32::try_from(frame_index)
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "frame index exceeds i32 range"))?;
    if exports.host_decode_frame.call(&mut *store, target_frame_index)? != 1 {
        return Ok(None);
    }

    read_current_frame(store, exports, frame_index).map(Some)
}

fn load_host_bytes(store: &mut Store<()>, exports: &WasmExports, input_bytes: &[u8]) -> RunnerResult<()> {
    let size = i32::try_from(input_bytes.len())
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "input file exceeds i32 range"))?;
    let input_ptr = exports.host_alloc.call(&mut *store, size)?;

    if input_ptr == 0 {
        return Err(io::Error::other("input allocation failed").into());
    }

    let offset = usize::try_from(input_ptr)
        .map_err(|_| io::Error::other("negative input pointer returned from wasm"))?;
    exports.memory.write(&mut *store, offset, input_bytes)?;
    ensure_success(exports.host_load.call(&mut *store, (input_ptr, size))?, "host load failed")?;
    Ok(())
}

fn read_current_frame(store: &mut Store<()>, exports: &WasmExports, frame_index: usize) -> RunnerResult<FrameData> {
    match exports.fixture {
        FixtureKind::Plmpeg | FixtureKind::LibjpegTurboMjpeg => read_current_rgb_frame(store, exports, frame_index),
        FixtureKind::Binjgb => read_current_binjgb_frame(store, exports, frame_index),
        FixtureKind::H264Mp4 => read_current_h264_frame(store, exports, frame_index),
    }
}

fn read_current_rgb_frame(
    store: &mut Store<()>,
    exports: &WasmExports,
    frame_index: usize,
) -> RunnerResult<FrameData> {
    let width = exports.host_get_width.call(&mut *store, ())?;
    let height = exports.host_get_height.call(&mut *store, ())?;
    let rgb_ptr = required_func(exports.host_get_rgb_ptr.as_ref(), "missing RGB pointer export")?
        .call(&mut *store, ())?;
    let rgb_size = required_func(exports.host_get_rgb_size.as_ref(), "missing RGB size export")?
        .call(&mut *store, ())?;

    if width <= 0 || height <= 0 || rgb_ptr <= 0 || rgb_size <= 0 {
        return Err(io::Error::other("wasm returned invalid frame metadata").into());
    }

    let rgb_offset = usize::try_from(rgb_ptr)
        .map_err(|_| io::Error::other("negative RGB pointer returned from wasm"))?;
    let rgb_length = usize::try_from(rgb_size)
        .map_err(|_| io::Error::other("negative RGB size returned from wasm"))?;
    let mut rgb_bytes = vec![0u8; rgb_length];

    exports.memory.read(&mut *store, rgb_offset, &mut rgb_bytes)?;

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
    let y_ptr = required_func(exports.host_get_y_ptr.as_ref(), "missing h264mp4_host_get_y_ptr")?
        .call(&mut *store, ())?;
    let u_ptr = required_func(exports.host_get_u_ptr.as_ref(), "missing h264mp4_host_get_u_ptr")?
        .call(&mut *store, ())?;
    let v_ptr = required_func(exports.host_get_v_ptr.as_ref(), "missing h264mp4_host_get_v_ptr")?
        .call(&mut *store, ())?;
    let y_size = required_func(exports.host_get_y_size.as_ref(), "missing h264mp4_host_get_y_size")?
        .call(&mut *store, ())?;
    let u_size = required_func(exports.host_get_u_size.as_ref(), "missing h264mp4_host_get_u_size")?
        .call(&mut *store, ())?;
    let v_size = required_func(exports.host_get_v_size.as_ref(), "missing h264mp4_host_get_v_size")?
        .call(&mut *store, ())?;

    if width <= 0
        || height <= 0
        || y_ptr <= 0
        || u_ptr <= 0
        || v_ptr <= 0
        || y_size <= 0
        || u_size <= 0
        || v_size <= 0
    {
        return Err(io::Error::other("wasm returned invalid YUV frame metadata").into());
    }

    let mut y_bytes = vec![
        0u8;
        usize::try_from(y_size).map_err(|_| io::Error::other("negative Y size returned from wasm"))?
    ];
    let mut u_bytes = vec![
        0u8;
        usize::try_from(u_size).map_err(|_| io::Error::other("negative U size returned from wasm"))?
    ];
    let mut v_bytes = vec![
        0u8;
        usize::try_from(v_size).map_err(|_| io::Error::other("negative V size returned from wasm"))?
    ];

    let y_offset = usize::try_from(y_ptr).map_err(|_| io::Error::other("negative Y pointer returned from wasm"))?;
    let u_offset = usize::try_from(u_ptr).map_err(|_| io::Error::other("negative U pointer returned from wasm"))?;
    let v_offset = usize::try_from(v_ptr).map_err(|_| io::Error::other("negative V pointer returned from wasm"))?;

    exports.memory.read(&mut *store, y_offset, &mut y_bytes)?;
    exports.memory.read(&mut *store, u_offset, &mut u_bytes)?;
    exports.memory.read(&mut *store, v_offset, &mut v_bytes)?;

    let rgb_bytes = yuv420_to_rgb_bytes(width, height, &y_bytes, &u_bytes, &v_bytes)?;
    let rgb_size = i32::try_from(rgb_bytes.len())
        .map_err(|_| io::Error::other("RGB output size exceeds i32 range"))?;

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

    if width <= 0 || height <= 0 || framebuffer_ptr <= 0 || framebuffer_size <= 0 {
        return Err(io::Error::other("wasm returned invalid binjgb frame metadata").into());
    }

    let framebuffer_offset = usize::try_from(framebuffer_ptr)
        .map_err(|_| io::Error::other("negative framebuffer pointer returned from wasm"))?;
    let framebuffer_length = usize::try_from(framebuffer_size)
        .map_err(|_| io::Error::other("negative framebuffer size returned from wasm"))?;
    let mut framebuffer_bytes = vec![0u8; framebuffer_length];
    let mut rgb_bytes = Vec::with_capacity(framebuffer_length / 2 * 3);

    exports
        .memory
        .read(&mut *store, framebuffer_offset, &mut framebuffer_bytes)?;

    for chunk in framebuffer_bytes.chunks_exact(2) {
        let pixel = u16::from_le_bytes([chunk[0], chunk[1]]);
        let r5 = ((pixel >> 10) & 0x1f) as u8;
        let g5 = ((pixel >> 5) & 0x1f) as u8;
        let b5 = (pixel & 0x1f) as u8;
        rgb_bytes.push((r5 << 3) | (r5 >> 2));
        rgb_bytes.push((g5 << 3) | (g5 >> 2));
        rgb_bytes.push((b5 << 3) | (b5 >> 2));
    }

    Ok(FrameData {
        frame_index,
        width,
        height,
        rgb_size: i32::try_from(rgb_bytes.len())
            .map_err(|_| io::Error::other("RGB output exceeds i32 range"))?,
        rgb_bytes,
    })
}

fn yuv420_to_rgb_bytes(width: i32, height: i32, y_bytes: &[u8], u_bytes: &[u8], v_bytes: &[u8]) -> RunnerResult<Vec<u8>> {
    let width_usize = usize::try_from(width).map_err(|_| io::Error::other("negative width returned from wasm"))?;
    let height_usize = usize::try_from(height).map_err(|_| io::Error::other("negative height returned from wasm"))?;
    let uv_width = width_usize / 2;
    let mut rgb = Vec::with_capacity(width_usize * height_usize * 3);

    for y in 0..height_usize {
        let y_row = y * width_usize;
        let uv_row = (y / 2) * uv_width;

        for x in 0..width_usize {
            let y_value = y_bytes[y_row + x] as f32;
            let uv_index = uv_row + (x / 2);
            let cb = u_bytes[uv_index] as f32 - 128.0;
            let cr = v_bytes[uv_index] as f32 - 128.0;
            let r = clamp_byte((y_value + 1.402 * cr).round() as i32);
            let g = clamp_byte((y_value - 0.344_136 * cb - 0.714_136 * cr).round() as i32);
            let b = clamp_byte((y_value + 1.772 * cb).round() as i32);

            rgb.push(r);
            rgb.push(g);
            rgb.push(b);
        }
    }

    Ok(rgb)
}

fn clamp_byte(value: i32) -> u8 {
    if value < 0 {
        return 0;
    }
    if value > 255 {
        return 255;
    }
    value as u8
}

fn required_func<'a, T>(value: Option<&'a T>, message: &str) -> RunnerResult<&'a T> {
    value.ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, message).into())
}

fn ensure_success(value: i32, message: &str) -> RunnerResult<()> {
    if value == 1 {
        return Ok(());
    }

    Err(io::Error::other(message.to_owned()).into())
}

fn basename_without_extension(path: &Path) -> String {
    path.file_stem()
        .and_then(std::ffi::OsStr::to_str)
        .map(str::to_owned)
        .unwrap_or_else(|| String::from("output"))
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
