const std = @import("std");

/// Utility mixins for bit flags represented by a packed struct of `bool`s.
pub fn BitFlagsImpl(comptime T: type) type {
    const type_info = switch (@typeInfo(T)) {
        .@"struct" => |struct_info| switch (struct_info.layout) {
            .@"packed" => struct_info,
            else => @compileError(
                "Expected packed struct, got " ++ @typeName(T),
            ),
        },
        else => @compileError(
            "Expected packed struct, got " ++ @typeName(T),
        ),
    };

    return struct {
        const Self = T;

        /// The backing integer for the specified packed struct type.
        pub const BackingInt = type_info.backing_integer orelse @compileError(
            "Backing integer required",
        );

        /// `true` iff `self` contains **all** the flags present in `other`.
        pub fn hasAll(self: Self, other: Self) bool {
            return self.intersection(other) == other;
        }

        /// `true` if `self` contains **any** of the flags present in `other`.
        pub fn hasAny(self: Self, other: Self) bool {
            return self.intersection(other) != Self{};
        }

        /// Creates a new flag set `T` containing only the common flags present
        /// in **both** `self` and `other`.
        pub fn intersection(self: Self, other: Self) Self {
            return @bitCast(self.val() & other.val());
        }

        /// Creates a new flag set `T` containing the combination of all flags
        /// present in either `self` **or** `other`.
        pub fn unionWith(self: Self, other: Self) Self {
            return @bitCast(self.val() | other.val());
        }

        /// Returns the integer representation of the bitflags.
        pub fn val(self: Self) BackingInt {
            return @bitCast(self);
        }

        pub fn format(
            self: Self,
            comptime fmt: []const u8,
            _: std.fmt.FormatOptions,
            writer: std.io.AnyWriter,
        ) !void {
            if (comptime fmt.len == 0 or std.mem.eql(u8, fmt, "s")) {
                try writer.writeAll("{");

                var count: BackingInt = 0;
                inline for (type_info.fields) |field| {
                    if (field.type == bool and @field(self, field.name)) {
                        if (count > 0) try writer.writeAll(" |");
                        try writer.writeAll(" ");
                        try writer.writeAll(field.name);
                        count += 1;
                    }
                }

                try writer.writeAll(" }");

                return;
            }

            if (comptime std.mem.eql(u8, fmt, "b")) {
                const width = std.fmt.comptimePrint("{d}", .{
                    @bitSizeOf(BackingInt),
                });

                try std.fmt.format(writer, "{b:0>" ++ width ++ "}", .{
                    @as(BackingInt, @bitCast(self)),
                });

                return;
            }

            try std.fmt.format(writer, "{" ++ fmt ++ "}", .{
                @as(BackingInt, @bitCast(self)),
            });
        }
    };
}

test BitFlagsImpl {
    const testing = std.testing;

    const Notes = packed struct(u8) {
        do: bool = false,
        re: bool = false,
        mi: bool = false,
        fa: bool = false,
        so: bool = false,
        la: bool = false,
        ti: bool = false,
        _: u1 = 0,

        const Impl = BitFlagsImpl(@This());
        pub const format = Impl.format;
        pub const hasAny = Impl.hasAny;
        pub const hasAll = Impl.hasAll;
        pub const intersection = Impl.intersection;
        pub const unionWith = Impl.unionWith;
        pub const val = Impl.val;
    };

    const empty = Notes{};
    try testing.expectEqual(0, empty.val());
    try testing.expectEqualStrings(
        "{ }",
        std.fmt.comptimePrint("{s}", .{empty}),
    );
    try testing.expectEqual(false, empty.hasAny(.{ .do = true }));
    try testing.expectEqual(false, empty.hasAll(.{ .do = true }));

    const chord_i = Notes{ .do = true, .mi = true, .so = true };
    try testing.expectEqual(0b00010101, chord_i.val());
    try testing.expectEqualStrings(
        "{ do | mi | so }",
        std.fmt.comptimePrint("{s}", .{chord_i}),
    );
    try testing.expectEqual(true, chord_i.hasAny(.{ .do = true, .re = true }));
    try testing.expectEqual(true, chord_i.hasAny(.{ .do = true, .mi = true }));
    try testing.expectEqual(false, chord_i.hasAny(.{ .re = true }));
    try testing.expectEqual(true, chord_i.hasAll(.{ .do = true, .mi = true }));
    try testing.expectEqual(false, chord_i.hasAll(.{ .do = true, .re = true }));

    const chord_iii: Notes = @bitCast(@as(u8, 0b01010100));
    try testing.expectEqual(
        Notes{ .mi = true, .so = true, .ti = true },
        chord_iii,
    );

    const chord_i_union_iii = chord_i.unionWith(chord_iii);
    try testing.expectEqual(
        Notes{ .do = true, .mi = true, .so = true, .ti = true },
        chord_i_union_iii,
    );

    const chord_i_intersect_iii = chord_i.intersection(chord_iii);
    try testing.expectEqual(
        Notes{ .mi = true, .so = true },
        chord_i_intersect_iii,
    );
}
