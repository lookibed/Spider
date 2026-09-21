-- SECTION environment
local environment = {}
local named = {}
local selected = nil

-- SECTION bits_u32
local function hn_bits_u32(source)
	return source % 4294967296
end

-- SECTION spectest
-- NEEDS environment
-- NEEDS from_bits_f32
-- NEEDS from_bits_i64
-- NEEDS into_bits_f32
-- NEEDS into_bits_i64
-- NEEDS memory_new
-- NEEDS table_new
do
	local spectest = {
		global_i32 = { 666 },
		global_i64 = { into_bits_i64(666, 0) },
		global_f32 = { into_bits_f32(666.6) },
		global_f64 = { 666.6 },

		table = rt_table_new({}, 10, 10),
		memory = rt_memory_new({}, 65536, 131072),
	}

	spectest.print = print

	function spectest.print_i32(argument)
		print(string.format("I32 `0x%08X`", argument % 4294967296))
	end

	function spectest.print_i64(argument)
		local half_1, half_2 = from_bits_i64(argument)

		print(string.format("I64 `0x%08X%08X`", half_2, half_1))
	end

	function spectest.print_f32(argument)
		argument = from_bits_f32(argument)

		print(string.format("F32 `%g`", argument))
	end

	function spectest.print_f64(argument)
		print(string.format("F64 `%g`", argument))
	end

	function spectest.print_i32_f32(argument_1, argument_2)
		argument_2 = from_bits_f32(argument_2)

		print(string.format("I32 `0x%08X`, F32 `%g`", argument_1 % 4294967296, argument_2))
	end

	function spectest.print_f64_f64(argument_1, argument_2)
		print(string.format("F64 `%g`, F64 `%g`", argument_1, argument_2))
	end

	environment.spectest = spectest
end

-- SECTION report_failure
-- The counter is a global because every section is printed inside its own
-- scope, while the harness epilogue reads the count from the chunk itself.
hn_failed_test_count = 0

function hn_report_failure(content, level, ...)
	local reason = string.format(content, ...)
	local report = debug.traceback(reason, level + 1)

	print(report)

	hn_failed_test_count = hn_failed_test_count + 1
end

-- SECTION assert_ok
-- NEEDS report_failure
function hn_assert_ok(callback)
	xpcall(callback, function(reason)
		hn_report_failure("%s", 2, reason)
	end)
end

-- SECTION assert_trap
-- NEEDS report_failure
function hn_assert_trap(reason, callback)
	if not pcall(callback) then
		return
	end

	hn_report_failure("should trap: %s", 2, reason)
end

-- SECTION assert_ref_null
-- NEEDS report_failure
function hn_assert_ref_null(source)
	if source == nil then
		return
	end

	hn_report_failure("`%s` should be null", 2, tostring(source))
end

-- SECTION assert_ref_extern
-- NEEDS report_failure
function hn_assert_ref_extern(source)
	if source ~= nil then
		return
	end

	hn_report_failure("source should be non null", 2)
end

-- SECTION assert_equal_i32
-- NEEDS bits_u32
-- NEEDS report_failure
function hn_assert_equal_i32(target)
	target = hn_bits_u32(target)

	return function(source)
		if type(source) ~= "number" then
			hn_report_failure("`%s` should be type `i32`", 2, tostring(source))

			return
		end

		source = hn_bits_u32(source)

		if source ~= target then
			hn_report_failure("`%08X` should equal `%08X`", 2, source, target)
		end
	end
end

-- SECTION assert_equal_i64
-- NEEDS from_bits_i64
-- NEEDS report_failure
function hn_assert_equal_i64(target)
	local target_1, target_2 = from_bits_i64(target)

	return function(source)
		if type(source) ~= "table" then
			hn_report_failure("`%s` should be type `i64`", 2, tostring(source))

			return
		end

		local source_1, source_2 = from_bits_i64(source)

		if source_1 ~= target_1 or source_2 ~= target_2 then
			hn_report_failure(
				"`%08X%08X` should equal `%08X%08X`",
				2,
				source_2,
				source_1,
				target_2,
				target_1
			)
		end
	end
end

-- SECTION is_f32_nan_canonical
-- NEEDS bits_u32
-- NEEDS report_failure
function hn_is_f32_nan_canonical(source)
	if type(source) ~= "number" then
		hn_report_failure("`%s` should be type `f32`", 2, tostring(source))

		return
	end

	local bits = hn_bits_u32(source) % 2147483648

	if bits ~= 2139095040 + 4194304 then
		hn_report_failure("`%08X` should equal canonical `f32` nan", 2, bits)
	end
end

-- SECTION is_f32_nan_arithmetic
-- NEEDS bits_u32
-- NEEDS report_failure
function hn_is_f32_nan_arithmetic(source)
	if type(source) ~= "number" then
		hn_report_failure("`%s` should be type `f32`", 2, tostring(source))

		return
	end

	local bits = hn_bits_u32(source) % 2147483648

	if bits < 2139095040 + 4194304 then
		hn_report_failure("`%08X` should equal arithmetic `f32` nan", 2, bits)
	end
end

-- SECTION assert_equal_f32
-- NEEDS bits_u32
-- NEEDS from_bits_f32
-- NEEDS report_failure
function hn_assert_equal_f32(target)
	target = hn_bits_u32(target)

	return function(source)
		if type(source) ~= "number" then
			hn_report_failure("`%s` should be type `f32`", 2, tostring(source))

			return
		end

		source = hn_bits_u32(source)

		if source ~= target then
			hn_report_failure(
				"`%08X` (%s) should equal `%08X` (%s)",
				2,
				source,
				tostring(from_bits_f32(source)),
				target,
				tostring(from_bits_f32(target))
			)
		end
	end
end

-- SECTION is_f64_nan_canonical
-- NEEDS into_bits_f64
-- NEEDS report_failure
function hn_is_f64_nan_canonical(source)
	if type(source) ~= "number" then
		hn_report_failure("`%s` should be type `f64`", 2, tostring(source))

		return
	end

	local source_1, source_2 = into_bits_f64(source)

	source_2 = source_2 % 2147483648

	if source_1 ~= 0 or source_2 ~= 2146435072 + 524288 then
		hn_report_failure("`%08X%08X` should equal canonical `f64` nan", 2, source_2, source_1)
	end
end

-- SECTION is_f64_nan_arithmetic
-- NEEDS into_bits_f64
-- NEEDS report_failure
function hn_is_f64_nan_arithmetic(source)
	if type(source) ~= "number" then
		hn_report_failure("`%s` should be type `f64`", 2, tostring(source))

		return
	end

	local source_1, source_2 = into_bits_f64(source)

	source_2 = source_2 % 2147483648

	if source_2 < 2146435072 + 524288 then
		hn_report_failure("`%08X%08X` should equal arithmetic `f64` nan", 2, source_2, source_1)
	end
end

-- SECTION assert_equal_f64
-- NEEDS into_bits_f64
-- NEEDS report_failure
function hn_assert_equal_f64(target_1, target_2)
	return function(source)
		if type(source) ~= "number" then
			hn_report_failure("`%s` should be type `f64`", 2, tostring(source))

			return
		end

		local source_1, source_2 = into_bits_f64(source)

		if source_1 ~= target_1 or source_2 ~= target_2 then
			hn_report_failure(
				"`%08X%08X` (%s) should equal `%08X%08X`",
				2,
				source_2,
				source_1,
				tostring(source),
				target_2,
				target_1
			)
		end
	end
end
