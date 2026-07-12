const std = @import("std");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const model_mod = @import("model.zig");
const sudo = @import("sudo.zig");
const status_json = @import("status_json.zig");
const effect_handlers = @import("effect_handlers.zig");
const mole = @import("mole.zig");

const canvas = native_sdk.canvas;
const testing = std.testing;

const AppUi = main.AppUi;
const Model = main.Model;
const Msg = main.Msg;
const JobKind = main.JobKind;

const AppMarkup = canvas.MarkupView(Model, Msg);

fn buildTree(arena: std.mem.Allocator, model: *const Model) !AppUi.Tree {
    var view = try AppMarkup.init(arena, main.app_markup);
    var ui = AppUi.init(arena);
    const node = view.build(&ui, model) catch |err| {
        if (err == error.MarkupBuild) {
            std.debug.print("app.native:{d}:{d}: {s}\n", .{ view.diagnostic.line, view.diagnostic.column, view.diagnostic.message });
        }
        return err;
    };
    return ui.finalize(node);
}

fn findByText(widget: canvas.Widget, kind: canvas.WidgetKind, text: []const u8) ?canvas.Widget {
    if (widget.kind == kind and std.mem.eql(u8, widget.text, text)) return widget;
    for (widget.children) |child| {
        if (findByText(child, kind, text)) |found| return found;
    }
    return null;
}

fn expectByText(widget: canvas.Widget, kind: canvas.WidgetKind, text: []const u8) !canvas.Widget {
    return findByText(widget, kind, text) orelse {
        std.debug.print("no {t} with text \"{s}\" in the view - if you changed app.native, update this test to match\n", .{ kind, text });
        return error.WidgetNotFound;
    };
}

fn findAnyText(widget: canvas.Widget, text: []const u8) ?canvas.Widget {
    if (std.mem.eql(u8, widget.text, text)) return widget;
    for (widget.children) |child| {
        if (findAnyText(child, text)) |found| return found;
    }
    return null;
}

test "parses mole status json into the model" {
    var model = main.initialModel();
    const sample =
        \\{
        \\  "health_score": 72,
        \\  "health_score_msg": "Good: Disk Almost Full",
        \\  "host": "test-mac",
        \\  "uptime": "2d 1h",
        \\  "collected_at": "2026-07-12T00:00:00+08:00",
        \\  "trash_size": 2147483648,
        \\  "hardware": { "model": "MacBook Pro", "cpu_model": "Apple M2 Pro" },
        \\  "cpu": { "usage": 41.5, "load1": 2.5 },
        \\  "memory": { "used_percent": 66.2 },
        \\  "disks": [
        \\    {
        \\      "mount": "/Volumes/Ext",
        \\      "used": 100,
        \\      "total": 200,
        \\      "used_percent": 50.0,
        \\      "external": true
        \\    },
        \\    {
        \\      "mount": "/",
        \\      "used": 400000000000,
        \\      "total": 500000000000,
        \\      "used_percent": 80.0,
        \\      "external": false
        \\    }
        \\  ],
        \\  "batteries": [ { "percent": 88, "status": "AC" } ],
        \\  "top_processes": [
        \\    { "name": "Brave", "cpu": 22.5, "memory_bytes": 524288000 }
        \\  ]
        \\}
    ;
    try status_json.applyStatusJson(&model, sample);
    try testing.expectEqual(@as(i32, 72), model.health_score);
    try testing.expectEqualStrings("Good: Disk Almost Full", model.healthMsg());
    try testing.expectEqualStrings("test-mac", model.hostText());
    try testing.expectEqualStrings("MacBook Pro · Apple M2 Pro", model.hardwareText());
    try testing.expect(@abs(model.cpu_pct - 41.5) < 0.01);
    try testing.expect(@abs(model.load1 - 2.5) < 0.01);
    try testing.expect(@abs(model.disk_pct - 80.0) < 0.01);
    try testing.expect(@abs(model.trash_gb - 2.0) < 0.01);
    try testing.expectEqual(@as(usize, 1), model.top_process_count);
    try testing.expectEqualStrings("Brave", model.top_processes[0].nameText());
}

