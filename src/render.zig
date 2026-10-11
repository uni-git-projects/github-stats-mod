// created by Adam Ross (https://www.github.com/profile-icons/github-stats-modified), 01/09/26 - 03/09/26.
const std = @import("std");
const i18n = @import("i18n.zig");
const templateFill = @import("template.zig").fill;
const themes = @import("theme.zig");

fn codeCount(text: []const u8) usize {
    return std.unicode.utf8CountCodepoints(text) catch text.len;
}

fn fitFontSize(
    text_len: usize,
    base_size: usize,
    min_size: usize,
    max_len_at_base: usize,
) usize {
    if (text_len <= max_len_at_base) {
        return base_size;
    }

    return @max(
        min_size,
        (base_size * max_len_at_base) / text_len,
    );
}

fn localizedLanguagesBlock(
    allocator: std.mem.Allocator,
    system_language: ?[]const u8,
    stats: anytype,
    translation: i18n.Translation,
    progress: []const u8,
    lang_list: []const u8,
) ![]const u8 {
    const rtl_class = i18n.rtlClass(system_language);
    const system_language_attr =
        if (system_language) |lang|
            try std.fmt.allocPrint(
                allocator,
                " systemLanguage=\"{s}\"",
                .{lang},
            )
        else
            "";
    const languages_by_str =
        if (stats.is_local)
            translation.by_line_changes_str
        else
            translation.by_file_size_str;
    const language_title_font_size = fitFontSize(codeCount(translation.programming_languages_str) + codeCount(languages_by_str) + 10, 16, 12, 48);

    return try std.fmt.allocPrint(allocator,
        \\<foreignObject{s} x="21" y="17" width="406.3" height="176">
        \\<div xmlns="http://www.w3.org/1999/xhtml" class="ellipsis{s}">
        \\
        \\<h2 style="font-size:{d}px">{d} [+{d}] {s} ({s})</h2>
        \\
        \\<div>
        \\<span class="progress">
        \\{s}
        \\</span>
        \\</div>
        \\
        \\<ul>
        \\
        \\{s}
        \\
        \\</ul>
        \\
        \\</div>
        \\</foreignObject>
        \\
    , .{
        system_language_attr,
        rtl_class,
        language_title_font_size,
        stats.languages.count(),
        stats.excluded_langs.count(),
        translation.programming_languages_str,
        languages_by_str,
        progress,
        lang_list,
    });
}

fn languagesLocaleBlocks(
    allocator: std.mem.Allocator,
    translations: std.json.ObjectMap,
    stats: anytype,
    progress: []const u8,
    lang_list: []const u8,
) ![]const u8 {
    var blocks = try std.ArrayList([]const u8).initCapacity(allocator, 16);
    errdefer blocks.deinit(allocator);

    var iterator = translations.iterator();
    while (iterator.next()) |entry| {
        const locale = entry.key_ptr.*;
        const value = entry.value_ptr.*;

        const locale_obj = switch (value) {
            .object => |obj| obj,
            else => continue,
        };

        const translation = try i18n.fromJson(locale_obj);

        try blocks.append(
            allocator,
            try localizedLanguagesBlock(
                allocator,
                locale,
                stats,
                translation,
                progress,
                lang_list,
            ),
        );
    }

    try blocks.append(
        allocator,
        try localizedLanguagesBlock(
            allocator,
            null,
            stats,
            try i18n.fallback(translations),
            progress,
            lang_list,
        ),
    );

    return try std.mem.concat(allocator, u8, blocks.items);
}

