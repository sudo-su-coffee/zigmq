const std = @import("std");

pub const zigmv_state = @import("zigmv_state.zig");
pub const zigmv_persist = @import("zigmv_persist.zig");
pub const zigmv_edge = @import("zigmv_edge.zig");
pub const metrics = @import("metrics.zig");
pub const zigmv_link = @import("zigmv_link.zig");
pub const zigmv_tenant = @import("zigmv_tenant.zig");

pub const version = "0.6.0";

pub const max_topic_length: usize = 256;
pub const max_payload_length: usize = 64 * 1024;
pub const max_control_line_length: usize = 1024;
pub const max_queue_messages: usize = 32;
pub const max_queue_bytes: usize = 256 * 1024;
pub const max_clients: usize = 1024;
pub const max_preauth_commands: usize = 8;
pub const max_subscriptions_per_client: usize = 1024;
pub const max_nats_subscriptions_per_client: usize = 1024;
pub const max_mqtt_subscriptions_per_client: usize = 1024;

pub const Publish = struct {
    topic: []const u8,
    payload: []const u8,
};

pub const Command = union(enum) {
    subscribe: struct { subject: []const u8, group: ?[]const u8 },
    unsubscribe: []const u8,
    publish: Publish,
    retain: struct { topic: []const u8, ttl_ms: u64, payload: []const u8 },
    request: struct { topic: []const u8, reply: []const u8, payload: []const u8 },
    replay: struct { from_sequence: u64, subject: []const u8 },
    auth: []const u8,
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
    MissingTtl,
    InvalidTtl,
    MissingSequence,
    InvalidSequence,
    MissingToken,
    TopicTooLong,
    PayloadTooLong,
    InvalidTopic,
    WildcardNotAllowed,
};

fn isSubjectChar(byte: u8, allow_wildcards: bool) bool {
    return switch (byte) {
        'a'...'z', 'A'...'Z', '0'...'9', '.', '-', '_' => true,
        '*', '>' => allow_wildcards,
        else => false,
    };
}

pub fn validateTopic(topic: []const u8) ParseError!void {
    return validateSubject(topic, false);
}

pub fn validateSubject(pattern: []const u8, allow_wildcards: bool) ParseError!void {
    if (pattern.len == 0) return error.MissingTopic;
    if (pattern.len > max_topic_length) return error.TopicTooLong;

    var start: usize = 0;
    while (start < pattern.len) {
        const relative_end = std.mem.indexOfScalar(u8, pattern[start..], '.') orelse pattern.len - start;
        const end = start + relative_end;
        const token = pattern[start..end];
        if (token.len == 0) return error.InvalidTopic;
        for (token) |byte| {
            if (!isSubjectChar(byte, allow_wildcards)) {
                if (byte == '*' or byte == '>') return error.WildcardNotAllowed;
                return error.InvalidTopic;
            }
        }
        if (token.len > 1 and (std.mem.indexOfScalar(u8, token, '*') != null or std.mem.indexOfScalar(u8, token, '>') != null)) {
            return error.InvalidTopic;
        }
        if (std.mem.eql(u8, token, ">") and end != pattern.len) return error.InvalidTopic;
        if (end == pattern.len) break;
        start = end + 1;
    }
}