test "parses mole history json" {
    var model = main.initialModel();
    const sample =
        \\{
        \\  "sessions": [
        \\    {
        \\      "command": "clean",
        \\      "started_at": "2026-07-08 09:56:33",
        \\      "size": "1.34GB",
        \\      "items": 127,
        \\      "actions": { "removed": 131 }
        \\    }
        \\  ]
        \\}
    ;
    try status_json.applyHistoryJson(&model, sample);
    try testing.expectEqual(@as(usize, 1), model.history_count);
    try testing.expectEqualStrings("clean", model.history[0].commandText());
    try testing.expectEqualStrings("1.34GB", model.history[0].sizeText());
    try testing.expectEqual(@as(u32, 127), model.history[0].items);
    try testing.expectEqual(@as(u32, 131), model.history[0].removed);
}

test "overview view builds with tabs and health card" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var model = main.initialModel();
    model.health_score = 64;
    model.setJobSummary("No job yet — dry-run is safe.");
    model.health_msg.set("Fair: High CPU");

    const tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .text, "Mac Cleaner");
    try testing.expect(findAnyText(tree.root, "Overview") != null);
    try testing.expect(findAnyText(tree.root, "Clean") != null);
    try testing.expect(findAnyText(tree.root, "History") != null);
    _ = try expectByText(tree.root, .button, "Open Clean");
    try testing.expectEqualStrings("Fair: High CPU", model.healthMsg());
}

test "clean tab shows action buttons" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var model = main.initialModel();
    model.tab = .clean;
    model.sudo_phase = .inactive;

    const tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .button, "Clean · dry-run");
    _ = try expectByText(tree.root, .button, "Clean · run");
    _ = try expectByText(tree.root, .button, "Optimize · dry-run");
    _ = try expectByText(tree.root, .button, "Purge · dry-run");
    _ = try expectByText(tree.root, .button, "Purge · run");
    _ = try expectByText(tree.root, .button, "Grant admin once");
}

test "the view lays out through the canvas engine" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();

    var model = main.initialModel();
    const tree = try buildTree(arena_state.allocator(), &model);

    var nodes: [256]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(tree.root, native_sdk.geometry.RectF.init(0, 0, 780, 620), &nodes);
    try testing.expect(layout.nodes.len > 0);
}

test "JobKind policy: confirm, sudo, refresh, argv" {
    try testing.expect(JobKind.clean_run.needsConfirm());
    try testing.expect(JobKind.optimize_run.needsConfirm());
    try testing.expect(JobKind.purge_run.needsConfirm());
    try testing.expect(!JobKind.clean_dry.needsConfirm());
    try testing.expect(!JobKind.optimize_dry.needsConfirm());

    try testing.expect(JobKind.clean_dry.wantsSudo());
    try testing.expect(JobKind.optimize_run.wantsSudo());
    try testing.expect(!JobKind.purge_dry.wantsSudo());

    try testing.expect(JobKind.clean_run.refreshesAfter());
    try testing.expect(JobKind.purge_run.refreshesAfter());
    try testing.expect(!JobKind.clean_dry.refreshesAfter());

    try testing.expectEqualStrings("clean", JobKind.clean_dry.subcommand());
    try testing.expectEqualStrings("optimize", JobKind.optimize_run.subcommand());
    try testing.expect(JobKind.clean_dry.isDryRun());
    try testing.expect(!JobKind.clean_run.isDryRun());

    var argv_buf: [3][]const u8 = undefined;
    const n = JobKind.clean_dry.fillArgv("/opt/homebrew/bin/mole", &argv_buf);
    try testing.expectEqual(@as(usize, 3), n);
    try testing.expectEqualStrings("clean", argv_buf[1]);
    try testing.expectEqualStrings("--dry-run", argv_buf[2]);
}

