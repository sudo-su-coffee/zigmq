const std = @import("std");
const net = std.net;
const zigmq = @import("zigmq");

const Allocator = std.mem.Allocator;
const TopicSubscribers = std.ArrayList(*Client);

const Client = struct {
    stream: net.Stream,
    allocator: Allocator,
    write_mutex: std.Thread.Mutex = .{},
    subscriptions: std.StringHashMap(void),

    fn init(stream: net.Stream, allocator: Allocator) Client {
        return .{
            .stream = stream,
            .allocator = allocator,
            .subscriptions = std.StringHashMap(void).init(allocator),
        };
    }

    fn deinit(self: *Client) void {
        self.subscriptions.deinit();
    }

    fn send(self: *Client, bytes: []const u8) !void {
        self.write_mutex.lock();
        defer self.write_mutex.unlock();
        try self.stream.writeAll(bytes);
    }

    fn sendMessage(self: *Client, topic: []const u8, payload: []const u8) !void {
        var header: [512]u8 = undefined;
        const header_bytes = try std.fmt.bufPrint(&header, "MSG {s} {d}\r\n", .{ topic, payload.len });
        self.write_mutex.lock();
        defer self.write_mutex.unlock();
        try self.stream.writeAll(header_bytes);
        try self.stream.writeAll(payload);
        try self.stream.writeAll("\r\n");
    }
};

const Broker = struct {
    allocator: Allocator,
    mutex: std.Thread.Mutex = .{},
    topics: std.StringHashMap(TopicSubscribers),

    fn init(allocator: Allocator) Broker {
        return .{
            .allocator = allocator,
            .topics = std.StringHashMap(TopicSubscribers).init(allocator),
        };
    }

    fn deinit(self: *Broker) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        var iterator = self.topics.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.topics.deinit();
    }

    fn subscribe(self: *Broker, client: *Client, topic: []const u8) !bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (client.subscriptions.contains(topic)) return false;

        const client_topic = try self.allocator.dupe(u8, topic);
        errdefer self.allocator.free(client_topic);
        try client.subscriptions.put(client_topic, {});
        errdefer {
            if (client.subscriptions.fetchRemove(topic)) |removed| {
                self.allocator.free(removed.key);
            }
        }

        var entry = try self.topics.getOrPut(topic);
        const new_topic = !entry.found_existing;
        if (new_topic) {
            const broker_topic = try self.allocator.dupe(u8, topic);
            entry.key_ptr.* = broker_topic;
            entry.value_ptr.* = .empty;
            errdefer {
                if (self.topics.fetchRemove(topic)) |removed_value| {
                    var removed = removed_value;
                    self.allocator.free(removed.key);
                    removed.value.deinit(self.allocator);
                }
            }
        }
        try entry.value_ptr.append(self.allocator, client);
        return true;
    }

    fn removeClientFromTopicLocked(self: *Broker, client: *Client, topic: []const u8) void {
        if (self.topics.getPtr(topic)) |subscribers| {
            if (std.mem.indexOfScalar(*Client, subscribers.items, client)) |index| {
                _ = subscribers.swapRemove(index);
            }
            if (subscribers.items.len == 0) {
                if (self.topics.fetchRemove(topic)) |removed_value| {
                    var removed = removed_value;
                    self.allocator.free(removed.key);
                    removed.value.deinit(self.allocator);
                }
            }
        }
    }

    fn unsubscribe(self: *Broker, client: *Client, topic: []const u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        const removed = client.subscriptions.fetchRemove(topic) orelse return false;
        self.allocator.free(removed.key);
        self.removeClientFromTopicLocked(client, topic);
        return true;
    }

    fn disconnect(self: *Broker, client: *Client) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var iterator = client.subscriptions.iterator();
        while (iterator.next()) |entry| {
            self.removeClientFromTopicLocked(client, entry.key_ptr.*);
            self.allocator.free(entry.key_ptr.*);
        }
    }

    fn publish(self: *Broker, topic: []const u8, payload: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const subscribers = self.topics.getPtr(topic) orelse return;
        for (subscribers.items) |client| {
            client.sendMessage(topic, payload) catch |err| {
                std.log.debug("delivery to subscriber failed: {s}", .{@errorName(err)});
            };
        }
    }
};

const help_text =
    "+OK zigmq commands: SUB <topic>, UNSUB <topic>, PUB <topic> <payload>, PING, PONG, HELP, QUIT\r\n";

