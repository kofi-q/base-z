const std = @import("std");

const _build = @import("src/_build.zig");

pub const addDocs = _build.addDocs;
pub const addFileRemove = _build.addFileRemove;
pub const addPathsCopy = _build.addPathsCopy;
pub const steps = _build.steps;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardOptimizeOption(.{});

    const step_check = b.step("check", "Generate documentation website");
    const step_docs = b.step("docs", "Generate documentation website");
    const step_test = b.step("test", "Run unit tests");

    var dep_base_internal = std.Build.Dependency{ .builder = b };

    const mod_base = b.addModule("base", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = mode,
    });

    const autodoc_main = _build.autodocMain(b);
    b.addNamedLazyPath("autodoc/main.wasm", autodoc_main.getEmittedBin());
    b.addNamedLazyPath("autodoc/main.js", b.path("src/autodoc/main.js"));
    b.addNamedLazyPath("autodoc/main.css", b.path("src/autodoc/main.css"));

    const docs_install = addDocs(
        b,
        b.addLibrary(.{
            .name = "base-z",
            .root_module = mod_base,
        }),
        .{
            .dep_base = &dep_base_internal,
            .html_logo = "base-z",
            .install_dir = .prefix,
            .install_subdir = "docs",
            .repo_url = "https://github.com/kofi-q/base-z",
        },
    );
    step_docs.dependOn(&docs_install.step);

    const lib_test = b.addTest(.{ .root_module = mod_base });
    step_check.dependOn(&lib_test.step);

    const run_test = b.addRunArtifact(lib_test);
    step_test.dependOn(&run_test.step);
}