test "applyStatusExit spawn_failed sets install message" {
    var model: Model = .{};
    model.status_loading = true;
    effect_handlers.applyStatusExit(&model, .{
        .key = 1,
        .reason = .spawn_failed,
    });
    try testing.expect(!model.status_loading);
    try testing.expect(model.status_error);
    try testing.expect(std.mem.indexOf(u8, model.healthMsg(), "Could not run mole") != null);
}

test "applyStatusExit non-zero exit uses stderr or default" {
    var model: Model = .{};
    model.status_loading = true;
    effect_handlers.applyStatusExit(&model, .{
        .key = 1,
        .reason = .exited,
        .code = 1,
        .stderr_tail = "",
    });
    try testing.expectEqualStrings("mole status failed", model.healthMsg());

    model = .{};
    model.status_loading = true;
    effect_handlers.applyStatusExit(&model, .{
        .key = 1,
        .reason = .exited,
        .code = 2,
        .stderr_tail = "auth failed",
    });
    try testing.expectEqualStrings("auth failed", model.healthMsg());
}

test "applyStatusExit bad JSON marks parse error" {
    var model: Model = .{};
    model.status_loading = true;
    effect_handlers.applyStatusExit(&model, .{
        .key = 1,
        .reason = .exited,
        .code = 0,
        .output = "{not json",
    });
    try testing.expect(model.status_error);
    try testing.expectEqualStrings("Failed to parse status JSON", model.healthMsg());
}

test "applyHistoryExit rejected sets history_error" {
    var model: Model = .{};
    model.history_loading = true;
    effect_handlers.applyHistoryExit(&model, .{
        .key = 2,
        .reason = .rejected,
    });
    try testing.expect(!model.history_loading);
    try testing.expect(model.history_error);
}

test "applyJobExit success cancel spawn_failed and refresh signal" {
    var model: Model = .{};
    model.job_running = true;
    model.job = .clean_dry;
    const refresh_dry = effect_handlers.applyJobExit(&model, .{
        .key = 3,
        .reason = .exited,
        .code = 0,
    });
    try testing.expect(!model.job_running);
    try testing.expect(!refresh_dry);
    try testing.expectEqualStrings("Finished successfully", model.jobSummary());
    try testing.expect(std.mem.indexOf(u8, model.logRows()[model.log_count - 1].content(), "Done") != null);

    model = .{};
    model.job_running = true;
    model.job = .clean_run;
    const refresh_run = effect_handlers.applyJobExit(&model, .{
        .key = 3,
        .reason = .exited,
        .code = 0,
    });
    try testing.expect(refresh_run);

    model = .{};
    model.job_running = true;
    model.job = .clean_run;
    _ = effect_handlers.applyJobExit(&model, .{
        .key = 3,
        .reason = .cancelled,
    });
    try testing.expectEqualStrings("Cancelled", model.jobSummary());

    model = .{};
    model.job_running = true;
    _ = effect_handlers.applyJobExit(&model, .{
        .key = 3,
        .reason = .spawn_failed,
    });
    try testing.expect(std.mem.indexOf(u8, model.jobSummary(), "Could not start mole") != null);
}

test "applyMoleMissing sets boot error without inventing a path" {
    var model: Model = .{};
    mole.applyMoleMissing(&model);
    try testing.expect(model.status_error);
    try testing.expect(!model.mole_available);
    try testing.expect(!model.status_loading);
    try testing.expect(std.mem.indexOf(u8, model.healthMsg(), "Mole not found") != null);
    try testing.expectEqualStrings("(not found)", model.molePath());
    try testing.expect(model.actionsDisabled());
    try testing.expect(model.showStatusError());
}

test "joinPath is used by mole discovery helper" {
    var buf: [128]u8 = undefined;
    const p = mole.joinPath("/usr/local/bin", "mo", &buf).?;
    try testing.expectEqualStrings("/usr/local/bin/mo", p);
}

test "confirm copy for optimize_run" {
    var model: Model = .{};
    model.confirm_job = .optimize_run;
    try testing.expectEqualStrings("Confirm real optimize", model.confirmTitle());
    try testing.expect(std.mem.indexOf(u8, model.confirmBody(), "mole optimize") != null);
}

