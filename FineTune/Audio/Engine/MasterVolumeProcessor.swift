import AudioToolbox

/// Final attenuation after EQ, automatic gain and limiting. RT-safe: no allocation,
/// locks or Objective-C calls. Each buffer starts at the same frame gain so planar
/// channels and multi-output aggregates receive identical attenuation.
enum MasterVolumeProcessor {
    nonisolated static func process(
        _ buffers: UnsafeMutableAudioBufferListPointer,
        targetGain: Float,
        currentGain: Float,
        rampCoefficient: Float
    ) -> Float {
        if targetGain == 1 && currentGain == 1 { return 1 }
        var finalGain = currentGain
        var longestBuffer = 0
        for buffer in buffers {
            guard let data = buffer.mData, buffer.mNumberChannels > 0 else { continue }
            let samples = data.assumingMemoryBound(to: Float.self)
            let channels = Int(buffer.mNumberChannels)
            let frames = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / channels
            var gain = currentGain
            for frame in 0..<frames {
                gain += (targetGain - gain) * rampCoefficient
                // End a fade to zero with exact silence, avoiding denormal tails.
                if targetGain == 0 && gain < 0.000001 { gain = 0 }
                for channel in 0..<channels {
                    samples[frame * channels + channel] *= gain
                }
            }
            if frames > longestBuffer {
                longestBuffer = frames
                finalGain = gain
            }
        }
        return finalGain
    }
}
