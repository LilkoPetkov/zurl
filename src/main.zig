const clap = @import("clap");
const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;

/// Main entrypoint to the application
pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = gpa_state.allocator();
    defer _ = gpa_state.deinit();

    try httpRequestCommand(gpa);
}

/// HTTP request structure taking care of initialising the HTTP request,
/// managing its lifetime and clenaing up all resources afterwards.
///
/// TODO: Adding payload option
const httpRequest = struct {
    allocator: Allocator,
    uri: std.Uri,
    url: []const u8,
    method: std.http.Method = .GET,
    response_writer: std.Io.Writer.Allocating = undefined,
    client: std.http.Client = undefined,
    headers_only: bool,
    headers: ?[]const u8,

    /// Setup Io Writer for the response body
    fn setupWriter(self: *@This()) void {
        self.response_writer = std.Io.Writer.Allocating.init(self.allocator);
    }

    /// Setup HTTP client for the requests
    fn setupClient(self: *@This()) void {
        self.client = .{ .allocator = self.allocator };
    }

    /// Takes care of making the request to the specified URL, using the
    /// described method (GET, POST, PATCH, etc) and passed headers, if
    /// any.
    ///Includes decompression of the response
    ///
    /// TODO: Fix issue with redirect behaviour, where HTTP redirects to
    /// HTTPS, resulting in TooManyRedirects or TlsNotInitialised
    fn makeHttpRequest(self: *@This()) !void {
        self.setupClient();
        self.setupWriter();
        defer self.destroy();

        var headers_array: std.ArrayList(std.http.Header) = try .initCapacity(self.allocator, 8);
        try self.processHeaders(&headers_array);
        defer self.freeHeaders(&headers_array);

        const opts: std.http.Client.RequestOptions = .{
            .redirect_behavior = std.http.Client.Request.RedirectBehavior.init(0),
            .extra_headers = headers_array.items,
        };

        var req = try self.client.request(self.method, self.uri, opts);
        defer req.deinit();
        try req.sendBodiless();

        const redirect_buffer = try self.allocator.alloc(u8, 8 * 1024);
        defer self.allocator.free(redirect_buffer);

        var response = try req.receiveHead(redirect_buffer);

        switch (self.headers_only) {
            true => {
                const buf = try self.allocator.dupe(u8, response.head.bytes);
                defer self.allocator.free(buf);

                try self.writeToStdout(buf);
            },
            false => {
                const decompress_buffer: []u8 = switch (response.head.content_encoding) {
                    .identity => &.{},
                    .zstd => try self.allocator.alloc(u8, std.compress.zstd.default_window_len),
                    .deflate, .gzip => try self.allocator.alloc(u8, std.compress.flate.max_window_len),
                    .compress => return error.UnsupportedCompressionMethod,
                };
                defer self.allocator.free(decompress_buffer);

                var transfer_buffer: [64]u8 = undefined;
                var decompress: std.http.Decompress = undefined;

                const reader = response.readerDecompressing(&transfer_buffer, &decompress, decompress_buffer);

                _ = reader.streamRemaining(&self.response_writer.writer) catch |err| switch (err) {
                    error.ReadFailed => return if (response.bodyErr() != null) response.bodyErr().? else error.ReadFailed,
                    else => |e| return e,
                };
                const buf = self.response_writer.written();

                try self.writeToStdout(buf);
            },
        }
    }

    /// Write message from 'buf' to stdout. Message is freed and flushed after
    /// print, but buffer is not. The owner is responsible for freeing the memory
    /// if buf is allocated from heap
    fn writeToStdout(self: *@This(), buf: []u8) !void {
        const stdout_buf = try self.allocator.alloc(u8, buf.len);
        defer self.allocator.free(stdout_buf);

        var stdout_writer = std.fs.File.stdout().writer(stdout_buf);
        const stdout = &stdout_writer.interface;

        try stdout.print("{s}\n", .{buf});
        try stdout.flush();
    }

    /// Freeing headers after use along with the ArrayList that owns them
    fn freeHeaders(self: *@This(), headers: *std.ArrayList(std.http.Header)) void {
        for (headers.items) |header| {
            self.allocator.free(header.name);
            self.allocator.free(header.value);
        }
        headers.deinit(self.allocator);
    }

    /// Process user string input into array list of headers. If unequal
    /// number of headers is passed, the last one would be ignored.
    ///
    /// Note: headers are grouped sequentially -> "k1,v1,k2,v2" would
    /// result in 'k1: v1' / 'k2, v2'
    fn processHeaders(self: @This(), headers: *std.ArrayList(std.http.Header)) !void {
        if (self.headers) |hdr_str| {
            var it = std.mem.splitAny(u8, hdr_str, ",");

            while (true) {
                const key_slice = it.next() orelse break;
                const value_slice = it.next() orelse "";

                const key_copy = try self.allocator.dupe(u8, std.mem.trim(u8, key_slice, " "));
                const value_copy = try self.allocator.dupe(u8, std.mem.trim(u8, value_slice, " "));

                try headers.append(self.allocator, std.http.Header{
                    .name = key_copy,
                    .value = value_copy,
                });
            }
        }
    }

    /// Clean up the allocated Io Writer and HTTP client
    fn destroy(self: *@This()) void {
        self.response_writer.deinit();
        self.client.deinit();
    }
};

