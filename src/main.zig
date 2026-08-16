const std = @import("std");
const net = std.net;
const posix = std.posix;
const zigmq = @import("zigmq");
const cli = @import("cli.zig");

const Allocator = std.mem.Allocator;
const Protocol = enum { custom, nats, mqtt };
const NatsSubscription = struct { subject: []u8, sid: []u8 };
const NatsSubscriptionRef = struct { subject: []const u8, sid: []const u8, client: *Client };
const MqttSubscription = struct { filter: []u8, client: *Client };
const RetainedMessage = struct { payload: []u8, expires_at_ns: i128 };
const WildcardSubscription = struct { pattern: []const u8, client: *Client };
const GroupSubscription = struct { pattern: []const u8, group: []const u8, client: *Client };

fn mqttEncodeRemainingLength(value: usize, output: *[4]u8) usize {
    var remaining = value;
    var index: usize = 0;
    while (true) {
        var encoded = @as(u8, @intCast(remaining % 128));
        remaining /= 128;
        if (remaining != 0) encoded |= 128;
        output[index] = encoded;
        index += 1;
        if (remaining == 0) return index;
    }
}

fn mqttTopicMatches(filter: []const u8, topic: []const u8) bool {
    var filter_start: usize = 0;
    var topic_start: usize = 0;
    while (true) {
        const filter_relative_end = std.mem.indexOfScalar(u8, filter[filter_start..], '/') orelse filter.len - filter_start;
        const filter_end = filter_start + filter_relative_end;
        const filter_level = filter[filter_start..filter_end];
        if (std.mem.eql(u8, filter_level, "#")) return true;
        if (topic_start >= topic.len) return false;
        const topic_relative_end = std.mem.indexOfScalar(u8, topic[topic_start..], '/') orelse topic.len - topic_start;
        const topic_end = topic_start + topic_relative_end;
        const topic_level = topic[topic_start..topic_end];
        if (!std.mem.eql(u8, filter_level, "+") and !std.mem.eql(u8, filter_level, topic_level)) return false;
        const filter_done = filter_end == filter.len;
        const topic_done = topic_end == topic.len;
        if (filter_done or topic_done) return filter_done and topic_done;
        filter_start = filter_end + 1;
        topic_start = topic_end + 1;
    }
}

var stop_requested = std.atomic.Value(bool).init(false);

const Client = struct {
    stream: net.Stream,
    allocator: Allocator,
    authenticated: bool,
    queue_mutex: std.Thread.Mutex = .{},
    queue_condition: std.Thread.Condition = .{},
    queue: std.ArrayList([]u8) = .empty,
    queue_head: usize = 0,
    queue_len: usize = 0,
    queue_bytes: usize = 0,
    closed: bool = false,
    last_delivery_generation: usize = 0,
    preauth_commands: usize = 0,
    mqtt_connected: bool = false,
    verbose: bool = true,
    subscriptions: std.StringHashMap(?[]u8),
    nats_subscriptions: std.ArrayList(NatsSubscription) = .empty,
    mqtt_subscriptions: std.ArrayList([]u8) = .empty,

    fn init(stream: net.Stream, allocator: Allocator, authenticated: bool) Client {
        return .{
            .stream = stream,
            .allocator = allocator,
            .authenticated = authenticated,
            .subscriptions = std.StringHashMap(?[]u8).init(allocator),
        };
    }

    fn requestClose(self: *Client) void {
        self.queue_mutex.lock();
        self.closed = true;
        self.queue_condition.broadcast();
        self.queue_mutex.unlock();
        _ = posix.shutdown(self.stream.handle, .both) catch {};
    }

    fn enqueueOwned(self: *Client, message: []u8) !void {
        self.queue_mutex.lock();
        defer self.queue_mutex.unlock();

        if (self.closed) {
            self.allocator.free(message);
            return error.Closed;
        }
        if (self.queue_len >= zigmq.max_queue_messages or self.queue_bytes + message.len > zigmq.max_queue_bytes) {
            self.closed = true;
            self.queue_condition.broadcast();
            self.allocator.free(message);
            _ = posix.shutdown(self.stream.handle, .both) catch {};
            return error.SlowConsumer;
        }
        self.queue.append(self.allocator, message) catch |err| {
            self.closed = true;
            self.queue_condition.broadcast();
            self.allocator.free(message);
            _ = posix.shutdown(self.stream.handle, .both) catch {};
            return err;
        };
        self.queue_len += 1;
        self.queue_bytes += message.len;
        self.queue_condition.signal();
    }

    fn send(self: *Client, bytes: []const u8) !void {
        const message = try self.allocator.dupe(u8, bytes);
        return self.enqueueOwned(message);
    }

    fn sendFmt(self: *Client, comptime format: []const u8, args: anytype) !void {
        var buffer: [1024]u8 = undefined;
        const bytes = try std.fmt.bufPrint(&buffer, format, args);
        return self.send(bytes);
    }

    fn sendCustomMessage(self: *Client, topic: []const u8, reply: ?[]const u8, payload: []const u8) !void {
        var header: [512]u8 = undefined;
        const header_bytes = if (reply) |reply_subject|
            try std.fmt.bufPrint(&header, "MSG {s} {s} {d}\r\n", .{ topic, reply_subject, payload.len })
        else
            try std.fmt.bufPrint(&header, "MSG {s} {d}\r\n", .{ topic, payload.len });
        const message = try self.allocator.alloc(u8, header_bytes.len + payload.len + 2);
        errdefer self.allocator.free(message);
        @memcpy(message[0..header_bytes.len], header_bytes);
        @memcpy(message[header_bytes.len .. header_bytes.len + payload.len], payload);
        @memcpy(message[header_bytes.len + payload.len ..], "\r\n");
        return self.enqueueOwned(message);
    }

    fn sendMqttPublish(self: *Client, topic: []const u8, payload: []const u8, retain: bool) !void {
        var length_bytes: [4]u8 = undefined;
        const remaining_length = 2 + topic.len + payload.len;
        const length_size = mqttEncodeRemainingLength(remaining_length, &length_bytes);
        const message = try self.allocator.alloc(u8, 1 + length_size + remaining_length);
        errdefer self.allocator.free(message);
        message[0] = if (retain) 0x31 else 0x30;
        @memcpy(message[1 .. 1 + length_size], length_bytes[0..length_size]);
        std.mem.writeInt(u16, message[1 + length_size ..][0..2], @as(u16, @intCast(topic.len)), .big);
        @memcpy(message[1 + length_size + 2 ..][0..topic.len], topic);
        @memcpy(message[1 + length_size + 2 + topic.len ..], payload);
        return self.enqueueOwned(message);
    }

    fn sendMqttAck(self: *Client, packet_type: u8, packet_id: u16) !void {
        var message = [_]u8{ packet_type, 0x02, 0, 0 };
        std.mem.writeInt(u16, message[2..4], packet_id, .big);
        return self.send(&message);
    }

    fn sendNatsMessage(self: *Client, subject: []const u8, sid: []const u8, payload: []const u8) !void {
        var header: [512]u8 = undefined;
        const header_bytes = try std.fmt.bufPrint(&header, "MSG {s} {s} {d}\r\n", .{ subject, sid, payload.len });
        const message = try self.allocator.alloc(u8, header_bytes.len + payload.len + 2);
        errdefer self.allocator.free(message);
        @memcpy(message[0..header_bytes.len], header_bytes);
        @memcpy(message[header_bytes.len .. header_bytes.len + payload.len], payload);
        @memcpy(message[header_bytes.len + payload.len ..], "\r\n");
        return self.enqueueOwned(message);
    }

    fn writerLoop(self: *Client) void {
        while (true) {
            self.queue_mutex.lock();
            while (self.queue_len == 0 and !self.closed) {
                self.queue_condition.wait(&self.queue_mutex);
            }
            if (self.queue_len == 0 and self.closed) {
                self.queue_mutex.unlock();
                return;
            }
            const message = self.queue.items[self.queue_head];
            self.queue.items[self.queue_head] = undefined;
            self.queue_head += 1;
            self.queue_len -= 1;
            self.queue_bytes -= message.len;
            if (self.queue_len == 0) {
                self.queue.clearRetainingCapacity();
                self.queue_head = 0;
            } else if (self.queue_head >= 16 and self.queue_head * 2 >= self.queue.items.len) {
                const remaining = self.queue.items.len - self.queue_head;
                std.mem.copyForwards([]u8, self.queue.items[0..remaining], self.queue.items[self.queue_head..]);
                self.queue.shrinkRetainingCapacity(remaining);
                self.queue_head = 0;
            }
            self.queue_mutex.unlock();

            self.stream.writeAll(message) catch {
                self.allocator.free(message);
                self.requestClose();
                return;
            };
            self.allocator.free(message);
        }
    }

    fn deinit(self: *Client) void {
        for (self.queue.items[self.queue_head..]) |message| self.allocator.free(message);
        self.queue.deinit(self.allocator);
        self.subscriptions.deinit();
        for (self.nats_subscriptions.items) |subscription| {
            self.allocator.free(subscription.subject);
            self.allocator.free(subscription.sid);
        }
        self.nats_subscriptions.deinit(self.allocator);
        for (self.mqtt_subscriptions.items) |filter| self.allocator.free(filter);
        self.mqtt_subscriptions.deinit(self.allocator);
    }
};

