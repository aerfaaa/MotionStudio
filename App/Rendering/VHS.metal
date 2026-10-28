#include <metal_stdlib>
using namespace metal;

struct VHSUniforms {
    float intensity;
    float tracking;
    float scanlines;
    float chromaLoss;
    float noise;
    float phase;
    uint tapeMode;
    float scale;
};

static float hashNoise(uint2 p, uint phase) {
    uint n = p.x * 374761393u + p.y * 668265263u + phase * 2246822519u;
    n = (n ^ (n >> 13)) * 1274126177u;
    n ^= n >> 16;
    return float(n & 0x00FFFFFFu) / 8388607.5 - 1.0;
}

kernel void vhsKernel(texture2d<float, access::read> source [[texture(0)]],
                      texture2d<float, access::write> destination [[texture(1)]],
                      constant VHSUniforms& u [[buffer(0)]],
                      uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= source.get_width() || gid.y >= source.get_height()) return;
    int width = int(source.get_width());
    int height = int(source.get_height());
    int y = int(gid.y);
    float modeNoise = u.tapeMode == 0 ? 1.0 : (u.tapeMode == 1 ? 1.45 : 2.0);
    float modeChroma = u.tapeMode == 0 ? 1.0 : (u.tapeMode == 1 ? 0.78 : 0.55);
    float phaseWave = sin(u.phase * 0.52) * u.tracking * 0.35;
    float band = (y % 47 == 0) ? u.tracking * 2.0 : ((y % 19 == 0) ? u.tracking * 0.35 : 0.0);
    band += phaseWave;
    int shift = int(round(u.intensity * (1.5 + float(u.tapeMode) * 0.7) + band));
    int x = int(gid.x);
    int redX = clamp(x + shift, 0, width - 1);
    int blueX = clamp(x - shift, 0, width - 1);
    float4 original = source.read(gid);
    float4 redSample = source.read(uint2(redX, y));
    float4 blueSample = source.read(uint2(blueX, y));
    float grey = dot(original.rgb, float3(0.2126, 0.7152, 0.0722));
    float chroma = clamp(1.0 - u.chromaLoss * modeChroma, 0.0, 1.0);
    float grain = hashNoise(gid, uint(max(0.0, u.phase))) * u.noise * modeNoise * u.intensity * 0.12;
    float scan = (y % 2 == 0) ? 1.0 - u.scanlines * 0.32 : 1.0;
    float3 rgb;
    rgb.r = (grey + (min(1.0, redSample.r + u.intensity * 0.035) - grey) * chroma + grain) * scan;
    rgb.g = (grey + (original.g - grey) * chroma + grain * 0.72) * scan;
    rgb.b = (grey + (min(1.0, blueSample.b + u.intensity * 0.015) - grey) * chroma + grain * 0.9) * scan;
    destination.write(float4(clamp(rgb, 0.0, 1.0), original.a), gid);
}
