import ApplicationServices
import CoreGraphics
import Foundation

enum FnKeyEvent: Equatable {
    case pressed
    case released
}

enum FnKeyMonitorError: LocalizedError {
    case inputMonitoringPermissionMissing
    case eventTapCreationFailed
    case runLoopSourceCreationFailed

    var errorDescription: String? {
        switch self {
        case .inputMonitoringPermissionMissing:
            return "Input Monitoring permission is required for Fn key detection."
        case .eventTapCreationFailed:
            return "Unable to create a global keyboard event tap for Fn key monitoring."
        case .runLoopSourceCreationFailed:
            return "Unable to create run loop source for Fn key monitoring."
        }
    }
}

protocol FnKeyMonitoring: AnyObject {
    var onEvent: ((FnKeyEvent) -> Void)? { get set }
    func start() throws
    func stop()
}

final class FnKeyMonitor: FnKeyMonitoring {
    var onEvent: ((FnKeyEvent) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isFnDown = false

    func start() throws {
        if #available(macOS 10.15, *), !CGPreflightListenEventAccess() {
            throw FnKeyMonitorError.inputMonitoringPermissionMissing
        }

        guard eventTap == nil else {
            return
        }

        let eventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let monitor = Unmanaged<FnKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            monitor.handleTapEvent(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        let userInfo = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: userInfo
        ) else {
            throw FnKeyMonitorError.eventTapCreationFailed
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            throw FnKeyMonitorError.runLoopSourceCreationFailed
        }

        eventTap = tap
        runLoopSource = source

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }

        if let tap = eventTap {
            CFMachPortInvalidate(tap)
            eventTap = nil
        }

        isFnDown = false
    }

    deinit {
        stop()
    }

    @discardableResult
    func process(flags: CGEventFlags) -> FnKeyEvent? {
        let fnDownNow = flags.contains(.maskSecondaryFn)
        guard fnDownNow != isFnDown else {
            return nil
        }

        isFnDown = fnDownNow
        return fnDownNow ? .pressed : .released
    }

    private func handleTapEvent(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return
        }

        guard type == .flagsChanged else {
            return
        }

        if let fnEvent = process(flags: event.flags) {
            onEvent?(fnEvent)
        }
    }
}