fn readFileExact(file: *std.fs.File, buffer: []u8) !void {
    var offset: usize = 0;
    while (offset < buffer.len) {
        const count = try file.read(buffer[offset..]);
        if (count == 0) return error.EndOfStream;
        offset += count;
    }
}

const Broker = struct {
    allocator: Allocator,
    protocol: Protocol,
    host: []const u8,
    port: u16,
    auth_token: ?[]const u8,
    mutex: std.Thread.Mutex = .{},
    clients: std.ArrayList(*Client) = .empty,
    exact_subscribers: std.StringHashMap(std.ArrayList(*Client)),
    wildcard_subscriptions: std.ArrayList(WildcardSubscription) = .empty,
    group_subscriptions: std.ArrayList(GroupSubscription) = .empty,
    nats_subscribers: std.StringHashMap(std.ArrayList(NatsSubscriptionRef)),
    nats_wildcard_subscriptions: std.ArrayList(NatsSubscriptionRef) = .empty,
    mqtt_subscriptions: std.ArrayList(MqttSubscription) = .empty,
    retained: std.StringHashMap(RetainedMessage),
    stream_file: ?std.fs.File = null,
    stream_sequence: u64 = 0,
    delivery_generation: usize = 0,

    fn init(allocator: Allocator, protocol: Protocol, host: []const u8, port: u16, auth_token: ?[]const u8, stream_file: ?std.fs.File) Broker {
        return .{
            .allocator = allocator,
            .protocol = protocol,
            .host = host,
            .port = port,
            .auth_token = auth_token,
            .exact_subscribers = std.StringHashMap(std.ArrayList(*Client)).init(allocator),
            .nats_subscribers = std.StringHashMap(std.ArrayList(NatsSubscriptionRef)).init(allocator),
            .retained = std.StringHashMap(RetainedMessage).init(allocator),
            .stream_file = stream_file,
        };
    }

    fn addClient(self: *Broker, client: *Client) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.clients.append(self.allocator, client);
    }

    fn removeClientLocked(self: *Broker, client: *Client) void {
        if (std.mem.indexOfScalar(*Client, self.clients.items, client)) |index| {
            _ = self.clients.swapRemove(index);
        }
    }

    fn removeNatsIndexLocked(self: *Broker, client: *Client, subject: []const u8, sid: []const u8) void {
        if (isWildcard(subject)) {
            for (self.nats_wildcard_subscriptions.items, 0..) |subscription, index| {
                if (subscription.client == client and std.mem.eql(u8, subscription.subject, subject) and std.mem.eql(u8, subscription.sid, sid)) {
                    _ = self.nats_wildcard_subscriptions.swapRemove(index);
                    return;
                }
            }
            return;
        }
        if (self.nats_subscribers.getPtr(subject)) |list| {
            for (list.items, 0..) |subscription, index| {
                if (subscription.client == client and std.mem.eql(u8, subscription.sid, sid)) {
                    _ = list.swapRemove(index);
                    break;
                }
            }
            if (list.items.len == 0) {
                const removed = self.nats_subscribers.fetchRemove(subject).?;
                var removed_list = removed.value;
                removed_list.deinit(self.allocator);
                self.allocator.free(removed.key);
            }
        }
    }

    fn disconnect(self: *Broker, client: *Client) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.removeClientLocked(client);
        var iterator = client.subscriptions.iterator();
        while (iterator.next()) |entry| {
            self.removeIndexLocked(client, entry.key_ptr.*);
            self.removeGroupIndexLocked(client, entry.key_ptr.*);
            if (entry.value_ptr.*) |group| self.allocator.free(group);
            self.allocator.free(entry.key_ptr.*);
        }
        client.subscriptions.clearRetainingCapacity();
        for (client.nats_subscriptions.items) |subscription| {
            self.removeNatsIndexLocked(client, subscription.subject, subscription.sid);
            self.allocator.free(subscription.subject);
            self.allocator.free(subscription.sid);
        }
        client.nats_subscriptions.clearRetainingCapacity();
        for (client.mqtt_subscriptions.items) |filter| {
            self.removeMqttSubscriptionLocked(client, filter);
            self.allocator.free(filter);
        }
        client.mqtt_subscriptions.clearRetainingCapacity();
    }

    fn closeAll(self: *Broker) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        for (self.clients.items) |client| client.requestClose();
    }

    fn deinit(self: *Broker) void {
        var exact_iterator = self.exact_subscribers.iterator();
        while (exact_iterator.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
            self.allocator.free(entry.key_ptr.*);
        }
        self.exact_subscribers.deinit();
        self.wildcard_subscriptions.deinit(self.allocator);
        self.group_subscriptions.deinit(self.allocator);
        var nats_iterator = self.nats_subscribers.iterator();
        while (nats_iterator.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
            self.allocator.free(entry.key_ptr.*);
        }
        self.nats_subscribers.deinit();
        self.nats_wildcard_subscriptions.deinit(self.allocator);
        self.mqtt_subscriptions.deinit(self.allocator);
        var retained_iterator = self.retained.iterator();
        while (retained_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.payload);
        }
        self.retained.deinit();
        if (self.stream_file) |file| file.close();
        self.clients.deinit(self.allocator);
    }

    fn isWildcard(pattern: []const u8) bool {
        return std.mem.indexOfAny(u8, pattern, "*>") != null;
    }

    fn addIndexLocked(self: *Broker, client: *Client, pattern: []const u8) !void {
        if (isWildcard(pattern)) {
            try self.wildcard_subscriptions.append(self.allocator, .{ .pattern = client.subscriptions.getKey(pattern).?, .client = client });
            return;
        }
        if (self.exact_subscribers.getPtr(pattern)) |list| {
            try list.append(self.allocator, client);
            return;
        }
        const key = try self.allocator.dupe(u8, pattern);
        errdefer self.allocator.free(key);
        var list: std.ArrayList(*Client) = .empty;
        errdefer list.deinit(self.allocator);
        try list.append(self.allocator, client);
        try self.exact_subscribers.put(key, list);
    }

    fn removeIndexLocked(self: *Broker, client: *Client, pattern: []const u8) void {
        if (isWildcard(pattern)) {
            for (self.wildcard_subscriptions.items, 0..) |subscription, index| {
                if (subscription.client == client and std.mem.eql(u8, subscription.pattern, pattern)) {
                    _ = self.wildcard_subscriptions.swapRemove(index);
                    return;
                }
            }
            return;
        }
        if (self.exact_subscribers.getPtr(pattern)) |list| {
            for (list.items, 0..) |subscriber, index| {
                if (subscriber == client) {
                    _ = list.swapRemove(index);
                    break;
                }
            }
            if (list.items.len == 0) {
                const removed = self.exact_subscribers.fetchRemove(pattern).?;
                var removed_list = removed.value;
                removed_list.deinit(self.allocator);
                self.allocator.free(removed.key);
            }
        }
    }

    fn addGroupIndexLocked(self: *Broker, client: *Client, pattern: []const u8, group: []const u8) !void {
        try self.group_subscriptions.append(self.allocator, .{
            .pattern = client.subscriptions.getKey(pattern).?,
            .group = client.subscriptions.get(pattern).?.?,
            .client = client,
        });
        _ = group;
    }

    fn removeGroupIndexLocked(self: *Broker, client: *Client, pattern: []const u8) void {
        for (self.group_subscriptions.items, 0..) |subscription, index| {
            if (subscription.client == client and std.mem.eql(u8, subscription.pattern, pattern)) {
                _ = self.group_subscriptions.swapRemove(index);
                return;
            }
        }
    }

    fn deliverCustom(self: *Broker, client: *Client, topic: []const u8, reply: ?[]const u8, payload: []const u8) void {
        if (client.last_delivery_generation == self.delivery_generation) return;
        client.last_delivery_generation = self.delivery_generation;
        client.sendCustomMessage(topic, reply, payload) catch |err| std.log.debug("custom delivery failed: {s}", .{@errorName(err)});
    }

    fn deliverOneGroup(self: *Broker, topic: []const u8, reply: ?[]const u8, payload: []const u8) void {
        for (self.group_subscriptions.items, 0..) |subscription, first_index| {
            if (!zigmq.subjectMatches(subscription.pattern, topic)) continue;
            var duplicate = false;
            for (self.group_subscriptions.items[0..first_index]) |previous| {
                if (std.mem.eql(u8, previous.pattern, subscription.pattern) and std.mem.eql(u8, previous.group, subscription.group)) {
                    duplicate = true;
                    break;
                }
            }
            if (duplicate) continue;
            var count: usize = 0;
            for (self.group_subscriptions.items) |candidate| {
                if (std.mem.eql(u8, candidate.pattern, subscription.pattern) and std.mem.eql(u8, candidate.group, subscription.group) and zigmq.subjectMatches(candidate.pattern, topic)) count += 1;
            }
            if (count == 0) continue;
            const chosen = self.delivery_generation % count;
            var current: usize = 0;
            for (self.group_subscriptions.items) |candidate| {
                if (std.mem.eql(u8, candidate.pattern, subscription.pattern) and std.mem.eql(u8, candidate.group, subscription.group) and zigmq.subjectMatches(candidate.pattern, topic)) {
                    if (current == chosen) {
                        self.deliverCustom(candidate.client, topic, reply, payload);
                        break;
                    }
                    current += 1;
                }
            }
        }
    }

    fn appendStreamLocked(self: *Broker, topic: []const u8, payload: []const u8) !void {
        const file = &(self.stream_file orelse return);
        if (topic.len > std.math.maxInt(u16) or payload.len > std.math.maxInt(u32)) return error.RecordTooLarge;
        self.stream_sequence +%= 1;
        var header: [22]u8 = undefined;
        std.mem.writeInt(u64, header[0..8], self.stream_sequence, .little);
        std.mem.writeInt(u64, header[8..16], @as(u64, @intCast(std.time.milliTimestamp())), .little);
        std.mem.writeInt(u16, header[16..18], @as(u16, @intCast(topic.len)), .little);
        std.mem.writeInt(u32, header[18..22], @as(u32, @intCast(payload.len)), .little);
        try file.writeAll(&header);
        try file.writeAll(topic);
        try file.writeAll(payload);
        try file.sync();
    }

    fn recoverStreamSequence(self: *Broker) !void {
        const file = &(self.stream_file orelse return);
        try file.seekTo(0);
        while (true) {
            var header: [22]u8 = undefined;
            readFileExact(file, &header) catch |err| switch (err) {
                error.EndOfStream => break,
                else => return err,
            };
            const sequence = std.mem.readInt(u64, header[0..8], .little);
            const topic_len = std.mem.readInt(u16, header[16..18], .little);
            const payload_len = std.mem.readInt(u32, header[18..22], .little);
            try file.seekBy(@as(i64, topic_len) + @as(i64, payload_len));
            if (sequence > self.stream_sequence) self.stream_sequence = sequence;
        }
        try file.seekFromEnd(0);
    }

    fn replay(self: *Broker, client: *Client, from_sequence: u64, subject: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        const file = &(self.stream_file orelse return error.StreamDisabled);
        try file.seekTo(0);
        while (true) {
            var header: [22]u8 = undefined;
            readFileExact(file, &header) catch |err| switch (err) {
                error.EndOfStream => break,
                else => return err,
            };
            const sequence = std.mem.readInt(u64, header[0..8], .little);
            const topic_len = std.mem.readInt(u16, header[16..18], .little);
            const payload_len = std.mem.readInt(u32, header[18..22], .little);
            const topic = try self.allocator.alloc(u8, topic_len);
            defer self.allocator.free(topic);
            const payload = try self.allocator.alloc(u8, payload_len);
            defer self.allocator.free(payload);
            try readFileExact(file, topic);
            try readFileExact(file, payload);
            if (sequence >= from_sequence and zigmq.subjectMatches(subject, topic)) {
                client.sendCustomMessage(topic, null, payload) catch |err| std.log.debug("replay delivery failed: {s}", .{@errorName(err)});
            }
        }
        try file.seekFromEnd(0);
    }

    fn publishCustom(self: *Broker, topic: []const u8, payload: []const u8, reply: ?[]const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.delivery_generation +%= 1;
        if (self.delivery_generation == 0) self.delivery_generation = 1;
        self.appendStreamLocked(topic, payload) catch |err| std.log.debug("stream append failed: {s}", .{@errorName(err)});
        if (self.exact_subscribers.get(topic)) |list| {
            for (list.items) |client| self.deliverCustom(client, topic, reply, payload);
        }
        for (self.wildcard_subscriptions.items) |subscription| {
            if (zigmq.subjectMatches(subscription.pattern, topic)) self.deliverCustom(subscription.client, topic, reply, payload);
        }
        self.deliverOneGroup(topic, reply, payload);
    }

    fn publish(self: *Broker, topic: []const u8, payload: []const u8) void {
        self.publishCustom(topic, payload, null);
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.nats_subscribers.get(topic)) |list| {
            for (list.items) |subscription| {
                subscription.client.sendNatsMessage(topic, subscription.sid, payload) catch |err| std.log.debug("nats delivery failed: {s}", .{@errorName(err)});
            }
        }
        for (self.nats_wildcard_subscriptions.items) |subscription| {
            if (zigmq.subjectMatches(subscription.subject, topic)) {
                subscription.client.sendNatsMessage(topic, subscription.sid, payload) catch |err| std.log.debug("nats delivery failed: {s}", .{@errorName(err)});
            }
        }
    }

    fn removeMqttSubscriptionLocked(self: *Broker, client: *Client, filter: []const u8) void {
        for (self.mqtt_subscriptions.items, 0..) |subscription, index| {
            if (subscription.client == client and std.mem.eql(u8, subscription.filter, filter)) {
                _ = self.mqtt_subscriptions.swapRemove(index);
                return;
            }
        }
    }

    fn mqttSubscribe(self: *Broker, client: *Client, filter: []const u8) !bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (client.mqtt_subscriptions.items.len >= zigmq.max_mqtt_subscriptions_per_client) return error.TooManySubscriptions;
        for (client.mqtt_subscriptions.items) |existing| {
            if (std.mem.eql(u8, existing, filter)) return false;
        }
        const copy = try self.allocator.dupe(u8, filter);
        errdefer self.allocator.free(copy);
        try client.mqtt_subscriptions.append(self.allocator, copy);
        errdefer _ = client.mqtt_subscriptions.pop();
        try self.mqtt_subscriptions.append(self.allocator, .{ .filter = copy, .client = client });
        return true;
    }

    fn mqttUnsubscribe(self: *Broker, client: *Client, filter: []const u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        for (client.mqtt_subscriptions.items, 0..) |existing, index| {
            if (std.mem.eql(u8, existing, filter)) {
                _ = client.mqtt_subscriptions.swapRemove(index);
                self.removeMqttSubscriptionLocked(client, filter);
                self.allocator.free(existing);
                return true;
            }
        }
        return false;
    }

    fn deliverMqttRetainedLocked(self: *Broker, client: *Client, filter: []const u8) void {
        const now = std.time.nanoTimestamp();
        var iterator = self.retained.iterator();
        while (iterator.next()) |entry| {
            const message = entry.value_ptr.*;
            if (message.expires_at_ns != 0 and now >= message.expires_at_ns) continue;
            if (mqttTopicMatches(filter, entry.key_ptr.*)) {
                client.sendMqttPublish(entry.key_ptr.*, message.payload, true) catch |err| std.log.debug("mqtt retained delivery failed: {s}", .{@errorName(err)});
            }
        }
    }

    fn publishMqtt(self: *Broker, topic: []const u8, payload: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        for (self.mqtt_subscriptions.items) |subscription| {
            if (mqttTopicMatches(subscription.filter, topic)) {
                subscription.client.sendMqttPublish(topic, payload, false) catch |err| std.log.debug("mqtt delivery failed: {s}", .{@errorName(err)});
            }
        }
    }

    fn setRetained(self: *Broker, topic: []const u8, payload: []const u8, ttl_ms: u64) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        const expires_at_ns: i128 = if (ttl_ms == 0) 0 else std.time.nanoTimestamp() + @as(i128, ttl_ms) * std.time.ns_per_ms;
        const payload_copy = try self.allocator.dupe(u8, payload);
        if (self.retained.getPtr(topic)) |existing| {
            self.allocator.free(existing.payload);
            existing.* = .{ .payload = payload_copy, .expires_at_ns = expires_at_ns };
            return;
        }
        const key = try self.allocator.dupe(u8, topic);
        errdefer self.allocator.free(key);
        self.retained.put(key, .{ .payload = payload_copy, .expires_at_ns = expires_at_ns }) catch |err| {
            self.allocator.free(payload_copy);
            return err;
        };
    }

    fn deliverRetainedLocked(self: *Broker, client: *Client, subject: []const u8) void {
        const now = std.time.nanoTimestamp();
        var iterator = self.retained.iterator();
        while (iterator.next()) |entry| {
            const message = entry.value_ptr.*;
            if (message.expires_at_ns != 0 and now >= message.expires_at_ns) continue;
            if (zigmq.subjectMatches(subject, entry.key_ptr.*)) {
                client.sendCustomMessage(entry.key_ptr.*, null, message.payload) catch |err| std.log.debug("retained delivery failed: {s}", .{@errorName(err)});
            }
        }
    }

    fn subscribe(self: *Broker, client: *Client, subject: []const u8, group: ?[]const u8) !bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (client.subscriptions.contains(subject)) return false;
        const copy = try self.allocator.dupe(u8, subject);
        errdefer self.allocator.free(copy);
        const group_copy = if (group) |value| try self.allocator.dupe(u8, value) else null;
        errdefer if (group_copy) |value| self.allocator.free(value);
        try client.subscriptions.put(copy, group_copy);
        errdefer {
            const removed = client.subscriptions.fetchRemove(subject).?;
            if (removed.value) |value| self.allocator.free(value);
            self.allocator.free(removed.key);
        }
        if (group) |group_name| {
            try self.addGroupIndexLocked(client, subject, group_name);
        } else {
            try self.addIndexLocked(client, subject);
        }
        return true;
    }

    fn deliverRetained(self: *Broker, client: *Client, subject: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.deliverRetainedLocked(client, subject);
    }

    fn unsubscribe(self: *Broker, client: *Client, subject: []const u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        const removed = client.subscriptions.fetchRemove(subject) orelse return false;
        self.removeIndexLocked(client, removed.key);
        self.removeGroupIndexLocked(client, removed.key);
        if (removed.value) |group| self.allocator.free(group);
        self.allocator.free(removed.key);
        return true;
    }

    fn natsSubscribe(self: *Broker, client: *Client, subject: []const u8, sid: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        for (client.nats_subscriptions.items) |subscription| {
            if (std.mem.eql(u8, subscription.sid, sid)) return error.DuplicateSubscription;
        }
        const subject_copy = try self.allocator.dupe(u8, subject);
        errdefer self.allocator.free(subject_copy);
        const sid_copy = try self.allocator.dupe(u8, sid);
        errdefer self.allocator.free(sid_copy);
        try client.nats_subscriptions.append(self.allocator, .{ .subject = subject_copy, .sid = sid_copy });
        errdefer {
            const removed = client.nats_subscriptions.pop().?;
            self.allocator.free(removed.subject);
            self.allocator.free(removed.sid);
        }
        const reference = NatsSubscriptionRef{ .subject = subject_copy, .sid = sid_copy, .client = client };
        if (isWildcard(subject)) {
            try self.nats_wildcard_subscriptions.append(self.allocator, reference);
            return;
        }
        if (self.nats_subscribers.getPtr(subject)) |list| {
            try list.append(self.allocator, reference);
            return;
        }
        const key = try self.allocator.dupe(u8, subject);
        errdefer self.allocator.free(key);
        var list: std.ArrayList(NatsSubscriptionRef) = .empty;
        errdefer list.deinit(self.allocator);
        try list.append(self.allocator, reference);
        try self.nats_subscribers.put(key, list);
    }

    fn natsUnsubscribe(self: *Broker, client: *Client, sid: []const u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        for (client.nats_subscriptions.items, 0..) |subscription, index| {
            if (std.mem.eql(u8, subscription.sid, sid)) {
                self.removeNatsIndexLocked(client, subscription.subject, subscription.sid);
                self.allocator.free(subscription.subject);
                self.allocator.free(subscription.sid);
                _ = client.nats_subscriptions.swapRemove(index);
                return true;
            }
        }
        return false;
    }
};

