const std = @import("std");

const Allocator = std.mem.Allocator;

pub const Item = struct {
    sequence: u64,
    subject: []u8,
    payload: []u8,
};

pub const SequenceResult = enum { accepted, duplicate, gap };

pub const Forwarder = struct {
    allocator: Allocator,
    export_filter: []const u8,
    max_items: usize,
    max_bytes: usize,
    queue: std.ArrayList(Item) = .empty,
    queued_bytes: usize = 0,
    next_sequence: u64 = 1,
    failures: u32 = 0,
    last_received_sequence: u64 = 0,

    pub fn init(allocator: Allocator, export_filter: []const u8, max_items: usize, max_bytes: usize) Forwarder {
        return .{
            .allocator = allocator,
            .export_filter = export_filter,
            .max_items = max_items,
            .max_bytes = max_bytes,
        };
    }

    pub fn deinit(self: *Forwarder) void {
        for (self.queue.items) |item| {
            self.allocator.free(item.subject);
            self.allocator.free(item.payload);
        }
        self.queue.deinit(self.allocator);
    }

    pub fn accepts(self: *const Forwarder, subject: []const u8) bool {
        return subjectMatches(self.export_filter, subject);
    }

    pub fn enqueue(self: *Forwarder, subject: []const u8, payload: []const u8) !u64 {
        if (!self.accepts(subject)) return error.FilterDenied;
        if (self.queue.items.len >= self.max_items or self.queued_bytes + payload.len > self.max_bytes) return error.QueueFull;
        const subject_copy = try self.allocator.dupe(u8, subject);
        errdefer self.allocator.free(subject_copy);
        const payload_copy = try self.allocator.dupe(u8, payload);
        errdefer self.allocator.free(payload_copy);
        const sequence = self.next_sequence;
        self.next_sequence +%= 1;
        if (self.next_sequence == 0) self.next_sequence = 1;
        try self.queue.append(self.allocator, .{ .sequence = sequence, .subject = subject_copy, .payload = payload_copy });
        self.queued_bytes += payload.len;
        return sequence;
    }

    pub fn dequeue(self: *Forwarder) ?Item {
        if (self.queue.items.len == 0) return null;
        const item = self.queue.orderedRemove(0);
        self.queued_bytes -= item.payload.len;
        return item;
    }

    pub fn recordFailure(self: *Forwarder) u64 {
        self.failures +%= 1;
        const shift: u6 = @intCast(@min(self.failures, 6));
        return @min(@as(u64, 60_000), @as(u64, 250) << shift);
    }

    pub fn recordSuccess(self: *Forwarder) void {
        self.failures = 0;
    }

    pub fn acceptSequence(self: *Forwarder, sequence: u64) SequenceResult {
        if (sequence <= self.last_received_sequence) return .duplicate;
        const result: SequenceResult = if (self.last_received_sequence != 0 and sequence != self.last_received_sequence + 1) .gap else .accepted;
        self.last_received_sequence = sequence;
        return result;
    }
};

pub fn encodeLinkFrame(sequence: u64, profile: []const u8, subject: []const u8, payload: []const u8, output: []u8) ![]const u8 {
    if (profile.len == 0 or subject.len == 0 or payload.len > std.math.maxInt(u32)) return error.InvalidFrame;
    const header = try std.fmt.bufPrint(output, "ZMV/1 LINK {d} {s} {s} {d}\r\n", .{ sequence, profile, subject, payload.len });
    const total = header.len + payload.len + 2;
    if (total > output.len) return error.BufferTooSmall;
    @memcpy(output[header.len .. header.len + payload.len], payload);
    @memcpy(output[header.len + payload.len .. total], &[_]u8{ '\r', '\n' });
    return output[0..total];
}

fn subjectMatches(filter: []const u8, subject: []const u8) bool {
    var filter_start: usize = 0;
    var subject_start: usize = 0;
    while (true) {
        const filter_end = filter_start + (std.mem.indexOfScalar(u8, filter[filter_start..], '.') orelse filter.len - filter_start);
        const subject_end = if (subject_start < subject.len) subject_start + (std.mem.indexOfScalar(u8, subject[subject_start..], '.') orelse subject.len - subject_start) else subject_start;
        const filter_token = filter[filter_start..filter_end];
        if (std.mem.eql(u8, filter_token, ">")) return true;
        if (subject_start >= subject.len) return false;
        const subject_token = subject[subject_start..subject_end];
        if (!std.mem.eql(u8, filter_token, "*") and !std.mem.eql(u8, filter_token, subject_token)) return false;
        const filter_done = filter_end == filter.len;
        const subject_done = subject_end == subject.len;
        if (filter_done or subject_done) return filter_done and subject_done;
        filter_start = filter_end + 1;
        subject_start = subject_end + 1;
    }
}

test "edge forwarder filters, bounds, sequences, and frees dequeued items" {
    var forwarder = Forwarder.init(std.testing.allocator, "telemetry.>", 1, 8);
    defer forwarder.deinit();
    try std.testing.expectError(error.FilterDenied, forwarder.enqueue("commands.open", "x"));
    try std.testing.expectEqual(@as(u64, 1), try forwarder.enqueue("telemetry.site1", "1234"));
    try std.testing.expectError(error.QueueFull, forwarder.enqueue("telemetry.site2", "x"));
    const item = forwarder.dequeue().?;
    defer std.testing.allocator.free(item.subject);
    defer std.testing.allocator.free(item.payload);
    try std.testing.expectEqualStrings("telemetry.site1", item.subject);
    try std.testing.expectEqual(@as(u64, 250), forwarder.recordFailure());
    try std.testing.expectEqual(@as(u64, 500), forwarder.recordFailure());
    forwarder.recordSuccess();
    try std.testing.expectEqual(@as(u64, 250), forwarder.recordFailure());
    try std.testing.expectEqual(SequenceResult.accepted, forwarder.acceptSequence(1));
    try std.testing.expectEqual(SequenceResult.duplicate, forwarder.acceptSequence(1));
    try std.testing.expectEqual(SequenceResult.gap, forwarder.acceptSequence(3));
}

test "encodes binary-safe edge link frames" {
    var output: [128]u8 = undefined;
    const frame = try encodeLinkFrame(7, "durable", "edge.commands", "A\x00B", &output);
    try std.testing.expect(std.mem.startsWith(u8, frame, "ZMV/1 LINK 7 durable edge.commands 3\r\n"));
    try std.testing.expectEqual(@as(u8, 0), frame[frame.len - 3]);
    try std.testing.expectEqualStrings("\r\n", frame[frame.len - 2 ..]);
}
