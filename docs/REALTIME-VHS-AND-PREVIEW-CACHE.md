# Real-time VHS effect and preview caching

This change adds a Metal compute fast path for the existing VHS effect while retaining the
MotionCore CPU processor as a fallback. The effect now exposes intensity, tracking distortion,
scanline strength, chroma loss, tape noise, and SP/LP/EP tape-speed settings.

## Preview cache behaviour

- Processed frames are keyed by source identity, resolved effect values, and a 12 fps animation
  phase for VHS/noise. A changed setting naturally produces a different cache key, so stale output
  is not reused for the edited settings.
- A processed-frame cache hit is checked before asking for the decoded source again. This means a
  processed result can still be reused after its source frame leaves the smaller decode cache.
- The processed cache is bounded to 120 entries and 96 MiB; it is an in-memory preview cache, not
  a permanent disk cache. A first pass caches frames as they are requested. A second pass can reuse
  frames that remain in the cache; frames evicted under memory pressure must be rendered again.
- The video source decoder still uses asynchronous `AVAssetImageGenerator` requests and deliberately
  coalesces stale requests. This is not yet a full After Effects-style sequential pre-render queue,
  and it does not guarantee that every frame of a long composition is cached after one playback.

## Important limitations

The Metal effect is GPU-accelerated, but its current bridge converts the `CGImage` to a Metal
texture and reads the result back to a `CGImage` because the current preview canvas consumes images.
That upload/readback can be a bottleneck. A future rendering-engine improvement should keep frames as
`CVPixelBuffer`/`MTLTexture` through preview composition and add a bounded sequential pre-render queue
with explicit cache invalidation/dependency tracking. A native iOS build and device profiling are
required to verify Metal shader compilation, visual quality, frame pacing, and memory use.
