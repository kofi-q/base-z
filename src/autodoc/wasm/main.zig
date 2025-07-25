const ArrayList = std.ArrayListUnmanaged;
const std = @import("std");
const log = std.log;
const assert = std.debug.assert;
const Ast = std.zig.Ast;
const Walk = @import("Walk.zig");
const markdown = @import("markdown.zig");
const Decl = Walk.Decl;

const codeSnippetHtml = @import("snippet_render.zig").codeSnippetHtml;
const fileSourceHtml = @import("html_render.zig").fileSourceHtml;
const appendEscaped = @import("html_render.zig").appendEscaped;
const resolveDeclLink = @import("html_render.zig").resolveDeclLink;
const missing_feature_url_escape = @import("html_render.zig").missing_feature_url_escape;

const gpa = std.heap.wasm_allocator;

const js = struct {
    /// Keep in sync with the `LOG_` constants in `main.js`.
    const LogLevel = enum(u8) {
        err,
        warn,
        info,
        debug,
    };

    extern "js" fn log(level: LogLevel, ptr: [*]const u8, len: usize) void;
};

pub const std_options: std.Options = .{
    .logFn = logFn,
    .log_level = .err,
};

pub fn panic(msg: []const u8, st: ?*std.builtin.StackTrace, addr: ?usize) noreturn {
    _ = st;
    _ = addr;
    log.err("panic: {s}", .{msg});
    @trap();
}

fn logFn(
    comptime message_level: log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const prefix = if (scope == .default) "" else @tagName(scope) ++ ": ";
    var buf: [500]u8 = undefined;
    const line = std.fmt.bufPrint(&buf, prefix ++ format, args) catch l: {
        buf[buf.len - 3 ..][0..3].* = "...".*;
        break :l &buf;
    };
    js.log(@field(js.LogLevel, @tagName(message_level)), line.ptr, line.len);
}

export fn alloc(n: usize) [*]u8 {
    const slice = gpa.alloc(u8, n) catch @panic("OOM");
    return slice.ptr;
}

export fn unpack(tar_ptr: [*]u8, tar_len: usize) void {
    const tar_bytes = tar_ptr[0..tar_len];
    //log.debug("received {d} bytes of tar file", .{tar_bytes.len});

    unpackInner(tar_bytes) catch |err| {
        std.debug.panic("unable to unpack tar: {s}", .{@errorName(err)});
    };
}

var query_string: std.ArrayListUnmanaged(u8) = .empty;
var query_results: std.ArrayListUnmanaged(Decl.Index) = .empty;

/// Resizes the query string to be the correct length; returns the pointer to
/// the query string.
export fn query_begin(query_string_len: usize) [*]u8 {
    query_string.resize(gpa, query_string_len) catch @panic("OOM");
    return query_string.items.ptr;
}

/// Executes the query. Returns the pointer to the query results which is an
/// array of u32.
/// The first element is the length of the array.
/// Subsequent elements are Decl.Index values which are all public
/// declarations.
export fn query_exec(ignore_case: bool) [*]Decl.Index {
    const query = query_string.items;
    log.debug("querying '{s}'", .{query});
    query_exec_fallible(query, ignore_case) catch |err| switch (err) {
        error.OutOfMemory => @panic("OOM"),
    };
    query_results.items[0] = @enumFromInt(query_results.items.len - 1);
    return query_results.items.ptr;
}

const max_matched_items = 1000;