const help_text = "+OK commands: SUB <subject> [group], UNSUB <subject>, PUB <subject> <payload>, RETAIN <topic> <ttl_ms> <payload>, REQ <topic> <reply> <payload>, AUTH <token>, PING, PONG, HELP, QUIT\r\n";

fn parseErrorText(err: zigmq.ParseError) []const u8 {
    return switch (err) {
        error.EmptyCommand => "empty command",
        error.InvalidCommand => "invalid command",
        error.MissingTopic => "topic is required",
        error.MissingPayload => "payload is required",
        error.MissingTtl => "ttl is required",
        error.InvalidTtl => "ttl is invalid",
        error.MissingSequence => "sequence is required",
        error.InvalidSequence => "sequence is invalid",
        error.MissingToken => "token is required",
        error.TopicTooLong => "topic is too long",
        error.PayloadTooLong => "payload is too long",
        error.InvalidTopic => "invalid topic",
        error.WildcardNotAllowed => "wildcard is not allowed here",
    };
}

fn parseProtocol(text: []const u8) !Protocol {
    if (std.mem.eql(u8, text, "custom")) return .custom;
    if (std.mem.eql(u8, text, "nats")) return .nats;
    if (std.mem.eql(u8, text, "mqtt")) return .mqtt;
    return error.InvalidProtocol;
}

