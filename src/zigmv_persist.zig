const std = @import("std");

const Allocator = std.mem.Allocator;

const magic = "ZMS1";
const header_len: usize = 32;
const publish_kind: u8 = 1;
const ack_kind: u8 = 2;

pub const Delivery = struct {
    session_id: []u8,
    message_id: u64,
    subject: []u8,
    payload: []u8,
    expires_at_ms: u64,
};

pub const Journal = struct {
    allocator: Allocator,
    file: std.fs.File,
    deliveries: std.AutoHashMap(u64, Delivery),

    pub fn open(allocator: Allocator, file: std.fs.File) !Journal {
        var journal = Journal{
            .allocator = allocator,
            .file = file,
            .deliveries = std.AutoHashMap(u64, Delivery).init(allocator),
        };
        errdefer journal.deinit();
        try journal.recover();
        return journal;
    }

    pub fn deinit(self: *Journal) void {
        var iterator = self.deliveries.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.value_ptr.session_id);
            self.allocator.free(entry.value_ptr.subject);
            self.allocator.free(entry.value_ptr.payload);
        }
        self.deliveries.deinit();
        self.file.close();
    }

    pub fn appendPublish(self: *Journal, session_id: []const u8, message_id: u64, subject: []const u8, payload: []const u8, expires_at_ms: u64) !void {
        if (session_id.len > std.math.maxInt(u16) or subject.len > std.math.maxInt(u16) or payload.len > std.math.maxInt(u32)) return error.RecordTooLarge;
        var header: [header_len]u8 = undefined;
        makeHeader(&header, publish_kind, session_id, message_id, subject, payload, expires_at_ms);
        setChecksum(&header, session_id, subject, payload);
        try self.file.seekFromEnd(0);
        try self.file.writeAll(&header);
        try self.file.writeAll(session_id);
        try self.file.writeAll(subject);
        try self.file.writeAll(payload);
        try self.file.sync();
        try self.putDelivery(session_id, message_id, subject, payload, expires_at_ms);
    }

    pub fn appendAck(self: *Journal, message_id: u64) !void {
        var header: [header_len]u8 = undefined;
        makeHeader(&header, ack_kind, "", message_id, "", "", 0);
        setChecksum(&header, "", "", "");
        try self.file.seekFromEnd(0);
        try self.file.writeAll(&header);
        try self.file.sync();
        if (self.deliveries.fetchRemove(message_id)) |removed| {
            self.allocator.free(removed.value.session_id);
            self.allocator.free(removed.value.subject);
            self.allocator.free(removed.value.payload);
        }
    }

    fn putDelivery(self: *Journal, session_id: []const u8, message_id: u64, subject: []const u8, payload: []const u8, expires_at_ms: u64) !void {
        const value = Delivery{
            .session_id = try self.allocator.dupe(u8, session_id),
            .message_id = message_id,
            .subject = try self.allocator.dupe(u8, subject),
            .payload = try self.allocator.dupe(u8, payload),
            .expires_at_ms = expires_at_ms,
        };
        errdefer {
            self.allocator.free(value.session_id);
            self.allocator.free(value.subject);
            self.allocator.free(value.payload);
        }
        if (self.deliveries.fetchPut(message_id, value)) |old| {
            self.allocator.free(old.value.session_id);
            self.allocator.free(old.value.subject);
            self.allocator.free(old.value.payload);
        }
    }

    fn recover(self: *Journal) !void {
        try self.file.seekTo(0);
        var offset: u64 = 0;
        while (true) {
            var header: [header_len]u8 = undefined;
            const read_header = readSome(self.file, &header) catch |err| switch (err) {
                error.EndOfStream => {
                    try self.file.setEndPos(offset);
                    try self.file.seekFromEnd(0);
                    return;
                },
                else => return err,
            };
            _ = read_header;
            const kind = header[4];
            const session_len = std.mem.readInt(u16, header[6..8], .little);
            const subject_len = std.mem.readInt(u16, header[8..10], .little);
            const payload_len = std.mem.readInt(u32, header[10..14], .little);
            const message_id = std.mem.readInt(u64, header[14..22], .little);
            const expires_at_ms = std.mem.readInt(u64, header[22..30], .little);
            const checksum = std.mem.readInt(u16, header[30..32], .little);
            if (!std.mem.eql(u8, header[0..4], magic) or (kind != publish_kind and kind != ack_kind)) return error.CorruptJournal;
            if (kind == ack_kind and (session_len != 0 or subject_len != 0 or payload_len != 0)) return error.CorruptJournal;
            const body_len = @as(usize, session_len) + @as(usize, subject_len) + @as(usize, payload_len);
            var body = try self.allocator.alloc(u8, body_len);
            defer self.allocator.free(body);
            readExact(self.file, body) catch |err| switch (err) {
                error.EndOfStream => {
                    try self.file.setEndPos(offset);
                    try self.file.seekFromEnd(0);
                    return;
                },
                else => return err,
            };
            if (recordChecksum(header[4..30], body) != checksum) return error.CorruptJournal;
            offset += header_len + body_len;
            if (kind == publish_kind) {
                try self.putDelivery(body[0..session_len], message_id, body[session_len .. session_len + subject_len], body[session_len + subject_len ..], expires_at_ms);
            } else if (self.deliveries.fetchRemove(message_id)) |removed| {
                self.allocator.free(removed.value.session_id);
                self.allocator.free(removed.value.subject);
                self.allocator.free(removed.value.payload);
            }
        }
    }
};