fn query_exec_fallible(query: []const u8, ignore_case: bool) !void {
    const Score = packed struct(u32) {
        points: u16,
        segments: u16,
    };
    const g = struct {
        var full_path_search_text: std.ArrayListUnmanaged(u8) = .empty;
        var full_path_search_text_lower: std.ArrayListUnmanaged(u8) = .empty;
        var doc_search_text: std.ArrayListUnmanaged(u8) = .empty;
        /// Each element matches a corresponding query_results element.
        var scores: std.ArrayListUnmanaged(Score) = .empty;
    };

    // First element stores the size of the list.
    try query_results.resize(gpa, 1);
    // Corresponding point value is meaningless and therefore undefined.
    try g.scores.resize(gpa, 1);

    decl_loop: for (Walk.decls.items, 0..) |*decl, decl_index| {
        const info = decl.extra_info();
        if (!info.is_pub) continue;

        try decl.reset_with_path(&g.full_path_search_text);
        if (decl.parent != .none)
            try Decl.append_parent_ns(&g.full_path_search_text, decl.parent);
        try g.full_path_search_text.appendSlice(gpa, info.name);

        try g.full_path_search_text_lower.resize(gpa, g.full_path_search_text.items.len);
        @memcpy(g.full_path_search_text_lower.items, g.full_path_search_text.items);

        const ast = decl.file.get_ast();
        if (info.first_doc_comment.unwrap()) |first_doc_comment| {
            try collect_docs(&g.doc_search_text, ast, first_doc_comment);
        }

        if (ignore_case) {
            ascii_lower(g.full_path_search_text_lower.items);
            ascii_lower(g.doc_search_text.items);
        }

        var it = std.mem.tokenizeScalar(u8, query, ' ');
        var points: u16 = 0;
        var bypass_limit = false;
        while (it.next()) |term| {
            // exact, case sensitive match of full decl path
            if (std.mem.eql(u8, g.full_path_search_text.items, term)) {
                points += 4;
                bypass_limit = true;
                continue;
            }
            // exact, case sensitive match of just decl name
            if (std.mem.eql(u8, info.name, term)) {
                points += 3;
                bypass_limit = true;
                continue;
            }
            // substring, case insensitive match of full decl path
            if (std.mem.indexOf(u8, g.full_path_search_text_lower.items, term) != null) {
                points += 2;
                continue;
            }
            if (std.mem.indexOf(u8, g.doc_search_text.items, term) != null) {
                points += 1;
                continue;
            }
            continue :decl_loop;
        }

        if (query_results.items.len < max_matched_items or bypass_limit) {
            try query_results.append(gpa, @enumFromInt(decl_index));
            try g.scores.append(gpa, .{
                .points = points,
                .segments = @intCast(count_scalar(g.full_path_search_text.items, '.')),
            });
        }
    }

    const sort_context: struct {
        pub fn swap(sc: @This(), a_index: usize, b_index: usize) void {
            _ = sc;
            std.mem.swap(Score, &g.scores.items[a_index], &g.scores.items[b_index]);
            std.mem.swap(Decl.Index, &query_results.items[a_index], &query_results.items[b_index]);
        }

        pub fn lessThan(sc: @This(), a_index: usize, b_index: usize) bool {
            _ = sc;
            const a_score = g.scores.items[a_index];
            const b_score = g.scores.items[b_index];
            if (b_score.points < a_score.points) {
                return true;
            } else if (b_score.points > a_score.points) {
                return false;
            } else if (a_score.segments < b_score.segments) {
                return true;
            } else if (a_score.segments > b_score.segments) {
                return false;
            } else {
                const a_decl = query_results.items[a_index];
                const b_decl = query_results.items[b_index];
                const a_file_path = a_decl.get().file.path();
                const b_file_path = b_decl.get().file.path();
                // This neglects to check the local namespace inside the file.
                return std.mem.lessThan(u8, b_file_path, a_file_path);
            }
        }
    } = .{};

    std.mem.sortUnstableContext(1, query_results.items.len, sort_context);

    if (query_results.items.len > max_matched_items)
        query_results.shrinkRetainingCapacity(max_matched_items);
}

const String = Slice(u8);

fn Slice(T: type) type {
    return packed struct(u64) {
        ptr: u32,
        len: u32,

        fn init(s: []const T) @This() {
            return .{
                .ptr = @intFromPtr(s.ptr),
                .len = s.len,
            };
        }
    };
}

const ErrorIdentifier = packed struct(u64) {
    token_index: Ast.TokenIndex,
    decl_index: Decl.Index,

    fn hasDocs(ei: ErrorIdentifier) bool {
        const decl_index = ei.decl_index;
        const ast = decl_index.get().file.get_ast();
        const token_index = ei.token_index;
        if (token_index == 0) return false;
        return ast.tokenTag(token_index - 1) == .doc_comment;
    }

    fn html(
        ei: ErrorIdentifier,
        base_decl: Decl.Index,
        out: *std.ArrayListUnmanaged(u8),
    ) !void {
        const decl_index = ei.decl_index;
        const ast = decl_index.get().file.get_ast();
        const name = ast.tokenSlice(ei.token_index);
        const has_link = base_decl != decl_index;

        try out.appendSlice(gpa, "<dt>");
        try out.appendSlice(gpa, name);
        if (has_link) {
            try out.appendSlice(gpa, " <a href=\"#");
            _ = missing_feature_url_escape;
            try decl_index.get().fqn(out);
            try out.appendSlice(gpa, "\">");
            try out.appendSlice(gpa, decl_index.get().extra_info().name);
            try out.appendSlice(gpa, "</a>");
        }
        try out.appendSlice(gpa, "</dt>");

        if (Decl.findFirstDocComment(ast, ei.token_index).unwrap()) |first_doc_comment| {
            try out.appendSlice(gpa, "<dd>");
            try render_docs(out, decl_index, first_doc_comment, false);
            try out.appendSlice(gpa, "</dd>");
        }
    }
};

var string_result: std.ArrayListUnmanaged(u8) = .empty;
var error_set_result: std.StringArrayHashMapUnmanaged(ErrorIdentifier) = .empty;

export fn decl_error_set(decl_index: Decl.Index) Slice(ErrorIdentifier) {
    return Slice(ErrorIdentifier)
        .init(decl_error_set_fallible(decl_index) catch @panic("OOM"));
}

