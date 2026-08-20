use std::io::Cursor;

static mut HEAP: [u8; 1024 * 1024 * 4] = [0; 1024 * 1024 * 4];
static mut HEAP_OFFSET: usize = 0;

#[no_mangle]
pub extern "C" fn gltf_host_alloc(size: i32) -> i32 {
    let size = size as usize;
    if size == 0 { return 0; }
    let offset = unsafe { HEAP_OFFSET };
    if offset + size > unsafe { HEAP.len() } { return 0; }
    unsafe { HEAP_OFFSET = offset + size };
    (unsafe { HEAP.as_ptr() as usize } + offset) as i32
}

#[no_mangle]
pub extern "C" fn gltf_host_load(_ptr: i32, _len: i32) -> i32 {
    1
}

#[no_mangle]
pub extern "C" fn gltf_compute_hash(ptr: i32, len: i32) -> i32 {
    if ptr == 0 || len <= 0 { return -1; }
    let bytes = unsafe { std::slice::from_raw_parts(ptr as *const u8, len as usize) };
    gltf_parse_and_hash(bytes)
}

fn gltf_parse_and_hash(bytes: &[u8]) -> i32 {
    let cursor = Cursor::new(bytes);
    let gltf = match gltf::Gltf::from_reader(cursor) {
        Ok(g) => g,
        Err(_) => return -1,
    };

    let meshes = gltf.meshes().count() as u32;
    let animations = gltf.animations().count() as u32;
    let nodes = gltf.nodes().count() as u32;
    let skins = gltf.skins().count() as u32;
    let scenes = gltf.scenes().count() as u32;

    let mut hash: u32 = 0x811C9DC5;
    hash ^= meshes; hash = hash.rotate_left(3);
    hash ^= animations; hash = hash.rotate_left(3);
    hash ^= nodes; hash = hash.rotate_left(3);
    hash ^= skins; hash = hash.rotate_left(3);
    hash ^= scenes; hash = hash.rotate_left(3);

    for (i, mesh) in gltf.meshes().enumerate() {
        let name = mesh.name().unwrap_or("").as_bytes();
        let name_hash = hash_bytes(name);
        hash ^= name_hash.wrapping_add(i as u32 * 0x9E3779B9);
        hash = hash.rotate_left(7);
    }

    for (i, animation) in gltf.animations().enumerate() {
        let name = animation.name().unwrap_or("").as_bytes();
        let name_hash = hash_bytes(name);
        hash ^= name_hash.wrapping_add(i as u32 * 0x9E3779B9);
        hash = hash.rotate_left(7);
        hash ^= animation.channels().count() as u32;
        hash = hash.rotate_left(3);
    }

    for (i, node) in gltf.nodes().enumerate() {
        let name_hash = hash_bytes(node.name().unwrap_or("").as_bytes());
        hash ^= name_hash.wrapping_add(i as u32 * 0x9E3779B9);
        hash = hash.rotate_left(7);
        if node.mesh().is_some() { hash ^= 0x4D455348; hash = hash.rotate_left(3); }
        if node.skin().is_some() { hash ^= 0x534B494E; hash = hash.rotate_left(3); }
    }

    hash as i32
}

fn hash_bytes(bytes: &[u8]) -> u32 {
    let mut hash: u32 = 0x811C9DC5;
    for &b in bytes {
        hash ^= b as u32;
        hash = hash.wrapping_mul(16777619);
        hash = hash.rotate_left(5);
    }
    hash
}
