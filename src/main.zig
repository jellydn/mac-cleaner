//! Mac Cleaner — native UI over the [Mole](https://mole.fit) CLI.
//! Wiring only: Model/Msg/update live in sibling modules.

const std = @import("std");
const runner = @import("runner");
const native_sdk = @import("native_sdk");

pub const panic = std.debug.FullPanic(native_sdk.debug.capturePanic);

const canvas = native_sdk.canvas;
const geometry = native_sdk.geometry;

const model_mod = @import("model.zig");
const update_mod = @import("update.zig");
const mole = @import("mole.zig");

pub const Model = model_mod.Model;
pub const Tab = model_mod.Tab;
pub const JobKind = model_mod.JobKind;
pub const SudoPhase = model_mod.SudoPhase;
pub const ProcessRow = model_mod.ProcessRow;
pub const HistoryRow = model_mod.HistoryRow;
pub const LogLine = model_mod.LogLine;
pub const Msg = update_mod.Msg;

const canvas_label = "main-canvas";
const window_width: f32 = 780;
const window_height: f32 = 620;

const app_permissions = [_][]const u8{ native_sdk.security.permission_command, native_sdk.security.permission_view };
const shell_views = [_]native_sdk.ShellView{
    .{ .label = canvas_label, .kind = .gpu_surface, .fill = true, .role = "Mac Cleaner canvas", .accessibility_label = "Mac Cleaner", .gpu_backend = .metal, .gpu_pixel_format = .bgra8_unorm, .gpu_present_mode = .timer, .gpu_alpha_mode = .@"opaque", .gpu_color_space = .srgb, .gpu_vsync = true },
};
const shell_windows = [_]native_sdk.ShellWindow{.{
    .label = "main",
    .title = "Mac Cleaner",
    .width = window_width,
    .height = window_height,
    .restore_state = false,
    .views = &shell_views,
}};
const shell_scene: native_sdk.ShellConfig = .{ .windows = &shell_windows };

const CleanerApp = native_sdk.UiApp(Model, Msg);
const Effects = CleanerApp.Effects;
const Loop = update_mod.makeUpdate(Effects);

pub const AppUi = canvas.Ui(Msg);
pub const app_markup = @embedFile("app.native");

pub fn initialModel() Model {
    var m: Model = .{};
    var path_buf: [mole.max_path_bytes]u8 = undefined;
    const resolved = mole.resolveMole(&path_buf);
    if (resolved.found) {
        mole.markMoleAvailable(&m, resolved.path);
    } else {
        mole.applyMoleMissing(&m);
    }
    return m;
}

/// Re-export for tests that parse Mole JSON.
pub const applyStatusJson = @import("status_json.zig").applyStatusJson;
pub const applyHistoryJson = @import("status_json.zig").applyHistoryJson;

pub fn main(init: std.process.Init) !void {
    const app_state = try CleanerApp.create(std.heap.page_allocator, .{
        .name = "mac-cleaner",
        .scene = shell_scene,
        .canvas_label = canvas_label,
        .update_fx = Loop.update,
        .init_fx = Loop.boot,
        .markup = .{ .source = app_markup, .watch_path = "src/app.native", .io = init.io },
    });
    defer app_state.destroy();
    app_state.model = initialModel();

    try runner.runWithOptions(app_state.app(), .{
        .app_name = "mac-cleaner",
        .window_title = "Mac Cleaner",
        .bundle_id = "dev.native_sdk.mac-cleaner",
        .icon_path = "assets/icon.png",
        .default_frame = geometry.RectF.init(0, 0, window_width, window_height),
        .restore_state = false,
        .js_window_api = false,
        .security = .{
            .permissions = &app_permissions,
            .navigation = .{ .allowed_origins = &.{ "zero://inline", "zero://app" } },
        },
    }, init);
}

test {
    _ = @import("tests.zig");
    _ = @import("bounded_str.zig");
    _ = @import("status_json.zig");
    _ = @import("effect_handlers.zig");
    _ = @import("mole.zig");
}