export fn error_set_node_list(base_decl: Decl.Index, node: Ast.Node.Index) Slice(ErrorIdentifier) {
    error_set_result.clearRetainingCapacity();
    addErrorsFromExpr(base_decl, &error_set_result, node) catch @panic("OOM");
    sort_error_set_result();
    return Slice(ErrorIdentifier).init(error_set_result.values());
}

export fn fn_error_set_decl(decl_index: Decl.Index, node: Ast.Node.Index) Decl.Index {
    return switch (decl_index.get().file.categorize_expr(node)) {
        .alias => |target| fn_error_set_decl(target, target.get().ast_node),
        else => decl_index,
    };
}

fn decl_error_set_fallible(decl_index: Decl.Index) Oom![]ErrorIdentifier {
    error_set_result.clearRetainingCapacity();
    try addErrorsFromDecl(decl_index, &error_set_result);
    sort_error_set_result();
    return error_set_result.values();
}

fn sort_error_set_result() void {
    const sort_context: struct {
        pub fn lessThan(sc: @This(), a_index: usize, b_index: usize) bool {
            _ = sc;
            const a_name = error_set_result.keys()[a_index];
            const b_name = error_set_result.keys()[b_index];
            return std.mem.lessThan(u8, a_name, b_name);
        }
    } = .{};
    error_set_result.sortUnstable(sort_context);
}

fn addErrorsFromDecl(
    decl_index: Decl.Index,
    out: *std.StringArrayHashMapUnmanaged(ErrorIdentifier),
) Oom!void {
    switch (decl_index.get().categorize()) {
        .error_set => |node| try addErrorsFromExpr(decl_index, out, node),
        .alias => |target| try addErrorsFromDecl(target, out),
        else => |cat| log.debug("unable to addErrorsFromDecl: {any}", .{cat}),
    }
}

fn addErrorsFromExpr(
    decl_index: Decl.Index,
    out: *std.StringArrayHashMapUnmanaged(ErrorIdentifier),
    node: Ast.Node.Index,
) Oom!void {
    const decl = decl_index.get();
    const ast = decl.file.get_ast();

    switch (decl.file.categorize_expr(node)) {
        .error_set => |n| switch (ast.nodeTag(n)) {
            .error_set_decl => {
                try addErrorsFromNode(decl_index, out, node);
            },
            .merge_error_sets => {
                const lhs, const rhs = ast.nodeData(n).node_and_node;
                try addErrorsFromExpr(decl_index, out, lhs);
                try addErrorsFromExpr(decl_index, out, rhs);
            },
            else => unreachable,
        },
        .alias => |target| try addErrorsFromDecl(target, out),
        else => return,
    }
}

fn addErrorsFromNode(
    decl_index: Decl.Index,
    out: *std.StringArrayHashMapUnmanaged(ErrorIdentifier),
    node: Ast.Node.Index,
) Oom!void {
    const decl = decl_index.get();
    const ast = decl.file.get_ast();
    const error_token = ast.nodeMainToken(node);
    var tok_i = error_token + 2;
    while (true) : (tok_i += 1) switch (ast.tokenTag(tok_i)) {
        .doc_comment, .comma => {},
        .identifier => {
            const name = ast.tokenSlice(tok_i);
            const gop = try out.getOrPut(gpa, name);
            // If there are more than one, take the one with doc comments.
            // If they both have doc comments, prefer the existing one.
            const new: ErrorIdentifier = .{
                .token_index = tok_i,
                .decl_index = decl_index,
            };
            if (!gop.found_existing or
                (!gop.value_ptr.hasDocs() and new.hasDocs()))
            {
                gop.value_ptr.* = new;
            }
        },
        .r_brace => break,
        else => unreachable,
    };
}

export fn type_fn_fields(decl_index: Decl.Index) Slice(Ast.Node.Index) {
    return decl_fields(decl_index);
}

export fn decl_fields(decl_index: Decl.Index) Slice(Ast.Node.Index) {
    return Slice(Ast.Node.Index).init(
        decl_fields_fallible(decl_index) catch @panic("OOM"),
    );
}

export fn decl_params(decl_index: Decl.Index) Slice(Ast.Node.Index) {
    return Slice(Ast.Node.Index).init(
        decl_params_fallible(decl_index) catch @panic("OOM"),
    );
}

fn decl_fields_fallible(decl_index: Decl.Index) ![]Ast.Node.Index {
    const decl = decl_index.get();
    const ast = decl.file.get_ast();

    switch (decl.categorize()) {
        .alias => |target| return decl_fields_fallible(target),

        .type_fn_instance => |instance| {
            return decl_fields_fallible(instance.type_fn);
        },

        .type_function => {
            // If the type function returns a reference to another type
            // function, get the fields from there
            if (decl.get_type_fn_return_type_fn()) |function_decl| {
                return decl_fields_fallible(function_decl);
            }
            // If the type function returns a container, such as a `struct`,
            // read that container's fields
            if (decl.get_type_fn_return_expr()) |return_expr| {
                switch (ast.nodeTag(return_expr)) {
                    .container_decl,
                    .container_decl_trailing,
                    .container_decl_two,
                    .container_decl_two_trailing,
                    .container_decl_arg,
                    .container_decl_arg_trailing,
                    => {
                        return ast_decl_fields_fallible(ast, return_expr);
                    },
                    else => {},
                }
            }
            return &.{};
        },

        else => {
            const value_node = decl.value_node() orelse return &.{};
            return ast_decl_fields_fallible(ast, value_node);
        },
    }
}