test "actionsDisabled when mole unavailable" {
    var model: Model = .{};
    model.mole_available = true;
    try testing.expect(!model.actionsDisabled());
    mole.applyMoleMissing(&model);
    try testing.expect(model.actionsDisabled());
}

test "sudo takePendingJob and applyAuthOutcome" {
    var model: Model = .{};
    model.pending_after_sudo = .clean_dry;
    model.sudo_phase = .prompting;
    const pending = sudo.takePendingJob(&model);
    try testing.expect(pending == .clean_dry);
    try testing.expect(model.pending_after_sudo == .none);

    sudo.applyAuthOutcome(&model, true);
    try testing.expect(model.sudo_phase.isActive());
    sudo.applyAuthOutcome(&model, false);
    try testing.expect(model.sudo_phase == .inactive);
}

test "handlePingDone expires active session" {
    var model: Model = .{};
    model.sudo_phase = .active;
    sudo.handlePingDone(&model, false);
    try testing.expect(model.sudo_phase == .inactive);
    try testing.expect(model.log_count > 0);
    try testing.expect(std.mem.indexOf(u8, model.logRows()[0].content(), "expired") != null);

    model = .{};
    model.sudo_phase = .inactive;
    sudo.handlePingDone(&model, true);
    try testing.expect(model.sudo_phase.isActive());
}

test "handleAuthDone pending job returned on grant success without Effects timer issues" {
    // Pure path: takePending + applyAuthOutcome (same as handleAuthDone core)
    var model: Model = .{};
    model.pending_after_sudo = .optimize_dry;
    model.sudo_phase = .prompting;
    const pending = sudo.takePendingJob(&model);
    sudo.applyAuthOutcome(&model, true);
    try testing.expect(pending == .optimize_dry);
    try testing.expect(model.sudo_phase.isActive());
    try testing.expect(model.pending_after_sudo == .none);
}

test "stripAnsi removes CSI colour codes" {
    var out: [64]u8 = undefined;
    try testing.expectEqualStrings("hello", model_mod.stripAnsi("hello", &out));
    try testing.expectEqualStrings("OK", model_mod.stripAnsi("\x1b[32mOK\x1b[0m", &out));
    try testing.expectEqualStrings("abc", model_mod.stripAnsi("a\x1b[1;31mb\x1b[0mc", &out));
}

test "appendLog strips ANSI via shipped path" {
    var model: Model = .{};
    model.appendLog("\x1b[32mAdmin session active\x1b[0m");
    try testing.expectEqual(@as(usize, 1), model.log_count);
    try testing.expectEqualStrings("Admin session active", model.logRows()[0].content());
    try testing.expect(std.mem.indexOfScalar(u8, model.logRows()[0].content(), 0x1b) == null);
}

test "sudo ensureThen phases" {
    var model: Model = .{};
    model.sudo_phase = .inactive;
    try testing.expect(sudo.ensureThen(&model, .clean_dry) == .grant_first);
    try testing.expect(model.pending_after_sudo == .clean_dry);

    model = .{};
    model.sudo_phase = .active;
    try testing.expect(sudo.ensureThen(&model, .clean_dry) == .start_now);

    model = .{};
    model.sudo_phase = .inactive;
    try testing.expect(sudo.ensureThen(&model, .purge_dry) == .start_now);

    model = .{};
    model.sudo_phase = .prompting;
    try testing.expect(sudo.ensureThen(&model, .clean_dry) == .busy);

    model = .{};
    model.sudo_phase = .unknown;
    try testing.expect(sudo.ensureThen(&model, .clean_dry) == .start_now);
}

test "actionsDisabled follows job and sudo prompting" {
    var model: Model = .{};
    try testing.expect(!model.actionsDisabled());
    model.job_running = true;
    try testing.expect(model.actionsDisabled());
    model.job_running = false;
    model.sudo_phase = .prompting;
    try testing.expect(model.actionsDisabled());
    model.sudo_phase = .active;
    try testing.expect(!model.actionsDisabled());
}