fn localizedOverviewBlock(
    allocator: std.mem.Allocator,
    system_language: ?[]const u8,
    stats: anytype,
    translation: i18n.Translation,
) ![]const u8 {
    const rtl_class = i18n.rtlClass(system_language);
    const system_language_attr =
        if (system_language) |lang|
            try std.fmt.allocPrint(
                allocator,
                " systemLanguage=\"{s}\"",
                .{lang},
            )
        else
            "";
    const repo_traffic_font_size = fitFontSize(codeCount(translation.repo_traffic_str), 12, 8, 36);

    return try std.fmt.allocPrint(allocator,
        \\<foreignObject{s} x="21" y="21" width="318" height="168">
        \\<div xmlns="http://www.w3.org/1999/xhtml" class="overview-root{s}">
        \\<table>
        \\<thead><tr style="transform: translateX(0);">
        \\<th class="title-cell" colspan="2">{s} {s}</th>
        \\</tr></thead>
        \\<tbody>
        \\<tr><td class="label-cell"><svg class="octicon" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg" version="1.1" width="16" height="16"><path fill-rule="evenodd" d="M8 .25a.75.75 0 01.673.418l1.882 3.815 4.21.612a.75.75 0 01.416 1.279l-3.046 2.97.719 4.192a.75.75 0 01-1.088.791L8 12.347l-3.766 1.98a.75.75 0 01-1.088-.79l.72-4.194L.818 6.374a.75.75 0 01.416-1.28l4.21-.611L7.327.668A.75.75 0 018 .25zm0 2.445L6.615 5.5a.75.75 0 01-.564.41l-3.097.45 2.24 2.184a.75.75 0 01.216.664l-.528 3.084 2.769-1.456a.75.75 0 01.698 0l2.77 1.456-.53-3.084a.75.75 0 01.216-.664l2.24-2.183-3.096-.45a.75.75 0 01-.564-.41L8 2.694v.001z"></path></svg>{s}</td><td class="value-cell">{d}</td></tr>
        \\<tr style="animation-delay: 150ms"><td class="label-cell"><svg class="octicon" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg" version="1.1" width="16" height="16" role="img"><path fill-rule="evenodd" d="M5 3.25a.75.75 0 11-1.5 0 .75.75 0 011.5 0zm0 2.122a2.25 2.25 0 10-1.5 0v.878A2.25 2.25 0 005.75 8.5h1.5v2.128a2.251 2.251 0 101.5 0V8.5h1.5a2.25 2.25 0 002.25-2.25v-.878a2.25 2.25 0 10-1.5 0v.878a.75.75 0 01-.75.75h-4.5A.75.75 0 015 6.25v-.878zm3.75 7.378a.75.75 0 11-1.5 0 .75.75 0 011.5 0zm3-8.75a.75.75 0 100-1.5.75.75 0 000 1.5z"></path></svg>{s}</td><td class="value-cell">{d}</td></tr>
        \\<tr style="animation-delay: 300ms"><td class="label-cell"><svg class="octicon" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg" version="1.1" width="16" height="16" aria-hidden="true"><path fill-rule="evenodd" d="M1 2.5A2.5 2.5 0 013.5 0h8.75a.75.75 0 01.75.75v3.5a.75.75 0 01-1.5 0V1.5h-8a1 1 0 00-1 1v6.708A2.492 2.492 0 013.5 9h3.25a.75.75 0 010 1.5H3.5a1 1 0 100 2h5.75a.75.75 0 010 1.5H3.5A2.5 2.5 0 011 11.5v-9zm13.23 7.79a.75.75 0 001.06-1.06l-2.505-2.505a.75.75 0 00-1.06 0L9.22 9.229a.75.75 0 001.06 1.061l1.225-1.224v6.184a.75.75 0 001.5 0V9.066l1.224 1.224z"></path></svg>{s}</td><td class="value-cell">{d}</td></tr>
        \\<tr style="animation-delay: 450ms"><td class="label-cell"><svg class="octicon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="16" height="16"><path fill-rule="evenodd" d="M8.75 1.75a.75.75 0 00-1.5 0V5H4a.75.75 0 000 1.5h3.25v3.25a.75.75 0 001.5 0V6.5H12A.75.75 0 0012 5H8.75V1.75zM4 13a.75.75 0 000 1.5h8a.75.75 0 100-1.5H4z"></path></svg>{s}</td><td class="value-cell">{d}</td></tr>
        \\<tr style="animation-delay: 600ms"><td class="label-cell"><svg class="octicon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="16" height="16"><path fill-rule="evenodd" d="M1.679 7.932c.412-.621 1.242-1.75 2.366-2.717C5.175 4.242 6.527 3.5 8 3.5c1.473 0 2.824.742 3.955 1.715 1.124.967 1.954 2.096 2.366 2.717a.119.119 0 010 .136c-.412.621-1.242 1.75-2.366 2.717C10.825 11.758 9.473 12.5 8 12.5c-1.473 0-2.824-.742-3.955-1.715C2.92 9.818 2.09 8.69 1.679 8.068a.119.119 0 010-.136zM8 2c-1.981 0-3.67.992-4.933 2.078C1.797 5.169.88 6.423.43 7.1a1.619 1.619 0 000 1.798c.45.678 1.367 1.932 2.637 3.024C4.329 13.008 6.019 14 8 14c1.981 0 3.67-.992 4.933-2.078 1.27-1.091 2.187-2.345 2.637-3.023a1.619 1.619 0 000-1.798c-.45-.678-1.367-1.932-2.637-3.023C11.671 2.992 9.981 2 8 2zm0 8a2 2 0 100-4 2 2 0 000 4z"></path></svg><span style="font-size:{d}px">{s}</span></td><td class="value-cell">{d}</td></tr>
        \\<tr style="animation-delay: 750ms"><td class="label-cell"><svg class="octicon" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg" version="1.1" width="16" height="16" aria-hidden="true"><path fill-rule="evenodd" d="M2 2.5A2.5 2.5 0 014.5 0h8.75a.75.75 0 01.75.75v12.5a.75.75 0 01-.75.75h-2.5a.75.75 0 110-1.5h1.75v-2h-8a1 1 0 00-.714 1.7.75.75 0 01-1.072 1.05A2.495 2.495 0 012 11.5v-9zm10.5-1V9h-8c-.356 0-.694.074-1 .208V2.5a1 1 0 011-1h8zM5 12.25v3.25a.25.25 0 00.4.2l1.45-1.087a.25.25 0 01.3 0L8.6 15.7a.25.25 0 00.4-.2v-3.25a.25.25 0 00-.25-.25h-3.5a.25.25 0 00-.25.25z"></path></svg>{s}</td><td class="value-cell">{d}</td></tr>
        \\</tbody>
        \\</table>
        \\</div>
        \\</foreignObject>
        \\
    , .{
        system_language_attr,
        rtl_class,
        translation.github_statistics_str,
        stats.name,
        translation.stars_str,
        stats.stars,
        translation.forks_str,
        stats.forks,
        translation.all_time_contributions_str,
        stats.contributions,
        translation.lines_of_code_changed_str,
        stats.lines_changed,
        repo_traffic_font_size,
        translation.repo_traffic_str,
        stats.traffic,
        translation.repos_with_contributions_str,
        stats.repos,
    });
}

