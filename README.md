# nvlatency

**NVIDIA Reflex & Frame Latency Tools for Linux**

A comprehensive toolkit for measuring, analyzing, and reducing input-to-display latency on NVIDIA GPUs under Linux. Brings Windows-level Reflex functionality to the Linux gaming ecosystem.

## Driver 590+ Optimizations

nvlatency is optimized for NVIDIA 590.48.01+ drivers which include:
- **Vulkan swapchain recreation performance** - Enables stutter-free latency marker injection during window resize/mode changes
- **Improved VK_NV_low_latency2 behavior** - More reliable Reflex integration
- **Better Wayland support** - Full functionality on modern Wayland compositors (1.20+)

## Overview

nvlatency provides:

- **Frame Latency Measurement** - Precise end-to-end latency tracking
- **NVIDIA Reflex Integration** - Low latency mode via VK_NV_low_latency2
- **Latency Visualization** - Real-time overlay and logging
- **Game Integration** - Automatic injection for supported games
- **Benchmarking Tools** - Comparative latency analysis

## Features

### Latency Metrics

```
┌─────────────────────────────────────────────────────────────┐
│                    Latency Pipeline                          │
├──────────┬──────────┬──────────┬──────────┬────────────────┤
│  Input   │   Sim    │  Render  │  Driver  │    Display     │
│  2.1ms   │  4.2ms   │  8.3ms   │  1.2ms   │    6.7ms       │
├──────────┴──────────┴──────────┴──────────┴────────────────┤
│              Total: 22.5ms (44.4 FPS equivalent)            │
└─────────────────────────────────────────────────────────────┘
```

### Supported Modes

| Mode | Description | Latency Reduction |
|------|-------------|-------------------|
| **Off** | Standard rendering | Baseline |
| **On** | Basic low latency | ~15-20% |
| **On + Boost** | Aggressive GPU scheduling | ~25-35% |
| **Ultra** | Maximum responsiveness | ~40-50%* |

*May reduce FPS in GPU-bound scenarios

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      nvlatency                               │
├─────────────┬─────────────┬─────────────┬──────────────────┤
│   measure   │   reflex    │   overlay   │     inject       │
│  (capture)  │  (control)  │   (visual)  │    (games)       │
├─────────────┴─────────────┴─────────────┴──────────────────┤
│                    nvvk (C ABI)                              │
├─────────────────────────────────────────────────────────────┤
│              VK_NV_low_latency2 Extension                    │
└─────────────────────────────────────────────────────────────┘
```

## Usage

### CLI Tool

```bash
# Check current latency mode
nvlatency status

# Enable Reflex mode
nvlatency enable --mode boost

# Measure latency for a game
nvlatency measure --pid $(pgrep game)

# Run game with latency monitoring
nvlatency run -- ./game.exe

# Benchmark comparison
nvlatency benchmark --duration 60 --modes off,on,boost
```

### Library API (Zig)

```zig
const nvlatency = @import("nvlatency");

pub fn main() !void {
    var ctx = try nvlatency.init(.{
        .mode = .boost,
        .target_fps = 144,
    });
    defer ctx.deinit();

    while (running) {
        ctx.markSimulationStart();
        // ... game simulation ...

        ctx.markRenderStart();
        // ... rendering ...

        ctx.markPresentStart();
        // ... present ...

        try ctx.sleep(); // Optimal frame pacing

        const metrics = ctx.getLatencyMetrics();
        std.log.info("Frame latency: {d:.1}ms", .{metrics.total_ms});
    }
}
```

### C API

```c
#include <nvlatency/nvlatency.h>

nvlatency_ctx_t* ctx = nvlatency_init(NVLATENCY_MODE_BOOST);

// In render loop
nvlatency_mark(ctx, NVLATENCY_MARKER_SIM_START);
// ... simulation ...
nvlatency_mark(ctx, NVLATENCY_MARKER_RENDER_START);
// ... render ...
nvlatency_mark(ctx, NVLATENCY_MARKER_PRESENT_START);
// ... present ...
nvlatency_sleep(ctx);

nvlatency_metrics_t metrics;
nvlatency_get_metrics(ctx, &metrics);
printf("Latency: %.1fms\n", metrics.total_ms);
```

## Building

```bash
# Build CLI and library
zig build -Doptimize=ReleaseFast

# Build with overlay support (requires Vulkan layer)
zig build -Doptimize=ReleaseFast -Doverlay=true

# Run tests
zig build test
```

## Installation

```bash
# System-wide install
sudo zig build install --prefix /usr/local

# User install
zig build install --prefix ~/.local

# Install Vulkan layer for overlay
sudo cp vulkan/nvlatency_layer.json /etc/vulkan/implicit_layer.d/
```

## Integration with Steam/Proton

```bash
# Add to Steam launch options
NVLATENCY_MODE=boost %command%

# Or use nvlatency wrapper
nvlatency run --mode boost -- %command%
```

## Related Projects

| Project | Purpose | Integration |
|---------|---------|-------------|
| **nvvk** | Vulkan extension library | Core dependency |
| **nvcontrol** | GUI control center | Visual latency config |
| **nvsync** | VRR/G-Sync manager | Frame timing coordination |
| **nvproton** | Proton integration | Automatic game injection |

## Requirements

- NVIDIA GPU (GTX 900 series or newer for Reflex)
- NVIDIA driver 590+ (recommended for swapchain performance fixes)
  - Minimum: 535+ (basic functionality)
- Vulkan 1.3+
- Zig 0.16+

## License

MIT License - See [LICENSE](LICENSE)

## Contributing

See [TODO.md](TODO.md) for the development roadmap.
