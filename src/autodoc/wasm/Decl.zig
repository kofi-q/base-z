const ArrayList = std.ArrayList;
const Decl = @This();
const std = @import("std");
const Ast = std.zig.Ast;
const Walk = @import("Walk.zig");
const gpa = std.heap.wasm_allocator;
const assert = std.debug.assert;
const log = std.log;
const Oom = error{OutOfMemory};

ast_node: Ast.Node.Index,
file: Walk.File.Index,
/// The decl whose namespace this is in.
parent: Index,

pub const ExtraInfo = struct {
    is_pub: bool,
    name: []const u8,
    first_doc_comment: Ast.OptionalTokenIndex,
};

pub const Index = enum(u32) {
    none = std.math.maxInt(u32),
    _,

    pub fn get(i: Index) *Decl {
        return &Walk.decls.items[@intFromEnum(i)];
    }
};

pub fn is_pub(d: *const Decl) bool {
    return d.extra_info().is_pub;
}

pub var getting_decl_name = false;

pub fn extra_info(d: *const Decl) ExtraInfo {
    const ast = d.file.get_ast();
    switch (ast.nodeTag(d.ast_node)) {
        .root => return .{
            .name = "",
            .is_pub = true,
            .first_doc_comment = if (ast.tokenTag(0) == .container_doc_comment)
                .fromToken(0)
            else
                .none,
        },

        .global_var_decl,
        .local_var_decl,
        .simple_var_decl,
        .aligned_var_decl,
        => {
            const var_decl = ast.fullVarDecl(d.ast_node).?;
            const name_token = var_decl.ast.mut_token + 1;
            assert(ast.tokenTag(name_token) == .identifier);
            const ident_name = ast.tokenSlice(name_token);
            return .{
                .name = ident_name,
                .is_pub = var_decl.visib_token != null,
                .first_doc_comment = findFirstDocComment(ast, var_decl.firstToken()),
            };
        },

        .fn_proto,
        .fn_proto_multi,
        .fn_proto_one,
        .fn_proto_simple,
        .fn_decl,
        => {
            var buf: [1]Ast.Node.Index = undefined;
            const fn_proto = ast.fullFnProto(&buf, d.ast_node).?;
            const name_token = fn_proto.name_token.?;
            assert(ast.tokenTag(name_token) == .identifier);
            const ident_name = ast.tokenSlice(name_token);
            return .{
                .name = ident_name,
                .is_pub = fn_proto.visib_token != null,
                .first_doc_comment = findFirstDocComment(ast, fn_proto.firstToken()),
            };
        },

        else => |t| {
            log.debug("hit '{s}'", .{@tagName(t)});
            unreachable;
        },
    }
}

pub fn value_node(d: *const Decl) ?Ast.Node.Index {
    const ast = d.file.get_ast();
    return switch (ast.nodeTag(d.ast_node)) {
        .fn_proto,
        .fn_proto_multi,
        .fn_proto_one,
        .fn_proto_simple,
        .fn_decl,
        .root,
        => d.ast_node,

        .global_var_decl,
        .local_var_decl,
        .simple_var_decl,
        .aligned_var_decl,
        => {
            const var_decl = ast.fullVarDecl(d.ast_node).?;
            if (ast.tokenTag(var_decl.ast.mut_token) == .keyword_const)
                return var_decl.ast.init_node.unwrap();

            return null;
        },

        else => null,
    };
}

pub fn categorize(decl: *const Decl) Walk.Category {
    return decl.file.categorize_decl(decl.ast_node);
}

pub fn myName(decl: *const Decl) []const u8 {
    if (decl.parent != .none) return decl.extra_info().name;

    for (Walk.modules.keys(), Walk.modules.values()) |pkg_name, pkg_file| {
        if (pkg_file == decl.file) return pkg_name;
    }

    return std.fs.path.stem(decl.file.path());
}

