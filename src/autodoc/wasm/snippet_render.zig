const std = @import("std");
const Ast = std.zig.Ast;
const assert = std.debug.assert;

// const Walk = @import("Walk");
const Walk = @import("Walk.zig");
const Decl = Walk.Decl;

const gpa = std.heap.wasm_allocator;
const Oom = error{OutOfMemory};

/// Delete this to find out where URL escaping needs to be added.
pub const missing_feature_url_escape = true;

pub const RenderSourceOptions = struct {
    skip_doc_comments: bool = false,
    skip_comments: bool = false,
    collapse_whitespace: bool = false,
    alias: Decl.Index = .none,
    parent: Decl.Index = .none,
    fn_link: Decl.Index = .none,
    /// Assumed to be sorted ascending.
    source_location_annotations: []const Annotation = &.{},
    /// Concatenated with dom_id.
    annotation_prefix: []const u8 = "l",
};

pub const Annotation = struct {
    file_byte_offset: u32,
    /// Concatenated with annotation_prefix.
    dom_id: u32,
};

pub fn codeSnippetHtml(
    ast: std.zig.Ast,
    file_index: Walk.File.Index,
    out: std.ArrayListUnmanaged(u8).Writer,
    // root_node: Ast.Node.Index,
    options: RenderSourceOptions,
) !void {
    const root_node: Ast.Node.Index = @enumFromInt(0);
    const file = file_index.get();
    // const ast = file.ast;

    const g = struct {
        var field_access_buffer: std.ArrayListUnmanaged(u8) = .empty;
    };

    const start_token = ast.firstToken(root_node);
    const end_token = ast.lastToken(root_node) + 1;

    var cursor: usize = ast.tokenStart(start_token);

    var indent: usize = 0;
    if (std.mem.lastIndexOf(u8, ast.source[0..cursor], "\n")) |newline_index| {
        for (ast.source[newline_index + 1 .. cursor]) |c| {
            if (c != ' ') break;
            indent += 1;
        }
    }

    var next_annotate_index: usize = 0;

    for (
        ast.tokens.items(.tag)[start_token..end_token],
        ast.tokens.items(.start)[start_token..end_token],
        start_token..,
    ) |tag, start, token_index| {
        const between = ast.source[cursor..start];
        if (std.mem.trim(u8, between, " \t\r\n").len > 0) {
            if (!options.skip_comments) {
                try out.writeAll("<span class=\"tok-comment\">");
                try appendUnindented(out, between, indent);
                try out.writeAll("</span>");
            }
        } else if (between.len > 0) {
            if (options.collapse_whitespace) {
                const list = out.context.self;
                if (list.items.len > 0 and
                    list.items[list.items.len - 1] != ' ')
                {
                    try out.writeByte(' ');
                }
            } else {
                try appendUnindented(out, between, indent);
            }
        }
        if (tag == .eof) break;
        const slice = ast.tokenSlice(token_index);
        cursor = start + slice.len;

        // Insert annotations.
        while (true) {
            if (next_annotate_index >= options.source_location_annotations.len) break;
            const next_annotation = options.source_location_annotations[next_annotate_index];
            if (cursor <= next_annotation.file_byte_offset) break;
            try out.print("<span id=\"{s}{d}\"></span>", .{
                options.annotation_prefix, next_annotation.dom_id,
            });
            next_annotate_index += 1;
        }

        switch (tag) {
            .eof => unreachable,

            .keyword_addrspace,
            .keyword_align,
            .keyword_and,
            .keyword_asm,
            .keyword_break,
            .keyword_catch,
            .keyword_comptime,
            .keyword_const,
            .keyword_continue,
            .keyword_defer,
            .keyword_else,
            .keyword_enum,
            .keyword_errdefer,
            .keyword_error,
            .keyword_export,
            .keyword_extern,
            .keyword_for,
            .keyword_if,
            .keyword_inline,
            .keyword_noalias,
            .keyword_noinline,
            .keyword_nosuspend,
            .keyword_opaque,
            .keyword_or,
            .keyword_orelse,
            .keyword_packed,
            .keyword_anyframe,
            .keyword_pub,
            .keyword_resume,
            .keyword_return,
            .keyword_linksection,
            .keyword_callconv,
            .keyword_struct,
            .keyword_suspend,
            .keyword_switch,
            .keyword_test,
            .keyword_threadlocal,
            .keyword_try,
            .keyword_union,
            .keyword_unreachable,
            .keyword_var,
            .keyword_volatile,
            .keyword_allowzero,
            .keyword_while,
            .keyword_anytype,
            .keyword_fn,
            => {
                try out.writeAll("<span class=\"tok-kw\">");
                try appendEscaped(out, slice);
                try out.writeAll("</span>");
            },

            .string_literal,
            .char_literal,
            .multiline_string_literal_line,
            => {
                try out.writeAll("<span class=\"tok-str\">");
                try appendEscaped(out, slice);
                try out.writeAll("</span>");
            },

            .builtin => {
                try out.writeAll("<span class=\"tok-builtin\">");
                try appendEscaped(out, slice);
                try out.writeAll("</span>");
            },

            .doc_comment,
            .container_doc_comment,
            => {
                if (!options.skip_doc_comments) {
                    try out.writeAll("<span class=\"tok-comment\">");
                    try appendEscaped(out, slice);
                    try out.writeAll("</span>");
                }
            },

            .identifier => i: {
                if (options.fn_link != .none) {
                    const fn_link = options.fn_link.get();
                    const fn_token = ast.nodeMainToken(fn_link.ast_node);

                    if (token_index == fn_token + 1) {
                        try out.writeAll("<a class=\"tok-fn\" href=\"#");
                        _ = missing_feature_url_escape;
                        const link_target = if (options.alias != .none) options.alias.get() else fn_link;
                        try link_target.fqn2Write(options.parent, out);
                        try out.writeAll("\">");
                        try appendEscaped(out, slice);
                        try out.writeAll("</a>");
                        break :i;
                    }
                }

                if (token_index > 0 and ast.tokenTag(token_index - 1) == .keyword_fn) {
                    try out.writeAll("<span class=\"tok-fn\">");
                    try appendEscaped(out, slice);
                    try out.writeAll("</span>");
                    break :i;
                }

                if (Walk.isPrimitiveNonType(slice)) {
                    try out.writeAll("<span class=\"tok-null\">");
                    try appendEscaped(out, slice);
                    try out.writeAll("</span>");
                    break :i;
                }

                if (std.zig.primitives.isPrimitive(slice)) {
                    try out.writeAll("<span class=\"tok-type\">");
                    try appendEscaped(out, slice);
                    try out.writeAll("</span>");
                    break :i;
                }

                if (file.token_parents.get(token_index)) |field_access_node| {
                    g.field_access_buffer.clearRetainingCapacity();
                    try walkFieldAccesses(
                        file_index,
                        &g.field_access_buffer,
                        field_access_node,
                    );
                    if (g.field_access_buffer.items.len == 0) {
                        try appendEscaped(out, slice);
                        break :i;
                    }

                    if (std.mem.startsWith(
                        u8,
                        g.field_access_buffer.items,
                        "std.",
                    ) or std.mem.startsWith(
                        u8,
                        g.field_access_buffer.items,
                        "builtin.",
                    )) {
                        try out.writeAll(
                            \\<a target="std"
                        ++
                            \\ href="https://ziglang.org/documentation/master/std/#
                        );
                    } else {
                        try out.writeAll("<a href=\"#");
                    }

                    _ = missing_feature_url_escape;
                    try out.writeAll(g.field_access_buffer.items);
                    try out.writeAll("\">");
                    try appendEscaped(out, slice);
                    try out.writeAll("</a>");

                    break :i;
                }

                ident: {
                    g.field_access_buffer.clearRetainingCapacity();
                    try resolveIdentLink(file_index, &g.field_access_buffer, token_index);

                    if (g.field_access_buffer.items.len == 0) break :ident;

                    if (std.mem.eql(u8, g.field_access_buffer.items, "std") or
                        std.mem.eql(u8, g.field_access_buffer.items, "builtin"))
                    {
                        try out.writeAll(
                            \\<a target="std"
                        ++
                            \\ href="https://ziglang.org/documentation/master/std/#
                        );
                    } else {
                        try out.writeAll("<a href=\"#");
                    }

                    _ = missing_feature_url_escape;
                    try out.writeAll(g.field_access_buffer.items);
                    try out.writeAll("\">");
                    try appendEscaped(out, slice);
                    try out.writeAll("</a>");

                    break :i;
                }

                try appendEscaped(out, slice);
            },

            .number_literal => {
                try out.writeAll("<span class=\"tok-number\">");
                try appendEscaped(out, slice);
                try out.writeAll("</span>");
            },

            .bang,
            .pipe,
            .pipe_pipe,
            .pipe_equal,
            .equal,
            .equal_equal,
            .equal_angle_bracket_right,
            .bang_equal,
            .l_paren,
            .r_paren,
            .semicolon,
            .percent,
            .percent_equal,
            .l_brace,
            .r_brace,
            .l_bracket,
            .r_bracket,
            .period,
            .period_asterisk,
            .ellipsis2,
            .ellipsis3,
            .caret,
            .caret_equal,
            .plus,
            .plus_plus,
            .plus_equal,
            .plus_percent,
            .plus_percent_equal,
            .plus_pipe,
            .plus_pipe_equal,
            .minus,
            .minus_equal,
            .minus_percent,
            .minus_percent_equal,
            .minus_pipe,
            .minus_pipe_equal,
            .asterisk,
            .asterisk_equal,
            .asterisk_asterisk,
            .asterisk_percent,
            .asterisk_percent_equal,
            .asterisk_pipe,
            .asterisk_pipe_equal,
            .arrow,
            .colon,
            .slash,
            .slash_equal,
            .comma,
            .ampersand,
            .ampersand_equal,
            .question_mark,
            .angle_bracket_left,
            .angle_bracket_left_equal,
            .angle_bracket_angle_bracket_left,
            .angle_bracket_angle_bracket_left_equal,
            .angle_bracket_angle_bracket_left_pipe,
            .angle_bracket_angle_bracket_left_pipe_equal,
            .angle_bracket_right,
            .angle_bracket_right_equal,
            .angle_bracket_angle_bracket_right,
            .angle_bracket_angle_bracket_right_equal,
            .tilde,
            => try appendEscaped(out, slice),

            .invalid, .invalid_periodasterisks => return error.InvalidToken,
        }
    }
}

