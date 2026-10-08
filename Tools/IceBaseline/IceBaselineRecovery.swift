// Copyright (c) 2026 Ryan.AI. MIT. Explicit, zero-move owned-fixture retirement.
import AppKit
import Darwin

struct IceCandidateDisposalObservation:Codable,Equatable,Sendable {
    let atUptime:Double,controllerGone:Bool,fixtureGone:Bool,originalWindowIDsAbsent:Bool
    var disposed:Bool { controllerGone && fixtureGone && originalWindowIDsAbsent }
}
/// Process-local capability. Decoding a JSON observation never creates it.
final class IceCandidateDisposalProof:@unchecked Sendable {
    let record:IceCandidateRecord,first:IceCandidateDisposalObservation,second:IceCandidateDisposalObservation
    fileprivate init(_ record:IceCandidateRecord,_ first:IceCandidateDisposalObservation,_ second:IceCandidateDisposalObservation) {
        self.record=record;self.first=first;self.second=second
    }
    func validate(_ expected:IceCandidateRecord,now:Double) throws {
        guard expected == record,IceBaselineRecovery.eligible(expected),first.disposed,second.disposed,
              first.atUptime.isFinite,second.atUptime.isFinite,now.isFinite,
              second.atUptime-first.atUptime>=0.1,now>=second.atUptime,now-second.atUptime<=0.5 else {throw IceCandidateFailure.binding}
    }
}
struct IceCandidateRetirementReceipt:Codable,Equatable,Sendable {
    let schemaVersion:Int,request:UUID,recoveryGeneration:UUID,record:IceCandidateRecord,recordSHA256:String
    let first:IceCandidateDisposalObservation,second:IceCandidateDisposalObservation
    let disposition:String,nativeReturnProven:Bool,physicalReleaseProven:Bool,nativePosts:Int
    init(_ proof:IceCandidateDisposalProof,request:UUID,generation:UUID)throws {
        schemaVersion=1;self.request=request;recoveryGeneration=generation;record=proof.record
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        recordSHA256=IceBaselineCandidateJournal.hash(try encoder.encode(record));first=proof.first;second=proof.second
        disposition="ownedFixtureDisposed";nativeReturnProven=false;physicalReleaseProven=false;nativePosts=0
    }
    func validate(_ expected:IceCandidateRecord)throws {
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        guard schemaVersion==1,record==expected,IceBaselineRecovery.eligible(record),first.disposed,second.disposed,
              first.atUptime.isFinite,second.atUptime.isFinite,second.atUptime-first.atUptime>=0.1,
              recordSHA256==IceBaselineCandidateJournal.hash(try encoder.encode(record)),
              disposition=="ownedFixtureDisposed",!nativeReturnProven,!physicalReleaseProven,nativePosts==0,
              recoveryGeneration != record.generation else {throw IceCandidateFailure.binding}
    }
}
enum IceBaselineRecovery {
    static func eligible(_ record:IceCandidateRecord)->Bool {
        record.phase == .stopped && !record.needsRelease && record.gestures.allSatisfy {
            $0.status == .registered && $0.routes.isEmpty || $0.status == .pairedTransportReturned
        }
    }
    static func sample(_ record:IceCandidateRecord)->IceCandidateDisposalObservation {
        func gone(_ pid:Int32)->Bool {
            // Signal 0 is a liveness read; EPERM/other errors remain unknown.
            guard pid>0 else{return false};let result=Darwin.kill(pid,0);return result<0 && errno==ESRCH
        }
        let rows=CGWindowListCopyWindowInfo(.optionAll,kCGNullWindowID) as? [[String:Any]]
        let ids:Set<UInt32>=Set((rows ?? []).compactMap{($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value})
        let original=Set([record.binding.target.id,record.binding.neighbor.id,record.binding.anchor.id,record.binding.divider.id])
        return .init(atUptime:ProcessInfo.processInfo.systemUptime,controllerGone:gone(record.binding.controller.pid),
            fixtureGone:gone(record.binding.fixture.pid),originalWindowIDsAbsent:rows != nil && ids.isDisjoint(with:original))
    }
    static func disposition(_ record:IceCandidateRecord,_ sample:IceCandidateDisposalObservation)->String {
        if record.needsRelease{return "blockedUnconfirmedDown"}
        if !eligible(record){return "retainedUnverifiedPhase"}
        return sample.disposed ? "eligibleForExplicitOwnedDisposalRetirement" : "retainedLiveOwnerOrWindow"
    }
    static func proveDisposed(_ record:IceCandidateRecord)async throws->IceCandidateDisposalProof {
        try record.validate();guard eligible(record)else{throw IceCandidateFailure.unresolvedDown}
        try Task.checkCancellation();let first=sample(record)
        guard first.disposed else{throw IceCandidateFailure.binding}
        try await Task.sleep(nanoseconds:120_000_000);try Task.checkCancellation()
        let second=sample(record),proof=IceCandidateDisposalProof(record,first,second)
        try proof.validate(record,now:ProcessInfo.processInfo.systemUptime);return proof
    }
    static func retire(_ store:IceBaselineCandidateJournal,nonce:UUID,expectedHash:String)async throws->IceCandidateRetirementReceipt {
        let fence=IceCandidateFence()
        return try await withTaskCancellationHandler(operation:{
            guard let record=try store.inspect(),record.binding.nonce==nonce else{throw IceCandidateFailure.binding}
            let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
            guard IceBaselineCandidateJournal.hash(try encoder.encode(record))==expectedHash else{throw IceCandidateFailure.binding}
            let proof=try await proveDisposed(record);try fence.check()
            let receipt=try IceCandidateRetirementReceipt(proof,request:UUID(),generation:fence.stop.generation)
            let worker=try fence.perform("retirement-archive-dispatch") {
                Task.detached{try store.retireDisposed(proof,receipt:receipt)}
            }
            let saved=try await worker.value;try fence.check();return saved
        },onCancel:{fence.cancel()})
    }
}
