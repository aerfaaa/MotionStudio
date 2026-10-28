# After Effects plugin workaround: render and import

## What this workaround does

MotionStudio cannot load an After Effects `.aex`/`.plugin` binary or execute the After Effects SDK. The practical bridge is to **run the effect in desktop After Effects, render its result, then import that render as footage**. This preserves the visible result, not the plugin's controls, effect stack, expressions, or editability.

The current app's Files importer accepts video files and creates a video layer. It does not import an AE plugin binary, and it does not translate `.aep` projects.

## Route A — safest, opaque output

Use this if the effect can be rendered against its final background or if transparency is not needed.

1. In After Effects, apply the plugin and render the required shot or animation.
2. Export a video file that your iPhone/iPad can decode. H.264 MP4 is the most conservative first test.
3. Copy the MP4 to Files/iCloud Drive or another location available in the iOS Files picker.
4. In MotionStudio, open the project and choose **Add > Files**. Select the MP4; it should become a video layer.
5. Scrub the playhead and check the beginning, middle, and end. If the app reports the file as unreadable, transcode it to H.264 MP4 with the included script.

## Route B — preserve transparency (experimental)

For an overlay, export a numbered PNG sequence from After Effects with **RGB + Alpha** and **Straight (Unmatted)** alpha where the plugin/output supports it. Use a consistent sequence such as `effect_00000.png`, `effect_00001.png`, and so on.

On Windows, install FFmpeg and add `ffmpeg.exe` and `ffprobe.exe` to `PATH`. From PowerShell, run:

```powershell
.\tools\ae-plugin-bridge.ps1 `
  -InputPattern 'C:\renders\effect_%05d.png' `
  -Output 'C:\renders\effect-alpha.mov' `
  -Mode Alpha `
  -FrameRate 30
```

This creates a ProRes 4444 MOV. Adjust the folder, filename pattern, starting frame number, and frame rate to match the sequence. If the first frame is numbered 1001, add `-StartNumber 1001`.

Import the MOV through **Add > Files**, then place it over a coloured background and inspect the transparent areas. **Do not assume alpha is preserved yet:** MotionStudio currently extracts preview frames through `AVAssetImageGenerator`; its handling of ProRes alpha has not been verified on the target iOS devices. If transparency appears black, white, or opaque, the workaround is not yet sufficient for transparent overlays. A proper follow-up would use an alpha-aware `AVAssetReader` path or import the PNG sequence as a native image-sequence layer.

## Route C — convert to a portable effect

Some plugin results can be approximated using an effect already implemented in MotionStudio, or by building an independent effect with the same broad visual idea. This is a manual recreation, not plugin compatibility. A colour-grading look may sometimes be represented by a 3D LUT, but that only works when the original effect can be expressed as a colour transform; it cannot reproduce spatial distortion, particles, tracking, temporal effects, or custom geometry.

## Included converter

`tools/ae-plugin-bridge.ps1` has two modes:

- `-Mode Opaque`: numbered images → H.264 MP4 (default; best first compatibility test).
- `-Mode Alpha`: numbered images → ProRes 4444 MOV (preserves alpha in the encoded file, but app-side alpha support is unverified).

The script prints `ffprobe` stream details after encoding. This confirms the output codec and pixel format only; it does **not** prove the file works on an iPhone or that MotionStudio preserves alpha.

## Prototype test result

A local synthetic 12-frame RGBA PNG sequence was encoded to ProRes 4444 using FFmpeg. `ffprobe` reported `codec_name=prores`, `profile=4444`, and an alpha-capable `yuva444p12le` pixel format. Decoding the sample back to RGBA returned alpha values from 0 to 255, including transparent and opaque pixels. That validates the **desktop conversion step**. It does not validate import or transparency in MotionStudio, because this environment has no Xcode/iOS runtime.

## Known limitations

- The plugin itself does not run inside MotionStudio.
- The render is baked footage: plugin parameters cannot be edited in MotionStudio.
- Audio is not included by this helper; add audio separately if needed.
- Alpha MOV playback and preview must be verified on a real iOS device before relying on it.
- A PNG sequence is the lossless fallback source. The app does not yet treat a sequence as one animated layer.