pub fn subjectMatches(pattern: []const u8, subject: []const u8) bool {
    var pattern_start: usize = 0;
    var subject_start: usize = 0;
    while (true) {
        const pattern_relative_end = std.mem.indexOfScalar(u8, pattern[pattern_start..], '.') orelse pattern.len - pattern_start;
        const pattern_end = pattern_start + pattern_relative_end;
        const pattern_token = pattern[pattern_start..pattern_end];
        if (std.mem.eql(u8, pattern_token, ">")) return true;

        if (subject_start >= subject.len) return false;
        const subject_relative_end = std.mem.indexOfScalar(u8, subject[subject_start..], '.') orelse subject.len - subject_start;
        const subject_end = subject_start + subject_relative_end;
        const subject_token = subject[subject_start..subject_end];
        if (!std.mem.eql(u8, pattern_token, "*") and !std.mem.eql(u8, pattern_token, subject_token)) return false;

        const pattern_done = pattern_end == pattern.len;
        const subject_done = subject_end == subject.len;
        if (pattern_done or subject_done) return pattern_done and subject_done;
        pattern_start = pattern_end + 1;
        subject_start = subject_end + 1;
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
    if (std.ascii.eqlIgnoreCase(operation.word, "AUTH")) {
        const token = nextWord(text, argument_start);
        if (token.word.len == 0) return error.MissingToken;
        if (skipSpaces(text, token.next) != text.len) return error.InvalidCommand;
        return .{ .auth = token.word };
    }

    if (std.ascii.eqlIgnoreCase(operation.word, "SUB") or std.ascii.eqlIgnoreCase(operation.word, "UNSUB")) {
        const argument = nextWord(text, argument_start);
        if (argument.word.len == 0) return error.MissingTopic;
        try validateSubject(argument.word, true);
        var group: ?[]const u8 = null;
        const group_start = skipSpaces(text, argument.next);
        if (group_start != text.len) {
            const group_word = nextWord(text, group_start);
            if (skipSpaces(text, group_word.next) != text.len) return error.InvalidCommand;
            try validateTopic(group_word.word);
            group = group_word.word;
        }
        if (std.ascii.eqlIgnoreCase(operation.word, "SUB")) return .{ .subscribe = .{ .subject = argument.word, .group = group } };
        if (group != null) return error.InvalidCommand;
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

    if (std.ascii.eqlIgnoreCase(operation.word, "RETAIN")) {
        const topic_word = nextWord(text, argument_start);
        if (topic_word.word.len == 0) return error.MissingTopic;
        try validateTopic(topic_word.word);
        const ttl_word = nextWord(text, skipSpaces(text, topic_word.next));
        if (ttl_word.word.len == 0) return error.MissingTtl;
        const ttl_ms = std.fmt.parseInt(u64, ttl_word.word, 10) catch return error.InvalidTtl;
        const payload_start = skipSpaces(text, ttl_word.next);
        if (payload_start == text.len) return error.MissingPayload;
        const payload = text[payload_start..];
        if (payload.len > max_payload_length) return error.PayloadTooLong;
        return .{ .retain = .{ .topic = topic_word.word, .ttl_ms = ttl_ms, .payload = payload } };
    }

    if (std.ascii.eqlIgnoreCase(operation.word, "REPLAY")) {
        const sequence_word = nextWord(text, argument_start);
        if (sequence_word.word.len == 0) return error.MissingSequence;
        const from_sequence = std.fmt.parseInt(u64, sequence_word.word, 10) catch return error.InvalidSequence;
        const subject_word = nextWord(text, skipSpaces(text, sequence_word.next));
        if (subject_word.word.len == 0) return error.MissingTopic;
        if (skipSpaces(text, subject_word.next) != text.len) return error.InvalidCommand;
        try validateSubject(subject_word.word, true);
        return .{ .replay = .{ .from_sequence = from_sequence, .subject = subject_word.word } };
    }

    if (std.ascii.eqlIgnoreCase(operation.word, "REQ")) {
        const topic_word = nextWord(text, argument_start);
        if (topic_word.word.len == 0) return error.MissingTopic;
        try validateTopic(topic_word.word);
        const reply_word = nextWord(text, skipSpaces(text, topic_word.next));
        if (reply_word.word.len == 0) return error.MissingTopic;
        try validateTopic(reply_word.word);
        const payload_start = skipSpaces(text, reply_word.next);
        if (payload_start == text.len) return error.MissingPayload;
        const payload = text[payload_start..];
        if (payload.len > max_payload_length) return error.PayloadTooLong;
        return .{ .request = .{ .topic = topic_word.word, .reply = reply_word.word, .payload = payload } };
    }

    return error.InvalidCommand;
}

fn expectParseError(line: []const u8, expected: ParseError) !void {
    try std.testing.expectError(expected, parseCommand(line));
}

test "parses subscription commands case insensitively" {
    const command = try parseCommand("  sUb sensors.room-1  ");
    try std.testing.expectEqualStrings("sensors.room-1", command.subscribe.subject);
    try std.testing.expect(command.subscribe.group == null);
}

test "parses publish payload with spaces" {
    const command = try parseCommand("PUB edge.temperature 21.5 degrees C");
    try std.testing.expectEqualStrings("edge.temperature", command.publish.topic);
    try std.testing.expectEqualStrings("21.5 degrees C", command.publish.payload);
}

test "parses grouped, retained, and request commands" {
    const grouped = try parseCommand("SUB jobs.created workers");
    try std.testing.expectEqualStrings("jobs.created", grouped.subscribe.subject);
    try std.testing.expectEqualStrings("workers", grouped.subscribe.group.?);
    const retained = try parseCommand("RETAIN sensors.room 5000 21.5");
    try std.testing.expectEqual(@as(u64, 5000), retained.retain.ttl_ms);
    const request = try parseCommand("REQ inventory.check _reply.1 item-42");
    try std.testing.expectEqualStrings("_reply.1", request.request.reply);
    const replay = try parseCommand("REPLAY 42 sensors.>");
    try std.testing.expectEqual(@as(u64, 42), replay.replay.from_sequence);
}

test "parses auth commands" {
    const command = try parseCommand("AUTH edge-secret");
    try std.testing.expectEqualStrings("edge-secret", command.auth);
}

test "rejects malformed commands" {
    try expectParseError("", error.EmptyCommand);
    try expectParseError("SUB", error.MissingTopic);
    try expectParseError("PUB topic", error.MissingPayload);
    try expectParseError("PUB bad/topic value", error.InvalidTopic);
    try expectParseError("AUTH", error.MissingToken);
    try expectParseError("NOPE topic", error.InvalidCommand);
}

test "validates wildcard patterns" {
    try validateSubject("sensors.*", true);
    try validateSubject("sensors.>", true);
    try validateSubject("sensors.*.room", true);
    try expectParseError("SUB sensors.>.room", error.InvalidTopic);
    try std.testing.expectError(error.WildcardNotAllowed, validateTopic("sensors.*"));
}

test "matches exact and wildcard subjects" {
    try std.testing.expect(subjectMatches("sensors.room1", "sensors.room1"));
    try std.testing.expect(!subjectMatches("sensors.room1", "sensors.room2"));
    try std.testing.expect(subjectMatches("sensors.*", "sensors.room2"));
    try std.testing.expect(!subjectMatches("sensors.*", "sensors.room2.temp"));
    try std.testing.expect(subjectMatches("sensors.>", "sensors.room2.temp"));
    try std.testing.expect(subjectMatches(">", "anything.deep.inside"));
}
