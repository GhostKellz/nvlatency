/**
 * nvlatency - NVIDIA Reflex & Frame Latency Tools for Linux
 *
 * C API for latency measurement and NVIDIA Reflex control.
 * Provides frame timing, latency metrics, and Reflex integration
 * via VK_NV_low_latency2.
 *
 * Usage:
 *   1. Call nvlat_init() after creating Vulkan swapchain
 *   2. Set Reflex mode with nvlat_set_reflex_mode()
 *   3. In render loop:
 *      - nvlat_begin_frame()
 *      - [game simulation]
 *      - nvlat_mark_simulation_end()
 *      - [render submission]
 *      - nvlat_mark_render_submit_start/end()
 *      - [present]
 *      - nvlat_end_frame()
 *   4. Query metrics with nvlat_get_metrics()
 *   5. Call nvlat_destroy() on cleanup
 */

#ifndef NVLATENCY_H
#define NVLATENCY_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Version */
#define NVLATENCY_VERSION_MAJOR 0
#define NVLATENCY_VERSION_MINOR 1
#define NVLATENCY_VERSION_PATCH 0

/* Opaque handle */
typedef struct nvlat_context* nvlat_ctx_t;

/* Result codes */
typedef enum {
    NVLAT_SUCCESS = 0,
    NVLAT_ERROR_NOT_SUPPORTED = -1,
    NVLAT_ERROR_INVALID_HANDLE = -2,
    NVLAT_ERROR_OUT_OF_MEMORY = -3,
    NVLAT_ERROR_UNKNOWN = -5
} nvlat_result_t;

/* Reflex modes */
typedef enum {
    NVLAT_REFLEX_OFF = 0,
    NVLAT_REFLEX_ON = 1,
    NVLAT_REFLEX_BOOST = 2
} nvlat_reflex_mode_t;

/* Frame timing data */
typedef struct {
    uint64_t frame_id;
    uint64_t simulation_us;
    uint64_t render_submit_us;
    uint64_t present_us;
    uint64_t total_us;
    uint64_t input_latency_us;
} nvlat_frame_timings_t;

/* Aggregated metrics */
typedef struct {
    uint64_t total_frames;
    uint64_t avg_frame_time_us;
    float avg_fps;
    float fps_1_low;
    uint64_t avg_input_latency_us;
} nvlat_metrics_t;

/* ============================================================================
 * Initialization
 * ============================================================================ */

/**
 * Initialize nvlatency context.
 *
 * @param device Vulkan VkDevice handle
 * @param swapchain Vulkan VkSwapchainKHR handle
 * @param get_device_proc_addr vkGetDeviceProcAddr function pointer
 * @return Context handle, or NULL on failure
 */
nvlat_ctx_t nvlat_init(
    void* device,
    uint64_t swapchain,
    void* (*get_device_proc_addr)(void*, const char*)
);

/**
 * Destroy nvlatency context.
 *
 * @param ctx Context handle
 */
void nvlat_destroy(nvlat_ctx_t ctx);

/**
 * Check if Reflex is supported.
 *
 * @param ctx Context handle
 * @return true if VK_NV_low_latency2 is available
 */
bool nvlat_is_supported(nvlat_ctx_t ctx);

/* ============================================================================
 * Reflex Control
 * ============================================================================ */

/**
 * Set Reflex mode.
 *
 * @param ctx Context handle
 * @param mode Reflex mode (off/on/boost)
 * @return NVLAT_SUCCESS or error code
 */
nvlat_result_t nvlat_set_reflex_mode(nvlat_ctx_t ctx, nvlat_reflex_mode_t mode);

/**
 * Get current Reflex mode.
 *
 * @param ctx Context handle
 * @return Current Reflex mode
 */
nvlat_reflex_mode_t nvlat_get_reflex_mode(nvlat_ctx_t ctx);

/* ============================================================================
 * Frame Marking
 * ============================================================================ */

/**
 * Begin a new frame. Call at start of game loop.
 *
 * @param ctx Context handle
 * @return Frame ID
 */
uint64_t nvlat_begin_frame(nvlat_ctx_t ctx);

/**
 * Mark input sample time. Call when sampling input.
 *
 * @param ctx Context handle
 */
void nvlat_mark_input_sample(nvlat_ctx_t ctx);

/**
 * Mark end of simulation/game logic.
 *
 * @param ctx Context handle
 */
void nvlat_mark_simulation_end(nvlat_ctx_t ctx);

/**
 * Mark start of render command submission.
 *
 * @param ctx Context handle
 */
void nvlat_mark_render_submit_start(nvlat_ctx_t ctx);

/**
 * Mark end of render command submission.
 *
 * @param ctx Context handle
 */
void nvlat_mark_render_submit_end(nvlat_ctx_t ctx);

/**
 * Mark start of present.
 *
 * @param ctx Context handle
 */
void nvlat_mark_present_start(nvlat_ctx_t ctx);

/**
 * Mark end of present.
 *
 * @param ctx Context handle
 */
void nvlat_mark_present_end(nvlat_ctx_t ctx);

/**
 * End frame and record metrics.
 *
 * @param ctx Context handle
 * @param out_timings Optional output for frame timings (can be NULL)
 */
void nvlat_end_frame(nvlat_ctx_t ctx, nvlat_frame_timings_t* out_timings);

/**
 * Reflex sleep - wait until optimal frame start.
 *
 * @param ctx Context handle
 * @param semaphore Vulkan timeline semaphore
 * @param value Semaphore value to wait for
 * @return NVLAT_SUCCESS or error code
 */
nvlat_result_t nvlat_sleep(nvlat_ctx_t ctx, uint64_t semaphore, uint64_t value);

/* ============================================================================
 * Metrics
 * ============================================================================ */

/**
 * Get aggregated metrics.
 *
 * @param ctx Context handle
 * @param out_metrics Output for metrics
 */
void nvlat_get_metrics(nvlat_ctx_t ctx, nvlat_metrics_t* out_metrics);

/**
 * Get current frame ID.
 *
 * @param ctx Context handle
 * @return Current frame ID
 */
uint64_t nvlat_get_frame_id(nvlat_ctx_t ctx);

/**
 * Reset all metrics.
 *
 * @param ctx Context handle
 */
void nvlat_reset_metrics(nvlat_ctx_t ctx);

/* ============================================================================
 * Utility
 * ============================================================================ */

/**
 * Get library version as packed uint32.
 * Format: (major << 16) | (minor << 8) | patch
 *
 * @return Version number
 */
uint32_t nvlat_get_version(void);

/**
 * Check if running on NVIDIA GPU.
 *
 * @return true if NVIDIA GPU detected
 */
bool nvlat_is_nvidia_gpu(void);

#ifdef __cplusplus
}
#endif

#endif /* NVLATENCY_H */
