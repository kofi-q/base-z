const std = @import("std");
const Writer = std.io.Writer;

/// A collection structure, with an array and a length, to/from which bounded,
/// variable-length slices can be written/read.
///
/// Useful to pass around small arrays whose exact size is only known at
/// runtime, but whose maximum size is known at comptime, without requiring
/// an `Allocator`. **Not** suitable for sensitive strings.
///
/// Adapted from `std.BoundedArray`, mostly with null-terminated strings
/// in mind.
pub fn BoundedArray(comptime T: type, comptime capacity: usize) type {
    const Len = std.math.IntFittingRange(0, capacity + 1);
    const buffer_size: Len = capacity + @sizeOf(T); // Make room for sentinel.

    return struct {
        const Self = @This();

        buf: [buffer_size]T,
        len: Len,

        pub fn initEmpty() Self {
            var arr = Self{
                .buf = undefined,
                .len = 0,
            };
            arr.clear();

            return arr;
        }

        /// Resize the length of the slice to 0.
        pub fn clear(self: *Self) void {
            self.len = 0;
            self.buf[0] = 0;
        }

        /// Const slice of the backing array set to the current length.
        pub fn constSlice(self: *const Self) []const T {
            return self.slice();
        }

        /// Null-terminated const slice of the backing array set to the current
        /// length.
        pub fn constSliceZ(self: *const Self) [:0]const T {
            return self.sliceZ();
        }

        pub fn copyFrom(self: *Self, source: []const T) !void {
            if (source.len > capacity) return error.Overflow;

            @memcpy(self.buf[0..source.len], source);
            self.len = @intCast(source.len);
            self.buf[source.len] = 0;
        }

        /// Adjust the length of the slice to match the given `source`, which
        /// must be a slice of this `BoundedArray`'s backing buffer.
        pub fn resizeToSlice(self: *Self, source: []const T) !void {
            std.debug.assert(&self.buf == source.ptr);

            if (source.len > capacity) return error.Overflow;

            self.len = @intCast(source.len);
            self.buf[self.len] = 0;
        }

        /// Represents a mutable or const slice of the backing array, depending
        /// on the given pointer type.
        pub fn Slice(comptime BufPtr: type) type {
            return switch (BufPtr) {
                *[buffer_size]T => []T,
                *const [buffer_size]T => []const T,
                else => unreachable,
            };
        }

        /// Slice of the backing array set to the current length.
        pub fn slice(self: anytype) Slice(@TypeOf(&self.buf)) {
            return self.buf[0..self.len];
        }

        /// Represents a mutable or const null-terminated slice of the backing
        /// array, depending on the given pointer type.
        fn SliceZ(comptime BufPtr: type) type {
            return switch (BufPtr) {
                *[buffer_size]T => [:0]T,
                *const [buffer_size]T => [:0]const T,
                else => unreachable,
            };
        }

        /// Null-terminated slice of the backing array set to the current
        /// length.
        pub fn sliceZ(self: anytype) SliceZ(@TypeOf(&self.buf)) {
            return self.buf[0..self.len :0];
        }

        pub fn format(self: @This(), writer: *Writer) Writer.Error!void {
            try Writer.print(writer, "{s}", .{self.constSlice()});
        }
    };
}

test BoundedArray {
    const testing = std.testing;
    const PathComponent = BoundedArray(u8, 255);
    var print_buf: [64]u8 = undefined;

    var basename = PathComponent.initEmpty();
    try testing.expectEqual(basename.slice().len, 0);
    try testing.expectEqualStrings("", basename.constSlice());
    try testing.expectEqualStrings("", basename.constSliceZ());

    try basename.copyFrom(@as([]const u8, "bounded_array.zig"));
    try testing.expectEqual("bounded_array.zig".len, basename.len);
    try testing.expectEqualStrings(
        "bounded_array.zig",
        basename.constSlice(),
    );
    try testing.expectEqualStrings(
        "bounded_array.zig",
        std.mem.span(basename.constSliceZ().ptr),
    );
    try testing.expectEqualStrings(
        "bounded_array.zig",
        try std.fmt.bufPrint(&print_buf, "{f}", .{basename}),
    );

    var basename_copy = basename;
    try testing.expectEqualStrings(
        "bounded_array.zig",
        basename_copy.constSlice(),
    );
    try testing.expectEqualStrings(
        "bounded_array.zig",
        basename_copy.constSliceZ(),
    );

    const basename_bare_ptr: [*]u8 = (&basename.buf).ptr;
    const way_too_long = basename_bare_ptr[0..256];
    try testing.expectError(
        error.Overflow,
        basename.resizeToSlice(way_too_long),
    );

    const fs = struct {
        fn getBasename(buf: []u8) ![]const u8 {
            return try std.fmt.bufPrint(buf, "foo.bar", .{});
        }
    };

    try basename.resizeToSlice(try fs.getBasename(&basename.buf));
    try testing.expectEqualStrings("foo.bar", basename.constSlice());
    try testing.expectEqualStrings("foo.bar", basename.constSliceZ());
    try testing.expectEqualStrings(
        "bounded_array.zig",
        basename_copy.constSlice(),
    );

    basename.clear();
    try testing.expectEqual(basename.slice().len, 0);
    try testing.expectEqualStrings("", basename.constSlice());
    try testing.expectEqualStrings("", basename.constSliceZ());
    try testing.expectEqualStrings(
        "bounded_array.zig",
        basename_copy.constSlice(),
    );
}
