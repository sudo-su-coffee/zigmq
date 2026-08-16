const std = @import("std");
const net = std.net;
const max_payload_length: usize = 64 * 1024;
const max_control_line_length: usize = 1024;

pub const Connection = struct {
    allocator: std.mem.Allocator,
    stream: net.Stream,
    reader: net.Stream.Reader,
    input_buffer: [max_payload_length + max_control_line_length]u8 = undefined,

    pub fn connect(allocator: std.mem.Allocator, host: []const u8, port: u16) !*Connection {
        const connection = try allocator.create(Connection);
        errdefer allocator.destroy(connection);
        connection.* = .{
            .allocator = allocator,
            .stream = try net.tcpConnectToHost(allocator, host, port),
            .reader = undefined,
        };
        connection.reader = connection.stream.reader(&connection.input_buffer);
        return connection;
    }

    pub fn deinit(self: *Connection) void {
        self.stream.close();
        self.allocator.destroy(self);
    }

    pub fn sendLine(self: *Connection, comptime format: []const u8, args: anytype) !void {
        var buffer: [1024]u8 = undefined;
        const line = try std.fmt.bufPrint(&buffer, format, args);
        try self.stream.writeAll(line);
    }

    pub fn sendBytes(self: *Connection, bytes: []const u8) !void {
        try self.stream.writeAll(bytes);
    }

    pub fn readLine(self: *Connection) !?[]const u8 {
        return self.reader.interface().takeDelimiter('\n') catch |err| switch (err) {
            error.ReadFailed => return error.ReadFailed,
            error.StreamTooLong => return error.LineTooLong,
        };
    }

    pub fn readMessage(self: *Connection, allocator: std.mem.Allocator) !Message {
        const raw_line = try self.readLine() orelse return error.EndOfStream;
        const line = std.mem.trim(u8, raw_line, " \t\r\n");
        var tokens = std.mem.tokenizeAny(u8, line, " \t");
        const kind = tokens.next() orelse return error.InvalidMessage;
        if (!std.mem.eql(u8, kind, "MSG")) return error.InvalidMessage;
        const subject = tokens.next() orelse return error.InvalidMessage;
        const first = tokens.next() orelse return error.InvalidMessage;
        const second = tokens.next();
        const size_text = second orelse first;
        const size = std.fmt.parseInt(usize, size_text, 10) catch return error.InvalidMessage;
        if (size > max_payload_length) return error.PayloadTooLong;
        const payload = try self.reader.interface().take(size);
        const terminator = try self.reader.interface().take(2);
        if (!std.mem.eql(u8, terminator, "\r\n")) return error.InvalidMessage;
        return .{
            .subject = try allocator.dupe(u8, subject),
            .sid = if (second != null) try allocator.dupe(u8, first) else null,
            .payload = try allocator.dupe(u8, payload),
        };
    }
};

pub const Message = struct {
    subject: []u8,
    sid: ?[]u8,
    payload: []u8,

    pub fn deinit(self: *Message, allocator: std.mem.Allocator) void {
        allocator.free(self.subject);
        if (self.sid) |sid| allocator.free(sid);
        allocator.free(self.payload);
    }
};
