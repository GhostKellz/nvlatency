//! High-precision timing infrastructure for latency measurement
//!
//! Provides nanosecond-precision timing using CLOCK_MONOTONIC
//! for accurate frame timing and latency calculations.

const std = @import("std");
const posix = std.posix;

/// Get current time in nanoseconds from monotonic clock
fn getNanoTime() i128 {
    const ts = posix.clock_gettime(.MONOTONIC) catch return 0;
    return @as(i128, ts.sec) * 1_000_000_000 + ts.nsec;
}

/// High-precision timer using monotonic clock
pub const Timer = struct {
    start_time: i128 = 0,

    /// Start or restart the timer
    pub fn start(self: *Timer) void {
        self.start_time = getNanoTime();
    }

    /// Get elapsed time in nanoseconds since start
    pub fn elapsedNs(self: *const Timer) u64 {
        const now = getNanoTime();
        const elapsed = now - self.start_time;
        return if (elapsed < 0) 0 else @intCast(elapsed);
    }

    /// Get elapsed time in microseconds
    pub fn elapsedUs(self: *const Timer) u64 {
        return self.elapsedNs() / 1000;
    }

    /// Get elapsed time in milliseconds
    pub fn elapsedMs(self: *const Timer) f64 {
        return @as(f64, @floatFromInt(self.elapsedNs())) / 1_000_000.0;
    }

    /// Get elapsed time and restart timer (lap)
    pub fn lap(self: *Timer) u64 {
        const elapsed = self.elapsedNs();
        self.start();
        return elapsed;
    }
};

/// Timestamp capture for frame events
pub const Timestamp = struct {
    time_ns: i128,

    pub fn now() Timestamp {
        return .{ .time_ns = getNanoTime() };
    }

    pub fn zero() Timestamp {
        return .{ .time_ns = 0 };
    }

    pub fn isValid(self: Timestamp) bool {
        return self.time_ns > 0;
    }

    /// Calculate duration to another timestamp in nanoseconds
    pub fn durationTo(self: Timestamp, other: Timestamp) u64 {
        if (other.time_ns <= self.time_ns) return 0;
        return @intCast(other.time_ns - self.time_ns);
    }

    /// Calculate duration to another timestamp in microseconds
    pub fn durationToUs(self: Timestamp, other: Timestamp) u64 {
        return self.durationTo(other) / 1000;
    }

    /// Calculate duration to another timestamp in milliseconds
    pub fn durationToMs(self: Timestamp, other: Timestamp) f64 {
        return @as(f64, @floatFromInt(self.durationTo(other))) / 1_000_000.0;
    }
};

/// Frame timing capture points
pub const FrameTimestamps = struct {
    frame_id: u64 = 0,

    // Input → Simulation → Render Submit → Present → Display
    input_sample: Timestamp = Timestamp.zero(),
    simulation_start: Timestamp = Timestamp.zero(),
    simulation_end: Timestamp = Timestamp.zero(),
    render_submit_start: Timestamp = Timestamp.zero(),
    render_submit_end: Timestamp = Timestamp.zero(),
    present_start: Timestamp = Timestamp.zero(),
    present_end: Timestamp = Timestamp.zero(),

    /// Reset all timestamps for new frame
    pub fn reset(self: *FrameTimestamps, frame_id: u64) void {
        self.* = .{ .frame_id = frame_id };
    }

    /// Calculate simulation time (game logic)
    pub fn simulationTimeUs(self: *const FrameTimestamps) u64 {
        if (!self.simulation_start.isValid() or !self.simulation_end.isValid()) return 0;
        return self.simulation_start.durationToUs(self.simulation_end);
    }

    /// Calculate render submit time (GPU work submission)
    pub fn renderSubmitTimeUs(self: *const FrameTimestamps) u64 {
        if (!self.render_submit_start.isValid() or !self.render_submit_end.isValid()) return 0;
        return self.render_submit_start.durationToUs(self.render_submit_end);
    }

    /// Calculate present time
    pub fn presentTimeUs(self: *const FrameTimestamps) u64 {
        if (!self.present_start.isValid() or !self.present_end.isValid()) return 0;
        return self.present_start.durationToUs(self.present_end);
    }

    /// Calculate total frame time (simulation start to present end)
    pub fn totalFrameTimeUs(self: *const FrameTimestamps) u64 {
        if (!self.simulation_start.isValid() or !self.present_end.isValid()) return 0;
        return self.simulation_start.durationToUs(self.present_end);
    }

    /// Calculate input-to-render latency (if input was sampled)
    pub fn inputToRenderUs(self: *const FrameTimestamps) u64 {
        if (!self.input_sample.isValid() or !self.render_submit_end.isValid()) return 0;
        return self.input_sample.durationToUs(self.render_submit_end);
    }
};

/// Rolling average calculator for latency metrics
pub fn RollingAverage(comptime size: usize) type {
    return struct {
        const Self = @This();

        samples: [size]u64 = [_]u64{0} ** size,
        index: usize = 0,
        count: usize = 0,

        /// Add a new sample
        pub fn add(self: *Self, value: u64) void {
            self.samples[self.index] = value;
            self.index = (self.index + 1) % size;
            if (self.count < size) self.count += 1;
        }

        /// Get the average of all samples
        pub fn average(self: *const Self) u64 {
            if (self.count == 0) return 0;
            var sum: u64 = 0;
            for (self.samples[0..self.count]) |s| {
                sum += s;
            }
            return sum / self.count;
        }

        /// Get minimum sample
        pub fn min(self: *const Self) u64 {
            if (self.count == 0) return 0;
            var m: u64 = std.math.maxInt(u64);
            for (self.samples[0..self.count]) |s| {
                if (s < m) m = s;
            }
            return m;
        }

        /// Get maximum sample
        pub fn max(self: *const Self) u64 {
            if (self.count == 0) return 0;
            var m: u64 = 0;
            for (self.samples[0..self.count]) |s| {
                if (s > m) m = s;
            }
            return m;
        }

        /// Get the 1% low (worst 1%)
        pub fn percentile1Low(self: *const Self) u64 {
            if (self.count == 0) return 0;
            // For simplicity, return max (actual percentile needs sorting)
            return self.max();
        }

        /// Reset all samples
        pub fn reset(self: *Self) void {
            self.* = .{};
        }
    };
}

// =============================================================================
// Tests
// =============================================================================

test "Timer basic" {
    const io = std.testing.io;
    var timer = Timer{};
    timer.start();

    // Sleep a tiny bit using proper Io-based sleep
    try std.Io.Clock.Duration.sleep(.{ .clock = .awake, .raw = .fromMilliseconds(1) }, io);

    const elapsed = timer.elapsedUs();
    try std.testing.expect(elapsed >= 900); // At least 0.9ms
    try std.testing.expect(elapsed < 10_000); // Less than 10ms
}

test "Timestamp duration" {
    const io = std.testing.io;
    const t1 = Timestamp.now();
    try std.Io.Clock.Duration.sleep(.{ .clock = .awake, .raw = .fromMilliseconds(1) }, io);
    const t2 = Timestamp.now();

    const duration_us = t1.durationToUs(t2);
    try std.testing.expect(duration_us >= 900);
    try std.testing.expect(duration_us < 10_000);
}

test "RollingAverage" {
    var avg = RollingAverage(4){};

    avg.add(100);
    avg.add(200);
    avg.add(300);
    avg.add(400);

    try std.testing.expectEqual(@as(u64, 250), avg.average());
    try std.testing.expectEqual(@as(u64, 100), avg.min());
    try std.testing.expectEqual(@as(u64, 400), avg.max());
}