fn ast_decl_fields_fallible(ast: *Ast, ast_index: Ast.Node.Index) ![]Ast.Node.Index {
    const g = struct {
        var result: std.ArrayListUnmanaged(Ast.Node.Index) = .empty;
    };
    g.result.clearRetainingCapacity();
    var buf: [2]Ast.Node.Index = undefined;
    const container_decl = ast.fullContainerDecl(&buf, ast_index) orelse return &.{};
    for (container_decl.ast.members) |member_node| switch (ast.nodeTag(member_node)) {
        .container_field_init,
        .container_field_align,
        .container_field,
        => try g.result.append(gpa, member_node),

        else => continue,
    };
    return g.result.items;
}

fn decl_params_fallible(decl_index: Decl.Index) ![]Ast.Node.Index {
    const g = struct {
        var result: std.ArrayListUnmanaged(Ast.Node.Index) = .empty;
    };
    g.result.clearRetainingCapacity();
    const decl = decl_index.get();
    const ast = decl.file.get_ast();
    const value_node = decl.value_node() orelse return &.{};
    var buf: [1]Ast.Node.Index = undefined;
    const fn_proto = ast.fullFnProto(&buf, value_node) orelse return &.{};
    try g.result.appendSlice(gpa, fn_proto.ast.params);
    return g.result.items;
}

export fn error_html(base_decl: Decl.Index, error_identifier: ErrorIdentifier) String {
    string_result.clearRetainingCapacity();
    error_identifier.html(base_decl, &string_result) catch @panic("OOM");
    return String.init(string_result.items);
}

export fn decl_field_html(
    decl_index: Decl.Index,
    field_node: Ast.Node.Index,
) String {
    string_result.clearRetainingCapacity();

    const decl = decl_index.get();
    switch (decl.categorize()) {
        .alias => |target| return decl_field_html(target, field_node),

        else => decl_field_html_fallible(
            &string_result,
            decl_index,
            field_node,
        ) catch @panic("OOM"),
    }

    return String.init(string_result.items);
}

export fn decl_param_html(decl_index: Decl.Index, param_node: Ast.Node.Index) String {
    string_result.clearRetainingCapacity();
    decl_param_html_fallible(&string_result, decl_index, param_node) catch @panic("OOM");
    return String.init(string_result.items);
}

fn decl_field_html_fallible(
    out: *std.ArrayListUnmanaged(u8),
    decl_index: Decl.Index,
    field_node: Ast.Node.Index,
) !void {
    const decl = decl_index.get();
    const ast = decl.file.get_ast();
    try out.appendSlice(gpa, "<pre><code>");
    try fileSourceHtml(decl.file, out, field_node, .{});
    try out.appendSlice(gpa, "</code></pre>");

    const field = ast.fullContainerField(field_node).?;

    if (Decl.findFirstDocComment(ast, field.firstToken()).unwrap()) |first_doc_comment| {
        try out.appendSlice(gpa, "<div class=\"fieldDocs\">");
        try render_docs(out, decl_index, first_doc_comment, false);
        try out.appendSlice(gpa, "</div>");
    }
}

fn decl_param_html_fallible(
    out: *std.ArrayListUnmanaged(u8),
    decl_index: Decl.Index,
    param_node: Ast.Node.Index,
) !void {
    const decl = decl_index.get();
    const ast = decl.file.get_ast();
    const colon = ast.firstToken(param_node) - 1;
    const name_token = colon - 1;
    const first_doc_comment = f: {
        var it = ast.firstToken(param_node);
        while (it > 0) {
            it -= 1;
            switch (ast.tokenTag(it)) {
                .doc_comment, .colon, .identifier, .keyword_comptime, .keyword_noalias => {},
                else => break,
            }
        }
        break :f it + 1;
    };
    const name = ast.tokenSlice(name_token);

    try out.appendSlice(gpa, "<pre><code>");
    try appendEscaped(out, name);
    try out.appendSlice(gpa, ": ");
    try fileSourceHtml(decl.file, out, param_node, .{});
    try out.appendSlice(gpa, "</code></pre>");

    if (ast.tokenTag(first_doc_comment) == .doc_comment) {
        try out.appendSlice(gpa, "<div class=\"fieldDocs\">");
        try render_docs(out, decl_index, first_doc_comment, false);
        try out.appendSlice(gpa, "</div>");
    }
}

