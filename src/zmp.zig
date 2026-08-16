const std = @import("std");

pub const version: u8 = 1;
pub const max_subject_length: usize = 256;
pub const max_payload_length: usize = 64 * 1024;

pub const DeliveryMode = enum { fast, acked, exact };

pub const FrameType = enum { hello, publish, subscribe, unsubscribe, ack, ping, pong, bye };

pub const Frame = struct {
    kind: FrameType,
    mode: DeliveryMode = .fast,
    id: u64 = 0,
    subject: []const u8 = "",
    payload: []const u8 = "",
};

pub const ParseError = error{
    EmptyFrame,
    InvalidVersion,
    InvalidCommand,
    InvalidMode,
    InvalidId,
    InvalidLength,
    MissingField,
    SubjectTooLong,
    PayloadTooLong,
    InvalidPayload,
};

fn parseMode(text: []const u8) ParseError!DeliveryMode {
    if (std.mem.eql(u8, text, "fast")) return .fast;
    if (std.mem.eql(u8, text, "acked")) return .acked;
    if (std.mem.eql(u8, text, "exact")) return .exact;
    return error.InvalidMode;
}

fn parseKind(text: []const u8) ParseError!FrameType {
    if (std.mem.eql(u8, text, "HELLO")) return .hello;
    if (std.mem.eql(u8, text, "PUB")) return .publish;
    if (std.mem.eql(u8, text, "SUB")) return .subscribe;
    if (std.mem.eql(u8, text, "UNSUB")) return .unsubscribe;
    if (std.mem.eql(u8, text, "ACK")) return .ack;
    if (std.mem.eql(u8, text, "PING")) return .ping;
    if (std.mem.eql(u8, text, "PONG")) return .pong;
    if (std.mem.eql(u8, text, "BYE")) return .bye;
    return error.InvalidCommand;
}

fn parseId(text: []const u8) ParseError!u64 {
    return std.fmt.parseInt(u64, text, 10) catch error.InvalidId;
}

fn validateSubject(subject: []const u8) ParseError!void {
    if (subject.len == 0) return error.MissingField;
    if (subject.len > max_subject_length) return error.SubjectTooLong;
}

/// Parse a complete ZMP frame. The header is ASCII and the payload is length-delimited.
/// Header form: `ZMP/1 COMMAND [mode] [id] [subject] [payload_length]\r\n`.
pub fn parse(frame: []const u8) ParseError!Frame {
    const header_end = std.mem.indexOf(u8, frame, "\r\n") orelse return error.InvalidLength;
    const header = frame[0..header_end];
    var tokens = std.mem.tokenizeScalar(u8, header, ' ');
    const magic = tokens.next() orelse return error.EmptyFrame;
    if (!std.mem.eql(u8, magic, "ZMP/1")) return error.InvalidVersion;
    const command = try parseKind(tokens.next() orelse return error.MissingField);
    var result = Frame{ .kind = command };

    switch (command) {
        .hello, .ping, .pong, .bye => {},
        .ack => result.id = try parseId(tokens.next() orelse return error.MissingField),
        .subscribe, .unsubscribe => {
            result.mode = try parseMode(tokens.next() orelse return error.MissingField);
            result.subject = tokens.next() orelse return error.MissingField;
            try validateSubject(result.subject);
        },
        .publish => {
            result.mode = try parseMode(tokens.next() orelse return error.MissingField);
            result.id = try parseId(tokens.next() orelse return error.MissingField);
            result.subject = tokens.next() orelse return error.MissingField;
            try validateSubject(result.subject);
            const payload_length = try std.fmt.parseInt(usize, tokens.next() orelse return error.MissingField, 10);
            if (payload_length > max_payload_length) return error.PayloadTooLong;
            const payload_start = header_end + 2;
            if (frame.len -| payload_start != payload_length + 2) return error.InvalidLength;
            if (!std.mem.eql(u8, frame[frame.len - 2 ..], "\r\n")) return error.InvalidPayload;
            result.payload = frame[payload_start .. payload_start + payload_length];
        },
    }
    if (tokens.next() != null) return error.InvalidCommand;
    return result;
}

pub fn encodeHeader(frame: Frame, output: []u8) ![]const u8 {
    return switch (frame.kind) {
        .hello => std.fmt.bufPrint(output, "ZMP/1 HELLO\r\n", .{}),
        .ping => std.fmt.bufPrint(output, "ZMP/1 PING\r\n", .{}),
        .pong => std.fmt.bufPrint(output, "ZMP/1 PONG\r\n", .{}),
        .bye => std.fmt.bufPrint(output, "ZMP/1 BYE\r\n", .{}),
        .ack => std.fmt.bufPrint(output, "ZMP/1 ACK {d}\r\n", .{frame.id}),
        .subscribe => std.fmt.bufPrint(output, "ZMP/1 SUB {s} {s}\r\n", .{ @tagName(frame.mode), frame.subject }),
        .unsubscribe => std.fmt.bufPrint(output, "ZMP/1 UNSUB {s} {s}\r\n", .{ @tagName(frame.mode), frame.subject }),
        .publish => std.fmt.bufPrint(output, "ZMP/1 PUB {s} {d} {s} {d}\r\n", .{ @tagName(frame.mode), frame.id, frame.subject, frame.payload.len }),
    };
}

test "parses compact publish frame" {
    const frame = try parse("ZMP/1 PUB acked 42 sensors.room 5\r\nhello\r\n");
    try std.testing.expectEqual(FrameType.publish, frame.kind);
    try std.testing.expectEqual(DeliveryMode.acked, frame.mode);
    try std.testing.expectEqual(@as(u64, 42), frame.id);
    try std.testing.expectEqualStrings("sensors.room", frame.subject);
    try std.testing.expectEqualStrings("hello", frame.payload);
}

test "parses subscriptions and control frames" {
    const sub = try parse("ZMP/1 SUB fast factory.>\r\n");
    try std.testing.expectEqual(FrameType.subscribe, sub.kind);
    try std.testing.expectEqual(DeliveryMode.fast, sub.mode);
    try std.testing.expectEqualStrings("factory.>", sub.subject);
    const ack = try parse("ZMP/1 ACK 99\r\n");
    try std.testing.expectEqual(@as(u64, 99), ack.id);
}

test "rejects malformed payload lengths" {
    try std.testing.expectError(error.InvalidLength, parse("ZMP/1 PUB fast 1 x 4\r\nabc\r\n"));
    try std.testing.expectError(error.InvalidMode, parse("ZMP/1 SUB nope x\r\n"));
}

test "encodes publish header" {
    var output: [128]u8 = undefined;
    const header = try encodeHeader(.{ .kind = .publish, .mode = .acked, .id = 7, .subject = "a.b", .payload = "xyz" }, &output);
    try std.testing.expectEqualStrings("ZMP/1 PUB acked 7 a.b 3\r\n", header);
}