fn overviewLocaleBlocks(
    allocator: std.mem.Allocator,
    translations: std.json.ObjectMap,
    stats: anytype,
) ![]const u8 {
    var blocks = try std.ArrayList([]const u8).initCapacity(allocator, 16);
    errdefer blocks.deinit(allocator);

    var iterator = translations.iterator();
    while (iterator.next()) |entry| {
        const locale = entry.key_ptr.*;
        const value = entry.value_ptr.*;

        const locale_obj = switch (value) {
            .object => |obj| obj,
            else => continue,
        };

        const translation = try i18n.fromJson(locale_obj);

        try blocks.append(
            allocator,
            try localizedOverviewBlock(
                allocator,
                locale,
                stats,
                translation,
            ),
        );
    }

    try blocks.append(
        allocator,
        try localizedOverviewBlock(
            allocator,
            null,
            stats,
            try i18n.fallback(translations),
        ),
    );

    return try std.mem.concat(allocator, u8, blocks.items);
}

pub fn overview(
    arena: *std.heap.ArenaAllocator,
    stats: anytype,
    template: []const u8,
    translations: std.json.ObjectMap,
    selected_theme: themes.Theme,
) ![]const u8 {
    const allocator = arena.allocator();
    return templateFill(
        allocator,
        template,
        struct {
            i18n_overview_blocks: []const u8,
            theme_css: []const u8,
        }{
            .i18n_overview_blocks = try overviewLocaleBlocks(
                allocator,
                translations,
                stats,
            ),
            .theme_css = themes.overviewCss(selected_theme),
        },
    );
}

pub fn languages(
    arena: *std.heap.ArenaAllocator,
    stats: anytype,
    template: []const u8,
    translations: std.json.ObjectMap,
    selected_theme: themes.Theme,
) ![]const u8 {
    const allocator = arena.allocator();

    const progress = try allocator.alloc([]const u8, stats.languages.count());
    const lang_list = try allocator.alloc([]const u8, stats.languages.count());

    for (
        stats.languages.keys(),
        stats.languages.values(),
        progress,
        lang_list,
        0..,
    ) |language, count, *progress_s, *lang_s, index| {
        const color = stats.language_colors.get(language);
        const percent =
            100 * if (stats.languages_total == 0)
                0.0
            else
                @as(f64, @floatFromInt(count)) /
                    @as(f64, @floatFromInt(stats.languages_total));

        progress_s.* = try std.fmt.allocPrint(allocator,
            \\<span style="
            \\  background-color: {s}; 
            \\  width: {d:.3}%;
            \\" class="progress-item"></span>
        , .{ color orelse "#000", percent });

        lang_s.* = try std.fmt.allocPrint(allocator,
            \\<li style="animation-delay: {d}ms;">
            \\  <svg 
            \\      xmlns="http://www.w3.org/2000/svg" 
            \\      class="octicon"
            \\      style="fill: {s};" 
            \\      viewBox="0 0 16 16" 
            \\      version="1.1" 
            \\      width="16" 
            \\      height="16"
            \\  ><path 
            \\      fill-rule="evenodd" 
            \\      d="M8 4a4 4 0 100 8 4 4 0 000-8z"
            \\  ></path></svg>
            \\  <span class="lang">{s}</span>
            \\  <span class="percent">{d:.2}%</span>
            \\</li>
            \\
        , .{ (index + 1) * 150, color orelse "#000", language, percent });
    }

    const progress_html = try std.mem.concat(allocator, u8, progress);
    const lang_list_html = try std.mem.concat(allocator, u8, lang_list);

    return templateFill(
        allocator,
        template,
        struct {
            i18n_languages_blocks: []const u8,
            theme_css: []const u8,
        }{
            .i18n_languages_blocks = try languagesLocaleBlocks(
                allocator,
                translations,
                stats,
                progress_html,
                lang_list_html,
            ),
            .theme_css = themes.languagesCss(selected_theme),
        },
    );
}