/// Command processing and parsing of args for the HTTP request
pub fn httpRequestCommand(allocator: Allocator) !void {
    const ps = comptime clap.parseParamsComptime(
        \\-h, --help            Display this help and exit.
        \\-u, --url             Target URL for the HTTP request <str>
        \\-m,  --method         HTTP method for the request <str>
        \\-I,  --headers_only   Returns response headers only <bool>
        \\-H,  --headers       Add custom headers (comma separated - key,value) <str>
        \\
    );
    const params = [_]clap.Param(u8){
        .{
            .id = 'h',
            .names = .{ .short = 'h', .long = "help" },
            .takes_value = .none,
        },
        .{
            .id = 'u',
            .names = .{ .short = 'u', .long = "url" },
            .takes_value = .one,
        },
        .{
            .id = 'm',
            .names = .{ .short = 'm', .long = "method" },
            .takes_value = .one,
        },
        .{
            .id = 'I',
            .names = .{ .short = 'I', .long = "headers_only" },
            .takes_value = .none,
        },
        .{
            .id = 'H',
            .names = .{ .short = 'H', .long = "headers" },
            .takes_value = .one,
        },
    };

    var url: ?[]const u8 = null;
    var method: std.http.Method = .GET;
    var headers_only: bool = false;
    var headers: ?[]const u8 = null;
    var uri: std.Uri = undefined;

    var iter = try std.process.ArgIterator.initWithAllocator(allocator);
    defer iter.deinit();

    _ = iter.next();

    var diag = clap.Diagnostic{};
    var parser = clap.streaming.Clap(u8, std.process.ArgIterator){
        .params = &params,
        .iter = &iter,
        .diagnostic = &diag,
    };

    while (parser.next() catch |err| {
        try diag.reportToFile(.stderr(), err);
        return err;
    }) |arg| {
        switch (arg.param.id) {
            'h' => return clap.helpToFile(.stderr(), clap.Help, &ps, .{}),
            'u' => {
                url = arg.value.?;
                uri = std.Uri.parse(url.?) catch |err| {
                    print("Error parsing: {?s} - {any}", .{ url, err });
                    return error.InvalidURL;
                };
            },
            'm' => {
                const buf = try allocator.alloc(u8, arg.value.?.len);
                defer allocator.free(buf);

                _ = std.ascii.upperString(buf, arg.value.?);
                method = std.meta.stringToEnum(std.http.Method, buf) orelse {
                    return error.InvalidMethod;
                };
            },
            'I' => headers_only = true,
            'H' => headers = arg.value.?,
            else => return error.InvalidArg,
        }
    }

    if (url == null) {
        return error.MissingUrl;
    }
    if (headers != null and std.mem.eql(u8, std.mem.trim(u8, headers.?, " "), "")) {
        return error.EmptyHeaders;
    }

    var request = httpRequest{ .allocator = allocator, .uri = uri, .method = method, .url = url.?, .headers_only = headers_only, .headers = headers };
    try request.makeHttpRequest();
}
