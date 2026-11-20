---
name: studio-sound
description: Studio standard for sound design in iOS apps with AVFoundation (AVAudioSession, AVAudioEngine, AVAudioPlayerNode, synthesized UI sounds). Use when adding UI sounds, audio feedback, ambient audio, or reviewing audio behaviour (silent switch, interruptions, mixing).
---

# Sound Design (AVFoundation)

## Activation
- Any `AVAudioSession`, `AVAudioEngine`, `AVAudioPlayer`, sound asset, or "add a sound to …".

## Standards
- **Session:** UI sounds use category `.ambient` (respects the silent switch, mixes with other audio). Never `.playback` for UI sounds. Configure once at launch in a `SoundEngine` actor/service.
- **Engine:** one shared `AVAudioEngine` with pre-attached `AVAudioPlayerNode`s and pre-loaded `AVAudioPCMBuffer`s → latency < 20 ms. No `AVAudioPlayer` per tap.
- **Assets:** short (≤ 1 s), 44.1/48 kHz, mono, normalised to about −16 LUFS, `.caf` or `.wav`. Created by us (synthesized in code or recorded) – origin documented in `ASSETS.md`. No sample packs of unclear license.
- **Synthesized sounds** are preferred for UI: generate the buffer in code (sine/triangle + envelope) so there is no asset at all. Keep generator code unit-tested (buffer length, peak ≤ 0 dBFS, no clicks: first/last samples near 0).
- **Restraint:** sound only for meaningful moments (success, completion, signature interaction). Global in-app toggle "Töne" (default on), stored in `@AppStorage`.
- **Sync:** sound, haptic and animation fire from the same state change (see `studio-haptics` `FeedbackCoordinator`).
- **Lifecycle:** handle `AVAudioSession.interruptionNotification` and route changes; restart engine when needed; stop engine in background.
- **Accessibility:** sound never carries information alone – always a visual (and haptic) counterpart.

## Quality checks
- [ ] Category is `.ambient` for UI sounds (unit test on the configuration value).
- [ ] Engine start failure is logged and the app continues silently (no crash).
- [ ] Generator tests pass (length, peak, fade).
- [ ] Toggle "Töne" off → no `play` calls (test via a `SoundPlaying` protocol mock).
- [ ] Final listening check on device (TestFlight) – simulator audio is not representative.

## Example (synthesized tick)
```swift
func makeTick(format: AVAudioFormat, frequency: Double = 1_760, duration: Double = 0.06) -> AVAudioPCMBuffer {
    let frames = AVAudioFrameCount(format.sampleRate * duration)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    let data = buffer.floatChannelData![0]
    for i in 0..<Int(frames) {
        let t = Double(i) / format.sampleRate
        let envelope = exp(-t * 60)                       // fast decay, no click at end
        let attack = min(1, Double(i) / 64)               // 64-sample fade-in, no click at start
        data[i] = Float(sin(2 * .pi * frequency * t) * envelope * attack * 0.5)
    }
    return buffer
}
```
