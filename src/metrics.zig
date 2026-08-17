const std = @import("std");

pub const Snapshot = struct {
    clients: u64,
    subscriptions: u64,
    pending_durable: u64,
    published_total: u64,
    delivered_total: u64,
    redelivered_total: u64,
    acknowledged_total: u64,
    expired_total: u64,
};

pub fn format(snapshot: Snapshot, version: []const u8, output: *[4096]u8) ![]const u8 {
    return std.fmt.bufPrint(output,
        "# HELP zigmv_build_info ZigMV broker build information.\n" ++
        "# TYPE zigmv_build_info gauge\n" ++
        "zigmv_build_info{{version=\"{s}\"}} 1\n" ++
        "# HELP zigmv_clients Active client connections.\n" ++
        "# TYPE zigmv_clients gauge\n" ++
        "zigmv_clients {d}\n" ++
        "# HELP zigmv_subscriptions Active ZigMV subscriptions.\n" ++
        "# TYPE zigmv_subscriptions gauge\n" ++
        "zigmv_subscriptions {d}\n" ++
        "# HELP zigmv_pending_durable Pending durable deliveries.\n" ++
        "# TYPE zigmv_pending_durable gauge\n" ++
        "zigmv_pending_durable {d}\n" ++
        "# HELP zigmv_published_total Messages accepted for publication.\n" ++
        "# TYPE zigmv_published_total counter\n" ++
        "zigmv_published_total {d}\n" ++
        "# HELP zigmv_delivered_total Deliveries enqueued for matching subscribers.\n" ++
        "# TYPE zigmv_delivered_total counter\n" ++
        "zigmv_delivered_total {d}\n" ++
        "# HELP zigmv_redelivered_total Durable retry deliveries.\n" ++
        "# TYPE zigmv_redelivered_total counter\n" ++
        "zigmv_redelivered_total {d}\n" ++
        "# HELP zigmv_acknowledged_total Accepted durable consumer acknowledgements.\n" ++
        "# TYPE zigmv_acknowledged_total counter\n" ++
        "zigmv_acknowledged_total {d}\n" ++
        "# HELP zigmv_expired_total Expired durable deliveries.\n" ++
        "# TYPE zigmv_expired_total counter\n" ++
        "zigmv_expired_total {d}\n",
        .{ version, snapshot.clients, snapshot.subscriptions, snapshot.pending_durable, snapshot.published_total, snapshot.delivered_total, snapshot.redelivered_total, snapshot.acknowledged_total, snapshot.expired_total },
    );
}

test "formats stable prometheus metrics" {
    var buffer: [4096]u8 = undefined;
    const text = try format(.{
        .clients = 2,
        .subscriptions = 3,
        .pending_durable = 4,
        .published_total = 5,
        .delivered_total = 6,
        .redelivered_total = 7,
        .acknowledged_total = 8,
        .expired_total = 9,
    }, "0.6.0", &buffer);
    try std.testing.expect(std.mem.indexOf(u8, text, "# TYPE zigmv_published_total counter") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "zigmv_pending_durable 4") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "zigmv_build_info{version=\"0.6.0\"} 1") != null);
}
