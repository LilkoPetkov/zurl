const std = @import("std");
const clap = @import("clap");
const print = std.debug.print;
const http = @import("http.zig");
const Allocator = std.mem.Allocator;

/// Command processing and parsing of args for the HTTP request
pub fn httpRequestCommand(allocator: Allocator) !void {
    const ps = comptime clap.parseParamsComptime(
        \\-h, --help            Display this help and exit.
        \\-u, --url             Target URL for the HTTP request <str>
        \\-m,  --method         HTTP method for the request <str>
        \\-I,  --headers_only   Returns response headers only <bool>
        \\-H,  --headers        Add custom headers (comma separated - key,value) <str>
        \\-d,  --payload        Body payload for the request <str>
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
        .{
            .id = 'd',
            .names = .{ .short = 'd', .long = "payload" },
            .takes_value = .one,
        },
    };

    var url: ?[]const u8 = null;
    var method: std.http.Method = .GET;
    var headers_only: bool = false;
    var headers: ?[]const u8 = null;
    var payload: ?[]const u8 = null;
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
            'd' => payload = arg.value.?,
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
    if (std.meta.eql(method, .GET) and payload != null) {
        return error.InvalidGetMethodWithPayload;
    }

    var request = http.httpRequest{
        .allocator = allocator,
        .uri = uri,
        .method = method,
        .url = url.?,
        .headers_only = headers_only,
        .headers = headers,
        .payload = payload,
    };
    try request.makeHttpRequest();
}
