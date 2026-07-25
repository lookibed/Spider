
Note: current manual test paths live under `tests/manual/fixtures/`, `tests/manual/generated/`, and `tests/manual/main.lua`. References to root-level `test.lua` below are historical.

---

### Отчет для разработчиков: "Почему Spider lua-jit не работает на Windows x64"

#### 1. В чем была проблема? (The Root Cause)
У `Spider` есть две фундаментальные проблемы при работе под Windows x64:

*   **Проблема А: Защита памяти (DEP - Data Execution Prevention).**
    На Linux/macOS использование `mmap` или простых аллокаторов памяти часто позволяет получить область, которую можно сразу исполнять. Windows, в отличие от них, жестко разделяет память: либо "запись", либо "исполнение". Попытка исполнить код из памяти, выделенной через стандартный `malloc` (как это делает `load_memory_invalid` в Spider), приводит к мгновенному падению процесса (Access Violation) из-за политик безопасности DEP.

*   **Проблема Б: Несоответствие ABI (Calling Convention).**
    `Spider` использует хардкодный машинный код (ассемблер x64) для ускорения операций с плавающей точкой (f32). Проблема в том, что этот ассемблер был написан под **System V AMD64 ABI** (Linux/macOS), где аргументы функции передаются в регистрах `RDI` и `RSI`.
    Однако, **Windows x64 (Microsoft x64 ABI)** ожидает аргументы в регистрах `RCX` и `RDX`. Из-за этого `Spider` читал "мусор" из регистров вместо нужных чисел, что приводило к неверным математическим вычислениям и зависаниям цикла.

---

#### 2. Что мы сделали, чтобы это починить? (The Fix)

Мы пропатчили `test.lua` (транслированный модуль), внедрив в него поддержку Windows ABI.

**Шаг 1: Исправление выделения памяти (VirtualAlloc)**
Мы добавили функцию `load_memory_windows`, которая обращается к `kernel32.dll` через FFI и вызывает `VirtualAlloc` с флагом `PAGE_EXECUTE_READWRITE` (0x40). Это явно разрешает процессору исполнять код из этой области памяти, обходя защиту DEP.

**Шаг 2: Патч ассемблерных вставок под Windows ABI**
Мы переписали блоки машинного кода для x64.
*   *Было (Linux/System V):* Код читал аргументы из `EDI` (`\x66\x0F\x6E\xC7`) и `ESI` (`\x66\x0F\x6E\xCE`).
*   *Стало (Windows):* Код теперь читает аргументы из `ECX` (`\x66\x0F\x6E\xC1`) и `EDX` (`\x66\x0F\x6E\xCA`).

Мы обновили `load_code_platform` в `test.lua`, чтобы он автоматически определял ОС и выбирал нужный ассемблерный блок (или стандартный, если ОС не Windows).

---
**Шаг 3: Костили в test.lua**
```lua
-- Добавили поддержку Windows x64
local function load_code_windows_x64()
    return "\x66\x0F\x6E\xC1\xF3\x0F\x51\xC0\x66\x0F\x7E\xC0\xC3\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC" ..
           "\x66\x0F\x6E\xC1\x66\x0F\x6E\xCA\xF3\x0F\x58\xC1\x66\x0F\x7E\xC0\xC3\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC" ..
           "\x66\x0F\x6E\xC1\x66\x0F\x6E\xCA\xF3\x0F\x5C\xC1\x66\x0F\x7E\xC0\xC3\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC" ..
           "\x66\x0F\x6E\xC1\x66\x0F\x6E\xCA\xF3\x0F\x59\xC1\x66\x0F\x7E\xC0\xC3\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC" ..
           "\x66\x0F\x6E\xC1\x66\x0F\x6E\xCA\xF3\x0F\x5E\xC1\x66\x0F\x7E\xC0\xC3\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC\xCC"
end

-- Изменили функцию загрузки кода для разных платформ
local function load_code_platform()
    if jit.arch == "x64" then
        if jit.os == "Windows" then
            return load_code_windows_x64() -- НАШ ИНЖЕКТ ДЛЯ WINDOWS!
        else
            return load_code_x64()
        end
    elseif jit.arch == "arm64" then
        return load_code_arm64()
    else
        -- обработка других архитектур
    end
end

-- Добавили функцию для работы с памятью в Windows
local function load_memory_windows(code)
    -- Подключаем Windows API напрямую из ядра!
    ffi.cdef([[
        void* __stdcall VirtualAlloc(void* lpAddress, size_t dwSize, uint32_t flAllocationType, uint32_t flProtect);
    ]])
    
    local kernel32 = ffi.load("kernel32")
    local MEM_COMMIT = 0x1000
    local MEM_RESERVE = 0x2000
    local PAGE_EXECUTE_READWRITE = 0x40 -- ВОТ ОНО! РАЗРЕШЕНИЕ НА ИСПОЛНЕНИЕ!

    -- Просим у винды память, в которой можно запускать машинный код
    local page = kernel32.VirtualAlloc(nil, #code, bit.bor(MEM_COMMIT, MEM_RESERVE), PAGE_EXECUTE_READWRITE)

    if page == nil then
        error("failed to allocate executable memory on Windows")
    end

    -- Копируем туда наш ассемблер
    ffi.copy(page, code, #code)

    return ffi_cast(u8_pointer_type, page)
end

-- Изменили функцию загрузки в память для разных платформ
local function load_memory_platform(code)
    if jit.os == "Linux" then
        return load_memory_linux(code)
    elseif jit.os == "OSX" then
        return load_memory_mac_os(code)
    elseif jit.os == "Windows" then
        -- ТЕПЕРЬ WINDOWS ПОДДЕРЖИВАЕТСЯ НАШИМ ХАКОМ!
        return load_memory_windows(code) 
    else
        return load_memory_invalid(code)
    end
end
```
