// created by Adam Ross (https://www.github.com/profile-icons/github-stats-modified), 01/09/26.
const std = @import("std");
const embedded_json = @embedFile("locales/i18n.json");

pub const Translation = struct {
    github_statistics_str: []const u8,
    stars_str: []const u8,
    forks_str: []const u8,
    all_time_contributions_str: []const u8,
    lines_of_code_changed_str: []const u8,
    repo_traffic_str: []const u8,
    repos_with_contributions_str: []const u8,
    programming_languages_str: []const u8,
    by_line_changes_str: []const u8,
    by_file_size_str: []const u8,
};

pub const Direction = enum {
    ltr,
    rtl,
};

pub fn parseEmbedded(allocator: std.mem.Allocator) !std.json.ObjectMap {
    return parse(allocator, embedded_json);
}

pub fn parse(
    allocator: std.mem.Allocator,
    data: []const u8,
) !std.json.ObjectMap {
    const parsed = try std.json.parseFromSliceLeaky(
        std.json.Value,
        allocator,
        data,
        .{},
    );

    return switch (parsed) {
        .object => |obj| obj,
        else => error.InvalidI18nFile,
    };
}

fn jsonString(obj: std.json.ObjectMap, key: []const u8) ![]const u8 {
    const value = obj.get(key) orelse return error.MissingI18nKey;
    return switch (value) {
        .string => |s| s,
        else => error.InvalidI18nValue,
    };
}

pub fn fromJson(obj: std.json.ObjectMap) !Translation {
    return .{
        .github_statistics_str = try jsonString(obj, "github_statistics_str"),
        .stars_str = try jsonString(obj, "stars_str"),
        .forks_str = try jsonString(obj, "forks_str"),
        .all_time_contributions_str = try jsonString(obj, "all_time_contributions_str"),
        .lines_of_code_changed_str = try jsonString(obj, "lines_of_code_changed_str"),
        .repo_traffic_str = try jsonString(obj, "repo_traffic_str"),
        .repos_with_contributions_str = try jsonString(obj, "repos_with_contributions_str"),
        .programming_languages_str = try jsonString(obj, "programming_languages_str"),
        .by_line_changes_str = try jsonString(obj, "by_line_changes_str"),
        .by_file_size_str = try jsonString(obj, "by_file_size_str"),
    };
}

pub fn fallback(translations: std.json.ObjectMap) !Translation {
    const fallback_value =
        translations.get("en") orelse
        return error.MissingEnglishI18nFallback;

    const fallback_obj = switch (fallback_value) {
        .object => |obj| obj,
        else => return error.InvalidI18nLocale,
    };

    return fromJson(fallback_obj);
}

pub fn direction(locale: ?[]const u8) Direction {
    const lang = locale orelse return .ltr;

    if (std.mem.startsWith(u8, lang, "ar") or
        std.mem.startsWith(u8, lang, "he") or
        std.mem.startsWith(u8, lang, "fa") or
        std.mem.startsWith(u8, lang, "ur") or
        std.mem.startsWith(u8, lang, "sd"))
    {
        return .rtl;
    }

    return .ltr;
}

pub fn isRtl(locale: ?[]const u8) bool {
    return direction(locale) == .rtl;
}

pub fn rtlClass(locale: ?[]const u8) []const u8 {
    return if (isRtl(locale)) " rtl" else "";
}
