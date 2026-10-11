// modified by Adam Ross (https://www.github.com/profile-icons/github-stats-modified), 26/05/26 - 03/09/26.
const builtin = @import("builtin");
const std = @import("std");
const version = @import("options").version;

const argparse = @import("argparse.zig");
const glob = @import("glob.zig");
const i18n = @import("i18n.zig");
const render = @import("render.zig");
const themes = @import("theme.zig");

const HttpClient = @import("http_client.zig");
const Statistics = @import("statistics.zig");

pub const std_options: std.Options = .{
    .logFn = logFn,
    // Even though we change it later, this is necessary to ensure that debug
    // logs aren't stripped in release builds.
    .log_level = .debug,
};

var log_level: std.log.Level = switch (builtin.mode) {
    .Debug => .debug,
    else => .warn,
};

fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    if (@intFromEnum(message_level) <= @intFromEnum(log_level)) {
        std.log.defaultLog(message_level, scope, format, args);
    }
}

const embedded_overview_template = @embedFile("templates/overview.svg");
const embedded_languages_template = @embedFile("templates/languages.svg");

const Args = struct {
    access_token: ?[]const u8 = null,
    json_input_file: ?[]const u8 = null,
    json_output_file: ?[]const u8 = null,
    silent: bool = false,
    debug: bool = false,
    verbose: bool = false,
    include_repos: ?[]const u8 = null,
    exclude_repos: ?[]const u8 = null,
    exclude_langs: ?[]const u8 = null,
    exclude_langs_type_data: bool = true,
    exclude_langs_type_prose: bool = true,
    exclude_langs_type_markup: bool = false,
    exclude_langs_type_programming: bool = false,
    exclude_private: bool = false,
    exclude_fork: bool = true,
    overview_output_file: ?[]const u8 = null,
    languages_output_file: ?[]const u8 = null,
    overview_template: ?[]const u8 = null,
    languages_template: ?[]const u8 = null,
    max_retries: ?usize = 25,
    is_local: bool = false,
    version: bool = false,
    dump_overview_template: ?[]const u8 = null,
    dump_languages_template: ?[]const u8 = null,
    theme: ?[]const u8 = "github",

    const Self = @This();

    pub fn init(main_init: std.process.Init) !Self {
        return try argparse.parse(main_init, Self, struct {
            fn errorCheck(a: Self, stderr: *std.Io.Writer) !bool {
                if ((a.access_token == null or a.access_token.?.len == 0) and
                    a.json_input_file == null and !a.version)
                {
                    try stderr.print(
                        "You must pass an input file or a GitHub token.\n",
                        .{},
                    );
                    return false;
                }
                if (themes.parse(a.theme orelse "github") == null) {
                    try stderr.print(
                        "Unknown theme '{s}'. Refer to theme.zig to see the list of supported themes.\n",
                        .{a.theme orelse ""},
                    );
                    return false;
                }
                return true;
            }
        }.errorCheck);
    }

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        inline for (@typeInfo(Self).@"struct".fields) |field| {
            switch (@typeInfo(field.type)) {
                .optional => |optional| {
                    switch (@typeInfo(optional.child)) {
                        .pointer => |pointer| switch (pointer.size) {
                            .slice => if (@field(self, field.name)) |p|
                                allocator.free(p),
                            else => comptime unreachable,
                        },
                        .bool, .int => {},
                        else => comptime unreachable,
                    }
                },
                .pointer => |p| switch (p.size) {
                    .slice => allocator.free(@field(self, field.name)),
                    else => comptime unreachable,
                },
                .bool, .int => {},
                else => comptime unreachable,
            }
        }
    }
};

fn isExcludeLangType(
    lang_type: Statistics.LangType,
    args: *const Args,
) bool {
    return switch (lang_type) {
        .data => args.exclude_langs_type_data,
        .prose => args.exclude_langs_type_prose,
        .markup => args.exclude_langs_type_markup,
        .programming => args.exclude_langs_type_programming,
        .unknown => true,
    };
}

