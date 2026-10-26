#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build/SoundHoreg.app/Contents/MacOS build/SoundHoreg.app/Contents/Resources
xcrun clang -target arm64-apple-macos14.4 -O2 -c Sources/AudioDSP.c -o build/AudioDSP.o
xcrun swiftc -module-cache-path build/ModuleCache -O -swift-version 5 -target arm64-apple-macos14.4 -import-objc-header Sources/AudioDSP.h Sources/AudioEvents.swift Sources/LevelAudit.swift Sources/Audio.swift Sources/Model.swift Sources/Main.swift build/AudioDSP.o -o build/SoundHoreg.app/Contents/MacOS/SoundHoreg -framework SwiftUI -framework AppKit -framework CoreAudio -framework AudioToolbox -framework AVFAudio
xcrun swiftc -O -module-cache-path build/ModuleCache -target arm64-apple-macos14.4 Tests/ToneSource.swift -o build/SoundHoreg.app/Contents/Resources/AuditTone -framework AVFAudio
codesign --force --sign - build/SoundHoreg.app/Contents/Resources/AuditTone
cp Info.plist build/SoundHoreg.app/Contents/Info.plist
cp Assets/Suara.icns build/SoundHoreg.app/Contents/Resources/SoundHoreg.icns
codesign --force --sign - --identifier id.auf.Suara build/SoundHoreg.app
