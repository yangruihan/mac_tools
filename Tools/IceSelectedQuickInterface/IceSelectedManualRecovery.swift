// Zero-input live manual-return acknowledgment. Original stopped record is
// archived unchanged, never rewritten to native/physical transport success.
import AppKit

struct IceSelectedManualObservation:Codable,Equatable,Sendable {
    let atUptime:Double,hidLeftDown:Bool,combinedLeftDown:Bool,pressedButtons:Int,noOwnerPopup:Bool
    var releasedAndAbsent:Bool{!hidLeftDown && !combinedLeftDown && pressedButtons==0 && noOwnerPopup}
}
struct IceSelectedManualReceipt:Codable,Equatable,Sendable {
    let version:Int,record:IceSelectedRecord,recordSHA256:String,returnEvidence:Data
    let first:IceSelectedManualObservation,second:IceSelectedManualObservation,verifiedAt:Double
    let disposition:String,nativePosts:Int,nativeReturnProven:Bool,physicalReleaseProven:Bool
    func validate(_ expected:IceSelectedRecord)throws {
        try expected.validate()
        guard IceSelectedManualRecovery.eligible(record) else{throw IceSelectedFailure.unresolvedDown}
        guard let plan=record.relativePlan,
              let payload=try JSONSerialization.jsonObject(with:returnEvidence) as? [String:Any],payload["nonce"] as? String==record.binding.nonce.uuidString,
              payload["criterion"] as? String==IceRelativeReturn.version,payload["relativeGeometryVerified"] as? Bool==true,
              let rawSamples=payload["samples"] else{throw IceSelectedFailure.binding}
        let samples=try JSONDecoder().decode([IceRelativeReturn.Snapshot].self,from:JSONSerialization.data(withJSONObject:rawSamples))
        guard samples.count>=5 else{throw IceSelectedFailure.binding}
        var stable=IceRelativeReturn.Stability(),delta:Double?
        for sample in samples.suffix(5) {
            let observed=stable.observe(plan,sample,now:sample.uptime)
            guard observed.0.proposedGeometrySatisfied,delta==nil || delta==observed.0.cohortTranslation else{throw IceSelectedFailure.binding}
            delta=observed.0.cohortTranslation
        }
        guard stable.count>=5,let last=samples.last,verifiedAt>=last.uptime,verifiedAt-last.uptime<=0.25 else{throw IceSelectedFailure.binding}
        guard version==2,record==expected,record.phase == .stopped,record.contract == .ordinaryIceRelativeV2,
              !record.needsRelease,record.gestures.allSatisfy({$0.status == .registered && $0.routes.isEmpty || $0.status == .pairedTransportReturned}),
              recordSHA256 == (try IceSelectedOwnedRecovery.digest(record)),!returnEvidence.isEmpty,
              first.releasedAndAbsent,second.releasedAndAbsent,second.atUptime-first.atUptime>=0.1,
              verifiedAt>=second.atUptime,disposition=="manualRelativeReturnObserved",nativePosts==0,!nativeReturnProven,!physicalReleaseProven else{throw IceSelectedFailure.binding}
    }
}
final class IceSelectedManualProof:@unchecked Sendable {
    let record:IceSelectedRecord,receipt:IceSelectedManualReceipt
    fileprivate init(_ receipt:IceSelectedManualReceipt){self.receipt=receipt;record=receipt.record}
    func validate(_ expected:IceSelectedRecord,now:Double)throws {
        try receipt.validate(expected)
        guard now>=receipt.verifiedAt,now-receipt.verifiedAt<=0.25 else{throw IceSelectedFailure.binding}
    }
}
enum IceSelectedManualRecovery {
    static func eligible(_ record:IceSelectedRecord)->Bool {
        record.phase == .stopped && record.contract == .ordinaryIceRelativeV2 && !record.needsRelease && record.relativePlan != nil
            && record.gestures.allSatisfy({$0.status == .registered && $0.routes.isEmpty || $0.status == .pairedTransportReturned})
    }
    // Native-only final read also runs under the serialized archive I/O boundary.
    // This does not pretend to prove a historic missing transport acknowledgment.
    static func currentReleasedAndNoPopup(_ record:IceSelectedRecord)->Bool {
        guard !CGEventSource.buttonState(.hidSystemState,button:.left),!CGEventSource.buttonState(.combinedSessionState,button:.left),
              let rows=CGWindowListCopyWindowInfo(.optionOnScreenOnly,kCGNullWindowID) as? [[String:Any]],rows.count<=4096 else{return false}
        for row in rows {
            guard let pid=(row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let level=(row[kCGWindowLayer as String] as? NSNumber)?.intValue else{return false}
            if pid==record.binding.owner.pid && level==Int(CGWindowLevelForKey(.popUpMenuWindow)){return false}
        };return true
    }
    @MainActor static func observation(_ record:IceSelectedRecord)throws->IceSelectedManualObservation {
        let out=IceSelectedManualObservation(atUptime:ProcessInfo.processInfo.systemUptime,
            hidLeftDown:CGEventSource.buttonState(.hidSystemState,button:.left),combinedLeftDown:CGEventSource.buttonState(.combinedSessionState,button:.left),
            pressedButtons:NSEvent.pressedMouseButtons,noOwnerPopup:currentReleasedAndNoPopup(record))
        guard out.releasedAndAbsent else{throw IceSelectedFailure.unresolvedDown};return out
    }
    @MainActor static func prove(_ record:IceSelectedRecord,nonce:UUID,expectedHash:String)async throws->IceSelectedManualProof {
        try record.validate()
        guard record.binding.nonce==nonce,try IceSelectedOwnedRecovery.digest(record)==expectedHash,
              record.phase == .stopped,record.contract == .ordinaryIceRelativeV2,!record.needsRelease,let original=record.relativePlan,
              record.gestures.allSatisfy({$0.status == .registered && $0.routes.isEmpty || $0.status == .pairedTransportReturned}) else{throw IceSelectedFailure.unresolvedDown}
        let windows=try IceBaselineWindows(),reader=try IceSelectedLiveRelative(binding:record.binding,windows:windows,restoring:original)
        let runtime=try IceSelectedRuntime([record.binding.controller,record.binding.owner]+reader.protectedProcesses)
        let first=try observation(record)
        try await Task.sleep(nanoseconds:120_000_000)
        let second=try observation(record)
        // Same complete directory and original frozen plan, not a new baseline.
        let proof=try await reader.verify(runtime:runtime)
        let final=try observation(record)
        try proof.validate(binding:record.binding,now:final.atUptime)
        let receipt=IceSelectedManualReceipt(version:2,record:record,recordSHA256:expectedHash,returnEvidence:proof.data,
            first:first,second:second,verifiedAt:final.atUptime,disposition:"manualRelativeReturnObserved",nativePosts:0,nativeReturnProven:false,physicalReleaseProven:false)
        try receipt.validate(record);return .init(receipt)
    }
    @MainActor static func archive(_ store:IceSelectedJournal,nonce:UUID,expectedHash:String)async throws->IceSelectedManualReceipt {
        guard let record=try store.inspect() else{throw IceSelectedFailure.binding}
        let proof=try await prove(record,nonce:nonce,expectedHash:expectedHash)
        return try await Task.detached{try store.archiveManualRecovery(proof)}.value
    }
}
