// Copyright (c) 2026 Ryan.AI. MIT. Explicit zero-input recovery for extinct own fixtures.
// Ordinary/live targets are ineligible; original transport status is never rewritten.
import AppKit
import Darwin

struct IceSelectedDisposalObservation: Codable, Equatable, Sendable {
    let atUptime:Double,controllerGone:Bool,ownerGone:Bool,windowsAbsent:Bool
    let hidLeftDown:Bool,combinedLeftDown:Bool,pressedMouseButtons:Int
    var disposedAndCurrentlyReleased:Bool {controllerGone && ownerGone && windowsAbsent && !hidLeftDown && !combinedLeftDown && pressedMouseButtons==0}
}
final class IceSelectedDisposalProof: @unchecked Sendable {
    let record:IceSelectedRecord,first:IceSelectedDisposalObservation,second:IceSelectedDisposalObservation
    let sessionEvidenceSHA256:String,disposition:String
    fileprivate init(_ record:IceSelectedRecord,_ first:IceSelectedDisposalObservation,_ second:IceSelectedDisposalObservation,_ digest:String,_ disposition:String) {
        self.record=record;self.first=first;self.second=second;sessionEvidenceSHA256=digest;self.disposition=disposition
    }
    func validate(_ expected:IceSelectedRecord,now:Double)throws {
        guard expected==record,IceSelectedOwnedRecovery.owned(record),first.disposedAndCurrentlyReleased,second.disposedAndCurrentlyReleased,
              second.atUptime-first.atUptime>=0.1,now>=second.atUptime,now-second.atUptime<=0.5,
              IceSelectedBinding.validHash(sessionEvidenceSHA256),try IceSelectedOwnedRecovery.evidence(record).0==sessionEvidenceSHA256,
              ["extinctOwnedPairedTransport","extinctOwnedPartialNoFinalPIDDelivery","extinctOwnedDeliveredDownRoute"].contains(disposition) else{throw IceSelectedFailure.binding}
    }
}
struct IceSelectedRetirementReceipt:Codable,Equatable,Sendable {
    let schemaVersion:Int,request:UUID,record:IceSelectedRecord,recordSHA256:String
    let first:IceSelectedDisposalObservation,second:IceSelectedDisposalObservation
    let sessionEvidenceSHA256:String,disposition:String
    let nativePosts:Int,nativeReturnProven:Bool,physicalReleaseProven:Bool
    init(_ proof:IceSelectedDisposalProof)throws {
        schemaVersion=1;request=UUID();record=proof.record;recordSHA256=try IceSelectedOwnedRecovery.digest(record)
        first=proof.first;second=proof.second;sessionEvidenceSHA256=proof.sessionEvidenceSHA256;disposition=proof.disposition
        nativePosts=0;nativeReturnProven=false;physicalReleaseProven=false
    }
    func validate(_ expected:IceSelectedRecord)throws {
        guard schemaVersion==1,record==expected,recordSHA256 == (try IceSelectedOwnedRecovery.digest(record)),
              IceSelectedOwnedRecovery.owned(record),first.disposedAndCurrentlyReleased,second.disposedAndCurrentlyReleased,
              second.atUptime-first.atUptime>=0.1,IceSelectedBinding.validHash(sessionEvidenceSHA256),nativePosts==0,!nativeReturnProven,!physicalReleaseProven,
              ["extinctOwnedPairedTransport","extinctOwnedPartialNoFinalPIDDelivery","extinctOwnedDeliveredDownRoute"].contains(disposition) else{throw IceSelectedFailure.binding}
    }
}
enum IceSelectedOwnedRecovery {
    static func digest(_ record:IceSelectedRecord)throws->String {let e=JSONEncoder();e.outputFormatting=[.sortedKeys];return IceSelectedJournal.hash(try e.encode(record))}
    static func owned(_ record:IceSelectedRecord)->Bool {
        let root="/tmp/mac-tools-ice-interface-product-candidate-20261009/Worker"
        return record.phase == .stopped && record.binding.owner.identifier=="com.ryanai.mactools.nativetargets" && record.binding.owner.team=="58TJ64422P"
            && record.binding.controller.team==record.binding.owner.team
            && record.binding.owner.executable==root+"/Ice Selected Fixture.app/Contents/MacOS/IceSelectedFixture"
            && record.binding.controller.executable==root+"/Ice Selected Controller.app/Contents/MacOS/IceSelectedController"
            && record.binding.target.process==record.binding.owner && record.binding.neighbor.process==record.binding.owner
            && record.binding.anchor.process==record.binding.controller
    }
    static func sample(_ record:IceSelectedRecord)->IceSelectedDisposalObservation {
        func gone(_ pid:Int32)->Bool {guard pid>0 else{return false};let n=Darwin.kill(pid,0);return n<0 && errno==ESRCH}
        let rows=CGWindowListCopyWindowInfo(.optionAll,kCGNullWindowID) as? [[String:Any]]
        let ids=Set((rows ?? []).compactMap{($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value})
        let own=[record.binding.target.id,record.binding.neighbor.id,record.binding.anchor.id]
        return .init(atUptime:ProcessInfo.processInfo.systemUptime,controllerGone:gone(record.binding.controller.pid),ownerGone:gone(record.binding.owner.pid),
                     windowsAbsent:rows != nil && own.allSatisfy{!ids.contains($0)} && !(rows ?? []).contains{r in
                         let p=(r[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
                         return p==record.binding.controller.pid || p==record.binding.owner.pid
                     },hidLeftDown:CGEventSource.buttonState(.hidSystemState,button:.left),combinedLeftDown:CGEventSource.buttonState(.combinedSessionState,button:.left),pressedMouseButtons:NSEvent.pressedMouseButtons)
    }
    /// Bind actual self-owned preparation and terminal trace. A partial transport
    /// requires exact two intents (PID null/session down), matching session receipt,
    /// deadline refusal, no final PID intent, and unchanged T/N before departure.
    /// This is a separate administrative disposition, never a transport ACK.
    static func evidence(_ record:IceSelectedRecord)throws->(String,String) {
        guard owned(record) else{throw IceSelectedFailure.binding}
        let root=URL(fileURLWithPath:"/tmp/mac-tools-ice-interface-product-candidate-20261009/Worker"),dir=root.appendingPathComponent("session-"+record.binding.nonce.uuidString)
        let archive=root.appendingPathComponent("build-history/"+record.binding.controller.sha256)
        guard IceSelectedJournal.hash(try Data(contentsOf:archive.appendingPathComponent("controller")))==record.binding.controller.sha256,
              let built=try JSONSerialization.jsonObject(with:Data(contentsOf:archive.appendingPathComponent("prepared-build.json"))) as? [String:Any],
              built["controllerSHA256"] as? String==record.binding.controller.sha256,
              built["fixtureSHA256"] as? String==record.binding.owner.sha256 else{throw IceSelectedFailure.binding}
        let prepared=try JSONDecoder().decode(IceSelectedSession.Prepared.self,from:Data(contentsOf:dir.appendingPathComponent("session.json")))
        guard prepared.selfOwned,prepared.selected==nil,prepared.nonce==record.binding.nonce,prepared.controllerSHA256==record.binding.controller.sha256 else{throw IceSelectedFailure.binding}
        let bytes=try Data(contentsOf:dir.appendingPathComponent("result.json"))
        guard bytes.count<2_000_000,let result=try JSONSerialization.jsonObject(with:bytes) as? [String:Any],
              let journal=result["journal"] as? [String:Any],let value=journal["durableRecord"],
              try JSONDecoder().decode(IceSelectedRecord.self,from:JSONSerialization.data(withJSONObject:value))==record,
              let events=result["events"] as? [[String:Any]],result["realClosedLoopVerified"] as? Bool==false else{throw IceSelectedFailure.binding}
        if !record.needsRelease,record.gestures.allSatisfy({$0.status == .registered && $0.routes.isEmpty || $0.status == .pairedTransportReturned}) {
            return (IceSelectedJournal.hash(bytes),"extinctOwnedPairedTransport")
        }
        // A different, explicit disposition for a vanished self fixture after
        // its one down route really returned. No up/native return is invented.
        if record.gestures.count==1,let g=record.gestures.first,g.status == .downReturned,g.routes.count==3,
           result["posts"] as? Int==3,record.contract == .ordinaryIceInterfaceV9 {
            let posts=events.filter{$0["phase"] as? String=="post-intent"}
            guard posts.count==3,events.filter({$0["phase"] as? String=="post-call-exit"}).count==3,
                  events.filter({$0["phase"] as? String=="route-receipt-continuation-resumed"}).count==1,
                  events.filter({$0["phase"] as? String=="raw-receipt-bound"}).count==2,
                  events.last?["phase"] as? String=="cursor-show" else{throw IceSelectedFailure.binding}
            for (actual,route) in zip(posts,g.routes) {
                guard actual["route"] as? String==route.destination,actual["type"] as? UInt32==route.packet.type,
                      actual["marker"] as? Int64==route.packet.marker,actual["window"] as? Int64==route.packet.window,
                      actual["pid"] as? Int64==route.packet.pid,actual["x"] as? Double==route.packet.x,
                      actual["y"] as? Double==route.packet.y else{throw IceSelectedFailure.binding}
            }
            guard events.filter({$0["phase"] as? String=="post-call-exit"}).allSatisfy({$0["returnedNormally"] as? Bool==true}),
                  events.filter({$0["phase"] as? String=="raw-receipt-bound"}).allSatisfy({row in
                    guard let received=row["receivedAtUptime"] as? Double,let posted=row["postedAtUptime"] as? Double,let deadline=row["deadlineUptime"] as? Double else{return false};return posted<=received && received<deadline
                  }) else{throw IceSelectedFailure.binding}
            let terminal=try JSONSerialization.jsonObject(with:Data(contentsOf:dir.appendingPathComponent("owner-state/lifetime-terminal.json"))) as? [String:Any]
            guard terminal?["pid"] as? Int32==record.binding.owner.pid,terminal?["nonce"] as? String==record.binding.nonce.uuidString,
                  terminal?["menuOpenKey"] is NSNull else{throw IceSelectedFailure.binding}
            return (IceSelectedJournal.hash(bytes),"extinctOwnedDeliveredDownRoute")
        }
        guard record.gestures.count==1,let g=record.gestures.first,g.status == .downReserved,g.routes.count==3,
              result["posts"] as? Int==2 else{throw IceSelectedFailure.unresolvedDown}
        let posted=events.filter{$0["phase"] as? String=="post-intent"}
        guard posted.count==2,posted[0]["type"] as? Int==0,posted[0]["route"] as? String=="PID \(record.binding.owner.pid)",
              posted[1]["type"] as? Int==1,posted[1]["route"] as? String=="session event tap",
              posted[1]["pid"] as? Int32==record.binding.owner.pid,posted[1]["window"] as? UInt32==record.binding.target.id,
              posted[1]["marker"] as? Int64==g.down.marker,posted[1]["x"] as? Double==g.down.x,posted[1]["y"] as? Double==g.down.y,
              events.contains(where:{$0["phase"] as? String=="session-received" && $0["marker"] as? Int64==g.down.marker && $0["window"] as? UInt32==record.binding.target.id}),
              events.contains(where:{$0["phase"] as? String=="route-deadline-rejected"}),
              events.last?["phase"] as? String=="cursor-show" else{throw IceSelectedFailure.unresolvedDown}
        let state=try JSONSerialization.jsonObject(with:Data(contentsOf:dir.appendingPathComponent("owner-state/latest.json"))) as? [String:Any]
        guard state?["pid"] as? Int32==record.binding.owner.pid,state?["nonce"] as? String==record.binding.nonce.uuidString,
              let models=state?["modelsAfter"] as? [[String:Any]],let control=state?["menuControl"] as? [String:Any],control["generation"] as? Int==0 else{throw IceSelectedFailure.binding}
        for item in [record.binding.target,record.binding.neighbor] {
            guard let model=models.first(where:{$0["windowNumber"] as? UInt32==item.id}),let rect=model["windowFrameAppKit"] as? [String:Double],
                  rect["x"]==item.frame.x,rect["width"]==item.frame.width,rect["height"]==item.frame.height else{throw IceSelectedFailure.binding}
        }
        return (IceSelectedJournal.hash(bytes),"extinctOwnedPartialNoFinalPIDDelivery")
    }
    static func retire(_ store:IceSelectedJournal,nonce:UUID,expectedHash:String)async throws->IceSelectedRetirementReceipt {
        guard let record=try store.inspect(),record.binding.nonce==nonce,try digest(record)==expectedHash else{throw IceSelectedFailure.binding}
        try record.validate();let (digest,disposition)=try evidence(record)
        let first=sample(record);guard first.disposedAndCurrentlyReleased else{throw IceSelectedFailure.unresolvedDown}
        try await Task.sleep(nanoseconds:120_000_000);try Task.checkCancellation()
        let second=sample(record),proof=IceSelectedDisposalProof(record,first,second,digest,disposition)
        try proof.validate(record,now:ProcessInfo.processInfo.systemUptime)
        let receipt=try IceSelectedRetirementReceipt(proof)
        return try await Task.detached{try store.retireDepartedOwned(proof,receipt:receipt)}.value
    }
}
