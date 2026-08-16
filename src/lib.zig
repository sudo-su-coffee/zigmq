const std = @import("std");
const protocol = @import("root.zig");

pub const version: [*:0]const u8 = "0.2.0";

pub export fn zigmq_version() [*:0]const u8 {
    return version;
}

pub export fn zigmq_validate_subject(pointer: [*]const u8, length: usize, allow_wildcards: bool) bool {
    protocol.validateSubject(pointer[0..length], allow_wildcards) catch return false;
    return true;
}

pub export fn zigmq_subject_matches(pattern_pointer: [*]const u8, pattern_length: usize, subject_pointer: [*]const u8, subject_length: usize) bool {
    return protocol.subjectMatches(pattern_pointer[0..pattern_length], subject_pointer[0..subject_length]);
}

pub export fn zigmq_fnv1a64(pointer: [*]const u8, length: usize) u64 {
    var hash: u64 = 14695981039346656037;
    for (pointer[0..length]) |byte| {
        hash ^= byte;
        hash *%= 1099511628211;
    }
    return hash;
}

pub export fn zigmq_pub_frame_size(subject_pointer: [*]const u8, subject_length: usize, payload_length: usize) usize {
    if (protocol.validateTopic(subject_pointer[0..subject_length])) |_| {} else |_| return 0;
    if (payload_length > protocol.max_payload_length) return 0;
    var header: [512]u8 = undefined;
    const header_bytes = std.fmt.bufPrint(&header, "PUB {d} {d}\r\n", .{ subject_length, payload_length }) catch return 0;
    return header_bytes.len + subject_length + payload_length + 2;
}

pub export fn zigmq_encode_pub_frame(
    subject_pointer: [*]const u8,
    subject_length: usize,
    payload_pointer: [*]const u8,
    payload_length: usize,
    output_pointer: [*]u8,
    output_capacity: usize,
) usize {
    if (protocol.validateTopic(subject_pointer[0..subject_length])) |_| {} else |_| return 0;
    if (payload_length > protocol.max_payload_length) return 0;
    var header: [512]u8 = undefined;
    const header_bytes = std.fmt.bufPrint(&header, "PUB {d} {d}\r\n", .{ subject_length, payload_length }) catch return 0;
    const total = header_bytes.len + subject_length + payload_length + 2;
    if (total > output_capacity) return 0;
    @memcpy(output_pointer[0..header_bytes.len], header_bytes);
    @memcpy(output_pointer[header_bytes.len .. header_bytes.len + subject_length], subject_pointer[0..subject_length]);
    const payload_start = header_bytes.len + subject_length;
    @memcpy(output_pointer[payload_start .. payload_start + payload_length], payload_pointer[0..payload_length]);
    @memcpy(output_pointer[payload_start + payload_length .. total], "\r\n");
    return total;
}

test "exported subject helpers" {
    try std.testing.expect(zigmq_validate_subject("sensors.*", 9, true));
    try std.testing.expect(zigmq_subject_matches("sensors.*", 9, "sensors.room", 12));
    try std.testing.expectEqual(@as(u64, 11831194018420276491), zigmq_fnv1a64("hello", 5));
}

test "encodes a length-prefixed publish frame" {
    var output: [128]u8 = undefined;
    const length = zigmq_encode_pub_frame("bench", 5, "hello", 5, &output, output.len);
    try std.testing.expectEqualStrings("PUB 5 5\r\nbenchhello\r\n", output[0..length]);
}
