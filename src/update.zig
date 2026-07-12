//! TEA update + boot for Mac Cleaner.

const native_sdk = @import("native_sdk");
const model_mod = @import("model.zig");
const mole = @import("mole.zig");
const sudo = @import("sudo.zig");
const effect_handlers = @import("effect_handlers.zig");

pub const Model = model_mod.Model;
pub const Tab = model_mod.Tab;
pub const JobKind = model_mod.JobKind;

pub const Msg = union(enum) {
    set_tab: Tab,
    refresh_status,
    refresh_history,
    start_clean_dry,
    start_clean_run,
    confirm_pending_job,
    cancel_confirm,
    start_optimize_dry,
    start_optimize_run,
    start_purge_dry,
    start_purge_run,
    grant_sudo,
    cancel_job,
    status_done: native_sdk.EffectExit,
    history_done: native_sdk.EffectExit,
    job_line: native_sdk.EffectLine,
    job_done: native_sdk.EffectExit,
    sudo_auth_done: native_sdk.EffectExit,
    sudo_ping_done: native_sdk.EffectExit,
    refresh_tick: native_sdk.EffectTimer,
    sudo_keepalive_tick: native_sdk.EffectTimer,
    chrome_changed: native_sdk.WindowChrome,

    pub const view_unbound = .{
        "status_done",
        "history_done",
        "job_line",
        "job_done",
        "sudo_auth_done",
        "sudo_ping_done",
        "refresh_tick",
        "sudo_keepalive_tick",
        "chrome_changed",
    };
};

const refresh_timer_key: u64 = 1;

/// Interactive grant sets `.prompting`; silent boot probe leaves `.unknown`.
fn wasInteractiveAuth(model: *const Model) bool {
    return model.sudo_phase == .prompting;
}