fn authMatches(line: []const u8, expected: []const u8) bool {
    const marker = "\"auth_token\"";
    const marker_start = std.mem.indexOf(u8, line, marker) orelse return false;
    const colon = std.mem.indexOfScalarPos(u8, line, marker_start + marker.len, ':') orelse return false;
    const value_start = std.mem.indexOfScalarPos(u8, line, colon + 1, '"') orelse return false;
    const value_end = std.mem.indexOfScalarPos(u8, line, value_start + 1, '"') orelse return false;
    return std.mem.eql(u8, line[value_start + 1 .. value_end], expected);
}

fn readLine(reader: *net.Stream.Reader) !?[]const u8 {
    return reader.interface().takeDelimiter('\n') catch |err| switch (err) {
        error.StreamTooLong => return error.LineTooLong,
        error.ReadFailed => return error.ReadFailed,
    };
}

const MqttPacket = struct { first: u8, body: []u8 };

fn mqttDecodeRemainingLength(reader: *net.Stream.Reader) !usize {
    var value: usize = 0;
    var multiplier: usize = 1;
    var count: usize = 0;
    while (count < 4) : (count += 1) {
        const encoded = try reader.interface().takeByte();
        value += @as(usize, encoded & 127) * multiplier;
        if ((encoded & 128) == 0) return value;
        multiplier *= 128;
    }
    return error.InvalidMqttLength;
}