fn appendUnindented(
    out: std.ArrayListUnmanaged(u8).Writer,
    s: []const u8,
    indent: usize,
) !void {
    var it = std.mem.splitScalar(u8, s, '\n');
    var is_first_line = true;
    while (it.next()) |line| if (is_first_line) {
        try appendEscaped(out, line);
        is_first_line = false;
    } else {
        try out.writeAll("\n");
        try appendEscaped(out, unindent(line, indent));
    };
}

pub fn appendEscaped(out: std.ArrayListUnmanaged(u8).Writer, s: []const u8) !void {
    for (s) |c| try switch (c) {
        '&' => out.writeAll("&amp;"),
        '<' => out.writeAll("&lt;"),
        '>' => out.writeAll("&gt;"),
        '"' => out.writeAll("&quot;"),
        else => out.writeByte(c),
    };
}

fn walkFieldAccesses(
    file_index: Walk.File.Index,
    out: *std.ArrayListUnmanaged(u8),
    node: Ast.Node.Index,
) Oom!void {
    const ast = file_index.get_ast();
    assert(ast.nodeTag(node) == .field_access);
    const object_node, const field_ident = ast.nodeData(node).node_and_token;
    switch (ast.nodeTag(object_node)) {
        .identifier => {
            const lhs_ident = ast.nodeMainToken(object_node);
            try resolveIdentLink(file_index, out, lhs_ident);
        },
        .field_access => {
            try walkFieldAccesses(file_index, out, object_node);
        },
        else => {},
    }
    if (out.items.len > 0) {
        try out.append(gpa, '.');
        try out.appendSlice(gpa, ast.tokenSlice(field_ident));
    }
}

