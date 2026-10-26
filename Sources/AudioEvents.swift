import Foundation
import CoreAudio

/// Listener blocks run on the main queue; no polling or work in the realtime audio thread.
final class AudioEvents {
    private struct Entry { let object: AudioObjectID; var address: AudioObjectPropertyAddress; let block: AudioObjectPropertyListenerBlock }
    private var entries: [String: Entry] = [:]
    func replace(_ properties: [(AudioObjectID, AudioObjectPropertySelector)], changed: @escaping () -> Void) {
        let wanted = Set(properties.map { "\($0.0):\($0.1)" })
        for key in Array(entries.keys) where !wanted.contains(key) {
            if var entry = entries.removeValue(forKey: key) { AudioObjectRemovePropertyListenerBlock(entry.object, &entry.address, .main, entry.block) }
        }
        for (object, selector) in properties {
            let key = "\(object):\(selector)"; guard entries[key] == nil else { continue }
            var a = address(selector)
            guard AudioObjectHasProperty(object, &a) else { continue }
            let block: AudioObjectPropertyListenerBlock = { _, _ in changed() }
            if AudioObjectAddPropertyListenerBlock(object, &a, .main, block) == noErr { entries[key] = Entry(object: object, address: a, block: block) }
        }
    }
    func cancel() { for var e in entries.values { AudioObjectRemovePropertyListenerBlock(e.object, &e.address, .main, e.block) }; entries.removeAll() }
    deinit { cancel() }
}
