import ApplicationServices
import AppKit

print("=== Quillside Debug Tool ===\n")

// 1. Check Accessibility Permission
let isTrusted = AXIsProcessTrusted()
print("1. Accessibility Permission: \(isTrusted ? "✅ GRANTED" : "❌ NOT GRANTED")")

if !isTrusted {
    print("   ⚠️  Please grant Accessibility permission first!")
    print("   System Settings → Privacy & Security → Accessibility")
    exit(1)
}

// 2. Check if Notes is running
let notesApp = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.apple.Notes" }
if let notes = notesApp {
    print("2. Notes App: ✅ RUNNING (PID: \(notes.processIdentifier))")
} else {
    print("2. Notes App: ❌ NOT RUNNING")
    print("   Please open Apple Notes first!")
    exit(1)
}

// 3. Check if Notes is frontmost
let isFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.Notes"
print("3. Notes Frontmost: \(isFrontmost ? "✅ YES" : "⚠️  NO (bring Notes to front)")")

// 4. Get Notes AXUIElement
let notesPID = notesApp!.processIdentifier
let notesElement = AXUIElementCreateApplication(notesPID)
print("4. Notes AXUIElement: ✅ Created")

// 5. Try to get windows
var windowsValue: CFTypeRef?
let windowsResult = AXUIElementCopyAttributeValue(notesElement, kAXWindowsAttribute as CFString, &windowsValue)
if windowsResult == .success, let windows = windowsValue as? [AXUIElement] {
    print("5. Notes Windows: ✅ Found \(windows.count) window(s)")
} else {
    print("5. Notes Windows: ❌ Failed (AXError: \(windowsResult.rawValue))")
    print("   Common causes:")
    print("   - Accessibility permission not fully applied (restart app)")
    print("   - Notes app is minimized or has no windows")
}

// 6. Try to get focused window
var focusedWindow: CFTypeRef?
let focusedResult = AXUIElementCopyAttributeValue(notesElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)
if focusedResult == .success {
    print("6. Focused Window: ✅ Found")
} else {
    print("6. Focused Window: ❌ Failed (AXError: \(focusedResult.rawValue))")
}

// 7. Try to get focused UI element
var focusedElement: CFTypeRef?
let focusedElementResult = AXUIElementCopyAttributeValue(notesElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
if focusedElementResult == .success {
    print("7. Focused Element: ✅ Found")
    
    // 8. Try to get selected text
    let element = focusedElement as! AXUIElement
    var selectedText: CFTypeRef?
    let selectedResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedText)
    if selectedResult == .success, let text = selectedText as? String {
        if text.isEmpty {
            print("8. Selected Text: ⚠️  Empty (select some text in Notes)")
        } else {
            print("8. Selected Text: ✅ Available (content hidden)")
        }
    } else {
        print("8. Selected Text: ❌ Failed (AXError: \(selectedResult.rawValue))")
    }
    
    // 9. Try to get selection bounds
    var rangeValue: CFTypeRef?
    let rangeResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue)
    if rangeResult == .success, rangeValue != nil {
        var boundsValue: CFTypeRef?
        let boundsResult = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue!,
            &boundsValue
        )
        if boundsResult == .success, boundsValue != nil {
            var rect = CGRect.zero
            AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect)
            print("9. Selection Bounds: ✅ \(rect)")
        } else {
            print("9. Selection Bounds: ❌ Failed (AXError: \(boundsResult.rawValue))")
        }
    } else {
        print("9. Selection Range: ❌ Failed (AXError: \(rangeResult.rawValue))")
    }
} else {
    print("7. Focused Element: ❌ Failed (AXError: \(focusedElementResult.rawValue))")
    print("   Click inside a note in Notes app first!")
}

print("\n=== Summary ===")
if isTrusted && notesApp != nil && isFrontmost {
    print("All basic checks passed. If features still don't work:")
    print("1. Make sure you have text selected in Notes")
    print("2. Try clicking inside the note editor area")
    print("3. Check Console.app for Quillside logs")
} else {
    print("Fix the issues marked with ❌ or ⚠️ above")
}
