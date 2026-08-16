const std = @import("std");

pub const max_topic_length: usize = 256;
pub const max_payload_length: usize = 64 * 1024;
pub const max_line_length: usize = max_topic_length + max_payload_length + 32;

pub const Publish = struct {
    topic: []const u8,
    payload: []const u8,
};

pub const Command = union(enum) {
    subscribe: []const u8,
    unsubscribe: []const u8,
    publish: Publish,
    ping,
    pong,
    help,
    quit,
};

pub const ParseError = error{
    EmptyCommand,
    InvalidCommand,
    MissingTopic,
    MissingPayload,
    TopicTooLong,
    PayloadTooLong,
    InvalidTopic,
};

fn isTopicChar(byte: u8) bool {
    return switch (byte) {
        'a'...'z', 'A'...'Z', '0'...'9', '.', '-', '_' => true,
        else => false,
    };
}

pub fn validateTopic(topic: []const u8) ParseError!void {
    if (topic.len == 0) return error.MissingTopic;
    if (topic.len > max_topic_length) return error.TopicTooLong;
    for (topic) |byte| {
        if (!isTopicChar(byte)) return error.InvalidTopic;
    }
}

fn skipSpaces(text: []const u8, start: usize) usize {
    var index = start;
    while (index < text.len and (text[index] == ' ' or text[index] == '\t')) : (index += 1) {}
    return index;
}

fn nextWord(text: []const u8, start: usize) struct { word: []const u8, next: usize } {
    var end = start;
    while (end < text.len and text[end] != ' ' and text[end] != '\t') : (end += 1) {}
    return .{ .word = text[start..end], .next = end };
}

pub fn parseCommand(raw_line: []const u8) ParseError!Command {
    const text = std.mem.trim(u8, raw_line, " \t\r\n");
    if (text.len == 0) return error.EmptyCommand;

    const operation = nextWord(text, 0);
    if (std.ascii.eqlIgnoreCase(operation.word, "PING")) return .ping;
    if (std.ascii.eqlIgnoreCase(operation.word, "PONG")) return .pong;
    if (std.ascii.eqlIgnoreCase(operation.word, "HELP")) return .help;
    if (std.ascii.eqlIgnoreCase(operation.word, "QUIT")) return .quit;

    const argument_start = skipSpaces(text, operation.next);
    if (std.ascii.eqlIgnoreCase(operation.word, "SUB") or std.ascii.eqlIgnoreCase(operation.word, "UNSUB")) {
        const argument = nextWord(text, argument_start);
        if (argument.word.len == 0) return error.MissingTopic;
        if (skipSpaces(text, argument.next) != text.len) return error.InvalidCommand;
        try validateTopic(argument.word);
        if (std.ascii.eqlIgnoreCase(operation.word, "SUB")) return .{ .subscribe = argument.word };
        return .{ .unsubscribe = argument.word };
    }

    if (std.ascii.eqlIgnoreCase(operation.word, "PUB")) {
        const topic_word = nextWord(text, argument_start);
        if (topic_word.word.len == 0) return error.MissingTopic;
        try validateTopic(topic_word.word);
        const payload_start = skipSpaces(text, topic_word.next);
        if (payload_start == text.len) return error.MissingPayload;
        const payload = text[payload_start..];
        if (payload.len > max_payload_length) return error.PayloadTooLong;
        return .{ .publish = .{ .topic = topic_word.word, .payload = payload } };
    }

    return error.InvalidCommand;
}

fn expectParseError(line: []const u8, expected: ParseError) !void {
    try std.testing.expectError(expected, parseCommand(line));
}

test "parses subscription commands case insensitively" {
    const command = try parseCommand("  sUb sensors.room-1  ");
    try std.testing.expectEqualStrings("sensors.room-1", command.subscribe);
}

test "parses publish payload with spaces" {
    const command = try parseCommand("PUB edge.temperature 21.5 degrees C");
    try std.testing.expectEqualStrings("edge.temperature", command.publish.topic);
    try std.testing.expectEqualStrings("21.5 degrees C", command.publish.payload);
}

test "parses control commands" {
    try std.testing.expect((try parseCommand("PING")) == .ping);
    try std.testing.expect((try parseCommand("pong")) == .pong);
    try std.testing.expect((try parseCommand("HELP")) == .help);
    try std.testing.expect((try parseCommand("QUIT")) == .quit);
}

test "rejects malformed commands" {
    try expectParseError("", error.EmptyCommand);
    try expectParseError("SUB", error.MissingTopic);
    try expectParseError("PUB topic", error.MissingPayload);
    try expectParseError("PUB bad/topic value", error.InvalidTopic);
    try expectParseError("NOPE topic", error.InvalidCommand);
}

test "enforces topic length" {
    var topic: [max_topic_length + 1]u8 = undefined;
    @memset(&topic, 'a');
    var line: [max_topic_length + 5]u8 = undefined;
    @memcpy(line[0..4], "SUB ");
    @memcpy(line[4..], &topic);
    try expectParseError(&line, error.TopicTooLong);
}
