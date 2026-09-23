#!/usr/bin/env python3
"""Generate a temporary UI-smoke variant with offscreen bitmap/layout evidence."""
from pathlib import Path
source = Path('app/ComputeMonitor.swift').read_text()
source = source.replace('        let switched = selected == .gpu', '''        content.view.layoutSubtreeIfNeeded()
        func inspect(_ view: NSView, depth: Int = 0) {
            let frame = view.convert(view.bounds, to: content.view)
            print("LAYOUT", depth, type(of: view), NSStringFromRect(frame))
            for child in view.subviews { inspect(child, depth: depth + 1) }
        }
        inspect(content.view)
        if let bitmap = content.view.bitmapImageRepForCachingDisplay(in: content.view.bounds) {
            content.view.cacheDisplay(in: content.view.bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/.build/step31-ui.png"))
            }
        }
        let switched = selected == .gpu''')
# Isolate test preferences from the normal app's saved primary selection.
source = source.replace('UserDefaults.standard.set(mode.rawValue, forKey: "primaryMetric")', '// no preference mutation in this temporary check')
Path('.build/step31-ui.swift').write_text(source)
