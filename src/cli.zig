const std = @import("std");
const zigmq = @import("zigmq");
const client = @import("client.zig");

const Allocator = std.mem.Allocator;
const stdout = std.fs.File.stdout();
const stdin = std.fs.File.stdin();

const Config = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 4222,
    auth_token: ?[]const u8 = null,
    raw: bool = false,
};

fn print(comptime format: []const u8, args: anytype) !void {
    var buffer: [4096]u8 = undefined;
    const bytes = try std.fmt.bufPrint(&buffer, format, args);
    try stdout.writeAll(bytes);
}

fn parsePort(text: []const u8) !u16 {
    return std.fmt.parseInt(u16, text, 10);
}

fn parseConfig(args: []const []const u8, start: usize) !Config {
    var config = Config{};
    var index = start;
    while (index < args.len) : (index += 1) {
        if (std.mem.eql(u8, args[index], "--host")) {
            index += 1;
            if (index >= args.len) return error.MissingHost;
            config.host = args[index];
        } else if (std.mem.eql(u8, args[index], "--port")) {
            index += 1;
            if (index >= args.len) return error.MissingPort;
            config.port = try parsePort(args[index]);
        } else if (std.mem.eql(u8, args[index], "--auth-token")) {
            index += 1;
            if (index >= args.len) return error.MissingAuthToken;
            config.auth_token = args[index];
        } else if (std.mem.eql(u8, args[index], "--raw")) {
            config.raw = true;
        } else {
            return error.UnknownOption;
        }
    }
    return config;
}

fn connect(allocator: Allocator, config: Config) !*client.Connection {
    const connection = try client.Connection.connect(allocator, config.host, config.port);
    errdefer connection.deinit();
    _ = try connection.readLine() orelse return error.EndOfStream;
    if (config.auth_token) |token| {
        try connection.sendLine("AUTH {s}\r\n", .{token});
        const response = try connection.readLine() orelse return error.EndOfStream;
        if (!std.mem.startsWith(u8, response, "+OK")) return error.AuthenticationFailed;
    }
    return connection;
}

fn requireArgument(args: []const []const u8, index: usize, name: []const u8) ![]const u8 {
    if (index >= args.len) {
        try print("missing {s}\n", .{name});
        return error.MissingArgument;
    }
    return args[index];
}

fn runPub(allocator: Allocator, args: []const []const u8) !void {
    const subject = try requireArgument(args, 2, "subject");
    try zigmq.validateTopic(subject);
    var config = Config{};
    var payload: []u8 = undefined;
    var owned_payload = false;
    if (args.len > 3 and args[3][0] != '-') {
        payload = @constCast(args[3]);
        config = try parseConfig(args, 4);
    } else {
        payload = try stdin.readToEndAlloc(allocator, zigmq.max_payload_length);
        owned_payload = true;
        config = try parseConfig(args, 3);
    }
    defer if (owned_payload) allocator.free(payload);

    const connection = try connect(allocator, config);
    defer connection.deinit();
    var header: [512]u8 = undefined;
    const header_bytes = try std.fmt.bufPrint(&header, "PUB {s} ", .{subject});
    try connection.sendBytes(header_bytes);
    try connection.sendBytes(payload);
    try connection.sendBytes("\r\n");
    const response = try connection.readLine() orelse return error.EndOfStream;
    try print("{s}\n", .{std.mem.trim(u8, response, " \t\r\n")});
}

fn runSub(allocator: Allocator, args: []const []const u8) !void {
    const subject = try requireArgument(args, 2, "subject");
    try zigmq.validateSubject(subject, true);
    const config = try parseConfig(args, 3);
    const connection = try connect(allocator, config);
    defer connection.deinit();
    try connection.sendLine("SUB {s}\r\n", .{subject});
    const response = try connection.readLine() orelse return error.EndOfStream;
    try print("{s}\n", .{std.mem.trim(u8, response, " \t\r\n")});
    while (true) {
        var message = try connection.readMessage(allocator);
        defer message.deinit(allocator);
        if (config.raw) {
            try stdout.writeAll(message.payload);
            try stdout.writeAll("\n");
        } else {
            try print("[{s}] ", .{message.subject});
            try stdout.writeAll(message.payload);
            try stdout.writeAll("\n");
        }
    }
}

fn runPing(allocator: Allocator, args: []const []const u8) !void {
    const config = try parseConfig(args, 2);
    const connection = try connect(allocator, config);
    defer connection.deinit();
    const start = std.time.nanoTimestamp();
    try connection.sendBytes("PING\r\n");
    const response = try connection.readLine() orelse return error.EndOfStream;
    const elapsed_ns = std.time.nanoTimestamp() - start;
    try print("{s} ({d} us)\n", .{ std.mem.trim(u8, response, " \t\r\n"), @divTrunc(elapsed_ns, 1000) });
}

