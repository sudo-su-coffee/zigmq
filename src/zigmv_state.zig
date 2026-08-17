const std = @import("std");

pub const Pending = struct {
    message_id: u64,
    deadline_ms: u64,
    attempts: u32 = 0,
};

pub const Store = struct {
    allocator: std.mem.Allocator,
    pending: std.AutoHashMap(u64, Pending),
    seen: std.AutoHashMap(u64, void),

    pub fn init(allocator: std.mem.Allocator) Store {
        return .{
            .allocator = allocator,
            .pending = std.AutoHashMap(u64, Pending).init(allocator),
            .seen = std.AutoHashMap(u64, void).init(allocator),
        };
    }

    pub fn deinit(self: *Store) void {
        self.pending.deinit();
        self.seen.deinit();
    }

    pub fn register(self: *Store, message_id: u64, deadline_ms: u64) !void {
        if (self.pending.contains(message_id)) return error.DuplicateMessage;
        try self.pending.put(message_id, .{ .message_id = message_id, .deadline_ms = deadline_ms });
    }

    pub fn acknowledge(self: *Store, message_id: u64) bool {
        return self.pending.remove(message_id);
    }

    pub fn acceptOnce(self: *Store, message_id: u64) !bool {
        if (self.seen.contains(message_id)) return false;
        try self.seen.put(message_id, {});
        return true;
    }

    pub fn collectDue(self: *Store, now_ms: u64, output: *std.ArrayList(u64)) !void {
        var iterator = self.pending.iterator();
        while (iterator.next()) |entry| {
            if (entry.value_ptr.deadline_ms <= now_ms) {
                try output.append(self.allocator, entry.key_ptr.*);
                entry.value_ptr.attempts +%= 1;
                entry.value_ptr.deadline_ms = now_ms;
            }
        }
    }
};

test "ack removes pending delivery" {
    var store = Store.init(std.testing.allocator);
    defer store.deinit();
    try store.register(42, 100);
    try std.testing.expect(store.acknowledge(42));
    try std.testing.expect(!store.acknowledge(42));
}

test "due collection schedules retry without removing delivery" {
    var store = Store.init(std.testing.allocator);
    defer store.deinit();
    try store.register(7, 100);
    var due: std.ArrayList(u64) = .empty;
    defer due.deinit(std.testing.allocator);
    try store.collectDue(100, &due);
    try std.testing.expectEqual(@as(usize, 1), due.items.len);
    try std.testing.expectEqual(@as(u64, 7), due.items[0]);
    try std.testing.expect(store.pending.contains(7));
}

test "duplicate delivery is accepted once" {
    var store = Store.init(std.testing.allocator);
    defer store.deinit();
    try std.testing.expect(try store.acceptOnce(99));
    try std.testing.expect(!(try store.acceptOnce(99)));
}
