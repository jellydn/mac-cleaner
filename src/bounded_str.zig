//! Fixed-capacity string used by the Model for markup-safe storage.

const std = @import("std");

pub fn BoundedStr(comptime n: usize) type {
    return struct {
        buf: [n]u8 = .{0} ** n,
        len: usize = 0,

        const Self = @This();

        pub fn set(self: *Self, src: []const u8) void {
            const copy_len = @min(self.buf.len, src.len);
            if (copy_len > 0) @memcpy(self.buf[0..copy_len], src[0..copy_len]);
            self.len = copy_len;
        }

        pub fn slice(self: *const Self) []const u8 {
            return self.buf[0..self.len];
        }

        pub fn orDefault(self: *const Self, fallback: []const u8) []const u8 {
            if (self.len == 0) return fallback;
            return self.slice();
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.len == 0;
        }

        pub fn clear(self: *Self) void {
            self.len = 0;
        }
    };
}

test "BoundedStr set and slice" {
    var s: BoundedStr(8) = .{};
    s.set("hello");
    try std.testing.expectEqualStrings("hello", s.slice());
    s.set("toolongvalue");
    try std.testing.expectEqual(@as(usize, 8), s.len);
    try std.testing.expectEqualStrings("toolongv", s.slice());
    try std.testing.expectEqualStrings("toolongv", s.orDefault("fallback"));
    var empty: BoundedStr(8) = .{};
    try std.testing.expectEqualStrings("fallback", empty.orDefault("fallback"));
}
