const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

/// QueryParameters is an alias for a String HashMap
pub const QueryParameters = std.StringHashMap([]const u8);

pub const Url = struct {
    path: []const u8,
    raw_path: []const u8,
    raw_query: []const u8,
    allocator: *Allocator,

    /// Builds a new URL from a given path
    pub fn init(allocator: *Allocator, path: []const u8) !Url {
        var buffer = try allocator.alloc(u8, path.len);
        std.mem.copy(u8, buffer, path);

        const query = blk: {
            var raw_query: []const u8 = undefined;
            if (std.mem.indexOf(u8, buffer, "?")) |index| {
                raw_query = buffer[index + 1 ..];
            } else {
                raw_query = "";
            }
            break :blk raw_query;
        };

        return Url{
            .path = buffer,
            .raw_path = buffer,
            .raw_query = query,
            .allocator = allocator,
        };
    }

    /// Frees Url's memory
    pub fn deinit(self: @This()) void {
        const allocator = self.allocator;
        // raw_path contains full buffer right now, so free only this for now.
        allocator.free(self.raw_path);
    }

    /// Builds query parameters from url's `raw_query`
    /// Memory is owned by caller
    pub fn queryParameters(self: @This(), allocator: *Allocator) !QueryParameters {
        var queries = QueryParameters.init(allocator);

        var query = self.raw_query;
        while (query.len > 0) {
            var key = query;
            if (std.mem.indexOfAny(u8, key, "&")) |index| {
                query = key[index..];
                key = key[0..index];
            }
            if (key.len == 0) continue;
            var value: []u8 = undefined;
            if (std.mem.indexOfAny(u8, key, "=")) |index| {
                value = key[index..];
                key = key[0..index];
            }

            key = try unescape(allocator, key);
            value = try unescape(allocator, value);

            _ = try queries.put(key, value);
        }
    }
};

/// Unescapes the given string literal by decoding the %hex number into ascii
/// memory is owned & freed by caller
fn unescape(allocator: *Allocator, value: []const u8) ![]const u8 {
    var perc_counter: usize = 0;
    var has_plus: bool = false;

    // find % and + symbols to determine buffer size
    var i: usize = 0;
    while (i < value.len) : (i += 1) {
        switch (value[i]) {
            '%' => {
                perc_counter += 1;
                if (i + 2 > value.len or !isHex(value[i + 1]) or !isHex(s[i + 2])) {
                    return error.MalformedUrl;
                }
                i += 2;
            },
            '+' => {
                has_plus = true;
            },
        }
    }
    if (perc_counter == 0 and !has_plus) return value;

    // replace url encoded string
    var buffer = try allocator.alloc(u8, value.len - 2 * perc_counter);
    i = 0;
    while (i < buffer.len) : (i += 1) {
        switch (value[i]) {
            '%' => {
                buffer[i] = std.fmt.charToDigit(value[i + 1], 16) << 4 | std.fmt.charToDigit(value[i + 2], 16);
                i += 2;
            },
            '+' => buffer[i] = ' ',
            else => buffer[i] = value[i],
        }
    }
    return buffer;
}

/// Escapes a string by encoding symbols so it can be safely used inside an URL
fn escape(value: []const u8) []const u8 {}

/// Returns true if the given byte is heximal
fn isHex(c: u8) bool {
    return switch (c) {
        '0'...'9', 'a'...'f', 'A'...'F' => true,
        else => false,
    };
}

test "Basic raw query" {
    const path = "/example?name=value";
    const url: Url = try Url.init(testing.allocator, path);
    defer url.deinit();

    testing.expectEqualSlices(u8, "name=value", url.raw_query);
}
