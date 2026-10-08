// Copyright (c) 2026 Ryan.AI. MIT. Actual complete original-contract inventory.
// Reuses only the six previously admitted read-only CGS entry points.
import AppKit

@MainActor final class IceBaselineNativePlan {
    typealias M=MenuBarHiddenMoveModel
    let binding:IceCandidateBinding,windows:IceBaselineWindows,publication:()throws->[String:Any]
    private let continuity=UUID()
    private var sequence:UInt64=0
    private(set)var lastStage="created"
    private(set)var lastFirst:M.Snapshot?,lastSecond:M.Snapshot?
    init(binding:IceCandidateBinding,windows:IceBaselineWindows,publication:@escaping()throws->[String:Any]) {
        self.binding=binding;self.windows=windows;self.publication=publication
    }
    func pair()throws->M.Plan {
        let first=try sample();lastFirst=first
        // Bounded synchronous provider required by the unchanged broker. No
        // nested run loop, retry or update after Permit. Queued input is checked
        // by both original listeners immediately after this provider returns.
        Thread.sleep(forTimeInterval:0.15)
        let second=try sample();lastSecond=second;lastStage="originalPlanValidation"
        return try M.Plan.capture(first,second,now:UInt64(ProcessInfo.processInfo.systemUptime*1000))
    }
    func sample()throws->M.Snapshot {
        lastStage="actualProfile"
        let version=ProcessInfo.processInfo.operatingSystemVersion
        let system=NSDictionary(contentsOfFile:"/System/Library/CoreServices/SystemVersion.plist")
        guard "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"==M.Profile.trial.version,
              system?["ProductBuildVersion"] as? String==M.Profile.trial.build else{throw M.Failure.environment}
        #if !arch(arm64)
        throw M.Failure.environment
        #endif
        lastStage="liveSignatureAndDisplay"
        let proof=try MenuBarProcessSignature.read(binding.fixture.pid)
        guard try IceCandidateBinding.Process(proof)==binding.fixture,let team=proof.team,!team.isEmpty,
              let screen=NSScreen.screens.first,let right=screen.auxiliaryTopRightArea,
              screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32==binding.display,
              let displayUUID=CGDisplayCreateUUIDFromDisplayID(binding.display)?.takeRetainedValue(),
              let app=MenuBarApplicationIdentity.current(pid:binding.fixture.pid) else{throw IceCandidateFailure.binding}
        lastStage="freshOwnedPublication"
        let before=try publication(),models=before["modelsAfter"] as? [[String:Any]] ?? []
        guard before["nonce"] as? String==binding.nonce.uuidString,before["pid"] as? Int32==binding.fixture.pid,
              let at=before["atUnix"] as? Double,(0...0.5).contains(Date().timeIntervalSince1970-at),
              let target=models.first(where:{$0["itemKey"] as? String==binding.target.key}),
              target["itemInstance"] as? String==binding.target.instance,target["windowNumber"] as? UInt32==binding.target.id,
              target["windowOcclusionVisible"] as? Bool==false else{throw IceCandidateFailure.binding}
        lastStage="completeNativeMembership"
        let cid=windows.connection(),space=windows.activeSpace(cid);var count:Int32=0
        guard space==binding.space,windows.count(cid,0,&count)==0,count>0,count<4096 else{throw M.Failure.inventory}
        var ids=[UInt32](repeating:0,count:Int(count)+1),actual:Int32=0
        let result=ids.withUnsafeMutableBufferPointer{windows.list(cid,0,Int32($0.count),$0.baseAddress!,&actual)}
        guard result==0,actual>0,actual<ids.count else{throw M.Failure.inventory}
        ids=Array(ids.prefix(Int(actual)));guard Set(ids).count==ids.count else{throw M.Failure.inventory}
        guard let rows=CGWindowListCopyWindowInfo(.optionAll,kCGNullWindowID) as? [[String:Any]] else{throw M.Failure.inventory}
        var items:[M.Item]=[],carriers:[M.Carrier]=[]
        for id in ids {
            lastStage="rawMember-\(id)"
            guard let row=rows.first(where:{($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value==id}),
                  let pid=(row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let layer=(row[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  let alpha=(row[kCGWindowAlpha as String] as? NSNumber)?.doubleValue else{throw M.Failure.inventory}
            var frame=CGRect.zero
            guard windows.getFrame(cid,id,&frame)==0,
                  let raw=windows.windowSpaces(cid,7,[id] as CFArray)?.takeRetainedValue() as? [NSNumber] else{throw M.Failure.inventory}
            let spaces=raw.map(\.uint64Value)
            if layer==Int(CGWindowLevelForKey(.statusWindow)) {
                guard let identity=MenuBarApplicationIdentity.current(pid:pid) else{throw M.Failure.identity}
                let value=row[kCGWindowIsOnscreen as String],shown=value as? Bool==true
                let flag:M.OnScreen=value==nil ? .missing : (CFGetTypeID(value as CFTypeRef)==CFBooleanGetTypeID() ? (shown ? .ordered : .falseValue) : .malformed)
                let target=MenuBarRecordedTarget(.init(id:id,pid:pid,frame:frame,onScreen:shown,application:identity))
                items.append(.init(identity:target,frame:frame,listedOnScreen:shown,onScreen:flag,alpha:alpha,spaces:spaces,
                    ownerOcclusionVisible:models.first(where:{$0["windowNumber"] as? UInt32==id})?["windowOcclusionVisible"] as? Bool))
            }else{
                carriers.append(.init(windowID:id,signature:try MenuBarProcessSignature.readCarrier(pid),frame:frame,layer:layer,spaces:spaces))
            }
        }
        lastStage="postInventoryPublicationAndSpace"
        let after=try publication()
        guard NSDictionary(dictionary:["v":models]).isEqual(to:["v":after["modelsAfter"] as Any]),windows.activeSpace(cid)==space else{throw M.Failure.unstable}
        sequence += 1
        let scope=M.Scope(profile:.trial,continuity:continuity,displayUUID:CFUUIDCreateString(nil,displayUUID) as String,
            displayID:binding.display,displayFrame:CGDisplayBounds(binding.display),scale:screen.backingScaleFactor,
            rotation:CGDisplayRotation(binding.display),activeSpace:UInt64(space),
            rightSafe:.init(x:right.minX,y:screen.frame.maxY-right.maxY,width:right.width,height:right.height))
        let owner=M.Owner(target:.init(.init(id:binding.target.id,pid:binding.fixture.pid,frame:.zero,onScreen:false,application:app)),
            signedIdentifier:proof.identifier,team:team,codeHash:proof.sha256,itemKey:binding.target.key,nonce:binding.nonce,
            itemInstance:UUID(uuidString:binding.target.instance)!)
        return .init(sequence:sequence,uptimeMilliseconds:UInt64(ProcessInfo.processInfo.systemUptime*1000),scope:scope,owner:owner,
            items:items.sorted{$0.frame.minX<$1.frame.minX},membershipIDs:ids,orderEvidence:.observedCoordinates,carriers:carriers)
    }
}
