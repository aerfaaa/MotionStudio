# Feature Batch 2: Transform panel and alignment guides

This batch builds on Feature Batch 1.

## Added
- The bottom editor panel labels the layer-property tab **Transform**.
- A **Size (px)** row lets users resize the selected layer by entering width and height. The existing linked-scale control determines whether aspect ratio is preserved.
- A persistent viewfinder toggle in the editor toolbar turns alignment guides on or off.
- While dragging a layer, its anchor snaps to the composition's horizontal and/or vertical center when close to the guide. Dashed guides appear during the snap, and a light haptic signals entering alignment.

## Limits
- Alignment guides currently snap to the composition center only; edge/object-to-object guides are future work.
- The Size (px) fields scale the selected layer; they do not destructively resample the source image.
- This batch does not add audio/video import or rendering/export.
- The iOS app must still be built with Xcode/iOS SDK. A repository syntax check cannot replace an iOS build.
