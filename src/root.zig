pub const BitFlagsImpl = @import("bit_flags.zig").BitFlagsImpl;
pub const BoundedArray = @import("bounded_array.zig").BoundedArray;

pub const build = struct {
    const mod = @import("_build.zig");

    pub const addDirRemove = mod.addDirRemove;
    pub const addDocs = mod.addDocs;
    pub const addFileRemove = mod.addFileRemove;
    pub const addPathsCopy = mod.addPathsCopy;
    pub const steps = mod.steps;
};

test {
    const std = @import("std");
    std.testing.refAllDecls(@This());
}
