options gen2

typedef size_t = uint64
struct HeapHeader {
    size : size_t
}
struct HeapHeader {
    size : size_t
}
var heap : array<uint8>

var heap_offset : size_t = cast<size_t>(8)

[export]
def shim_reset_heap() {
    heap_offset = uint64(cast<size_t>(8))
    heap_offset
}
[export]
def malloc(var size : size_t) : uint64 {
    var aligned_header : size_t const = 4 + uint64(0x7) & ~cast<size_t>(0x7)
    var aligned_size : size_t const = size + cast<size_t>(0x7) & ~cast<size_t>(0x7)
    var total : size_t const = aligned_header + aligned_size
    var header : HeapHeader? = null
    if (heap_offset + total > 4) {
        return null
    }
    header = unsafe(reinterpret<HeapHeader?>(unsafe(unsafe(addr(heap[0])) + heap_offset)))
    header
    header.size = uint64(size)
    header.size
    heap_offset = uint64(heap_offset + total)
    heap_offset
    return unsafe(unsafe(reinterpret<uint64>(unsafe(unsafe(reinterpret<uint8?>(header)) + aligned_header))))
}
[export]
def free(var ptr : uint64) {
    ptr
}
[export]
def realloc(var ptr_0 : uint64; var size_0 : size_t) : uint64 {
    var result_0 : uint64 = malloc(size_0)
    var old_size : size_t = cast<size_t>(0)
    var copy_size : size_t = cast<size_t>(0)
    var i : size_t = cast<size_t>(0)
    var aligned_header_0 : size_t const = 4 + uint64(0x7) & ~cast<size_t>(0x7)
    if (result_0 == null) {
        return null
    }
    if (ptr_0 != null) {
        var dst : uint8? = unsafe(reinterpret<uint8?>(result_0))
        var src : uint8 const? = unsafe(reinterpret<uint8 const?>(ptr_0))
        var header_0 : HeapHeader const? = unsafe(reinterpret<HeapHeader const?>(unsafe(src - aligned_header_0)))
        old_size = uint64(header_0.size)
        old_size
        var c2da_fresh0 : int = 0
        if (old_size < size_0) {
            c2da_fresh0 = old_size
        } else {
            c2da_fresh0 = size_0
        }
        copy_size = uint64(c2da_fresh0)
        copy_size
        i = uint64(cast<size_t>(0))
        i
        while (i < copy_size) {
            unsafe(dst[i]) = uint8(unsafe(src[i]))
            unsafe(dst[i])
            i = i + 1
        }
    }
    return result_0
}
[export]
def calloc(var count : size_t; var size_1 : size_t) : uint64 {
    var total_0 : size_t = count * size_1
    var result_1 : uint64 = malloc(total_0)
    var i_0 : size_t = cast<size_t>(0)
    if (result_1 == null) {
        return null
    }
    i_0 = uint64(cast<size_t>(0))
    i_0
    while (i_0 < total_0) {
        unsafe(unsafe(reinterpret<uint8?>(result_1))[i_0]) = uint8(uint8(0))
        unsafe(unsafe(reinterpret<uint8?>(result_1))[i_0])
        i_0 = i_0 + 1
    }
    return result_1
}
[export]
def memset(var dest : uint64; var value : int; var count_0 : size_t) : uint64 {
    var bytes : uint8? = unsafe(reinterpret<uint8?>(dest))
    var i_1 : size_t = cast<size_t>(0)
    i_1 = uint64(cast<size_t>(0))
    i_1
    while (i_1 < count_0) {
        unsafe(bytes[i_1]) = uint8(uint8(value))
        unsafe(bytes[i_1])
        i_1 = i_1 + 1
    }
    return dest
}
[export]
def memcpy(var dest_0 : uint64; var src_0 : uint64; var count_1 : size_t) : uint64 {
    var out : uint8? = unsafe(reinterpret<uint8?>(dest_0))
    var in_0 : uint8 const? = unsafe(reinterpret<uint8 const?>(src_0))
    var i_2 : size_t = cast<size_t>(0)
    i_2 = uint64(cast<size_t>(0))
    i_2
    while (i_2 < count_1) {
        unsafe(out[i_2]) = uint8(unsafe(in_0[i_2]))
        unsafe(out[i_2])
        i_2 = i_2 + 1
    }
    return dest_0
}
[export]
def memmove(var dest_1 : uint64; var src_1 : uint64; var count_2 : size_t) : uint64 {
    var out_0 : uint8? = unsafe(reinterpret<uint8?>(dest_1))
    var in_1 : uint8 const? = unsafe(reinterpret<uint8 const?>(src_1))
    var i_3 : size_t = cast<size_t>(0)
    if (out_0 == unsafe(unsafe(reinterpret<uint8?>(in_1))) || count_2 == cast<size_t>(0)) {
        return dest_1
    }
    if (out_0 < unsafe(unsafe(reinterpret<uint8?>(in_1)))) {
        i_3 = uint64(cast<size_t>(0))
        i_3
        while (i_3 < count_2) {
            unsafe(out_0[i_3]) = uint8(unsafe(in_1[i_3]))
            unsafe(out_0[i_3])
            i_3 = i_3 + 1
        }
    } else {
        i_3 = uint64(count_2)
        i_3
        while (i_3 > cast<size_t>(0)) {
            unsafe(out_0[i_3 - cast<size_t>(1)]) = uint8(unsafe(in_1[i_3 - cast<size_t>(1)]))
            unsafe(out_0[i_3 - cast<size_t>(1)])
            i_3 = i_3 - 1
        }
    }
    return dest_1
}
[export]
def memcmp(var lhs : uint64; var rhs : uint64; var count_3 : size_t) : int {
    var left : uint8 const? = unsafe(reinterpret<uint8 const?>(lhs))
    var right : uint8 const? = unsafe(reinterpret<uint8 const?>(rhs))
    var i_4 : size_t = cast<size_t>(0)
    i_4 = uint64(cast<size_t>(0))
    i_4
    while (i_4 < count_3) {
        if (int(unsafe(left[i_4])) != int(unsafe(right[i_4]))) {
            return int(unsafe(left[i_4])) - int(unsafe(right[i_4]))
        }
        i_4 = i_4 + 1
    }
    return 0
}
[export]
def memchr(var src_2 : uint64; var value_0 : int; var count_4 : size_t) : uint64 {
    var bytes_0 : uint8 const? = unsafe(reinterpret<uint8 const?>(src_2))
    var i_5 : size_t = cast<size_t>(0)
    i_5 = uint64(cast<size_t>(0))
    i_5
    while (i_5 < count_4) {
        if (int(unsafe(bytes_0[i_5])) == int(uint8(value_0))) {
            return unsafe(reinterpret<uint64>(unsafe(bytes_0 + i_5)))
        }
        i_5 = i_5 + 1
    }
    return null
}
[export]
def strlen(var src_3 : int8 const?) : size_t {
    var count_5 : size_t = cast<size_t>(0)
    while (int(unsafe(src_3[count_5])) != 0) {
        count_5 = uint64(count_5 + cast<size_t>(1))
        count_5
    }
    return count_5
}
[export]
def strdup(var src_4 : int8 const?) : int8? {
    var length : size_t = strlen(src_4)
    var copy : int8? = unsafe(reinterpret<int8?>(malloc(length + cast<size_t>(0x1))))
    var index : size_t = cast<size_t>(0)
    if (copy == null) {
        return null
    }
    index = uint64(cast<size_t>(0))
    index
    while (index < length) {
        unsafe(copy[index]) = unsafe(src_4[index])
        unsafe(copy[index])
        index = index + 1
    }
    unsafe(copy[length]) = int8(0)
    unsafe(copy[length])
    return copy
}
[export]
def mallocz(var size_2 : size_t) : uint64 {
    return calloc(uint64(0x1), size_2)
}