fn parseErrorText(err: zigmq.ParseError) []const u8 {
    return switch (err) {
        error.EmptyCommand => "empty command",
        error.InvalidCommand => "invalid command",
        error.MissingTopic => "topic is required",
        error.MissingPayload => "payload is required",
        error.TopicTooLong => "topic is too long",
        error.PayloadTooLong => "payload is too long",
        error.InvalidTopic => "invalid topic",
    };
}

fn handleCommand(broker: *Broker, client: *Client, line: []const u8) bool {
    const command = zigmq.parseCommand(line) catch |err| {
        var response: [128]u8 = undefined;
        const bytes = std.fmt.bufPrint(&response, "-ERR {s}\r\n", .{parseErrorText(err)}) catch return false;
        client.send(bytes) catch return false;
        return true;
    };

    switch (command) {
        .subscribe => |topic| {
            const added = broker.subscribe(client, topic) catch {
                client.send("-ERR out of memory\r\n") catch return false;
                return true;
            };
            if (added) {
                client.send("+OK SUB\r\n") catch return false;
            } else {
                client.send("+OK already subscribed\r\n") catch return false;
            }
            return true;
        },
        .unsubscribe => |topic| {
            if (broker.unsubscribe(client, topic)) {
                client.send("+OK UNSUB\r\n") catch return false;
            } else {
                client.send("+OK not subscribed\r\n") catch return false;
            }
            return true;
        },
        .publish => |message| {
            broker.publish(message.topic, message.payload);
            client.send("+OK PUB\r\n") catch return false;
            return true;
        },
        .ping => {
            client.send("PONG\r\n") catch return false;
            return true;
        },
        .pong => {
            client.send("+OK\r\n") catch return false;
            return true;
        },
        .help => {
            client.send(help_text) catch return false;
            return true;
        },
        .quit => {
            client.send("+OK BYE\r\n") catch {};
            return false;
        },
    }
}

fn handleClient(broker: *Broker, stream: net.Stream, allocator: Allocator) void {
    var client = Client.init(stream, allocator);
    defer client.deinit();
    defer broker.disconnect(&client);
    defer stream.close();

    client.send("+OK zigmq ready\r\n") catch return;

    var line_buffer: [zigmq.max_line_length]u8 = undefined;
    var line_length: usize = 0;
    var byte_buffer: [4096]u8 = undefined;

    while (true) {
        const count = stream.read(&byte_buffer) catch |err| {
            std.log.debug("client read failed: {s}", .{@errorName(err)});
            return;
        };
        if (count == 0) return;

        for (byte_buffer[0..count]) |byte| {
            if (byte == '\r') continue;
            if (byte == '\n') {
                if (!handleCommand(broker, &client, line_buffer[0..line_length])) return;
                line_length = 0;
                continue;
            }
            if (line_length == line_buffer.len) {
                client.send("-ERR command line too long\r\n") catch {};
                return;
            }
            line_buffer[line_length] = byte;
            line_length += 1;
        }
    }
}

fn parsePort(text: []const u8) !u16 {
    return std.fmt.parseInt(u16, text, 10);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var host: []const u8 = "127.0.0.1";
    var port: u16 = 4222;
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        if (std.mem.eql(u8, args[index], "--host")) {
            index += 1;
            if (index >= args.len) return error.MissingHost;
            host = args[index];
        } else if (std.mem.eql(u8, args[index], "--port")) {
            index += 1;
            if (index >= args.len) return error.MissingPort;
            port = try parsePort(args[index]);
        } else if (std.mem.eql(u8, args[index], "--help")) {
            std.debug.print("Usage: zigmq [--host 127.0.0.1] [--port 4222]\n", .{});
            return;
        } else {
            std.debug.print("Unknown argument: {s}\n", .{args[index]});
            return error.InvalidArgument;
        }
    }

    const address = try net.Address.parseIp4(host, port);
    var server = try address.listen(.{ .reuse_address = true });
    defer server.deinit();

    var broker = Broker.init(allocator);
    defer broker.deinit();

    std.debug.print("zigmq listening on {s}:{d}\n", .{ host, port });
    while (true) {
        const connection = server.accept() catch |err| {
            std.log.err("accept failed: {s}", .{@errorName(err)});
            continue;
        };
        const thread = std.Thread.spawn(.{}, handleClient, .{ &broker, connection.stream, allocator }) catch |err| {
            std.log.err("could not start client thread: {s}", .{@errorName(err)});
            connection.stream.close();
            continue;
        };
        thread.detach();
    }
}