pub fn makeUpdate(comptime Effects: type) type {
    return struct {
        pub fn boot(model: *Model, fx: *Effects) void {
            var path_buf: [mole.max_path_bytes]u8 = undefined;
            const resolved = mole.resolveMole(&path_buf);
            if (resolved.found) {
                mole.markMoleAvailable(model, resolved.path);
                mole.spawnStatus(Effects, model, fx, Effects.exitMsg(.status_done));
                mole.spawnHistory(Effects, model, fx, Effects.exitMsg(.history_done));
            } else {
                mole.applyMoleMissing(model);
            }
            // Adopt existing sudo timestamp without a dialog.
            sudo.spawnAuth(Effects, model, fx, false, Effects.exitMsg(.sudo_auth_done));
            fx.startTimer(.{
                .key = refresh_timer_key,
                .interval_ms = 45_000,
                .mode = .repeating,
                .on_fire = Effects.timerMsg(.refresh_tick),
            });
        }

        pub fn update(model: *Model, msg: Msg, fx: *Effects) void {
            switch (msg) {
                .set_tab => |tab| {
                    model.tab = tab;
                    if (tab == .history and model.history_count == 0 and !model.history_loading) {
                        mole.spawnHistory(Effects, model, fx, Effects.exitMsg(.history_done));
                    }
                },
                .refresh_status => mole.spawnStatus(Effects, model, fx, Effects.exitMsg(.status_done)),
                .refresh_history => mole.spawnHistory(Effects, model, fx, Effects.exitMsg(.history_done)),
                .start_clean_dry => requestJob(model, fx, .clean_dry),
                .start_clean_run => requestJob(model, fx, .clean_run),
                .start_optimize_dry => requestJob(model, fx, .optimize_dry),
                .start_optimize_run => requestJob(model, fx, .optimize_run),
                .start_purge_dry => requestJob(model, fx, .purge_dry),
                .start_purge_run => requestJob(model, fx, .purge_run),
                .confirm_pending_job => {
                    const pending = model.confirm_job;
                    model.confirm_job = .none;
                    if (pending != .none) ensureSudoThenStartJob(model, fx, pending);
                },
                .cancel_confirm => model.confirm_job = .none,
                .grant_sudo => {
                    if (model.sudo_phase.isActive() or model.sudo_phase.isPrompting()) return;
                    model.pending_after_sudo = .none;
                    sudo.spawnAuth(Effects, model, fx, true, Effects.exitMsg(.sudo_auth_done));
                },
                .cancel_job => mole.cancelJob(Effects, model, fx),
                .status_done => |exit| effect_handlers.applyStatusExit(model, exit),
                .history_done => |exit| effect_handlers.applyHistoryExit(model, exit),
                .job_line => |line| model.appendLog(line.line),
                .job_done => |exit| {
                    if (effect_handlers.applyJobExit(model, exit)) {
                        mole.spawnStatus(Effects, model, fx, Effects.exitMsg(.status_done));
                        mole.spawnHistory(Effects, model, fx, Effects.exitMsg(.history_done));
                    }
                },
                .sudo_auth_done => |exit| onSudoAuthDone(model, fx, exit),
                .sudo_ping_done => |exit| {
                    const ok = exit.reason == .exited and exit.code == 0;
                    sudo.handlePingDone(model, ok);
                },
                .refresh_tick => |timer| {
                    if (timer.outcome == .fired and !model.status_loading and !model.job_running) {
                        mole.spawnStatus(Effects, model, fx, Effects.exitMsg(.status_done));
                    }
                },
                .sudo_keepalive_tick => |timer| {
                    if (timer.outcome == .fired and model.sudo_phase.isActive() and !model.sudo_phase.isPrompting()) {
                        sudo.spawnPing(Effects, fx, Effects.exitMsg(.sudo_ping_done));
                    }
                },
                .chrome_changed => |chrome| {
                    model.chrome_leading = chrome.insets.left;
                    model.header_height = @max(44, chrome.insets.top);
                },
            }
        }

        fn requestJob(model: *Model, fx: *Effects, kind: JobKind) void {
            if (model.job_running or model.sudo_phase.isPrompting()) return;
            if (kind.needsConfirm()) {
                model.confirm_job = kind;
                return;
            }
            ensureSudoThenStartJob(model, fx, kind);
        }

        fn ensureSudoThenStartJob(model: *Model, fx: *Effects, kind: JobKind) void {
            switch (sudo.ensureThen(model, kind)) {
                .busy => {},
                .start_now => mole.spawnJob(
                    Effects,
                    model,
                    fx,
                    kind,
                    Effects.lineMsg(.job_line),
                    Effects.exitMsg(.job_done),
                ),
                .grant_first => sudo.spawnAuth(Effects, model, fx, true, Effects.exitMsg(.sudo_auth_done)),
            }
        }

        fn onSudoAuthDone(model: *Model, fx: *Effects, exit: native_sdk.EffectExit) void {
            const interactive = wasInteractiveAuth(model);
            const reason_ok = exit.reason == .exited;
            const code: ?i32 = if (reason_ok) exit.code else null;
            const pending = sudo.handleAuthDone(
                Effects,
                model,
                fx,
                code,
                reason_ok,
                interactive,
                Effects.timerMsg(.sudo_keepalive_tick),
            );
            // Log only for interactive auth; job start owns the log after clearLog.
            if (interactive and pending == .none) {
                if (model.sudo_phase.isActive()) {
                    model.appendLog("Admin access granted for this session");
                } else if (reason_ok and code != null and code.? == 2) {
                    model.appendLog("Admin dialog cancelled");
                } else if (!model.sudo_phase.isActive()) {
                    model.appendLog("Admin authentication failed");
                }
            }
            if (pending != .none) {
                mole.spawnJob(
                    Effects,
                    model,
                    fx,
                    pending,
                    Effects.lineMsg(.job_line),
                    Effects.exitMsg(.job_done),
                );
            }
        }
    };
}