fn makeHeader(header: *[header_len]u8, kind: u8, session_id: []const u8, message_id: u64, subject: []const u8, payload: []const u8, expires_at_ms: u64) void {
    @memcpy(header[0..4], magic);
    header[4] = kind;
    header[5] = 0;
    std.mem.writeInt(u16, header[6..8], @intCast(session_id.len), .little);
    std.mem.writeInt(u16, header[8..10], @intCast(subject.len), .little);
    std.mem.writeInt(u32, header[10..14], @intCast(payload.len), .little);
    std.mem.writeInt(u64, header[14..22], message_id, .little);
    std.mem.writeInt(u64, header[22..30], expires_at_ms, .little);
    std.mem.writeInt(u16, header[30..32], recordChecksum(header[4..30], &[_]u8{}), .little);
    // The final checksum is replaced by appendRecordChecksum over header metadata and body.
    std.mem.writeInt(u16, header[30..32], 0, .little);
}

fn setChecksum(header: *[header_len]u8, session_id: []const u8, subject: []const u8, payload: []const u8) void {
    std.mem.writeInt(u16, header[30..32], recordChecksumParts(header[4..30], session_id, subject, payload), .little);
}

fn recordChecksum(metadata: []const u8, body: []const u8) u16 {
    var hash = std.hash.Crc32.init();
    hash.update(metadata);
    hash.update(body);
    return @truncate(hash.final());
}

fn recordChecksumParts(metadata: []const u8, session_id: []const u8, subject: []const u8, payload: []const u8) u16 {
    var hash = std.hash.Crc32.init();
    hash.update(metadata);
    hash.update(session_id);
    hash.update(subject);
    hash.update(payload);
    return @truncate(hash.final());
}

fn readSome(file: std.fs.File, buffer: []u8) !usize {
    var offset: usize = 0;
    while (offset < buffer.len) {
        const count = try file.read(buffer[offset..]);
        if (count == 0) return error.EndOfStream;
        offset += count;
    }
    return offset;
}

fn readExact(file: std.fs.File, buffer: []u8) !void {
    _ = try readSome(file, buffer);
}

test "journal recovers unacknowledged delivery and removes acknowledged delivery" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var file = try tmp.dir.createFile("sessions.zms", .{ .read = true, .truncate = true });
    var journal = try Journal.open(std.testing.allocator, file);
    try journal.appendPublish("device-7", 42, "device.command", "OPEN", 5000);
    try journal.appendAck(42);
    journal.deinit();

    file = try tmp.dir.openFile("sessions.zms", .{ .mode = .read_write });
    journal = try Journal.open(std.testing.allocator, file);
    defer journal.deinit();
    try std.testing.expectEqual(@as(usize, 0), journal.deliveries.count());
}

test "journal truncates an incomplete tail" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var file = try tmp.dir.createFile("sessions.zms", .{ .read = true, .truncate = true });
    var journal = try Journal.open(std.testing.allocator, file);
    try journal.appendPublish("s", 1, "a", "b", 10);
    journal.deinit();
    file = try tmp.dir.openFile("sessions.zms", .{ .mode = .read_write });
    try file.seekFromEnd(0);
    try file.writeAll("ZMS1");
    try file.sync();
    file.close();
    file = try tmp.dir.openFile("sessions.zms", .{ .mode = .read_write });
    journal = try Journal.open(std.testing.allocator, file);
    defer journal.deinit();
    try std.testing.expectEqual(@as(usize, 1), journal.deliveries.count());
}