export fn decl_fn_proto_html(
    decl_index: Decl.Index,
    alias: Decl.Index,
    parent: Decl.Index,
    linkify_fn_name: bool,
) String {
    const decl = decl_index.get();
    const ast = decl.file.get_ast();

    switch (decl.categorize()) {
        .alias => |target| return decl_fn_proto_html(
            target,
            if (alias == .none) decl_index else alias,
            parent,
            linkify_fn_name,
        ),
        else => {},
    }

    const proto_node = switch (ast.nodeTag(decl.ast_node)) {
        .fn_decl => ast.nodeData(decl.ast_node).node_and_node[0],

        .fn_proto,
        .fn_proto_one,
        .fn_proto_simple,
        .fn_proto_multi,
        => decl.ast_node,

        else => unreachable,
    };

    string_result.clearRetainingCapacity();
    fileSourceHtml(decl.file, &string_result, proto_node, .{
        .alias = alias,
        .collapse_whitespace = .empty_lines,
        .fn_link = if (linkify_fn_name) decl_index else .none,
        .parent = parent,
        .skip_comments = true,
        .skip_doc_comments = true,
    }) catch |err| {
        std.debug.panic("unable to render source: {s}", .{@errorName(err)});
    };
    return String.init(string_result.items);
}

export fn decl_source_html(decl_index: Decl.Index) String {
    const decl = decl_index.get();

    string_result.clearRetainingCapacity();
    fileSourceHtml(decl.file, &string_result, decl.ast_node, .{}) catch |err| {
        std.debug.panic("unable to render source: {s}", .{@errorName(err)});
    };
    return String.init(string_result.items);
}

export fn decl_doctest_html(decl_index: Decl.Index) String {
    const decl = decl_index.get();
    const doctest_ast_node = decl.file.get().doctests.get(decl.ast_node) orelse
        return String.init("");

    string_result.clearRetainingCapacity();
    fileSourceHtml(decl.file, &string_result, doctest_ast_node, .{}) catch |err| {
        std.debug.panic("unable to render source: {s}", .{@errorName(err)});
    };
    return String.init(string_result.items);
}

export fn decl_fqn(decl_index: Decl.Index) String {
    const decl = decl_index.get();
    string_result.clearRetainingCapacity();
    decl.fqn(&string_result) catch @panic("OOM");
    return String.init(string_result.items);
}

export fn decl_parent(decl_index: Decl.Index) Decl.Index {
    const decl = decl_index.get();
    return decl.parent;
}

export fn fn_error_set(decl_index: Decl.Index) Ast.Node.OptionalIndex {
    const decl = decl_index.get();
    const ast = decl.file.get_ast();
    var buf: [1]Ast.Node.Index = undefined;
    const full = ast.fullFnProto(&buf, decl.ast_node).?;
    const return_type = full.ast.return_type.unwrap().?;
    return switch (ast.nodeTag(return_type)) {
        .error_set_decl => return_type.toOptional(),
        .error_union => ast.nodeData(return_type).node_and_node[0].toOptional(),
        else => .none,
    };
}

export fn decl_file_path(decl_index: Decl.Index) String {
    const decl = decl_index.get();
    switch (decl.categorize()) {
        .namespace,
        .container,
        .global_variable,
        .function,
        .type_function,
        .type_fn_instance,
        .type,
        .type_type,
        .error_set,
        .global_const,
        .primitive,
        => {
            string_result.clearRetainingCapacity();
            string_result.appendSlice(gpa, decl_index.get().file.path()) catch @panic("OOM");
            return String.init(string_result.items);
        },

        .alias => |target| return decl_file_path(target),
    }
}

export fn decl_category_name(decl_index: Decl.Index) String {
    const decl = decl_index.get();
    const ast = decl.file.get_ast();
    const name = switch (decl.categorize()) {
        .namespace, .container => |node| {
            if (ast.nodeTag(decl.ast_node) == .root)
                return String.init("struct");
            string_result.clearRetainingCapacity();
            var buf: [2]Ast.Node.Index = undefined;
            const container_decl = ast.fullContainerDecl(&buf, node).?;
            if (container_decl.layout_token) |t| {
                if (ast.tokenTag(t) == .keyword_extern) {
                    string_result.appendSlice(gpa, "extern ") catch @panic("OOM");
                }
            }
            const main_token_tag = ast.tokenTag(container_decl.ast.main_token);
            string_result.appendSlice(gpa, main_token_tag.lexeme().?) catch @panic("OOM");
            return String.init(string_result.items);
        },
        .global_variable => "Global Variable",
        .function => "Function",
        .type_function => "Type Function",
        .type_fn_instance => "Type",
        .type, .type_type => "Type",
        .error_set => "Error Set",
        .global_const => "Constant",
        .primitive => "Primitive Value",
        .alias => |target| return decl_category_name(target),
    };
    return String.init(name);
}

export fn decl_name(decl_index: Decl.Index) String {
    Decl.getting_decl_name = true;
    defer Decl.getting_decl_name = false;
    const decl = decl_index.get();
    string_result.clearRetainingCapacity();

    const name = n: {
        if (decl.parent != .none) break :n decl.extra_info().name;

        for (Walk.modules.keys(), Walk.modules.values()) |pkg_name, pkg_file| {
            if (pkg_file == decl.file) break :n pkg_name;
        }

        break :n std.fs.path.stem(decl.file.path());
    };

    string_result.appendSlice(gpa, name) catch @panic("OOM");
    return String.init(string_result.items);
}

