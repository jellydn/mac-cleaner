//! Mole CLI path resolution and spawn helpers.

const std = @import("std");
const model_mod = @import("model.zig");
const Model = model_mod.Model;
const JobKind = model_mod.JobKind;

pub const max_path_bytes = std.Io.Dir.max_path_bytes;

/// Homebrew installs on Apple Silicon and Intel (preferred over PATH).
const mole_candidates = [_][]const u8{
    "/opt/homebrew/bin/mole",
    "/usr/local/bin/mole",
    "/opt/homebrew/bin/mo",
    "/usr/local/bin/mo",
};

pub const status_key: u64 = 1;
pub const history_key: u64 = 2;
pub const job_key: u64 = 3;

pub const ResolveResult = struct {
    path: []const u8,
    found: bool,
};

pub fn pathExists(path: []const u8) bool {
    var buffer: [max_path_bytes:0]u8 = undefined;
    if (path.len == 0 or path.len >= buffer.len) return false;
    @memcpy(buffer[0..path.len], path);
    buffer[path.len] = 0;
    return std.c.access(buffer[0..path.len :0].ptr, std.c.F_OK) == 0;
}

/// Join `dir` + `/` + `name` into `buf`. Returns slice of buf or null if too long.
pub fn joinPath(dir: []const u8, name: []const u8, buf: []u8) ?[]const u8 {
    if (dir.len == 0 or name.len == 0) return null;
    const need = dir.len + 1 + name.len;
    if (need > buf.len) return null;
    @memcpy(buf[0..dir.len], dir);
    buf[dir.len] = '/';
    @memcpy(buf[dir.len + 1 ..][0..name.len], name);
    return buf[0..need];
}

/// Discover mole: Homebrew candidates first, then `$PATH` for `mole` then `mo`.
/// `buf` holds PATH-resolved paths (must outlive returned path when found via PATH).
pub fn resolveMole(buf: []u8) ResolveResult {
    for (mole_candidates) |path| {
        if (pathExists(path)) return .{ .path = path, .found = true };
    }

    const path_z = std.c.getenv("PATH") orelse return .{ .path = "", .found = false };
    const path_env = std.mem.span(path_z);
    var iter = std.mem.splitScalar(u8, path_env, ':');
    while (iter.next()) |dir| {
        if (dir.len == 0) continue;
        for ([_][]const u8{ "mole", "mo" }) |name| {
            const joined = joinPath(dir, name, buf) orelse continue;
            if (pathExists(joined)) {
                // Copy into buf is already joined; return that slice.
                return .{ .path = joined, .found = true };
            }
        }
    }
    return .{ .path = "", .found = false };
}

/// Boot/UX when mole binary cannot be found.
pub fn applyMoleMissing(model: *Model) void {
    model.mole_available = false;
    model.setMolePath("(not found)");
    model.status_loading = false;
    model.status_error = true;
    model.history_loading = false;
    model.history_error = true;
    model.health_msg.set("Mole not found — brew install mole (or put mole on PATH)");
}

pub fn markMoleAvailable(model: *Model, path: []const u8) void {
    model.mole_available = true;
    model.setMolePath(path);
}

pub fn spawnStatus(comptime Effects: type, model: *Model, fx: *Effects, on_exit: anytype) void {
    if (!model.mole_available) return;
    if (model.status_loading) return;
    model.status_loading = true;
    model.status_error = false;
    const mole_bin = model.molePath();
    fx.spawn(.{
        .key = status_key,
        .argv = &.{ mole_bin, "status", "--json" },
        .output = .collect,
        .on_exit = on_exit,
    });
}

pub fn spawnHistory(comptime Effects: type, model: *Model, fx: *Effects, on_exit: anytype) void {
    if (!model.mole_available) return;
    if (model.history_loading) return;
    model.history_loading = true;
    model.history_error = false;
    const mole_bin = model.molePath();
    fx.spawn(.{
        .key = history_key,
        .argv = &.{ mole_bin, "history", "--json", "--limit", "12" },
        .output = .collect,
        .on_exit = on_exit,
    });
}

pub fn spawnJob(comptime Effects: type, model: *Model, fx: *Effects, kind: JobKind, on_line: anytype, on_exit: anytype) void {
    if (!model.mole_available) return;
    if (model.job_running or kind == .none) return;
    model.job = kind;
    model.job_running = true;
    model.confirm_job = .none;
    model.pending_after_sudo = .none;
    model.clearLog();
    model.setJobSummary(kind.title());
    model.appendLog(kind.title());
    if (kind.wantsSudo()) {
        if (model.sudo_phase.isActive()) {
            model.appendLog("Admin session active — system cleanup enabled");
        } else {
            model.appendLog("No admin session — user-level only (system caches skipped)");
        }
    }

    const mole_bin = model.molePath();
    var argv_buf: [3][]const u8 = undefined;
    const argv_len = kind.fillArgv(mole_bin, &argv_buf);
    fx.spawn(.{
        .key = job_key,
        .argv = argv_buf[0..argv_len],
        .on_line = on_line,
        .on_exit = on_exit,
    });
}

pub fn cancelJob(comptime Effects: type, model: *Model, fx: *Effects) void {
    if (!model.job_running) return;
    fx.cancel(job_key);
    model.appendLog("Cancelling…");
}

test "joinPath builds dir/name" {
    var buf: [64]u8 = undefined;
    const p = joinPath("/opt/homebrew/bin", "mole", &buf).?;
    try std.testing.expectEqualStrings("/opt/homebrew/bin/mole", p);
}
