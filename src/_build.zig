const std = @import("std");

pub const steps = @import("_build/steps.zig");

pub const DocsOpts = struct {
    dep_base: ?*std.Build.Dependency = null,
    html_head_extra: []const u8 = "",
    html_logo: []const u8,
    install_dir: std.Build.InstallDir,
    install_subdir: []const u8,
    repo_url: ?[]const u8 = null,
};

pub fn addDocs(
    b: *std.Build,
    lib: *std.Build.Step.Compile,
    opts: DocsOpts,
) *std.Build.Step.InstallDir {
    const dep_base = opts.dep_base orelse b.dependency("base", .{
        .target = lib.root_module.resolved_target.?,
        .optimize = lib.root_module.optimize.?,
    });

    const original = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = opts.install_dir,
        .install_subdir = opts.install_subdir,
    });

    const html_repo_link = if (opts.repo_url) |repo_url| b.fmt(
        @embedFile("autodoc/fragments/repo_link.html"),
        .{ .repo_url = repo_url },
    ) else "";

    const index_html = b.fmt(@embedFile("autodoc/index.html"), .{
        .head_extra = opts.html_head_extra,
        .logo = opts.html_logo,
        .repo_link = html_repo_link,
    });

    const main_js = dep_base.namedLazyPath("autodoc/main.js");
    const main_css = dep_base.namedLazyPath("autodoc/main.css");
    const main_wasm = dep_base.namedLazyPath("autodoc/main.wasm");

    const patch = b.addWriteFiles();
    _ = patch.add("index.html", index_html);
    _ = patch.addCopyFile(main_js, "main.js");
    _ = patch.addCopyFile(main_css, "main.css");
    _ = patch.addCopyFile(main_wasm, "main.wasm");

    patch.step.dependOn(&original.step);
    patch.step.addWatchInput(main_js) catch @panic("OOM");
    patch.step.addWatchInput(main_css) catch @panic("OOM");
    patch.step.addWatchInput(main_wasm) catch @panic("OOM");

    const patch_install = b.addInstallDirectory(.{
        .source_dir = patch.getDirectory(),
        .install_dir = opts.install_dir,
        .install_subdir = opts.install_subdir,
    });
    patch_install.step.dependOn(&patch.step);

    return patch_install;
}

pub fn autodocMain(b: *std.Build) *std.Build.Step.Compile {
    const mod = b.createModule(.{
        .link_libc = false,
        .optimize = .ReleaseSmall,
        .root_source_file = b.path("src/autodoc/wasm/main.zig"),
        .strip = true,
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
            .cpu_features_add = std.Target.wasm.featureSet(&.{
                .atomics,
                .reference_types,
            }),
        }),
    });

    const exe = b.addExecutable(.{
        .name = "autodoc.main",
        .root_module = mod,
    });
    exe.entry = .disabled;
    exe.rdynamic = true;

    return exe;
}

pub fn addDirRemove(b: *std.Build, path: std.Build.LazyPath) *steps.DirRemove {
    return steps.DirRemove.create(b, path);
}

pub fn addFileRemove(
    b: *std.Build,
    path: std.Build.LazyPath,
) *steps.FileRemove {
    return steps.FileRemove.create(b, path);
}

pub fn addPathsCopy(
    b: *std.Build,
    write_files: *std.Build.Step.WriteFile,
) *steps.PathCopy {
    return steps.PathCopy.create(b, write_files);
}