export fn decl_docs_html(decl_index: Decl.Index, short: bool) String {
    const decl = decl_index.get();
    string_result.clearRetainingCapacity();

    switch (decl.categorize()) {
        .alias => |target| blk: {
            if (decl.extra_info().first_doc_comment.unwrap()) |comment| {
                render_docs(
                    &string_result,
                    decl_index,
                    comment,
                    short,
                ) catch @panic("OOM");

                break :blk;
            }

            return decl_docs_html(target, short);
        },

        else => if (decl.extra_info().first_doc_comment.unwrap()) |comment| {
            render_docs(
                &string_result,
                decl_index,
                comment,
                short,
            ) catch @panic("OOM");
        },
    }

    return String.init(string_result.items);
}

fn collect_docs(
    list: *std.ArrayListUnmanaged(u8),
    ast: *const Ast,
    first_doc_comment: Ast.TokenIndex,
) Oom!void {
    list.clearRetainingCapacity();
    var it = first_doc_comment;
    while (true) : (it += 1) switch (ast.tokenTag(it)) {
        .doc_comment, .container_doc_comment => {
            // It is tempting to trim this string but think carefully about how
            // that will affect the markdown parser.
            const line = ast.tokenSlice(it)[3..];
            try list.appendSlice(gpa, line);
        },
        else => break,
    };
}

fn render_docs(
    out: *std.ArrayListUnmanaged(u8),
    decl_index: Decl.Index,
    first_doc_comment: Ast.TokenIndex,
    short: bool,
) !void {
    const decl = decl_index.get();
    const ast = decl.file.get_ast();

    var parser = try markdown.Parser.init(gpa);
    defer parser.deinit();
    var it = first_doc_comment;
    while (true) : (it += 1) switch (ast.tokenTag(it)) {
        .doc_comment, .container_doc_comment => {
            const line = ast.tokenSlice(it)[3..];
            if (short and line.len == 0) break;
            try parser.feedLine(line);
        },
        else => break,
    };

    var parsed_doc = try parser.endInput();
    defer parsed_doc.deinit(gpa);

    const renderer: MarkdownRenderer = .{
        .context = decl_index,
        .renderFn = renderMarkdownNode,
    };
    try renderer.render(parsed_doc, out.writer(gpa));
}

const MarkdownWriter = std.ArrayListUnmanaged(u8).Writer;
const MarkdownRenderer = markdown.Renderer(MarkdownWriter, Decl.Index);

fn renderMarkdownNode(
    r: MarkdownRenderer,
    doc: markdown.Document,
    node: markdown.Document.Node.Index,
    writer: MarkdownWriter,
) !void {
    const g = struct {
        var link_buffer: std.ArrayListUnmanaged(u8) = .empty;
    };

    const data = doc.nodes.items(.data)[@intFromEnum(node)];
    switch (doc.nodes.items(.tag)[@intFromEnum(node)]) {
        .code_block => {
            const tag = doc.string(data.code_block.tag);
            if (tag.len > 0 and !std.mem.eql(u8, tag, "zig")) {
                return writer.print(
                    \\<pre><code class="highlight language-{s}">{f}</code></pre>
                    \\
                , .{
                    if (tag.len > 0) tag else "none",
                    markdown.fmtHtml(doc.string(data.code_block.content)),
                });
            }

            const snippet_ast = try std.zig.Ast.parse(
                gpa,
                doc.string(data.code_block.content),
                .zig,
            );

            if (snippet_ast.errors.len > 0) {
                return MarkdownRenderer.renderDefault(r, doc, node, writer);
            }

            // var virtual_file_name = std.ArrayListUnmanaged(u8).empty;
            // try r.context.get().fqn(&virtual_file_name);
            // try virtual_file_name.writer(gpa).print("/snippet", .{});
            // log.info("adding virtual file: {s}", .{virtual_file_name.items});
            // const file_index = Walk.add_file(
            //     virtual_file_name.items,
            //     doc.string(data.code_block.content),
            //     // snippet_ast,
            // ) catch {
            //     return MarkdownRenderer.renderDefault(r, doc, node, writer);
            // };

            try writer.writeAll("<pre><code>");

            try codeSnippetHtml(
                snippet_ast,
                @enumFromInt(0),
                // file_index,
                writer,
                .{},
            );
            // try fileSourceHtml(
            //     file_index,
            //     writer.context.self,
            //     @enumFromInt(0),
            //     .{},
            // );

            try writer.writeAll("</code></pre>\n");
        },
        .code_span => {
            const content = doc.string(data.text.content);
            const search_path = blk: {
                if (std.mem.endsWith(u8, content, "()")) {
                    break :blk content[0 .. content.len - "()".len];
                }

                break :blk content;
            };
            const match =
                resolve_decl_path(r.context, search_path) orelse
                resolve_decl_path(
                    find_module_root(@enumFromInt(0)),
                    search_path,
                ) orelse {
                    if (std.mem.startsWith(u8, search_path, "std.") or
                        std.mem.startsWith(u8, search_path, "builtin."))
                    {
                        try writer.writeAll("<code>");
                        try writer.writeAll(
                            \\<a target="std" class="external"
                        ++
                            \\ href="https://ziglang.org/documentation/master/std/#
                        );
                        _ = missing_feature_url_escape;
                        try writer.writeAll(search_path);
                        try writer.print("\">{f}</a>", .{
                            markdown.fmtHtml(content),
                        });
                        try writer.writeAll("</code>");

                        return;
                    }

                    try writer.writeAll("<code>");
                    try writer.print("{f}", .{
                        markdown.fmtHtml(content),
                    });
                    try writer.writeAll("</code>");
                    return;
                };

            g.link_buffer.clearRetainingCapacity();
            try resolveDeclLink(match, &g.link_buffer);

            try writer.writeAll("<code>");
            try writer.writeAll("<a href=\"#");
            _ = missing_feature_url_escape;
            try writer.writeAll(g.link_buffer.items);
            try writer.print("\">{f}</a>", .{
                markdown.fmtHtml(content),
            });
            try writer.writeAll("</code>");
        },

        else => try MarkdownRenderer.renderDefault(r, doc, node, writer),
    }
}

