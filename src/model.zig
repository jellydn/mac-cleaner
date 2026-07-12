//! Application model: tabs, jobs, sudo phase, fixed-buffer rows, view projections.

const std = @import("std");
const BoundedStr = @import("bounded_str.zig").BoundedStr;

// ------------------------------------------------------------------ tabs

pub const Tab = enum {
    overview,
    clean,
    history,

    pub fn label(self: Tab) []const u8 {
        return switch (self) {
            .overview => "Overview",
            .clean => "Clean",
            .history => "History",
        };
    }
};

// ------------------------------------------------------------------ jobs

pub const JobKind = enum {
    none,
    clean_dry,
    clean_run,
    optimize_dry,
    optimize_run,
    purge_dry,
    purge_run,

    pub fn title(self: JobKind) []const u8 {
        return switch (self) {
            .none => "Idle",
            .clean_dry => "Clean (dry run)",
            .clean_run => "Clean",
            .optimize_dry => "Optimize (dry run)",
            .optimize_run => "Optimize",
            .purge_dry => "Purge (dry run)",
            .purge_run => "Purge",
        };
    }

    pub fn needsConfirm(self: JobKind) bool {
        return self == .clean_run or self == .optimize_run or self == .purge_run;
    }

    /// Clean/optimize benefit from a cached sudo session (system caches).
    pub fn wantsSudo(self: JobKind) bool {
        return switch (self) {
            .clean_dry, .clean_run, .optimize_dry, .optimize_run => true,
            .purge_dry, .purge_run, .none => false,
        };
    }

    /// After a successful real clean/optimize/purge, refresh status + history.
    pub fn refreshesAfter(self: JobKind) bool {
        return self == .clean_run or self == .optimize_run or self == .purge_run;
    }

    /// Mole subcommand name (`clean` / `optimize` / `purge`).
    pub fn subcommand(self: JobKind) []const u8 {
        return switch (self) {
            .clean_dry, .clean_run => "clean",
            .optimize_dry, .optimize_run => "optimize",
            .purge_dry, .purge_run => "purge",
            .none => "",
        };
    }

    pub fn isDryRun(self: JobKind) bool {
        return switch (self) {
            .clean_dry, .optimize_dry, .purge_dry => true,
            .clean_run, .optimize_run, .purge_run, .none => false,
        };
    }

    /// Write argv into `out` (capacity ≥ 3). Returns length. Caller must keep
    /// `mole` alive until spawn copies the argv.
    pub fn fillArgv(self: JobKind, mole: []const u8, out: *[3][]const u8) usize {
        return switch (self) {
            .clean_dry => blk: {
                out.* = .{ mole, "clean", "--dry-run" };
                break :blk 3;
            },
            .clean_run => blk: {
                out.* = .{ mole, "clean", "" };
                break :blk 2;
            },
            .optimize_dry => blk: {
                out.* = .{ mole, "optimize", "--dry-run" };
                break :blk 3;
            },
            .optimize_run => blk: {
                out.* = .{ mole, "optimize", "" };
                break :blk 2;
            },
            .purge_dry => blk: {
                out.* = .{ mole, "purge", "--dry-run" };
                break :blk 3;
            },
            .purge_run => blk: {
                out.* = .{ mole, "purge", "" };
                break :blk 2;
            },
            .none => 0,
        };
    }
};

// ------------------------------------------------------------------ sudo

/// Lifecycle of the app-owned sudo timestamp + keepalive.
pub const SudoPhase = enum {
    /// Boot probe in flight (or not yet run).
    unknown,
    inactive,
    prompting,
    active,

    pub fn isActive(self: SudoPhase) bool {
        return self == .active;
    }

    pub fn isPrompting(self: SudoPhase) bool {
        return self == .prompting;
    }

    /// Show "Grant admin once" when we are not already active or mid-dialog.
    pub fn showGrantButton(self: SudoPhase) bool {
        return self == .inactive or self == .unknown;
    }

    pub fn statusText(self: SudoPhase) []const u8 {
        return switch (self) {
            .unknown => "Admin: checking…",
            .inactive => "Admin: not granted — system clean needs it",
            .prompting => "Admin: prompting…",
            .active => "Admin: active (once per session)",
        };
    }

    pub fn statusBarLabel(self: SudoPhase) []const u8 {
        return switch (self) {
            .active => "admin on",
            .prompting => "admin…",
            .unknown, .inactive => "admin off",
        };
    }
};

// ------------------------------------------------------------------ rows

