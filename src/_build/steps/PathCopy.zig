//! Lazily adds file/directory copies to an existing `std.Build.Step.WriteFile`
//! step, based on file/directory paths or that may or may not be generated
//! during the build.

const std = @import("std");
const ArrayList = std.ArrayListUnmanaged;

const PathCopy = @This();

generated_directory: std.Build.GeneratedFile,
paths: ArrayList(Path) = .{},
step: std.Build.Step,
write_files: *std.Build.Step.WriteFile,

pub const Path = struct {
    source: std.Build.LazyPath,
    sub_path: []const u8,
};

pub fn create(
    owner: *std.Build,
    write_files: *std.Build.Step.WriteFile,
) *PathCopy {
    const path_copy = owner.allocator.create(PathCopy) catch @panic("OOM");
    path_copy.* = .{
        .generated_directory = .{ .step = &path_copy.step },
        .step = std.Build.Step.init(.{
            .id = .custom,
            .makeFn = make,
            .name = "PathCopy",
            .owner = owner,
        }),
        .write_files = write_files,
    };
    write_files.step.dependOn(&path_copy.step);

    return path_copy;
}

pub fn addPath(
    self: *PathCopy,
    source: std.Build.LazyPath,
    sub_path: []const u8,
) void {
    const b = self.step.owner;
    self.paths.append(b.allocator, .{
        .source = source,
        .sub_path = b.dupe(sub_path),
    }) catch @panic("OOM");

    source.addStepDependencies(&self.step);

    self.maybeUpdateName();
}

fn maybeUpdateName(self: *PathCopy) void {
    if (self.paths.items.len != 1) return;

    self.step.name = self.step.owner.fmt(
        "PathCopy {s}",
        .{self.paths.items[0].sub_path},
    );
}

fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
    _ = options;
    const b = step.owner;
    const self: *PathCopy = @fieldParentPtr("step", step);
    step.clearWatchInputs();

    var cwd = try std.fs.cwd().openDir(".", .{ .iterate = true });
    defer cwd.close();

    for (self.paths.items) |path| {
        try step.addWatchInput(path.source);

        const stat = try cwd.statFile(
            try path.source.getPath3(b, step).toString(b.allocator),
        );

        _ = switch (stat.kind) {
            .directory => self.write_files.addCopyDirectory(
                path.source,
                path.sub_path,
                .{},
            ),
            .file => self.write_files.addCopyFile(path.source, path.sub_path),
            else => {},
        };
    }
}
