const std = @import("std");
const http = @import("http.zig");
const testing = std.testing;
const eql = std.mem.eql;
const Allocator = std.mem.Allocator;

var r: http.httpRequest = setupResources() catch |err| {
    std.debug.print("Error: {any}\n", .{err});
};
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

fn setupResources() !http.httpRequest {
    const url = "https://test.com";
    const uri = try std.Uri.parse(url);

    return http.httpRequest{
        .allocator = allocator,
        .uri = uri,
        .url = url,
        .method = .GET,
        .headers_only = false,
        .headers = null,
        .payload = null,
    };
}

fn cleanTestingResources() void {
    r.destroy();
    gpa.deinit();
}

test "processHeaders with even number of key-value pairs" {
    r.headers = "h1,v1,h2,v2";
    var headers_array: std.ArrayList(std.http.Header) = try .initCapacity(allocator, 8);
    try r.processHeaders(&headers_array);
    defer r.freeHeaders(&headers_array);

    const first_header_set = headers_array.items[0];
    {
        try testing.expect(eql(u8, first_header_set.name, "h1"));
        try testing.expect(eql(u8, first_header_set.value, "v1"));
    }

    const second_header_set = headers_array.items[1];
    {
        try testing.expect(eql(u8, second_header_set.name, "h2"));
        try testing.expect(eql(u8, second_header_set.value, "v2"));
    }
}

test "processHeaders with empty input" {
    var headers_array: std.ArrayList(std.http.Header) = try .initCapacity(allocator, 8);
    defer r.freeHeaders(&headers_array);

    r.headers = "";
    try r.processHeaders(&headers_array);
    try testing.expect(headers_array.items.len == 0);
}

test "processHeaders with uneven number of key-value pairs" {
    var headers_array: std.ArrayList(std.http.Header) = try .initCapacity(allocator, 8);
    defer r.freeHeaders(&headers_array);

    r.headers = "h1,v1,h2";
    try r.processHeaders(&headers_array);
    try testing.expect(headers_array.items.len == 2);

    const second_header_set = headers_array.items[1];
    try testing.expect(eql(u8, second_header_set.name, "h2"));
    try testing.expect(eql(u8, second_header_set.value, ""));
}

test "processHeaders with leading/trailing whitespace" {
    var headers_array: std.ArrayList(std.http.Header) = try .initCapacity(allocator, 8);
    defer r.freeHeaders(&headers_array);

    r.headers = " h1 , v1 ";
    try r.processHeaders(&headers_array);
    try testing.expect(headers_array.items.len == 1);

    const first_header_set = headers_array.items[0];
    try testing.expect(eql(u8, first_header_set.name, "h1"));
    try testing.expect(eql(u8, first_header_set.value, "v1"));
}
