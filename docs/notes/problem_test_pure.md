Note: current manual test paths live under `tests/manual/fixtures/`, `tests/manual/generated/`, and `tests/manual/main.lua`. The command transcript below is historical.

D:\Backups\Spider>.\target\release\spider-cli.exe -t lua-jit -o test_pure.wasm > test.lua

D:\Backups\Spider>luajit main.lua
Starting LuaJIT benchmark...
luajit: main.lua:4: attempt to call local 'wasm_module_loader' (a nil value)
stack traceback:
        main.lua:4: in main chunk
        [C]: at 0x7ff79f0a4830

D:\Backups\Spider>luajit main.lua
Starting LuaJIT benchmark...
Result (Hash): 84991312
LuaJIT Execution time: 1.4270 seconds

D:\Backups\Spider>.\target\release\spider-cli.exe -t lua-no-ffi -o test_pure.wasm > test.lua

D:\Backups\Spider>luajit main.lua
Starting LuaJIT benchmark...
luajit: test.lua:17: attempt to call global 'buffer_write_u32' (a nil value)
stack traceback:
        test.lua:17: in function 'buffer_write_f32'
        test.lua:25: in function 'rt_convert_s32_to_f32'
        test.lua:107: in function 'render_frame'
        main.lua:6: in main chunk
        [C]: at 0x7ff79f0a4830

РЕДАКТИРОВАТЬ ИЛИ ЧИТАТЬ test_pure.wasm или main.lua ЗАПРЕЩЕНО!
Как видно таргет lua-jit теперь работает на win10 верно, а с lua-no-ffi Ошибка, почини таргет.
ТЕСТ РАБОТОСПОСОБНОСТИ:
D:\Backups\Spider>.\target\release\spider-cli.exe -t lua-no-ffi -o test_pure.wasm > test.lua
D:\Backups\Spider>luajit main.lua
Ожидаемый вывод main это hash 84991312 и любое время выполнения
