const std = @import("std");
const net = std.net;
const Allocator = std.mem.Allocator;
const tls = @import("zigmv_tls");

pub const Config = struct {
    allocator: Allocator,
    certificate_path: []const u8,
    private_key_path: []const u8,
    client_ca_path: ?[]const u8 = null,
    require_client_certificate: bool = false,

    pub fn validate(self: Config) !void {
        if (self.certificate_path.len == 0 or self.private_key_path.len == 0) return error.MissingTlsCertificate;
        if (self.require_client_certificate and self.client_ca_path == null) return error.MissingClientCa;
    }
};

const input_buffer_len = tls.input_buffer_len;
const output_buffer_len = tls.output_buffer_len;

pub const Connection = struct {
    stream: net.Stream,
    io_reader: std.Io.Reader,
    io_writer: std.Io.Writer,
    input_storage: [input_buffer_len]u8 = undefined,
    output_storage: [output_buffer_len]u8 = undefined,
    tls_connection: tls.Connection,
    secure: bool = true,

    const Self = @This();

    pub fn connect(allocator: Allocator, stream: net.Stream, config: Config, server_name: []const u8) !Self {
        try config.validate();
        var self = Self{
            .stream = stream,
            .io_reader = undefined,
            .io_writer = undefined,
            .tls_connection = undefined,
        };
        self.io_reader = .{ .vtable = &reader_vtable, .buffer = &self.input_storage, .seek = 0, .end = 0 };
        self.io_writer = .{ .vtable = &writer_vtable, .buffer = &self.output_storage, .end = 0 };
        var cert_key: ?tls.config.CertKeyPair = null;
        defer if (cert_key) |*pair| pair.deinit(allocator);
        if (config.certificate_path.len > 0 and config.private_key_path.len > 0) cert_key = try tls.config.CertKeyPair.fromFilePathAbsolute(allocator, config.certificate_path, config.private_key_path);
        var roots: tls.config.cert.Bundle = .{};
        defer roots.deinit(allocator);
        if (config.client_ca_path) |path| roots = try tls.config.cert.fromFilePathAbsolute(allocator, path);
        self.tls_connection = try tls.client(&self.io_reader, &self.io_writer, .{
            .host = server_name,
            .root_ca = roots,
            .auth = if (cert_key) |*pair| pair else null,
        });
        return self;
    }

    pub fn accept(allocator: Allocator, stream: net.Stream, config: Config) !Self {
        try config.validate();
        var self = Self{
            .stream = stream,
            .io_reader = undefined,
            .io_writer = undefined,
            .tls_connection = undefined,
        };
        self.io_reader = .{
            .vtable = &reader_vtable,
            .buffer = &self.input_storage,
            .seek = 0,
            .end = 0,
        };
        self.io_writer = .{
            .vtable = &writer_vtable,
            .buffer = &self.output_storage,
            .end = 0,
        };
        var cert_key = try tls.config.CertKeyPair.fromFilePathAbsolute(allocator, config.certificate_path, config.private_key_path);
        defer cert_key.deinit(allocator);
        var client_ca: ?tls.config.cert.Bundle = null;
        defer if (client_ca) |*bundle| bundle.deinit(allocator);
        if (config.client_ca_path) |path| client_ca = try tls.config.cert.fromFilePathAbsolute(allocator, path);
        const client_auth: ?tls.config.ClientAuth = if (client_ca) |bundle| .{
            .root_ca = bundle,
            .auth_type = if (config.require_client_certificate) .require else .request,
        } else null;
        self.tls_connection = try tls.server(&self.io_reader, &self.io_writer, .{
            .auth = &cert_key,
            .client_auth = client_auth,
        });
        return self;
    }

    pub fn read(self: *Self, buffer: []u8) !usize {
        return self.tls_connection.read(buffer);
    }

    pub fn writeAll(self: *Self, bytes: []const u8) !void {
        return self.tls_connection.writeAll(bytes);
    }

    pub fn rebind(self: *Self) void {
        self.tls_connection.input = &self.io_reader;
        self.tls_connection.output = &self.io_writer;
    }

    pub fn close(self: *Self) void {
        self.tls_connection.close() catch {};
    }

    fn readerStream(reader: *std.Io.Reader, writer: *std.Io.Writer, limit: std.Io.Limit) std.Io.Reader.StreamError!usize {
        const self: *Self = @alignCast(@fieldParentPtr("io_reader", reader));
        var scratch: [4096]u8 = undefined;
        const count = limit.toInt() orelse scratch.len;
        const amount = @min(count, scratch.len);
        const n = self.stream.read(scratch[0..amount]) catch return error.ReadFailed;
        if (n == 0) return error.EndOfStream;
        return writer.write(scratch[0..n]) catch error.WriteFailed;
    }

    fn writerFlush(writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const self: *Self = @alignCast(@fieldParentPtr("io_writer", writer));
        const bytes = writer.buffered();
        if (bytes.len == 0) return;
        var offset: usize = 0;
        while (offset < bytes.len) {
            const n = self.stream.write(bytes[offset..]) catch return error.WriteFailed;
            if (n == 0) return error.WriteFailed;
            offset += n;
        }
        writer.end = 0;
    }

    const reader_vtable: std.Io.Reader.VTable = .{ .stream = readerStream };
    const writer_vtable: std.Io.Writer.VTable = .{ .drain = writerDrain, .flush = writerFlush };

    fn writerDrain(writer: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const self: *Self = @alignCast(@fieldParentPtr("io_writer", writer));
        var total: usize = 0;
        for (data) |slice| {
            for (0..splat) |_| {
                var offset: usize = 0;
                while (offset < slice.len) {
                    const n = self.stream.write(slice[offset..]) catch return error.WriteFailed;
                    if (n == 0) return error.WriteFailed;
                    offset += n;
                    total += n;
                }
            }
        }
        return total;
    }
};


