//! Parse Mole `status --json` / `history --json` into the Model.

const std = @import("std");
const model_mod = @import("model.zig");
const Model = model_mod.Model;
const ProcessRow = model_mod.ProcessRow;
const HistoryRow = model_mod.HistoryRow;

pub fn applyStatusJson(self: *Model, json_bytes: []const u8) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, json_bytes, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    const root = parsed.value;
    if (root != .object) return error.InvalidStatus;

    if (root.object.get("health_score")) |v| {
        self.health_score = asI32(v) orelse self.health_score;
    }
    if (stringField(root, "health_score_msg")) |s| self.health_msg.set(s);
    if (stringField(root, "host")) |s| self.host.set(s);
    if (stringField(root, "uptime")) |s| self.uptime.set(s);
    if (stringField(root, "collected_at")) |s| self.collected_at.set(s);

    if (root.object.get("hardware")) |hw| {
        if (hw == .object) {
            const model_s = stringField(hw, "model") orelse "";
            const cpu_s = stringField(hw, "cpu_model") orelse "";
            var buf: [64]u8 = undefined;
            const label = if (model_s.len > 0 and cpu_s.len > 0)
                std.fmt.bufPrint(&buf, "{s} · {s}", .{ model_s, cpu_s }) catch model_s
            else if (model_s.len > 0) model_s else cpu_s;
            if (label.len > 0) self.hardware.set(label);
        }
    }

    if (root.object.get("trash_size")) |t| {
        self.trash_gb = @floatCast(jsonNumber(t) / (1024.0 * 1024.0 * 1024.0));
    }

    if (root.object.get("cpu")) |cpu| {
        if (cpu == .object) {
            if (cpu.object.get("usage")) |u| self.cpu_pct = asF32(u) orelse self.cpu_pct;
            if (cpu.object.get("load1")) |l| self.load1 = asF32(l) orelse self.load1;
        }
    }
    if (root.object.get("memory")) |mem| {
        if (mem == .object) {
            if (mem.object.get("used_percent")) |u| self.mem_pct = asF32(u) orelse self.mem_pct;
        }
    }

    if (root.object.get("disks")) |disks| {
        if (disks == .array) {
            if (pickRootDisk(disks.array.items)) |chosen| {
                if (chosen.object.get("used_percent")) |u| {
                    self.disk_pct = asF32(u) orelse self.disk_pct;
                }
                const used = jsonNumber(chosen.object.get("used"));
                const total = jsonNumber(chosen.object.get("total"));
                if (total > 0) {
                    self.disk_total_gb = @floatCast(total / (1024.0 * 1024.0 * 1024.0));
                    self.disk_free_gb = @floatCast((total - used) / (1024.0 * 1024.0 * 1024.0));
                }
            }
        }
    }

    if (root.object.get("batteries")) |bats| {
        if (bats == .array and bats.array.items.len > 0 and bats.array.items[0] == .object) {
            const b = bats.array.items[0];
            if (b.object.get("percent")) |p| self.battery_pct = asF32(p) orelse self.battery_pct;
            if (stringField(b, "status")) |s| self.battery_status.set(s);
        }
    }

    if (root.object.get("top_processes")) |procs| {
        if (procs == .array) {
            self.top_process_count = 0;
            for (procs.array.items) |p| {
                if (self.top_process_count >= self.top_processes.len) break;
                if (p != .object) continue;
                var row: ProcessRow = .{};
                if (stringField(p, "name")) |n| row.name.set(n);
                if (p.object.get("cpu")) |c| row.cpu = asF32(c) orelse 0;
                if (p.object.get("memory_bytes")) |m| {
                    row.memory_mb = @floatCast(jsonNumber(m) / (1024.0 * 1024.0));
                } else if (p.object.get("memory")) |m| {
                    row.memory_mb = asF32(m) orelse 0;
                }
                self.top_processes[self.top_process_count] = row;
                self.top_process_count += 1;
            }
        }
    }
    self.status_error = false;
}

pub fn applyHistoryJson(self: *Model, json_bytes: []const u8) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, json_bytes, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    const root = parsed.value;
    if (root != .object) return error.InvalidHistory;

    self.history_count = 0;
    const sessions = root.object.get("sessions") orelse return;
    if (sessions != .array) return;

    for (sessions.array.items) |s| {
        if (self.history_count >= self.history.len) break;
        if (s != .object) continue;
        var row: HistoryRow = .{};
        if (stringField(s, "command")) |c| row.command.set(c);
        if (stringField(s, "started_at")) |t| row.when.set(t);
        if (stringField(s, "size")) |sz| row.size.set(sz);
        if (s.object.get("items")) |it| {
            row.items = asU32(it) orelse 0;
        }
        if (s.object.get("actions")) |actions| {
            if (actions == .object) {
                if (actions.object.get("removed")) |r| {
                    row.removed = asU32(r) orelse 0;
                }
            }
        }
        self.history[self.history_count] = row;
        self.history_count += 1;
    }
    self.history_error = false;
}

/// Prefer internal root mount `/` over external volumes.
pub fn pickRootDisk(items: []const std.json.Value) ?std.json.Value {
    if (items.len == 0) return null;
    // Prefer `/` that is not marked external.
    for (items) |d| {
        if (d != .object) continue;
        const mount = d.object.get("mount") orelse continue;
        if (mount != .string or !std.mem.eql(u8, mount.string, "/")) continue;
        const external = d.object.get("external");
        if (external == null or (external.? == .bool and external.?.bool == false)) return d;
    }
    // Any `/` mount.
    for (items) |d| {
        if (d != .object) continue;
        const mount = d.object.get("mount") orelse continue;
        if (mount == .string and std.mem.eql(u8, mount.string, "/")) return d;
    }
    return if (items[0] == .object) items[0] else null;
}

fn stringField(v: std.json.Value, key: []const u8) ?[]const u8 {
    if (v != .object) return null;
    const field = v.object.get(key) orelse return null;
    return if (field == .string) field.string else null;
}

fn jsonNumber(v: ?std.json.Value) f64 {
    const val = v orelse return 0;
    return switch (val) {
        .float => |f| f,
        .integer => |i| @floatFromInt(i),
        .number_string => |s| std.fmt.parseFloat(f64, s) catch 0,
        else => 0,
    };
}

fn asF32(v: std.json.Value) ?f32 {
    return switch (v) {
        .float => |f| @floatCast(f),
        .integer => |i| @floatFromInt(i),
        .number_string => |s| @floatCast(std.fmt.parseFloat(f64, s) catch return null),
        else => null,
    };
}

fn asI32(v: std.json.Value) ?i32 {
    return switch (v) {
        .integer => |i| @intCast(i),
        .float => |f| @intFromFloat(f),
        else => null,
    };
}

fn asU32(v: std.json.Value) ?u32 {
    return switch (v) {
        .integer => |i| @intCast(@max(i, 0)),
        else => null,
    };
}

test "pickRootDisk prefers internal root" {
    const sample =
        \\[
        \\  {"mount":"/Volumes/X","external":true,"used_percent":10},
        \\  {"mount":"/","external":false,"used_percent":80,"used":1,"total":2}
        \\]
    ;
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, sample, .{});
    defer parsed.deinit();
    const chosen = pickRootDisk(parsed.value.array.items).?;
    try std.testing.expectEqualStrings("/", chosen.object.get("mount").?.string);
}
