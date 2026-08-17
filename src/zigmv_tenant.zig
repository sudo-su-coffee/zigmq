const std = @import("std");

pub const Policy = struct {
    allocator: std.mem.Allocator,
    tenant: []u8,
    subject_prefix: []u8,
    publish_limit: u64,
    byte_limit: u64,
    published: u64 = 0,
    bytes: u64 = 0,

    pub fn init(allocator: std.mem.Allocator, tenant: []const u8, subject_prefix: []const u8, publish_limit: u64, byte_limit: u64) !Policy {
        if (tenant.len == 0 or subject_prefix.len == 0 or publish_limit == 0 or byte_limit == 0) return error.InvalidPolicy;
        return .{
            .allocator = allocator,
            .tenant = try allocator.dupe(u8, tenant),
            .subject_prefix = try allocator.dupe(u8, subject_prefix),
            .publish_limit = publish_limit,
            .byte_limit = byte_limit,
        };
    }

    pub fn deinit(self: *Policy) void {
        self.allocator.free(self.tenant);
        self.allocator.free(self.subject_prefix);
    }

    pub fn allowsSubject(self: *const Policy, subject: []const u8) bool {
        return std.mem.startsWith(u8, subject, self.subject_prefix) and (subject.len == self.subject_prefix.len or subject[self.subject_prefix.len] == '.');
    }

    pub fn chargePublish(self: *Policy, subject: []const u8, payload_bytes: usize) !void {
        if (!self.allowsSubject(subject)) return error.SubjectDenied;
        if (self.published >= self.publish_limit or payload_bytes > self.byte_limit -| self.bytes) return error.QuotaExceeded;
        self.published += 1;
        self.bytes += payload_bytes;
    }

    pub fn resetCounters(self: *Policy) void {
        self.published = 0;
        self.bytes = 0;
    }
};

test "tenant policy scopes subjects and quotas" {
    var policy = try Policy.init(std.testing.allocator, "fleet-a", "tenant.fleet-a", 2, 10);
    defer policy.deinit();
    try std.testing.expect(policy.allowsSubject("tenant.fleet-a.telemetry"));
    try std.testing.expect(!policy.allowsSubject("tenant.fleet-b.telemetry"));
    try policy.chargePublish("tenant.fleet-a.telemetry", 4);
    try policy.chargePublish("tenant.fleet-a.command", 6);
    try std.testing.expectError(error.QuotaExceeded, policy.chargePublish("tenant.fleet-a.telemetry", 1));
    policy.resetCounters();
    try policy.chargePublish("tenant.fleet-a.telemetry", 1);
}
