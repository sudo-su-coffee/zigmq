const std = @import("std");

const Allocator = std.mem.Allocator;

pub const CursorResult = enum { accepted, duplicate, gap };

pub const LinkSession = struct {
    allocator: Allocator,
    identity: []u8,
    secret: []u8,
    last_sequence: u64 = 0,
    authenticated: bool = false,

    pub fn init(allocator: Allocator, identity: []const u8, secret: []const u8) !LinkSession {
        if (identity.len == 0 or identity.len > 128 or std.mem.indexOfAny(u8, identity, " \t\r\n") != null) return error.InvalidIdentity;
        if (secret.len == 0 or secret.len > 4096) return error.InvalidSecret;
        return .{
            .allocator = allocator,
            .identity = try allocator.dupe(u8, identity),
            .secret = try allocator.dupe(u8, secret),
        };
    }

    pub fn deinit(self: *LinkSession) void {
        std.crypto.secureZero(u8, self.secret);
        self.allocator.free(self.secret);
        self.allocator.free(self.identity);
    }

    pub fn authenticate(self: *LinkSession, presented: []const u8) bool {
        if (presented.len != self.secret.len) return false;
        var difference: u8 = 0;
        for (self.secret, presented) |expected, actual| difference |= expected ^ actual;
        self.authenticated = difference == 0;
        return self.authenticated;
    }

    pub fn acceptSequence(self: *LinkSession, sequence: u64) !CursorResult {
        if (!self.authenticated) return error.Unauthenticated;
        if (sequence == 0) return error.InvalidSequence;
        if (sequence <= self.last_sequence) return .duplicate;
        const result: CursorResult = if (self.last_sequence != 0 and sequence != self.last_sequence + 1) .gap else .accepted;
        self.last_sequence = sequence;
        return result;
    }
};

test "link authentication and cursor semantics" {
    var link = try LinkSession.init(std.testing.allocator, "edge-a", "secret");
    defer link.deinit();
    try std.testing.expect(!link.authenticate("wrong"));
    try std.testing.expect(link.authenticate("secret"));
    try std.testing.expectEqual(CursorResult.accepted, try link.acceptSequence(1));
    try std.testing.expectEqual(CursorResult.duplicate, try link.acceptSequence(1));
    try std.testing.expectEqual(CursorResult.gap, try link.acceptSequence(3));
}

test "unauthenticated links cannot advance cursors" {
    var link = try LinkSession.init(std.testing.allocator, "edge-a", "secret");
    defer link.deinit();
    try std.testing.expectError(error.Unauthenticated, link.acceptSequence(1));
}