fn readMqttPacket(reader: *net.Stream.Reader, allocator: Allocator) !MqttPacket {
    const first = try reader.interface().takeByte();
    const remaining_length = try mqttDecodeRemainingLength(reader);
    if (remaining_length > zigmq.max_payload_length + zigmq.max_topic_length + 1024) return error.MqttPacketTooLarge;
    const body = try allocator.alloc(u8, remaining_length);
    errdefer allocator.free(body);
    if (remaining_length > 0) try reader.interface().readSliceAll(body);
    return .{ .first = first, .body = body };
}

fn mqttReadU16(body: []const u8, index: *usize) !u16 {
    if (body.len -| index.* < 2) return error.InvalidMqttPacket;
    const value = std.mem.readInt(u16, body[index.*..][0..2], .big);
    index.* += 2;
    return value;
}

fn mqttReadBytes(body: []const u8, index: *usize) ![]const u8 {
    const length = try mqttReadU16(body, index);
    if (body.len -| index.* < length) return error.InvalidMqttPacket;
    const value = body[index.*..][0..length];
    index.* += length;
    return value;
}

fn mqttValidateTopicName(topic: []const u8) !void {
    if (topic.len == 0 or topic.len > zigmq.max_topic_length) return error.InvalidMqttTopic;
    if (std.mem.indexOfAny(u8, topic, "#+\x00") != null) return error.InvalidMqttTopic;
}

