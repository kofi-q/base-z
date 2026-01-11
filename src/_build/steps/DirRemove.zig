//! The MIT License (Expat)
//!
//! Copyright (c) Zig contributors
//!
//! Permission is hereby granted, free of charge, to any person obtaining a copy
//! of this software and associated documentation files (the "Software"), to deal
//! in the Software without restriction, including without limitation the rights
//! to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//! copies of the Software, and to permit persons to whom the Software is
//! furnished to do so, subject to the following conditions:
//!
//! The above copyright notice and this permission notice shall be included in
//! all copies or substantial portions of the Software.
//!
//! THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//! IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//! FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//! AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//! LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//! OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//! THE SOFTWARE.
//!
//! Modified compatibility with Zig 0.16.0-dev Io API changes.

const std = @import("std");
const fs = std.fs;
const Step = std.Build.Step;
const LazyPath = std.Build.LazyPath;

pub const base_id: Step.Id = .remove_dir;

const DirRemove = @This();
step: Step,
doomed_path: LazyPath,

pub fn create(b: *std.Build, doomed_path: LazyPath) *DirRemove {
    const remove_dir = b.allocator.create(DirRemove) catch @panic("OOM");
    remove_dir.* = .{
        .step = Step.init(.{
            .id = base_id,
            .name = b.fmt("RemoveDir {s}", .{doomed_path.getDisplayName()}),
            .owner = b,
            .makeFn = make,
        }),
        .doomed_path = doomed_path.dupe(b),
    };
    return remove_dir;
}

fn make(step: *Step, options: Step.MakeOptions) !void {
    _ = options;

    const b = step.owner;
    const remove_dir: *DirRemove = @fieldParentPtr("step", step);

    step.clearWatchInputs();
    try step.addWatchInput(remove_dir.doomed_path);

    const io = b.graph.io;
    const full_doomed_path = remove_dir.doomed_path.getPath2(b, step);

    b.build_root.handle.deleteTree(io, full_doomed_path) catch |err| {
        if (b.build_root.path) |base| {
            return step.fail("unable to recursively delete path '{s}/{s}': {s}", .{
                base, full_doomed_path, @errorName(err),
            });
        } else {
            return step.fail("unable to recursively delete path '{s}': {s}", .{
                full_doomed_path, @errorName(err),
            });
        }
    };
}
