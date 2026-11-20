---
name: studio-graphics-3d
description: Studio standard for high-end graphics in iOS apps - SwiftUI Metal shaders, Canvas, MeshGradient, SpriteKit, RealityKit and Metal. Use when adding a visual effect, particle system, 3D object, shader, generative background, or when choosing between these technologies.
---

# Graphics, 3D, SpriteKit, RealityKit, Metal

## Activation
- Any `.colorEffect/.distortionEffect/.layerEffect`, `ShaderLibrary`, `Canvas`, `MeshGradient`, `SpriteView`, `RealityView`, `MTKView`, `.metal` file.
- Request for "wow effect", 3D, particles, generative art.

## Choose the lightest tool that achieves the effect
| Need | Use | Min iOS |
|---|---|---|
| Per-pixel color/distortion on a view | SwiftUI shader (`[[ stitchable ]]` Metal function + `ShaderLibrary`) | 17 |
| Animated organic gradient | `MeshGradient` | 18 |
| Many 2D shapes, custom drawing | `Canvas` (+ `TimelineView`) | 15 |
| 2D particles, physics, game-like scenes | SpriteKit via `SpriteView` | 14 |
| 3D models, lighting, PBR materials | RealityKit `RealityView` | 18 (iOS) |
| Full control, compute, custom pipelines | Metal (`MTKView` in `UIViewRepresentable`) | – |

## Standards
- 60 fps on iPhone 12-class hardware, 120 fps on ProMotion where the effect is continuous. Measure, don't assume.
- Shaders: keep stitchable functions small, parameters as `Float` uniforms driven from SwiftUI state; time via `TimelineView(.animation)` and `startDate.distance(to: timeline.date)`. Provide `maxSampleOffset` for `layerEffect`/`distortionEffect`.
- Everything decorative must stop or simplify with Reduce Motion and in Low Power Mode (`ProcessInfo.processInfo.isLowPowerModeEnabled`).
- Decorative graphics are hidden from VoiceOver (`.accessibilityHidden(true)`); meaningful ones get a label.
- 3D assets: USDZ, created by us or with clear license, ≤ 5 MB each; record origin in `apps/<App>/ASSETS.md`.
- Simulator note: the iOS Simulator renders Metal on the host GPU; performance numbers from CI are only relative. Final frame-rate check on a real device via TestFlight.

## Quality checks
- [ ] Effect visible and correct in the screenshot matrix (light/dark).
- [ ] Reduce Motion / Low Power variant implemented and screenshot-tested.
- [ ] Shader compiles in CI (Metal is compiled at build time – a failing shader fails the build).
- [ ] No asset without entry in `ASSETS.md`.

## Example (stitchable shader)
```metal
#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

[[ stitchable ]] half4 shimmer(float2 position, half4 color, float time, float width) {
    float band = sin((position.x + position.y) / width - time * 2.0) * 0.5 + 0.5;
    return half4(color.rgb + half3(band * 0.15), color.a);
}
```
```swift
TimelineView(.animation) { context in
    let t = Float(start.distance(to: context.date))
    Text("Hallo").font(Typography.display)
        .colorEffect(ShaderLibrary.shimmer(.float(t), .float(40)))
}
```