fn resolveIdentLink(
    file_index: Walk.File.Index,
    out: *std.ArrayListUnmanaged(u8),
    ident_token: Ast.TokenIndex,
) Oom!void {
    const decl_index = file_index.get().lookup_token(ident_token);
    if (decl_index == .none) return;
    try resolveDeclLink(decl_index, out);
}

fn unindent(s: []const u8, indent: usize) []const u8 {
    var indent_idx: usize = 0;
    for (s) |c| {
        if (c == ' ' and indent_idx < indent) {
            indent_idx += 1;
        } else {
            break;
        }
    }
    return s[indent_idx..];
}

pub fn resolveDeclLink(
    decl_index: Decl.Index,
    out: *std.ArrayListUnmanaged(u8),
) Oom!void {
    const decl = decl_index.get();
    switch (decl.categorize()) {
        .alias => |alias_decl| try alias_decl.get().fqn(out),
        else => try decl.fqn(out),
    }
}

pub fn tmpFile(bytes: []u8) !Walk.File.Index {
    var ast = blk: {
        var ast = try Ast.parse(gpa, bytes, .zig);
        if (ast.errors.len > 0) {
            defer ast.deinit(gpa);

            const token_offsets = ast.tokens.items(.start);
            var rendered_err: std.ArrayListUnmanaged(u8) = .{};
            defer rendered_err.deinit(gpa);
            for (ast.errors) |err| {
                const err_offset = token_offsets[err.token] + ast.errorOffset(err);
                const err_loc = std.zig.findLineColumn(ast.source, err_offset);
                rendered_err.clearRetainingCapacity();
                try ast.renderError(err, rendered_err.writer(gpa));
                std.log.err(
                    "{d}:{d}: {s}",
                    .{ err_loc.line + 1, err_loc.column + 1, rendered_err.items },
                );
            }
            return Ast.parse(gpa, "", .zig);
        }
        break :blk ast;
    };

    assert(ast.errors.len == 0);
    const file_index: Walk.File.Index = @enumFromInt(Walk.files.entries.len);
    // try files.put(gpa, file_name, .{ .ast = ast });

    var w: Walk = .{
        .file = file_index,
    };
    const scope = try gpa.create(Walk.Scope);
    scope.* = .{ .tag = .top };

    const decl_index = try file_index.add_decl(.root, .none);
    try w.struct_decl(scope, decl_index, .root, ast.containerDeclRoot());

    const file = file_index.get();
    shrinkToFit(&file.ident_decls);
    shrinkToFit(&file.token_parents);
    shrinkToFit(&file.node_decls);
    shrinkToFit(&file.doctests);
    shrinkToFit(&file.scopes);

    return file_index;
}

fn shrinkToFit(m: anytype) void {
    m.shrinkAndFree(gpa, m.entries.len);
}