fn mqttValidateFilter(filter: []const u8) !void {
    if (filter.len == 0 or filter.len > zigmq.max_topic_length) return error.InvalidMqttFilter;
    var start: usize = 0;
    while (true) {
        const relative_end = std.mem.indexOfScalar(u8, filter[start..], '/') orelse filter.len - start;
        const end = start + relative_end;
        const level = filter[start..end];
        if (std.mem.indexOfScalar(u8, level, '#')) |position| {
            if (!std.mem.eql(u8, level, "#") or end != filter.len or position != 0) return error.InvalidMqttFilter;
        }
        if (std.mem.indexOfScalar(u8, level, '+')) |position| {
            if (!std.mem.eql(u8, level, "+") or position != 0) return error.InvalidMqttFilter;
        }
        if (end == filter.len) return;
        start = end + 1;
    }
}

fn mqttSendFixed(client: *Client, first: u8, body: []const u8) !void {
    var length_bytes: [4]u8 = undefined;
    const length_size = mqttEncodeRemainingLength(body.len, &length_bytes);
    const packet = try client.allocator.alloc(u8, 1 + length_size + body.len);
    errdefer client.allocator.free(packet);
    packet[0] = first;
    @memcpy(packet[1 .. 1 + length_size], length_bytes[0..length_size]);
    @memcpy(packet[1 + length_size ..], body);
    return client.enqueueOwned(packet);
}

fn readNatsPayload(reader: *net.Stream.Reader, allocator: Allocator, length: usize) ![]u8 {
    if (length > zigmq.max_payload_length) return error.PayloadTooLong;
    const payload = try allocator.alloc(u8, length);
    errdefer allocator.free(payload);
    if (length > 0) reader.interface().readSliceAll(payload) catch return error.InvalidPayload;
    const terminator = reader.interface().take(2) catch return error.InvalidPayload;
    if (!std.mem.eql(u8, terminator, "\r\n")) return error.InvalidPayload;
    return payload;
}

