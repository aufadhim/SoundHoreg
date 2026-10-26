import Foundation
import AVFAudio
let engine = AVAudioEngine()
let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
var phase = 0.0
let source = AVAudioSourceNode { _, _, frames, out in
    let buffers = UnsafeMutableAudioBufferListPointer(out)
    for f in 0..<Int(frames) {
        let v = Float(sin(phase) * 0.02); phase += 2 * .pi * 997 / rate
        if phase > 2 * .pi { phase -= 2 * .pi }
        for buffer in buffers { buffer.mData?.assumingMemoryBound(to: Float.self)[f] = v }
    }
    return noErr
}
engine.attach(source); engine.connect(source, to: engine.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!)
engine.mainMixerNode.outputVolume = 0
try engine.start()
while let command = readLine() { if command == "start" { engine.mainMixerNode.outputVolume = 1 }; if command == "pause" { engine.mainMixerNode.outputVolume = 0 }; if command == "stop" { break } }
engine.stop()
