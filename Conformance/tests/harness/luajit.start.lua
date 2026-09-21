-- SECTION environment
local environment = {}
local named = {}
local selected = nil

-- SECTION spectest
-- NEEDS bit
-- NEEDS environment
-- NEEDS from_bits_f32
-- NEEDS from_bits_f64
-- NEEDS into_bits_f32
-- NEEDS into_bits_f64
-- NEEDS memory_new
-- NEEDS table_new
do
	local spectest = {
		global_i32 = { 666 },
		global_i64 = { 666LL },
		global_f32 = { into_bits_f32(666.6) },
		global_f64 = { into_bits_f64(666.6) },

		table = rt_table_new({}, 10, 10),
		memory = rt_memory_new({}, 65536, 131072),
	}

	spectest.print = print

	function spectest.print_i32(argument)
		print(string.format("I32 `0x%s`", string.upper(bit.tohex(argument))))
	end

	function spectest.print_i64(argument)
		-- `string.format` rejects 64 bit cdata for the integer specifiers, so
		-- the halves are rendered by the bit library instead.
		print(string.format("I64 `0x%s`", string.upper(bit.tohex(argument))))
	end

	function spectest.print_f32(argument)
		argument = from_bits_f32(argument)

		print(string.format("F32 `%g`", argument))
	end

	function spectest.print_f64(argument)
		argument = from_bits_f64(argument)

		print(string.format("F64 `%g`", argument))
	end

	function spectest.print_i32_f32(argument_1, argument_2)
		argument_2 = from_bits_f32(argument_2)

		print(string.format("I32 `0x%s`, F32 `%g`", string.upper(bit.tohex(argument_1)), argument_2))
	end

	function spectest.print_f64_f64(argument_1, argument_2)
		argument_1 = from_bits_f64(argument_1)
		argument_2 = from_bits_f64(argument_2)

		print(string.format("F64 `%g`, F64 `%g`", argument_1, argument_2))
	end

	environment.spectest = spectest
end

-- SECTION report_failure
local hn_failed_test_count = 0

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

	hn_report_failure("`%s` should be null", 2, source)
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
-- NEEDS bit
-- NEEDS report_failure
function hn_assert_equal_i32(target)
	return function(source)
		if type(source) ~= "number" then
			hn_report_failure("`%s` should be type `i32`", 2, source)
		elseif source ~= target then
			hn_report_failure(
				"`%s` (%s) should equal `%s` (%s)",
				2,
				string.upper(bit.tohex(source)),
				source,
				string.upper(bit.tohex(target)),
				target
			)
		end
	end
end

-- SECTION assert_equal_i64
-- NEEDS bit
-- NEEDS ffi
-- NEEDS report_failure
function hn_assert_equal_i64(target)
	return function(source)
		if not ffi.istype("int64_t", source) then
			hn_report_failure("`%s` should be type `i64`", 2, source)
		elseif source ~= target then
			hn_report_failure(
				"`%s` (%s) should equal `%s` (%s)",
				2,
				string.upper(bit.tohex(source)),
				source,
				string.upper(bit.tohex(target)),
				target
			)
		end
	end
end

-- SECTION is_f32_nan_canonical
-- NEEDS bit
-- NEEDS bit_and
-- NEEDS report_failure
function hn_is_f32_nan_canonical(source)
	if type(source) ~= "number" then
		hn_report_failure("`%s` should be type `f32`", 2, source)

		return
	end

	-- The canonical `f32` nan has every exponent bit set, the most significant
	-- mantissa bit set and every other mantissa bit clear.
	if bit_and(source, 0x7FFFFFFF) ~= 0x7FC00000 then
		hn_report_failure("`%s` should be a canonical `f32` nan", 2, string.upper(bit.tohex(source)))
	end
end

-- SECTION is_f32_nan_arithmetic
-- NEEDS bit
-- NEEDS bit_and
-- NEEDS report_failure
function hn_is_f32_nan_arithmetic(source)
	if type(source) ~= "number" then
		hn_report_failure("`%s` should be type `f32`", 2, source)

		return
	end

	-- An arithmetic `f32` nan has every exponent bit set and the most
	-- significant mantissa bit set; the remaining payload is unspecified.
	if bit_and(source, 0x7FC00000) ~= 0x7FC00000 then
		hn_report_failure("`%s` should be an arithmetic `f32` nan", 2, string.upper(bit.tohex(source)))
	end
end

-- SECTION assert_equal_f32
-- NEEDS bit
-- NEEDS from_bits_f32
-- NEEDS report_failure
function hn_assert_equal_f32(target)
	return function(source)
		if type(source) ~= "number" then
			hn_report_failure("`%s` should be type `f32`", 2, source)
		elseif source ~= target then
			hn_report_failure(
				"`%s` (%s) should equal `%s` (%s)",
				2,
				string.upper(bit.tohex(source)),
				from_bits_f32(source),
				string.upper(bit.tohex(target)),
				from_bits_f32(target)
			)
		end
	end
end

-- SECTION is_f64_nan_canonical
-- NEEDS bit
-- NEEDS bit_and
-- NEEDS ffi
-- NEEDS report_failure
function hn_is_f64_nan_canonical(source)
	if not ffi.istype("int64_t", source) then
		hn_report_failure("`%s` should be type `f64`", 2, source)

		return
	end

	-- The canonical `f64` nan has every exponent bit set, the most significant
	-- mantissa bit set and every other mantissa bit clear.
	if bit_and(source, 0x7FFFFFFFFFFFFFFFLL) ~= 0x7FF8000000000000LL then
		hn_report_failure("`%s` should be a canonical `f64` nan", 2, string.upper(bit.tohex(source)))
	end
end

-- SECTION is_f64_nan_arithmetic
-- NEEDS bit
-- NEEDS bit_and
-- NEEDS ffi
-- NEEDS report_failure
function hn_is_f64_nan_arithmetic(source)
	if not ffi.istype("int64_t", source) then
		hn_report_failure("`%s` should be type `f64`", 2, source)

		return
	end

	-- An arithmetic `f64` nan has every exponent bit set and the most
	-- significant mantissa bit set; the remaining payload is unspecified.
	if bit_and(source, 0x7FF8000000000000LL) ~= 0x7FF8000000000000LL then
		hn_report_failure("`%s` should be an arithmetic `f64` nan", 2, string.upper(bit.tohex(source)))
	end
end

-- SECTION assert_equal_f64
-- NEEDS bit
-- NEEDS ffi
-- NEEDS from_bits_f64
-- NEEDS report_failure
function hn_assert_equal_f64(target)
	return function(source)
		if not ffi.istype("int64_t", source) then
			hn_report_failure("`%s` should be type `f64`", 2, source)
		elseif source ~= target then
			hn_report_failure(
				"`%s` (%s) should equal `%s` (%s)",
				2,
				string.upper(bit.tohex(source)),
				from_bits_f64(source),
				string.upper(bit.tohex(target)),
				from_bits_f64(target)
			)
		end
	end
end