/// Looks up a direct child of `decl` by name.
pub fn get_child(decl: *const Decl, name: []const u8) ?Decl.Index {
    switch (decl.categorize()) {
        .alias => |target| {
            return target.get().get_child(name);
        },
        .namespace, .container => |node| {
            const file = decl.file.get();
            const scope = file.scopes.get(node) orelse return null;
            const child_node = scope.get_child(name) orelse return null;
            return file.node_decls.get(child_node);
        },
        .type, .type_function => {
            // Find a decl with this function as the parent, with a name matching `name`
            for (Walk.decls.items, 0..) |*candidate, i| {
                if (candidate.parent != .none and
                    candidate.parent.get() == decl and
                    std.mem.eql(u8, candidate.extra_info().name, name))
                {
                    return @enumFromInt(i);
                }
            }

            return null;
        },
        .type_fn_instance => |instance| {
            // const file = decl.file.get();
            // const decl_index = file
            //     .node_decls
            //     .get(instance.node_type_fn) orelse .none;
            const decl_index = instance.type_fn;
            const type_fn_decl = decl_index.get();

            // Find a decl with this function as the parent, with a name matching `name`
            for (Walk.decls.items, 0..) |*candidate, i| {
                if (candidate.parent != .none and
                    candidate.parent.get() == type_fn_decl and
                    std.mem.eql(u8, candidate.extra_info().name, name))
                {
                    return @enumFromInt(i);
                }
            }

            return null;
        },
        else => {
            return null;
        },
    }
}

/// If the type function returns another type function, return the index of that type function.
pub fn get_type_fn_return_type_fn(decl: *const Decl) ?Decl.Index {
    if (decl.get_type_fn_return_expr()) |return_expr| {
        const ast = decl.file.get_ast();
        var buffer: [1]Ast.Node.Index = undefined;
        const call = ast.fullCall(&buffer, return_expr) orelse return null;
        const token = ast.nodeMainToken(call.ast.fn_expr);
        const name = ast.tokenSlice(token);
        if (decl.lookup(name)) |function_decl| {
            return function_decl;
        }
    }
    return null;
}

/// Gets the expression after the `return` keyword in a type function declaration.
pub fn get_type_fn_return_expr(decl: *const Decl) ?Ast.Node.Index {
    switch (decl.categorize()) {
        .type_function => {
            const ast = decl.file.get_ast();

            const body_node = ast.nodeData(decl.ast_node).node_and_node[1];

            var buf: [2]Ast.Node.Index = undefined;
            const statements = ast.blockStatements(&buf, body_node) orelse return null;

            for (statements) |stmt| {
                if (ast.nodeTag(stmt) == .@"return") {
                    return ast.nodeData(stmt).node;
                }
            }
            return null;
        },
        else => return null,
    }
}

/// Looks up a decl by name accessible in `decl`'s namespace.
pub fn lookup(decl: *const Decl, name: []const u8) ?Decl.Index {
    const namespace_node = switch (decl.categorize()) {
        .namespace, .container => |node| node,
        else => decl.parent.get().ast_node,
    };
    const file = decl.file.get();
    const scope = file.scopes.get(namespace_node) orelse return null;
    const resolved_node = scope.lookup(&file.ast, name) orelse return null;
    return file.node_decls.get(resolved_node);
}

/// Appends the fully qualified name to `out`.
pub fn fqn(decl: *const Decl, out: *std.ArrayList(u8)) Oom!void {
    const name = decl.extra_info().name;

    if (std.mem.eql(u8, name, "std") or
        std.mem.eql(u8, name, "builtin"))
        return out.appendSlice(gpa, name);

    try decl.append_path(out);
    if (decl.parent != .none) {
        try append_parent_ns(out, decl.parent);
        try out.appendSlice(gpa, name);
    } else {
        out.items.len -= 1; // remove the trailing '.'
    }
}

/// Appends the fully qualified name to `out`.
pub fn fqn2(decl: *const Decl, parent_idx: Decl.Index, out: *std.ArrayList(u8)) Oom!void {
    const name = decl.extra_info().name;

    if (std.mem.eql(u8, name, "std") or
        std.mem.eql(u8, name, "builtin"))
        return out.appendSlice(gpa, name);

    if (parent_idx == .none) {
        try decl.append_path(out);
        out.items.len -= 1; // remove the trailing '.'
        return;
    }

    const parent = parent_idx.get();
    try fqn2(parent, parent.parent, out);
    try out.append(gpa, '.');
    try out.appendSlice(gpa, name);
}

/// Appends the fully qualified name to `out`.
pub fn fqnWrite(
    decl: *const Decl,
    out: std.ArrayList(u8).Writer,
) !void {
    const name = decl.extra_info().name;

    if (std.mem.eql(u8, name, "std") or
        std.mem.eql(u8, name, "builtin"))
        return out.writeAll(gpa, name);

    try decl.appendPath(out);
    if (decl.parent != .none) {
        try appendParentNs(out, decl.parent);
        try out.writeAll(gpa, name);
    } else {
        out.context.self.items.len -= 1; // remove the trailing '.'
    }
}