pub const ProcessRow = struct {
    name: BoundedStr(48) = .{},
    cpu: f32 = 0,
    memory_mb: f32 = 0,

    pub fn nameText(self: *const ProcessRow) []const u8 {
        return self.name.slice();
    }

    pub fn cpuText(self: *const ProcessRow, arena: std.mem.Allocator) []const u8 {
        return std.fmt.allocPrint(arena, "{d:.0}%", .{self.cpu}) catch "?%";
    }

    pub fn memText(self: *const ProcessRow, arena: std.mem.Allocator) []const u8 {
        return std.fmt.allocPrint(arena, "{d:.0} MB", .{self.memory_mb}) catch "? MB";
    }
};

pub const HistoryRow = struct {
    command: BoundedStr(32) = .{},
    when: BoundedStr(32) = .{},
    size: BoundedStr(24) = .{},
    items: u32 = 0,
    removed: u32 = 0,

    pub fn commandText(self: *const HistoryRow) []const u8 {
        return self.command.slice();
    }
    pub fn whenText(self: *const HistoryRow) []const u8 {
        return self.when.slice();
    }
    pub fn sizeText(self: *const HistoryRow) []const u8 {
        return self.size.slice();
    }
    pub fn itemsText(self: *const HistoryRow, arena: std.mem.Allocator) []const u8 {
        return std.fmt.allocPrint(arena, "{d} items · {d} removed", .{ self.items, self.removed }) catch "";
    }
};

pub const LogLine = struct {
    text: BoundedStr(220) = .{},

    pub fn content(self: *const LogLine) []const u8 {
        return self.text.slice();
    }
};

// ------------------------------------------------------------------ model