fn handleCustomCommand(broker: *Broker, client: *Client, line: []const u8) bool {
    const command = zigmq.parseCommand(line) catch |err| {
        var response: [128]u8 = undefined;
        const bytes = std.fmt.bufPrint(&response, "-ERR {s}\r\n", .{parseErrorText(err)}) catch return false;
        client.send(bytes) catch return false;
        return true;
    };
    switch (command) {
        .auth => |token| {
            if (broker.auth_token) |expected| {
                if (std.mem.eql(u8, token, expected)) {
                    client.authenticated = true;
                    client.send("+OK AUTH\r\n") catch return false;
                } else {
                    client.send("-ERR authentication failed\r\n") catch return false;
                    return false;
                }
            } else {
                client.send("+OK authentication disabled\r\n") catch return false;
            }
            return true;
        },
        else => {},
    }
    if (!client.authenticated) {
        client.send("-ERR authentication required\r\n") catch return false;
        return true;
    }
    switch (command) {
        .subscribe => |subscription| {
            const added = broker.subscribe(client, subscription.subject, subscription.group) catch {
                client.send("-ERR out of memory\r\n") catch return false;
                return true;
            };
            client.send(if (added) "+OK SUB\r\n" else "+OK already subscribed\r\n") catch return false;
            if (added) broker.deliverRetained(client, subscription.subject);
            return true;
        },
        .unsubscribe => |subject| {
            client.send(if (broker.unsubscribe(client, subject)) "+OK UNSUB\r\n" else "+OK not subscribed\r\n") catch return false;
            return true;
        },
        .publish => |message| {
            broker.publish(message.topic, message.payload);
            client.send("+OK PUB\r\n") catch return false;
            return true;
        },
        .retain => |message| {
            broker.setRetained(message.topic, message.payload, message.ttl_ms) catch {
                client.send("-ERR out of memory\r\n") catch return false;
                return true;
            };
            broker.publish(message.topic, message.payload);
            client.send("+OK RETAIN\r\n") catch return false;
            return true;
        },
        .request => |message| {
            broker.publishCustom(message.topic, message.payload, message.reply);
            client.send("+OK REQ\r\n") catch return false;
            return true;
        },
        .replay => |message| {
            client.send("+OK REPLAY\r\n") catch return false;
            broker.replay(client, message.from_sequence, message.subject) catch {
                client.send("-ERR stream is disabled or unreadable\r\n") catch return false;
            };
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
        .auth => unreachable,
    }
}

fn natsVerbose(line: []const u8) bool {
    const trimmed = std.mem.replaceOwned(u8, std.heap.page_allocator, line, " ", "") catch return true;
    defer std.heap.page_allocator.free(trimmed);
    return std.mem.indexOf(u8, trimmed, "\"verbose\":false") == null;
}

fn natsError(client: *Client, message: []const u8) bool {
    client.sendFmt("-ERR '{s}'\r\n", .{message}) catch return false;
    return true;
}

fn handleNatsCommand(broker: *Broker, client: *Client, reader: *net.Stream.Reader, line: []const u8) bool {
    var tokens = std.mem.tokenizeAny(u8, std.mem.trim(u8, line, " \t\r\n"), " \t");
    const operation = tokens.next() orelse return natsError(client, "Empty Command");
    if (std.ascii.eqlIgnoreCase(operation, "CONNECT")) {
        if (broker.auth_token) |expected| {
            if (!authMatches(line, expected)) return natsError(client, "Authorization Violation");
        }
        client.verbose = natsVerbose(line);
        client.authenticated = true;
        if (client.verbose) client.send("+OK\r\n") catch return false;
        return true;
    }
    if (std.ascii.eqlIgnoreCase(operation, "PING")) {
        client.send("PONG\r\n") catch return false;
        return true;
    }
    if (std.ascii.eqlIgnoreCase(operation, "PONG")) return true;
    if (!client.authenticated) return natsError(client, "Authorization Violation");

    if (std.ascii.eqlIgnoreCase(operation, "SUB")) {
        const subject = tokens.next() orelse return natsError(client, "Bad Subscription");
        const second = tokens.next() orelse return natsError(client, "Bad Subscription");
        const sid = tokens.next() orelse second;
        if (tokens.next() != null) return natsError(client, "Bad Subscription");
        zigmq.validateSubject(subject, true) catch return natsError(client, "Invalid Subject");
        broker.natsSubscribe(client, subject, sid) catch return natsError(client, "Bad Subscription");
        if (client.verbose) client.send("+OK\r\n") catch return false;
        return true;
    }
    if (std.ascii.eqlIgnoreCase(operation, "UNSUB")) {
        const sid = tokens.next() orelse return natsError(client, "Bad Subscription");
        if (tokens.next() != null) return natsError(client, "Bad Subscription");
        _ = broker.natsUnsubscribe(client, sid);
        if (client.verbose) client.send("+OK\r\n") catch return false;
        return true;
    }
    if (std.ascii.eqlIgnoreCase(operation, "PUB")) {
        const subject = tokens.next() orelse return natsError(client, "Bad Publish");
        const second = tokens.next() orelse return natsError(client, "Bad Publish");
        const third = tokens.next();
        if (tokens.next() != null) return natsError(client, "Bad Publish");
        const size_text = third orelse second;
        const size = std.fmt.parseInt(usize, size_text, 10) catch return natsError(client, "Bad Publish");
        zigmq.validateTopic(subject) catch return natsError(client, "Invalid Subject");
        const payload = readNatsPayload(reader, broker.allocator, size) catch return natsError(client, "Bad Publish");
        defer broker.allocator.free(payload);
        broker.publish(subject, payload);
        if (client.verbose) client.send("+OK\r\n") catch return false;
        return true;
    }
    if (std.ascii.eqlIgnoreCase(operation, "INFO")) return true;
    return natsError(client, "Unknown Protocol Operation");
}

fn natsInfo(broker: *Broker, client: *Client) !void {
    const auth_required = if (broker.auth_token != null) "true" else "false";
    try client.sendFmt("INFO {{\"server_id\":\"zigmq\",\"server_name\":\"zigmq\",\"version\":\"0.2.0\",\"proto\":1,\"host\":\"{s}\",\"port\":{d},\"headers\":false,\"max_payload\":{d},\"auth_required\":{s}}}\r\n", .{ broker.host, broker.port, zigmq.max_payload_length, auth_required });
}

fn mqttConnack(client: *Client, return_code: u8) !void {
    const body = [_]u8{ 0, return_code };
    try mqttSendFixed(client, 0x20, &body);
}

fn mqttConnackDirect(client: *Client, return_code: u8) !void {
    const packet = [_]u8{ 0x20, 0x02, 0x00, return_code };
    try client.stream.writeAll(&packet);
}

fn mqttSuback(client: *Client, packet_id: u16, codes: []const u8) !void {
    const body = try client.allocator.alloc(u8, 2 + codes.len);
    defer client.allocator.free(body);
    std.mem.writeInt(u16, body[0..2], packet_id, .big);
    @memcpy(body[2..], codes);
    try mqttSendFixed(client, 0x90, body);
}

fn mqttUnsuback(client: *Client, packet_id: u16) !void {
    var body: [2]u8 = undefined;
    std.mem.writeInt(u16, &body, packet_id, .big);
    try mqttSendFixed(client, 0xB0, &body);
}

fn handleMqttConnect(broker: *Broker, client: *Client, body: []const u8) !bool {
    if (client.mqtt_connected) return false;
    var index: usize = 0;
    const protocol_name = try mqttReadBytes(body, &index);
    if (!std.mem.eql(u8, protocol_name, "MQTT")) {
        try mqttConnackDirect(client, 0x01);
        return false;
    }
    if (body.len -| index < 4) return error.InvalidMqttPacket;
    const protocol_level = body[index];
    index += 1;
    const connect_flags = body[index];
    index += 1;
    _ = try mqttReadU16(body, &index);
    if (protocol_level != 4 or (connect_flags & 0x01) != 0 or (connect_flags & 0x1C) != 0) {
        try mqttConnackDirect(client, 0x01);
        return false;
    }
    _ = try mqttReadBytes(body, &index);
    const username = if ((connect_flags & 0x80) != 0) try mqttReadBytes(body, &index) else null;
    const password = if ((connect_flags & 0x40) != 0) try mqttReadBytes(body, &index) else null;
    if (index != body.len) return error.InvalidMqttPacket;
    if (broker.auth_token) |expected| {
        const credential = password orelse username orelse {
            try mqttConnackDirect(client, 0x04);
            return false;
        };
        if (!std.mem.eql(u8, credential, expected)) {
            try mqttConnackDirect(client, 0x04);
            return false;
        }
    }
    client.mqtt_connected = true;
    client.authenticated = true;
    try mqttConnack(client, 0x00);
    return true;
}

fn handleMqttSubscribe(broker: *Broker, client: *Client, body: []const u8) !bool {
    var index: usize = 0;
    const packet_id = try mqttReadU16(body, &index);
    var codes: std.ArrayList(u8) = .empty;
    defer codes.deinit(client.allocator);
    var retained_filters: std.ArrayList([]const u8) = .empty;
    defer retained_filters.deinit(client.allocator);
    while (index < body.len) {
        const filter = try mqttReadBytes(body, &index);
        if (index >= body.len) return error.InvalidMqttPacket;
        const requested_qos = body[index];
        index += 1;
        mqttValidateFilter(filter) catch {
            try codes.append(client.allocator, 0x80);
            continue;
        };
        if (requested_qos > 0) {
            try codes.append(client.allocator, 0x80);
            continue;
        }
        _ = broker.mqttSubscribe(client, filter) catch |err| {
            try codes.append(client.allocator, if (err == error.TooManySubscriptions) 0x97 else 0x80);
            continue;
        };
        try codes.append(client.allocator, 0x00);
        try retained_filters.append(client.allocator, filter);
    }
    if (codes.items.len == 0) return error.InvalidMqttPacket;
    try mqttSuback(client, packet_id, codes.items);
    broker.mutex.lock();
    defer broker.mutex.unlock();
    for (retained_filters.items) |filter| broker.deliverMqttRetainedLocked(client, filter);
    return true;
}

fn handleMqttUnsubscribe(broker: *Broker, client: *Client, body: []const u8) !bool {
    var index: usize = 0;
    const packet_id = try mqttReadU16(body, &index);
    while (index < body.len) {
        const filter = try mqttReadBytes(body, &index);
        _ = broker.mqttUnsubscribe(client, filter);
    }
    if (index != body.len) return error.InvalidMqttPacket;
    try mqttUnsuback(client, packet_id);
    return true;
}

fn handleMqttPublish(broker: *Broker, client: *Client, first: u8, body: []const u8) !bool {
    _ = client;
    const qos = (first >> 1) & 0x03;
    if (qos != 0) return error.UnsupportedMqttQos;
    var index: usize = 0;
    const topic = try mqttReadBytes(body, &index);
    try mqttValidateTopicName(topic);
    const payload = body[index..];
    if (payload.len > zigmq.max_payload_length) return error.PayloadTooLong;
    if ((first & 0x01) != 0) try broker.setRetained(topic, payload, 0);
    broker.publishCustom(topic, payload, null);
    broker.publishMqtt(topic, payload);
    return true;
}

fn handleMqttCommand(broker: *Broker, client: *Client, reader: *net.Stream.Reader) bool {
    const packet = readMqttPacket(reader, broker.allocator) catch return false;
    defer broker.allocator.free(packet.body);
    const packet_type = packet.first >> 4;
    const flags = packet.first & 0x0F;
    if (!client.mqtt_connected) {
        if (packet_type != 1 or flags != 0) return false;
        return handleMqttConnect(broker, client, packet.body) catch false;
    }
    return switch (packet_type) {
        3 => if (flags & 0x08 != 0) false else handleMqttPublish(broker, client, packet.first, packet.body) catch false,
        8 => if (flags != 2) false else handleMqttSubscribe(broker, client, packet.body) catch false,
        10 => if (flags != 2) false else handleMqttUnsubscribe(broker, client, packet.body) catch false,
        12 => blk: {
            if (packet.body.len != 0 or flags != 0) break :blk false;
            mqttSendFixed(client, 0xD0, &[_]u8{}) catch break :blk false;
            break :blk true;
        },
        14 => packet.body.len == 0 and flags == 0,
        else => false,
    };
}

fn handleClient(broker: *Broker, stream: net.Stream) void {
    const initially_authenticated = broker.auth_token == null;
    var client = Client.init(stream, broker.allocator, initially_authenticated);
    defer client.deinit();
    defer stream.close();
    if (broker.addClient(&client)) |_| {} else |_| return;
    defer broker.disconnect(&client);

    const writer = std.Thread.spawn(.{}, Client.writerLoop, .{&client}) catch return;
    defer writer.join();

    if (broker.protocol == .nats) {
        natsInfo(broker, &client) catch return;
    } else if (broker.protocol == .custom) {
        client.send(if (initially_authenticated) "+OK zigmq ready\r\n" else "+OK zigmq ready auth=required\r\n") catch return;
    }

    var input_buffer: [zigmq.max_control_line_length + 1]u8 = undefined;
    var reader = stream.reader(&input_buffer);
    while (!stop_requested.load(.seq_cst)) {
        const keep_running = if (broker.protocol == .mqtt) blk: {
            break :blk handleMqttCommand(broker, &client, &reader);
        } else blk: {
            const line = readLine(&reader) catch |err| {
                if (err == error.LineTooLong) client.send("-ERR command line too long\r\n") catch {};
                break :blk false;
            } orelse break :blk false;
            break :blk if (broker.protocol == .nats)
                handleNatsCommand(broker, &client, &reader, line)
            else
                handleCustomCommand(broker, &client, line);
        };
        if (!keep_running) break;
    }
    client.requestClose();
}

fn signalHandler(_: i32) callconv(.c) void {
    stop_requested.store(true, .seq_cst);
}

fn installSignalHandlers() void {
    const action = posix.Sigaction{ .handler = .{ .handler = signalHandler }, .mask = posix.sigemptyset(), .flags = 0 };
    posix.sigaction(posix.SIG.INT, &action, null);
    posix.sigaction(posix.SIG.TERM, &action, null);
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

    if (args.len >= 2 and !std.mem.startsWith(u8, args[1], "--") and !std.mem.eql(u8, args[1], "server")) {
        return cli.run(allocator, args);
    }
    var host: []const u8 = "127.0.0.1";
    var port: u16 = 4222;
    var port_explicit = false;
    var protocol: Protocol = .custom;
    var auth_token: ?[]const u8 = null;
    var stream_path: ?[]const u8 = null;
    var index: usize = if (args.len >= 2 and std.mem.eql(u8, args[1], "server")) 2 else 1;
    while (index < args.len) : (index += 1) {
        if (std.mem.eql(u8, args[index], "--host")) {
            index += 1;
            if (index >= args.len) return error.MissingHost;
            host = args[index];
        } else if (std.mem.eql(u8, args[index], "--port")) {
            index += 1;
            if (index >= args.len) return error.MissingPort;
            port = try parsePort(args[index]);
            port_explicit = true;
        } else if (std.mem.eql(u8, args[index], "--protocol")) {
            index += 1;
            if (index >= args.len) return error.MissingProtocol;
            protocol = try parseProtocol(args[index]);
        } else if (std.mem.eql(u8, args[index], "--auth-token")) {
            index += 1;
            if (index >= args.len or args[index].len == 0) return error.MissingAuthToken;
            auth_token = args[index];
        } else if (std.mem.eql(u8, args[index], "--stream")) {
            index += 1;
            if (index >= args.len or args[index].len == 0) return error.MissingStreamPath;
            stream_path = args[index];
        } else if (std.mem.eql(u8, args[index], "--help")) {
            std.debug.print("Usage: zigmq [--host 127.0.0.1] [--port 4222|1883] [--protocol custom|nats|mqtt] [--auth-token token] [--stream path]\n", .{});
            return;
        } else {
            std.debug.print("Unknown argument: {s}\n", .{args[index]});
            return error.InvalidArgument;
        }
    }

    if (!port_explicit and protocol == .mqtt) port = 1883;
    stop_requested.store(false, .seq_cst);
    installSignalHandlers();
    const address = try net.Address.parseIp4(host, port);
    var server = try address.listen(.{ .reuse_address = true, .force_nonblocking = true });
    defer server.deinit();
    var stream_file: ?std.fs.File = null;
    if (stream_path) |path| {
        stream_file = try std.fs.cwd().createFile(path, .{ .read = true, .truncate = false, .lock = .exclusive });
    }
    var broker = Broker.init(allocator, protocol, host, port, auth_token, stream_file);
    defer broker.deinit();
    try broker.recoverStreamSequence();
    var threads: std.ArrayList(std.Thread) = .empty;
    defer threads.deinit(allocator);

    std.debug.print("zigmq listening on {s}:{d} protocol={s}\n", .{ host, port, @tagName(protocol) });
    while (!stop_requested.load(.seq_cst)) {
        const connection = server.accept() catch |err| {
            if (stop_requested.load(.seq_cst)) break;
            if (err == error.WouldBlock or err == error.Interrupted) {
                std.Thread.sleep(10 * std.time.ns_per_ms);
                continue;
            }
            std.log.err("accept failed: {s}", .{@errorName(err)});
            continue;
        };
        const thread = std.Thread.spawn(.{}, handleClient, .{ &broker, connection.stream }) catch |err| {
            std.log.err("could not start client thread: {s}", .{@errorName(err)});
            connection.stream.close();
            continue;
        };
        threads.append(allocator, thread) catch {
            thread.detach();
        };
    }
    broker.closeAll();
    for (threads.items) |thread| thread.join();
    std.debug.print("zigmq stopped\n", .{});
}