fn isIncludeRepo(
    include_repos: []const []const u8,
    exclude_repos: []const []const u8,
    exclude_private: bool,
    exclude_fork: bool,
    name: []const u8,
    is_private: bool,
    is_fork: bool,
) bool {
    if (exclude_private and is_private) return false;
    if (exclude_fork and is_fork) return false;
    if (include_repos.len > 0) return glob.matchAny(include_repos, name);
    return !glob.matchAny(exclude_repos, name);
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    const args = try Args.init(init);
    defer args.deinit(allocator);
    if (args.silent) {
        log_level = .warn;
    } else if (args.debug) {
        log_level = .debug;
    } else if (args.verbose) {
        log_level = .info;
    }

    if (args.version) {
        const stdout = std.Io.File.stdout();
        var writer = stdout.writer(io, &.{});
        try writer.interface.print(
            \\GitHub Stats version {s}
            \\https://github.com/jstrieb/github-stats
            \\Created by Jacob Strieb
            \\
        , .{version});
        return;
    }

    if (args.dump_overview_template) |path| {
        try writeFile(io, path, embedded_overview_template);
        return;
    }

    if (args.dump_languages_template) |path| {
        try writeFile(io, path, embedded_languages_template);
        return;
    }

    const include_repos =
        if (args.include_repos) |include|
            try splitList(allocator, include, " ,\t\r\n|\"'\x00")
        else
            null;
    defer if (include_repos) |include| allocator.free(include);
    const exclude_repos =
        if (args.exclude_repos) |exclude|
            try splitList(allocator, exclude, " ,\t\r\n|\"'\x00")
        else
            null;
    defer if (exclude_repos) |exclude| allocator.free(exclude);
    const exclude_langs =
        if (args.exclude_langs) |exclude|
            try splitList(allocator, exclude, ",\t\r\n|\"'\x00")
        else
            null;
    defer if (exclude_langs) |exclude| allocator.free(exclude);

    var stats: Statistics = if (args.json_input_file) |path| stats: {
        const data = try readFile(allocator, io, path);
        defer allocator.free(data);
        break :stats try Statistics.initFromJson(allocator, data);
    } else if (args.access_token) |access_token| stats: {
        std.log.info(
            "Collecting statistics from GitHub {s}",
            .{if (args.is_local) "commit logs" else "API"},
        );
        var client: HttpClient = try .init(allocator, io, access_token);
        defer client.deinit();
        break :stats try Statistics.initWithOptionalParams(
            &client,
            allocator,
            io,
            .{
                .max_retries = args.max_retries,
                .use_api_line_stats = !args.is_local,
                .include_repos = include_repos orelse &.{},
                .exclude_repos = exclude_repos orelse &.{},
                .exclude_private = args.exclude_private,
                .exclude_fork = args.exclude_fork,
            },
        );
    } else unreachable;
    defer stats.deinit(allocator);

    if (args.json_output_file) |path| {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        try writeFile(
            io,
            path,
            try std.json.Stringify.valueAlloc(
                arena.allocator(),
                stats,
                .{ .whitespace = .indent_2 },
            ),
        );
    }

    const selected_theme = themes.parse(args.theme orelse "github") orelse unreachable;

    var i18n_arena = std.heap.ArenaAllocator.init(allocator);
    defer i18n_arena.deinit();

    const i18n_json = try i18n.parseEmbedded(i18n_arena.allocator());

    var aggregate_stats: struct {
        languages: std.array_hash_map.String(u64),
        language_colors: std.array_hash_map.String([]const u8),
        excluded_langs: std.array_hash_map.String(bool),
        is_local: bool,
        contributions: usize,
        name: []const u8,
        languages_total: u64 = 0,
        stars: usize = 0,
        forks: usize = 0,
        lines_changed: usize = 0,
        traffic: usize = 0,
        repos: usize = 0,
    } = .{
        .is_local = args.is_local,
        .contributions = stats.repo_contributions +
            stats.issue_contributions +
            stats.commit_contributions +
            stats.pr_contributions +
            stats.review_contributions,
        .languages = try .init(allocator, &.{}, &.{}),
        .language_colors = try .init(allocator, &.{}, &.{}),
        .excluded_langs = try .init(allocator, &.{}, &.{}),
        .name = stats.name,
    };
    defer aggregate_stats.languages.deinit(allocator);
    defer aggregate_stats.language_colors.deinit(allocator);
    defer aggregate_stats.excluded_langs.deinit(allocator);

    for (stats.repositories) |repository| {
        if (!isIncludeRepo(
            include_repos orelse &.{},
            exclude_repos orelse &.{},
            args.exclude_private,
            args.exclude_fork,
            repository.name,
            repository.is_private,
            repository.is_fork,
        )) {
            continue;
        }
        aggregate_stats.stars += repository.stars;
        aggregate_stats.forks += repository.forks;
        aggregate_stats.lines_changed += repository.lines_changed;
        aggregate_stats.traffic += repository.traffic;
        aggregate_stats.repos += 1;
        if (repository.languages) |langs| for (langs) |language| {
            const lang_lines_changed = @as(u64, language.lines_changed);
            if (lang_lines_changed == 0) {
                continue;
            }

            const is_exclude_lang_name =
                glob.matchAny(exclude_langs orelse &.{}, language.name);
            const is_exclude_lang_type =
                isExcludeLangType(language.lang_type, &args);
            if (is_exclude_lang_name or is_exclude_lang_type) {
                try aggregate_stats.excluded_langs.put(
                    allocator,
                    language.name,
                    true,
                );
                continue;
            }

            if (language.color) |color| {
                try aggregate_stats.language_colors.put(
                    allocator,
                    language.name,
                    color,
                );
            }
            var total = aggregate_stats.languages.get(language.name) orelse 0;

            total += lang_lines_changed;
            try aggregate_stats.languages.put(allocator, language.name, total);
            aggregate_stats.languages_total += lang_lines_changed;
        };
    }
    aggregate_stats.languages.sort(struct {
        values: @TypeOf(aggregate_stats.languages.values()),
        pub fn lessThan(self: @This(), a: usize, b: usize) bool {
            // Sort in reverse order
            return self.values[a] > self.values[b];
        }
    }{ .values = aggregate_stats.languages.values() });

    {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        try writeFile(
            io,
            args.overview_output_file orelse "overview.svg",
            try render.overview(
                &arena,
                aggregate_stats,
                if (args.overview_template) |template|
                    try readFile(arena.allocator(), io, template)
                else
                    embedded_overview_template,
                i18n_json,
                selected_theme,
            ),
        );

        try writeFile(
            io,
            args.languages_output_file orelse "languages.svg",
            try render.languages(
                &arena,
                aggregate_stats,
                if (args.languages_template) |template|
                    try readFile(arena.allocator(), io, template)
                else
                    embedded_languages_template,
                i18n_json,
                selected_theme,
            ),
        );
    }
}