/// Appends the fully qualified name to `out`.
pub fn fqn2Write(
    decl: *const Decl,
    parent_idx: Decl.Index,
    out: *std.Io.Writer,
) !void {
    const name = decl.extra_info().name;

    if (std.mem.eql(u8, name, "std") or
        std.mem.eql(u8, name, "builtin"))
        return out.writeAll(name);

    if (parent_idx == .none) {
        try decl.appendPath(out);
        out.end -= 1; // remove the trailing '.'
        return;
    }

    const parent = parent_idx.get();
    try fqn2Write(parent, parent.parent, out);
    try out.writeByte('.');
    try out.writeAll(name);
}

pub fn reset_with_path(decl: *const Decl, list: *std.ArrayList(u8)) Oom!void {
    list.clearRetainingCapacity();
    try append_path(decl, list);
}

pub fn append_path(decl: *const Decl, list: *std.ArrayList(u8)) Oom!void {
    const start = list.items.len;
    // Prefer the module name alias.
    for (Walk.modules.keys(), Walk.modules.values()) |pkg_name, pkg_file| {
        if (pkg_file == decl.file) {
            try list.ensureUnusedCapacity(gpa, pkg_name.len + 1);
            list.appendSliceAssumeCapacity(pkg_name);
            list.appendAssumeCapacity('.');
            return;
        }
    }

    const file_path = decl.file.path();
    try list.ensureUnusedCapacity(gpa, file_path.len + 1);
    list.appendSliceAssumeCapacity(file_path);
    for (list.items[start..]) |*byte| switch (byte.*) {
        '/' => byte.* = '.',
        else => continue,
    };
    if (std.mem.endsWith(u8, list.items, ".zig")) {
        list.items.len -= 3;
    } else {
        list.appendAssumeCapacity('.');
    }
}

pub fn appendPath(
    decl: *const Decl,
    out: *std.Io.Writer,
) !void {
    const start = out.end;
    // Prefer the module name alias.
    for (Walk.modules.keys(), Walk.modules.values()) |pkg_name, pkg_file| {
        if (pkg_file == decl.file) {
            try out.writeAll(pkg_name);
            try out.writeByte('.');
            return;
        }
    }

    const file_path = decl.file.path();
    // try out.ensureUnusedCapacity(gpa, file_path.len + 1);
    try out.writeAll(file_path);

    for (out.buffer[start..]) |*byte| switch (byte.*) {
        '/' => byte.* = '.',
        else => continue,
    };
    if (std.mem.endsWith(u8, out.buffered(), ".zig")) {
        out.end -= 3;
    } else {
        try out.writeByte('.');
    }
}

pub fn append_parent_ns(list: *std.ArrayList(u8), parent: Decl.Index) Oom!void {
    assert(parent != .none);
    const decl = parent.get();
    if (decl.parent != .none) {
        try append_parent_ns(list, decl.parent);
        try list.appendSlice(gpa, decl.extra_info().name);
        try list.append(gpa, '.');
    }
}

pub fn appendParentNs(out: std.ArrayList(u8).Writer, parent: Decl.Index) !void {
    assert(parent != .none);
    const decl = parent.get();
    if (decl.parent != .none) {
        try append_parent_ns(out, decl.parent);
        try out.writeAll(decl.extra_info().name);
        try out.writeByte('.');
    }
}

pub fn findFirstDocComment(ast: *const Ast, token: Ast.TokenIndex) Ast.OptionalTokenIndex {
    var found_any = false;
    var it = token;
    while (it > 0) {
        it -= 1;
        const is_doc_comment = ast.tokenTag(it) == .doc_comment;
        found_any = found_any or is_doc_comment;

        if (!is_doc_comment) {
            if (!found_any) break;
            return .fromToken(it + 1);
        }
    }

    return .none;
}

/// Successively looks up each component.
pub fn find(search_string: []const u8) Decl.Index {
    var path_components = std.mem.splitScalar(u8, search_string, '.');
    const file = Walk.modules.get(path_components.first()) orelse return .none;
    var current_decl_index = file.findRootDecl();
    var actual_decl_index = current_decl_index;
    while (path_components.next()) |component| {
        while (true) switch (actual_decl_index.get().categorize()) {
            .alias => |target| actual_decl_index = target,
            else => break,
        };
        actual_decl_index = actual_decl_index.get().get_child(component) orelse return .none;
        current_decl_index = actual_decl_index;
    }
    return current_decl_index;
}
