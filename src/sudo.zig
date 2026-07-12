//! Session-scoped sudo grant + keepalive for Mole system clean/optimize.

const model_mod = @import("model.zig");
const Model = model_mod.Model;
const JobKind = model_mod.JobKind;
const SudoPhase = model_mod.SudoPhase;

pub const auth_key: u64 = 4;
pub const ping_key: u64 = 5;
pub const keepalive_timer_key: u64 = 2;

const grant_script = @embedFile("scripts/grant-sudo.sh");
const probe_script = @embedFile("scripts/probe-sudo.sh");

pub fn startKeepalive(comptime Effects: type, model: *Model, fx: *Effects, on_fire: anytype) void {
    if (model.sudo_keepalive_on) return;
    model.sudo_keepalive_on = true;
    fx.startTimer(.{
        .key = keepalive_timer_key,
        .interval_ms = 30_000,
        .mode = .repeating,
        .on_fire = on_fire,
    });
}

pub fn markActive(comptime Effects: type, model: *Model, fx: *Effects, on_fire: anytype) void {
    model.sudo_phase = .active;
    startKeepalive(Effects, model, fx, on_fire);
}

pub fn spawnPing(comptime Effects: type, fx: *Effects, on_exit: anytype) void {
    fx.spawn(.{
        .key = ping_key,
        .argv = &.{ "/usr/bin/sudo", "-n", "-v" },
        .output = .collect,
        .on_exit = on_exit,
    });
}

/// `interactive`: password dialog. Silent probe only checks existing timestamp.
pub fn spawnAuth(comptime Effects: type, model: *Model, fx: *Effects, interactive: bool, on_exit: anytype) void {
    if (model.sudo_phase.isPrompting()) return;
    if (interactive) {
        model.sudo_phase = .prompting;
    } else if (model.sudo_phase == .unknown) {
        // stay unknown while probing
    } else if (model.sudo_phase == .active) {
        return;
    }
    const script: []const u8 = if (interactive) grant_script else probe_script;
    fx.spawn(.{
        .key = auth_key,
        .argv = &.{ "/bin/bash", "-c", script },
        .output = .collect,
        .on_exit = on_exit,
    });
}

/// Take and clear any job waiting on sudo grant.
pub fn takePendingJob(model: *Model) JobKind {
    const pending = model.pending_after_sudo;
    model.pending_after_sudo = .none;
    return pending;
}

/// Pure phase transition after auth completes (no timer side effects).
pub fn applyAuthOutcome(model: *Model, granted: bool) void {
    model.sudo_phase = if (granted) .active else .inactive;
}

pub fn handleAuthDone(
    comptime Effects: type,
    model: *Model,
    fx: *Effects,
    exit_code: ?i32,
    reason_ok: bool,
    was_interactive: bool,
    on_keepalive: anytype,
) JobKind {
    const pending = takePendingJob(model);
    const granted = reason_ok and exit_code != null and exit_code.? == 0;
    if (granted) {
        markActive(Effects, model, fx, on_keepalive);
        if (was_interactive and pending == .none) {
            model.setJobSummary("Admin access active");
        }
    } else {
        applyAuthOutcome(model, false);
        if (was_interactive and pending == .none) {
            model.setJobSummary("Admin not granted");
        }
    }
    return pending;
}

pub fn handlePingDone(model: *Model, ok: bool) void {
    if (ok) {
        model.sudo_phase = .active;
    } else if (model.sudo_phase.isActive()) {
        model.sudo_phase = .inactive;
        model.appendLog("Admin session expired — grant again for system cleanup");
    }
}

/// Decide whether to start a job now, grant sudo first, or ignore (busy).
pub fn ensureThen(model: *Model, kind: JobKind) enum { start_now, grant_first, busy } {
    if (model.job_running or kind == .none) return .busy;
    if (model.sudo_phase.isPrompting()) return .busy;
    if (!kind.wantsSudo() or model.sudo_phase.isActive()) return .start_now;
    // Boot probe still in flight — don't open a second auth; run user-level.
    if (model.sudo_phase == .unknown) return .start_now;
    model.pending_after_sudo = kind;
    model.setJobSummary("Waiting for admin password…");
    return .grant_first;
}