pub const Model = struct {
    // Storage / effect-only: markup binds helpers instead.
    pub const view_unbound = .{
        "tab",
        "mole_path",
        "status_loading",
        "status_error",
        "mole_available",
        "health_score",
        "health_msg",
        "host",
        "uptime",
        "hardware",
        "cpu_pct",
        "mem_pct",
        "disk_pct",
        "disk_free_gb",
        "disk_total_gb",
        "battery_pct",
        "battery_status",
        "trash_gb",
        "load1",
        "collected_at",
        "top_processes",
        "top_process_count",
        "job",
        "confirm_job",
        "pending_after_sudo",
        "sudo_phase",
        "sudo_keepalive_on",
        "log_lines",
        "log_count",
        "job_summary",
        "history",
        "history_count",
    };

    tab: Tab = .overview,
    chrome_leading: f32 = 0,
    header_height: f32 = 44,

    mole_path: BoundedStr(96) = .{},
    /// False when resolve failed at boot; gates actions and spawns.
    mole_available: bool = true,

    status_loading: bool = false,
    status_error: bool = false,
    health_score: i32 = 0,
    health_msg: BoundedStr(96) = .{},
    host: BoundedStr(48) = .{},
    uptime: BoundedStr(32) = .{},
    hardware: BoundedStr(64) = .{},
    cpu_pct: f32 = 0,
    mem_pct: f32 = 0,
    disk_pct: f32 = 0,
    disk_free_gb: f32 = 0,
    disk_total_gb: f32 = 0,
    battery_pct: f32 = 0,
    battery_status: BoundedStr(24) = .{},
    trash_gb: f32 = 0,
    load1: f32 = 0,
    collected_at: BoundedStr(40) = .{},
    top_processes: [8]ProcessRow = @splat(.{}),
    top_process_count: usize = 0,

    job: JobKind = .none,
    job_running: bool = false,
    confirm_job: JobKind = .none,
    pending_after_sudo: JobKind = .none,
    log_lines: [48]LogLine = @splat(.{}),
    log_count: usize = 0,
    job_summary: BoundedStr(160) = .{},

    sudo_phase: SudoPhase = .unknown,
    sudo_keepalive_on: bool = false,

    history_loading: bool = false,
    history_error: bool = false,
    history: [12]HistoryRow = @splat(.{}),
    history_count: usize = 0,

    // ---- path / text projections ----

    pub fn molePath(self: *const Model) []const u8 {
        return self.mole_path.slice();
    }
    pub fn healthMsg(self: *const Model) []const u8 {
        return self.health_msg.orDefault("Waiting for Mole…");
    }
    pub fn hostText(self: *const Model) []const u8 {
        return self.host.orDefault("—");
    }
    pub fn uptimeText(self: *const Model) []const u8 {
        return self.uptime.orDefault("—");
    }
    pub fn hardwareText(self: *const Model) []const u8 {
        return self.hardware.orDefault("—");
    }
    pub fn batteryText(self: *const Model) []const u8 {
        return self.battery_status.orDefault("—");
    }
    pub fn collectedText(self: *const Model) []const u8 {
        return self.collected_at.orDefault("not yet");
    }
    pub fn jobSummary(self: *const Model) []const u8 {
        if (self.job_summary.isEmpty()) {
            if (self.job_running) return "Running…";
            return "No job yet — dry-run is safe.";
        }
        return self.job_summary.slice();
    }
    pub fn jobTitle(self: *const Model) []const u8 {
        return self.job.title();
    }

    pub fn trashText(self: *const Model, arena: std.mem.Allocator) []const u8 {
        if (self.trash_gb < 0.01) return "Empty";
        return std.fmt.allocPrint(arena, "{d:.2} GB", .{self.trash_gb}) catch "?";
    }
    pub fn loadText(self: *const Model, arena: std.mem.Allocator) []const u8 {
        return std.fmt.allocPrint(arena, "{d:.2}", .{self.load1}) catch "?";
    }
    pub fn healthScoreText(self: *const Model, arena: std.mem.Allocator) []const u8 {
        if (self.status_loading and self.health_msg.isEmpty()) return "…";
        return std.fmt.allocPrint(arena, "{d}", .{self.health_score}) catch "?";
    }
    pub fn cpuText(self: *const Model, arena: std.mem.Allocator) []const u8 {
        return std.fmt.allocPrint(arena, "{d:.0}%", .{self.cpu_pct}) catch "?%";
    }
    pub fn memText(self: *const Model, arena: std.mem.Allocator) []const u8 {
        return std.fmt.allocPrint(arena, "{d:.0}%", .{self.mem_pct}) catch "?%";
    }
    pub fn diskText(self: *const Model, arena: std.mem.Allocator) []const u8 {
        return std.fmt.allocPrint(arena, "{d:.0}%", .{self.disk_pct}) catch "?%";
    }
    pub fn diskProgress(self: *const Model) f32 {
        return std.math.clamp(self.disk_pct / 100.0, 0, 1);
    }
    pub fn memProgress(self: *const Model) f32 {
        return std.math.clamp(self.mem_pct / 100.0, 0, 1);
    }
    pub fn cpuProgress(self: *const Model) f32 {
        return std.math.clamp(self.cpu_pct / 100.0, 0, 1);
    }
    pub fn diskDetail(self: *const Model, arena: std.mem.Allocator) []const u8 {
        return std.fmt.allocPrint(arena, "{d:.1} GB free of {d:.1} GB", .{ self.disk_free_gb, self.disk_total_gb }) catch "";
    }
    pub fn batteryPctText(self: *const Model, arena: std.mem.Allocator) []const u8 {
        if (self.battery_status.isEmpty() and self.battery_pct == 0) return "—";
        return std.fmt.allocPrint(arena, "{d:.0}%", .{self.battery_pct}) catch "?%";
    }

    pub fn confirmTitle(self: *const Model) []const u8 {
        return switch (self.confirm_job) {
            .clean_run => "Confirm real clean",
            .optimize_run => "Confirm real optimize",
            .purge_run => "Confirm project purge",
            else => "Confirm",
        };
    }
    pub fn confirmBody(self: *const Model) []const u8 {
        return switch (self.confirm_job) {
            .clean_run => "This runs mole clean and permanently frees disk space (caches, logs, leftovers). Prefer dry-run first. Continue?",
            .optimize_run => "This runs mole optimize and may refresh system caches and services. Prefer dry-run first. Continue?",
            .purge_run => "This runs mole purge and deletes old project build artifacts under your scan paths. Prefer dry-run first. Continue?",
            else => "Continue?",
        };
    }

    pub fn topProcesses(self: *const Model) []const ProcessRow {
        return self.top_processes[0..self.top_process_count];
    }
    pub fn historyRows(self: *const Model) []const HistoryRow {
        return self.history[0..self.history_count];
    }
    pub fn logRows(self: *const Model) []const LogLine {
        return self.log_lines[0..self.log_count];
    }

    // ---- UI flags ----

    pub fn statusBusy(self: *const Model) bool {
        return self.status_loading;
    }
    /// Bound to `disabled=` on action buttons (true = greyed out).
    pub fn actionsDisabled(self: *const Model) bool {
        return !self.mole_available or self.job_running or self.sudo_phase.isPrompting();
    }
    /// Overview banner: parse/spawn errors or mole missing (not every transient flag alone).
    pub fn showStatusError(self: *const Model) bool {
        return self.status_error or !self.mole_available;
    }
    pub fn showConfirm(self: *const Model) bool {
        return self.confirm_job != .none;
    }
    pub fn showSudoActive(self: *const Model) bool {
        return self.sudo_phase.isActive();
    }
    pub fn showSudoIdle(self: *const Model) bool {
        return self.sudo_phase.showGrantButton();
    }
    pub fn showSudoPrompting(self: *const Model) bool {
        return self.sudo_phase.isPrompting();
    }
    pub fn sudoStatusText(self: *const Model) []const u8 {
        return self.sudo_phase.statusText();
    }
    pub fn showEmptyLog(self: *const Model) bool {
        return self.log_count == 0 and !self.job_running;
    }
    pub fn showEmptyHistory(self: *const Model) bool {
        return self.history_count == 0 and !self.history_loading;
    }
    pub fn showEmptyProcs(self: *const Model) bool {
        return self.top_process_count == 0 and !self.status_loading;
    }
    pub fn isOverview(self: *const Model) bool {
        return self.tab == .overview;
    }
    pub fn isClean(self: *const Model) bool {
        return self.tab == .clean;
    }
    pub fn isHistory(self: *const Model) bool {
        return self.tab == .history;
    }
    pub fn overviewTab(self: *const Model) Tab {
        _ = self;
        return .overview;
    }
    pub fn cleanTab(self: *const Model) Tab {
        _ = self;
        return .clean;
    }
    pub fn historyTab(self: *const Model) Tab {
        _ = self;
        return .history;
    }

    pub fn statusBar(self: *const Model, arena: std.mem.Allocator) []const u8 {
        const mole = if (self.mole_path.isEmpty()) "mole?" else self.molePath();
        const admin = self.sudo_phase.statusBarLabel();
        if (self.job_running) {
            return std.fmt.allocPrint(arena, "{s} · {s} · {s} running", .{ mole, admin, self.job.title() }) catch "running";
        }
        if (self.sudo_phase.isPrompting()) {
            return std.fmt.allocPrint(arena, "{s} · waiting for admin password…", .{mole}) catch "admin";
        }
        if (self.status_loading) {
            return std.fmt.allocPrint(arena, "{s} · {s} · refreshing status…", .{ mole, admin }) catch "loading";
        }
        return std.fmt.allocPrint(arena, "{s} · {s} · health {d} · disk {d:.0}%", .{ mole, admin, self.health_score, self.disk_pct }) catch "Mac Cleaner";
    }

    // ---- mutators ----

    pub fn setMolePath(self: *Model, path: []const u8) void {
        self.mole_path.set(path);
    }

    pub fn setJobSummary(self: *Model, text: []const u8) void {
        self.job_summary.set(text);
    }

    pub fn clearLog(self: *Model) void {
        self.log_count = 0;
        for (&self.log_lines) |*line| line.* = .{};
    }

    pub fn appendLog(self: *Model, text: []const u8) void {
        const trimmed = std.mem.trimEnd(u8, text, "\r\n");
        if (trimmed.len == 0) return;

        var strip_buf: [220]u8 = undefined;
        const cleaned = stripAnsi(trimmed, &strip_buf);
        if (cleaned.len == 0) return;

        if (self.log_count >= self.log_lines.len) {
            var i: usize = 0;
            while (i + 1 < self.log_lines.len) : (i += 1) {
                self.log_lines[i] = self.log_lines[i + 1];
            }
            self.log_count = self.log_lines.len - 1;
        }
        self.log_lines[self.log_count].text.set(cleaned);
        self.log_count += 1;
    }
};

/// Copy `src` into `out` without ANSI CSI sequences (`ESC [ ... final`).
/// Also drops other C0 controls except tab. Returns the written slice of `out`.
pub fn stripAnsi(src: []const u8, out: []u8) []const u8 {
    var o: usize = 0;
    var i: usize = 0;
    while (i < src.len and o < out.len) {
        const c = src[i];
        if (c == 0x1b) {
            i += 1;
            if (i < src.len and src[i] == '[') {
                i += 1;
                while (i < src.len) {
                    const b = src[i];
                    i += 1;
                    if (b >= 0x40 and b <= 0x7e) break; // CSI final byte
                }
            } else if (i < src.len) {
                // Skip single-char escape forms (e.g. ESC + letter)
                i += 1;
            }
            continue;
        }
        if (c < 0x20 and c != '\t') {
            i += 1;
            continue;
        }
        out[o] = c;
        o += 1;
        i += 1;
    }
    return out[0..o];
}
