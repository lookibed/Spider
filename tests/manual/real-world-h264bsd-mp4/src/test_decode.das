options gen2
[export] def main() : int {
    print("h264bsd decoder test\n")
    var w = h264mp4_probe_width()
    print("width={w}\n")
    var h = h264mp4_probe_height()
    print("height={h}\n")
    var fc = h264mp4_probe_frame_count(8)
    print("frame_count={fc}\n")
    return 0
}