fn resolve_decl_path(decl_index: Decl.Index, path: []const u8) ?Decl.Index {
    var path_components = std.mem.splitScalar(u8, path, '.');
    var decl_current = decl_index.get().lookup(path_components.first()) orelse return null;
    while (path_components.next()) |component| {
        switch (decl_current.get().categorize()) {
            .alias => |aliasee| decl_current = aliasee,
            else => {},
        }
        decl_current = decl_current.get().get_child(component) orelse return null;
    }
    return decl_current;
}

export fn decl_type_html(decl_index: Decl.Index) String {
    const decl = decl_index.get();
    const ast = decl.file.get_ast();
    string_result.clearRetainingCapacity();
    t: {
        // If there is an explicit type, use it.
        if (ast.fullVarDecl(decl.ast_node)) |var_decl| {
            if (var_decl.ast.type_node.unwrap()) |type_node| {
                string_result.appendSlice(gpa, "<code>") catch @panic("OOM");
                fileSourceHtml(decl.file, &string_result, type_node, .{
                    .skip_comments = true,
                    .collapse_whitespace = .all,
                }) catch |e| {
                    std.debug.panic("unable to render html: {s}", .{@errorName(e)});
                };
                string_result.appendSlice(gpa, "</code>") catch @panic("OOM");
                break :t;
            }
        }
    }
    return String.init(string_result.items);
}

const Oom = error{OutOfMemory};

fn unpackInner(tar_bytes: []u8) !void {
    var fbs = std.io.fixedBufferStream(tar_bytes);
    var file_name_buffer: [1024]u8 = undefined;
    var link_name_buffer: [1024]u8 = undefined;
    var it = std.tar.iterator(fbs.reader(), .{
        .file_name_buffer = &file_name_buffer,
        .link_name_buffer = &link_name_buffer,
    });
    while (try it.next()) |tar_file| {
        switch (tar_file.kind) {
            .file => {
                if (tar_file.size == 0 and tar_file.name.len == 0) continue;
                if (std.mem.startsWith(u8, tar_file.name, "std/")) continue;
                if (std.mem.startsWith(u8, tar_file.name, "builtin/")) continue;

                if (std.mem.containsAtLeast(u8, tar_file.name, 1, "/test/") or
                    std.mem.containsAtLeast(u8, tar_file.name, 1, "/tests/") or
                    std.mem.containsAtLeast(u8, tar_file.name, 1, "/testing/"))
                    continue;

                if (std.mem.endsWith(u8, tar_file.name, "test_cases.zig"))
                    continue;

                if (std.mem.endsWith(u8, tar_file.name, "test.zig")) {
                    const idx_sep = tar_file.name.len - "test.zig".len - 1;
                    switch (tar_file.name[idx_sep]) {
                        '.', '/', '_' => continue,
                        else => {},
                    }
                }

                if (!std.mem.endsWith(u8, tar_file.name, ".zig")) {
                    log.warn("skipping non-zig src: '{s}'", .{tar_file.name});
                    continue;
                }

                log.debug("found file: '{s}'", .{tar_file.name});
                const file_name = try gpa.dupe(u8, tar_file.name);
                if (std.mem.indexOfScalar(u8, file_name, '/')) |pkg_name_end| {
                    const pkg_name = file_name[0..pkg_name_end];
                    const gop = try Walk.modules.getOrPut(gpa, pkg_name);
                    const file: Walk.File.Index = @enumFromInt(Walk.files.entries.len);

                    if (!gop.found_existing or
                        std.mem.eql(u8, file_name[pkg_name_end..], "/root.zig") or
                        std.mem.eql(u8, file_name[pkg_name_end + 1 .. file_name.len - ".zig".len], pkg_name))
                    {
                        gop.value_ptr.* = file;
                    }

                    const file_bytes = tar_bytes[fbs.pos..][0..@intCast(tar_file.size)];
                    assert(file == try Walk.add_file(file_name, file_bytes));
                }
            },
            else => continue,
        }
    }
}

