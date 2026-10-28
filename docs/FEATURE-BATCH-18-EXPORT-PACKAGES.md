# Batch 18 — GIF, image sequence, and portable project packages

## Added

- **Animated GIF export** renders the full composition one frame at a time through the same frame renderer used by MP4 export, and writes frames incrementally with ImageIO. The GIF loops indefinitely and uses the composition frame rate for frame delay.
- **PNG image sequence export** renders `frame-000000.png`, `frame-000001.png`, etc., adds `sequence.json` with dimensions and frame rate, and packages the sequence as a ZIP file.
- **MotionStudio project package export** creates a `.motionpack` ZIP containing `project.json` and the project's `media/` folder.
- **Project package import** is available from the home screen's `+` menu. It validates the archive paths and CRCs, decodes and validates `project.json`, copies media into a new local project folder, and opens the imported project.
- ZIP archive creation streams file payloads to disk and uses the ZIP store method to avoid requiring third-party dependencies or loading an entire image sequence archive into RAM.

## Interoperability note

Alight Motion's editable project interchange is XML / its own project-package workflow, not HTML. `.motionpack` is MotionStudio's own portable format and is only intended to round-trip between MotionStudio versions that support this package format. Alight Motion XML import/export is not claimed here. A real XML export from the user's version of Alight Motion is needed to map layer types, keyframes, assets, and effects accurately; unknown effects should be reported rather than silently treated as equivalent.

## Limitations

- GIF has no audio and can become very large for long, high-resolution compositions. For sharing, use a short composition or lower dimensions/frame rate first.
- PNG sequence export does not include audio. It exports full-resolution PNGs and a manifest, packaged into a ZIP.
- ZIP packages use the uncompressed ZIP store method and classic ZIP limits (maximum 65,535 entries and 4 GiB per archive). The archive reader only accepts this app's stored-entry format, not arbitrary compressed ZIP files.
- The `.motionpack` archive includes source project media, but does not include transient preview-cache files.
- Full iOS compilation and physical-device export/import tests still require an Xcode/iOS build environment.
