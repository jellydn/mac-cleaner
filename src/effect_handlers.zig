//! Pure model mutations for Mole subprocess exits — unit-tested without Effects.

const std = @import("std");
const native_sdk = @import("native_sdk");
const model_mod = @import("model.zig");
const status_json = @import("status_json.zig");

const Model = model_mod.Model;

pub fn applyStatusExit(model: *Model, exit: native_sdk.EffectExit) void {
    model.status_loading = false;
    switch (exit.reason) {
        .exited => {
            if (exit.code == 0) {
                status_json.applyStatusJson(model, exit.output) catch {
                    model.status_error = true;
                    model.health_msg.set("Failed to parse status JSON");
                };
            } else {
                model.status_error = true;
                if (exit.stderr_tail.len > 0) {
                    model.health_msg.set(exit.stderr_tail);
                } else {
                    model.health_msg.set("mole status failed");
                }
            }
        },
        .rejected, .spawn_failed => {
            model.status_error = true;
            model.health_msg.set("Could not run mole — is it installed?");
        },
        .cancelled, .signaled => {},
    }
}

pub fn applyHistoryExit(model: *Model, exit: native_sdk.EffectExit) void {
    model.history_loading = false;
    switch (exit.reason) {
        .exited => {
            if (exit.code == 0) {
                status_json.applyHistoryJson(model, exit.output) catch {
                    model.history_error = true;
                };
            } else {
                model.history_error = true;
            }
        },
        .rejected, .spawn_failed => model.history_error = true,
        .cancelled, .signaled => {},
    }
}

/// Applies job exit to the model. Returns true when status+history should refresh
/// (exited + job.refreshesAfter()), matching prior update.zig behavior.
pub fn applyJobExit(model: *Model, exit: native_sdk.EffectExit) bool {
    model.job_running = false;
    var should_refresh = false;
    switch (exit.reason) {
        .exited => {
            if (exit.code == 0) {
                model.setJobSummary("Finished successfully");
                model.appendLog("Done");
            } else {
                var buf: [160]u8 = undefined;
                const msg_text = std.fmt.bufPrint(&buf, "Exit code {d}", .{exit.code}) catch "Failed";
                model.setJobSummary(msg_text);
                model.appendLog(msg_text);
                if (exit.stderr_tail.len > 0) model.appendLog(exit.stderr_tail);
            }
            if (model.job.refreshesAfter()) should_refresh = true;
        },
        .cancelled => {
            model.setJobSummary("Cancelled");
            model.appendLog("Cancelled");
        },
        .rejected, .spawn_failed => {
            model.setJobSummary("Could not start mole");
            model.appendLog("Could not start mole — check install path");
        },
        .signaled => {
            model.setJobSummary("Terminated by signal");
            model.appendLog("Terminated by signal");
        },
    }
    return should_refresh;
}