fn runShell(allocator: Allocator, args: []const []const u8) !void {
    const config = try parseConfig(args, 2);
    const connection = try connect(allocator, config);
    defer connection.deinit();
    try print("zigmq {s}:{d}> ", .{ config.host, config.port });
    var buffer: [zigmq.max_control_line_length]u8 = undefined;
    while (true) {
        const read = try stdin.read(&buffer);
        if (read == 0) break;
        try connection.sendBytes(buffer[0..read]);
        const response = try connection.readLine() orelse break;
        try print("{s}\nzigmq {s}:{d}> ", .{ std.mem.trim(u8, response, " \t\r\n"), config.host, config.port });
    }
}

fn runBenchPub(allocator: Allocator, args: []const []const u8) !void {
    const subject = try requireArgument(args, 3, "subject");
    try zigmq.validateTopic(subject);
    var config = Config{};
    var count: usize = 10_000;
    var size: usize = 12;
    var index: usize = 4;
    while (index < args.len) : (index += 1) {
        if (std.mem.eql(u8, args[index], "--count")) {
            index += 1;
            if (index >= args.len) return error.MissingCount;
            count = try std.fmt.parseInt(usize, args[index], 10);
        } else if (std.mem.eql(u8, args[index], "--size")) {
            index += 1;
            if (index >= args.len) return error.MissingSize;
            size = try std.fmt.parseInt(usize, args[index], 10);
        } else {
            const remaining = try parseConfig(args, index);
            config = remaining;
            break;
        }
    }
    if (size > zigmq.max_payload_length) return error.PayloadTooLarge;
    const payload = try allocator.alloc(u8, size);
    defer allocator.free(payload);
    @memset(payload, 'x');
    const connection = try connect(allocator, config);
    defer connection.deinit();
    var header: [512]u8 = undefined;
    const header_bytes = try std.fmt.bufPrint(&header, "PUB {s} ", .{subject});
    const start = std.time.nanoTimestamp();
    var sent: usize = 0;
    while (sent < count) : (sent += 1) {
        try connection.sendBytes(header_bytes);
        try connection.sendBytes(payload);
        try connection.sendBytes("\r\n");
        _ = try connection.readLine() orelse return error.EndOfStream;
    }
    const elapsed_ns = std.time.nanoTimestamp() - start;
    const rate = @as(f64, @floatFromInt(count)) / (@as(f64, @floatFromInt(elapsed_ns)) / @as(f64, std.time.ns_per_s));
    try print("published {d} messages at {d:.1} msg/sec\n", .{ count, rate });
}

pub fn printHelp() !void {
    try print("zigmq - pure Zig edge messaging toolkit\n\n", .{});
    try print("Usage:\n  zigmq server [--host HOST] [--port PORT] [--auth-token TOKEN]\n", .{});
    try print("  zigmq pub SUBJECT [MESSAGE] [--host HOST] [--port PORT] [--auth-token TOKEN]\n", .{});
    try print("  zigmq sub SUBJECT [--raw] [--host HOST] [--port PORT] [--auth-token TOKEN]\n", .{});
    try print("  zigmq ping [--host HOST] [--port PORT] [--auth-token TOKEN]\n", .{});
    try print("  zigmq shell [--host HOST] [--port PORT] [--auth-token TOKEN]\n", .{});
    try print("  zigmq bench pub SUBJECT [--count N] [--size BYTES] [--host HOST] [--port PORT]\n", .{});
    try print("\nExamples:\n  zigmq sub sensors.*\n  echo hello | zigmq pub sensors.room\n  zigmq bench pub bench --count 10000 --size 12\n", .{});
}

pub fn run(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 2 or std.mem.eql(u8, args[1], "help") or std.mem.eql(u8, args[1], "--help")) {
        return printHelp();
    }
    if (std.mem.eql(u8, args[1], "pub")) return runPub(allocator, args);
    if (std.mem.eql(u8, args[1], "sub")) return runSub(allocator, args);
    if (std.mem.eql(u8, args[1], "ping")) return runPing(allocator, args);
    if (std.mem.eql(u8, args[1], "shell")) return runShell(allocator, args);
    if (std.mem.eql(u8, args[1], "bench")) {
        if (args.len > 2 and std.mem.eql(u8, args[2], "pub")) return runBenchPub(allocator, args);
        try print("supported benchmark: zigmq bench pub SUBJECT\n", .{});
        return error.UnknownCommand;
    }
    return error.UnknownCommand;
}