fn ascii_lower(bytes: []u8) void {
    for (bytes) |*b| b.* = std.ascii.toLower(b.*);
}

export fn module_name(index: u32) String {
    const names = Walk.modules.keys();
    return String.init(if (index >= names.len) "" else names[index]);
}

export fn find_module_root(pkg: Walk.ModuleIndex) Decl.Index {
    const root_file = Walk.modules.values()[@intFromEnum(pkg)];
    const result = root_file.findRootDecl();
    assert(result != .none);
    return result;
}

/// Set by `set_input_string`.
var input_string: std.ArrayListUnmanaged(u8) = .empty;

export fn set_input_string(len: usize) [*]u8 {
    input_string.resize(gpa, len) catch @panic("OOM");
    return input_string.items.ptr;
}

/// Looks up the root struct decl corresponding to a file by path.
/// Uses `input_string`.
export fn find_file_root() Decl.Index {
    const file: Walk.File.Index = @enumFromInt(
        Walk.files.getIndex(input_string.items) orelse return .none,
    );
    return file.findRootDecl();
}

/// Uses `input_string`.
/// Tries to look up the Decl component-wise but then falls back to a file path
/// based scan.
export fn find_decl() Decl.Index {
    const result = Decl.find(input_string.items);
    if (result != .none) return result;

    const g = struct {
        var match_fqn: std.ArrayListUnmanaged(u8) = .empty;
    };
    for (Walk.decls.items, 0..) |*decl, decl_index| {
        g.match_fqn.clearRetainingCapacity();
        decl.fqn(&g.match_fqn) catch @panic("OOM");
        if (std.mem.eql(u8, g.match_fqn.items, input_string.items)) {
            return @enumFromInt(decl_index);
        }
    }
    return .none;
}

/// Set only by `categorize_decl`; read only by `get_aliasee`, valid only
/// when `categorize_decl` returns `.alias`.
var global_aliasee: Decl.Index = .none;

export fn get_aliasee() Decl.Index {
    return global_aliasee;
}

export fn categorize_decl(decl_index: Decl.Index, resolve_alias_count: usize) Walk.Category.Tag {
    Walk.looking_for_gold = true;
    defer Walk.looking_for_gold = false;

    global_aliasee = .none;
    var chase_alias_n = resolve_alias_count;
    var decl = decl_index.get();

    while (true) {
        const result = decl.categorize();
        switch (result) {
            .alias => |new_index| {
                assert(new_index != .none);
                global_aliasee = new_index;
                if (chase_alias_n > 0) {
                    chase_alias_n -= 1;
                    decl = new_index.get();
                    continue;
                }
            },
            else => {},
        }
        return result;
    }
}

export fn type_fn_members(parent: Decl.Index, include_private: bool) Slice(Decl.Index) {
    const decl = parent.get();

    // If the type function returns another type function, get the members of that function
    if (decl.get_type_fn_return_type_fn()) |function_decl| {
        return type_fn_members(function_decl, include_private);
    }

    return namespace_members(parent, include_private);
}

export fn namespace_members(
    parent_idx: Decl.Index,
    include_private: bool,
) Slice(Decl.Index) {
    const g = struct {
        var members: std.ArrayListUnmanaged(Decl.Index) = .empty;
    };

    g.members.clearRetainingCapacity();

    namespaceMembersInner(parent_idx, include_private, &g.members);

    return Slice(Decl.Index).init(g.members.items);
}

fn namespaceMembersInner(
    parent_idx: Decl.Index,
    include_private: bool,
    out_members: *std.ArrayListUnmanaged(Decl.Index),
) void {
    const parent = parent_idx.get();
    switch (parent.categorize()) {
        .alias => |target| {
            namespaceMembersInner(
                target,
                include_private,
                out_members,
            );
        },

        .type_fn_instance => |instance| {
            namespaceMembersInner(
                instance.type_fn,
                include_private,
                out_members,
            );
        },

        else => for (Walk.decls.items, 0..) |*decl, i| {
            if (decl.parent != parent_idx) continue;

            const member_decl_idx: Decl.Index = @enumFromInt(i);
            if (include_private or decl.is_pub()) {
                out_members.append(gpa, member_decl_idx) catch {
                    @panic("OOM");
                };
            }
        },
    }
}

fn count_scalar(haystack: []const u8, needle: u8) usize {
    var total: usize = 0;
    for (haystack) |elem| total += @intFromBool(elem == needle);

    return total;
}
