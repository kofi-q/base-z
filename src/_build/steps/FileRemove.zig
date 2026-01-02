//! Build step for deleting a single file.
//!
//! Adapted from `std.Build.Step.RemoveDir`:
//! The MIT License (Expat) - Copyright (c) Zig contributors

const std = @import("std");

const FileRemove = @This();

path: std.Build.LazyPath,
step: std.Build.Step,

pub fn create(owner: *std.Build, path: std.Build.LazyPath) *FileRemove {
    const remove_file = owner.allocator.create(FileRemove) catch @panic("OOM");
    remove_file.* = .{
        .step = .init(.{
            .id = std.Build.Step.Id.custom,
            .name = owner.fmt("FileRemove {s}", .{path.getDisplayName()}),
            .owner = owner,
            .makeFn = make,
        }),
        .path = path.dupe(owner),
    };
    return remove_file;
}

fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
    _ = options;

    const b = step.owner;
    const remove_file: *FileRemove = @fieldParentPtr("step", step);

    step.clearWatchInputs();
    try step.addWatchInput(remove_file.path);

    const full_path = b.fmt("{f}", .{remove_file.path.getPath3(b, step)});

    var io_threaded = std.Io.Threaded.init(b.allocator, .{});
    defer io_threaded.deinit();
    const io = io_threaded.ioBasic();

    b.build_root.handle.deleteFile(io, full_path) catch |err| switch (err) {
        error.FileNotFound => return,
        else => {
            if (b.build_root.path) |base| return step.fail(
                "unable to delete file '{s}/{s}': {t}",
                .{ base, full_path, err },
            );

            return step.fail("unable to delete file '{s}': {t}", .{
                full_path, err,
            });
        },
    };
}