pub const Transport = struct {
    kind: Kind,
    stream: net.Stream,
    tls_connection: ?Connection = null,

    pub const Kind = enum { plain, tls };

    pub fn plain(stream: net.Stream) Transport {
        return .{ .kind = .plain, .stream = stream };
    }

    pub fn tlsAccept(allocator: Allocator, stream: net.Stream, config: Config) !Transport {
        const connection = try Connection.accept(allocator, stream, config);
        return .{ .kind = .tls, .stream = stream, .tls_connection = connection };
    }

    pub fn tlsConnect(allocator: Allocator, stream: net.Stream, config: Config, server_name: []const u8) !Transport {
        const connection = try Connection.connect(allocator, stream, config, server_name);
        return .{ .kind = .tls, .stream = stream, .tls_connection = connection };
    }

    pub fn rebind(self: *Transport) void {
        if (self.kind == .tls) self.tls_connection.?.rebind();
    }

    pub fn read(self: *Transport, buffer: []u8) !usize {
        return switch (self.kind) {
            .plain => self.stream.read(buffer),
            .tls => self.tls_connection.?.read(buffer),
        };
    }

    pub fn writeAll(self: *Transport, bytes: []const u8) !void {
        return switch (self.kind) {
            .plain => self.stream.writeAll(bytes),
            .tls => self.tls_connection.?.writeAll(bytes),
        };
    }

    pub fn close(self: *Transport) void {
        if (self.kind == .tls) self.tls_connection.?.close();
        self.stream.close();
    }

    pub fn reader(self: *Transport) Reader {
        return .{ .context = self, .read_fn = transportRead };
    }

    fn transportRead(context: *anyopaque, buffer: []u8) !usize {
        const self: *Transport = @ptrCast(@alignCast(context));
        return self.read(buffer);
    }
};

pub const Reader = struct {
    context: *anyopaque,
    read_fn: *const fn (*anyopaque, []u8) anyerror!usize,
    buffer: [8192]u8 = undefined,
    line_buffer: [8192]u8 = undefined,
    start: usize = 0,
    end: usize = 0,

    pub fn fill(self: *Reader) !void {
        if (self.start < self.end) return;
        self.start = 0;
        self.end = try self.read_fn(self.context, &self.buffer);
        if (self.end == 0) return error.EndOfStream;
    }

    pub fn takeByte(self: *Reader) !u8 {
        try self.fill();
        const value = self.buffer[self.start];
        self.start += 1;
        return value;
    }

    pub fn take(self: *Reader, count: usize) ![]const u8 {
        if (count > self.buffer.len) return error.ReadFailed;
        while (self.end - self.start < count) {
            if (self.start != 0 and self.start < self.end) {
                const remaining = self.end - self.start;
                std.mem.copyForwards(u8, self.buffer[0..remaining], self.buffer[self.start..self.end]);
                self.start = 0;
                self.end = remaining;
            } else if (self.start == self.end) {
                self.start = 0;
                self.end = 0;
            }
            const n = self.read_fn(self.context, self.buffer[self.end..]);
            if (n catch 0 == 0) return error.EndOfStream;
            self.end += n catch unreachable;
        }
        const result = self.buffer[self.start .. self.start + count];
        self.start += count;
        return result;
    }

    pub fn readSliceAll(self: *Reader, destination: []u8) !void {
        var offset: usize = 0;
        while (offset < destination.len) {
            const available = self.end - self.start;
            if (available == 0) {
                self.start = 0;
                self.end = try self.read_fn(self.context, &self.buffer);
                if (self.end == 0) return error.EndOfStream;
                continue;
            }
            const amount = @min(available, destination.len - offset);
            @memcpy(destination[offset .. offset + amount], self.buffer[self.start .. self.start + amount]);
            self.start += amount;
            offset += amount;
        }
    }

    pub fn takeDelimiter(self: *Reader, delimiter: u8) !?[]const u8 {
        var line_len: usize = 0;
        while (line_len < self.buffer.len) {
            const byte = self.takeByte() catch |err| if (err == error.EndOfStream and line_len == 0) return null else return err;
            self.line_buffer[line_len] = byte;
            line_len += 1;
            if (byte == delimiter) return self.line_buffer[0..line_len];
        }
        return error.StreamTooLong;
    }
};