test {
    std.testing.refAllDecls(@This());
}

fn readFile(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
) ![]const u8 {
    std.log.info("Reading data from '{s}'", .{path});
    const in =
        if (std.mem.eql(u8, path, "-"))
            std.Io.File.stdin()
        else
            try std.Io.Dir.cwd().openFile(io, path, .{});
    defer if (!std.mem.eql(u8, path, "-")) in.close(io);
    var read_buffer: [64 * 1024]u8 = undefined;
    var reader = in.reader(io, &read_buffer);
    return try (&reader.interface).allocRemaining(allocator, .unlimited);
}

fn writeFile(
    io: std.Io,
    path: []const u8,
    data: []const u8,
) !void {
    std.log.info("Writing data to '{s}'", .{path});
    const out =
        if (std.mem.eql(u8, path, "-"))
            std.Io.File.stdout()
        else
            try std.Io.Dir.cwd().createFile(io, path, .{});
    defer if (!std.mem.eql(u8, path, "-")) out.close(io);
    var write_buffer: [64 * 1024]u8 = undefined;
    var writer = out.writer(io, &write_buffer);
    try writer.interface.writeAll(data);
    try writer.interface.flush();
}

fn splitList(
    allocator: std.mem.Allocator,
    original: []const u8,
    separators: []const u8,
) ![][]const u8 {
    var list = try std.ArrayList([]const u8).initCapacity(allocator, 16);
    errdefer list.deinit(allocator);
    var iterator = std.mem.tokenizeAny(u8, original, separators);
    while (iterator.next()) |pattern| {
        try list.append(allocator, std.mem.trim(u8, pattern, " "));
    }
    return try list.toOwnedSlice(allocator);
}
