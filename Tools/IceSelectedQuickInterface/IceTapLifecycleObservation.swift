// Copyright (c) 2026 Ryan.AI. MIT.
// Public listen-only tap lifecycle observation. No event posting or UI activation.
import AppKit

@MainActor enum IceTapLifecycleObservation {
    static func run()async throws->[String:Any] {
        guard CGPreflightListenEventAccess() else{throw IceBaselineError.source}
        try IceSelectedSession.requireNoOtherWorker()
        let start=ProcessInfo.processInfo.systemUptime
        var records:[[String:Any]]=[]
        for cycle in 0..<6 {
            let prepared=cycle<3
            let mode=prepared ? "createdDisabledThenEnabled" : "createdThenEnabled"
            let tap=EventTap(options:.listenOnly,location:.sessionEventTap,place:.tailAppendEventTap,types:[.leftMouseDown,.leftMouseUp]) {proxy,type,event in
                // Never record any human input packet or return an altered event.
                if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
                    records.append(["phase":"tap-disable-notice","cycle":cycle,"mode":mode,"type":type.rawValue,"reason":type == .tapDisabledByTimeout ? "timeout" : "userInput","tapEnabled":proxy.isEnabled,"elapsedMS":(ProcessInfo.processInfo.systemUptime-start)*1000])
                }
                return event
            }
            records.append(["phase":"created","cycle":cycle,"mode":mode,"enabled":tap.isEnabled,"elapsedMS":(ProcessInfo.processInfo.systemUptime-start)*1000])
            if prepared {
                tap.disable()
                records.append(["phase":"explicit-disable","cycle":cycle,"elapsedMS":(ProcessInfo.processInfo.systemUptime-start)*1000])
                try await Task.sleep(nanoseconds:20_000_000)
            }
            tap.enable()
            records.append(["phase":"enable-source","cycle":cycle,"mode":mode,"enabled":tap.isEnabled,"elapsedMS":(ProcessInfo.processInfo.systemUptime-start)*1000])
            try await Task.sleep(nanoseconds:80_000_000)
            tap.disable()
            records.append(["phase":"finished-disabled","cycle":cycle,"elapsedMS":(ProcessInfo.processInfo.systemUptime-start)*1000])
        }
        return ["provenance":"nativePublicListenOnlyTapLifecycle","nativePosts":0,"AXActions":0,"cursorEffects":0,"thirdPartyActions":0,"permissionRequests":0,"humanPacketsRecorded":0,"cycles":6,"records":records]
    }
}
