Note: current manual test paths live under `tests/manual/fixtures/`, `tests/manual/generated/`, and `tests/manual/main.lua`. The command transcript below is historical.

D:\Backups\Spider>.\target\release\spider-cli.exe -t lua-no-ffi -o test_pure.wasm > test.lua

thread 'main' (14260) panicked at Targets\LuaNoFFI\Printer\src\library\sections.rs:167:33:
`transmute_n32` is not a section
note: run with `RUST_BACKTRACE=1` environment variable to display a backtrace

что за ошибка в чем причина выяснить и отчитаться(НЕ ИСПРАВЛЯТЬ!)
