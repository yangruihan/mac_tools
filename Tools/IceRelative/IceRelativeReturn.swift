// Copyright (c) 2026 Ryan.AI. MIT. Pure proposed geometry criterion; no native effects.
import Foundation
import CoreGraphics

enum IceRelativeReturn {
    static let version="relativeCohortSlotV1-proposal"
    struct Rect:Codable,Equatable {
        var x:Double,y:Double,width:Double,height:Double
        var right:Double{x+width}
        var valid:Bool{[x,y,width,height,right].allSatisfy(\.isFinite) && width>0 && height>0}
        func sameShapeAndRow(_ other:Self)->Bool {y==other.y && width==other.width && height==other.height}
    }
    struct Identity:Codable,Equatable {
        var windowID:UInt32,pid:Int32,launch:Double?,executable:String?,identifier:String?,team:String?,sha256:String?
        var processPinned:Bool {
            windowID>0 && pid>0 && launch.map{$0.isFinite && $0>0}==true && executable?.hasPrefix("/")==true
                && identifier?.isEmpty==false && sha256.map{$0.count==64 && $0.allSatisfy{"0123456789abcdef".contains($0)}}==true
        }
    }
    struct Member:Codable,Equatable {var identity:Identity,frame:Rect}
    struct Scope:Codable,Equatable {var display:UInt32,space:UInt64,bar:Rect,approvedArea:Rect}
    struct Snapshot:Codable,Equatable {
        var sequence:Int,uptime:Double,scope:Scope,members:[Member]
        // This is an input fact, not an authorization token. The caller must
        // establish coherence through actual before/after native reads.
        var coherent:Bool,completeDirectory:Bool,readerHealthy:Bool,provenance:String
    }
    struct Plan:Codable,Equatable {
        var baseline:Snapshot,target:UInt32,neighbor:UInt32,anchor:UInt32,returnOnLeft:Bool
        // Frozen before moving: target, original neighbor, and one distinct
        // adjacent witness form a consecutive, unchanging three-window cohort.
        var cohort:[UInt32]
    }
    enum Rejection:String,Codable {case invalidPlan,invalidSnapshot,scopeChanged,identityChanged,missingOrDuplicateWindow,shapeOrRowChanged,
        singleOrUnequalDisplacement,wrongNeighborSide,orderChanged,gapChanged,rightBoundaryChanged,regionChanged,incompleteDirectory,tornSnapshot,unhealthyReader,staleSample,reusedSequence}
    struct Decision:Codable,Equatable {
        let version:String,cohortTranslation:Double?,exactOriginalNeighborSide:Bool
        let commonTranslationConsistent:Bool,strictProtectedAbsoluteFrames:Bool?,strictAllPeerFrames:Bool?
        let proposedGeometrySatisfied:Bool,rejections:[Rejection],provenance:String
        // JSON/offline arithmetic can never grant a live permit or clear a journal.
        let liveAdmission:Bool,mayMarkJournalReturned:Bool
    }
    static func ordered(_ members:[Member])->[Member] {members.sorted{$0.frame.x==$1.frame.x ? $0.identity.windowID<$1.identity.windowID : $0.frame.x<$1.frame.x}}
    static func region(_ r:Rect,_ a:Rect)->String {
        if r.y != a.y || r.height != a.height{return "otherRow"}
        if r.right<=a.x{return "leftOfApprovedArea"}
        if r.x>=a.right{return "rightOfApprovedArea"}
        if r.x>=a.x && r.right<=a.right{return "withinApprovedArea"}
        return "crossesApprovedAreaBoundary"
    }
    static func evaluate(_ plan:Plan,_ current:Snapshot)->Decision {
        let base=plan.baseline
        var rejected:[Rejection]=[]
        func reject(_ why:Rejection){if !rejected.contains(why){rejected.append(why)}}
        func table(_ s:Snapshot)->[UInt32:Member]? {
            let ids=s.members.map{$0.identity.windowID}
            guard !s.members.isEmpty,ids.allSatisfy({$0>0}),Set(ids).count==ids.count,
                  s.members.allSatisfy({$0.identity.pid>0 && $0.frame.valid}) else{return nil}
            return Dictionary(uniqueKeysWithValues:s.members.map{($0.identity.windowID,$0)})
        }
        let before=table(base),after=table(current)
        guard let before,let after else {
            return .init(version:version,cohortTranslation:nil,exactOriginalNeighborSide:false,commonTranslationConsistent:false,
                         strictProtectedAbsoluteFrames:nil,strictAllPeerFrames:nil,proposedGeometrySatisfied:false,rejections:[.missingOrDuplicateWindow],provenance:current.provenance,liveAdmission:false,mayMarkJournalReturned:false)
        }
        let shapePinned=Set(plan.cohort+[plan.anchor])
        let baselineOrder=ordered(base.members).map{ $0.identity.windowID }
        let cohortOrder=baselineOrder.filter{plan.cohort.contains($0)}
        let cohortPositions=cohortOrder.compactMap{baselineOrder.firstIndex(of:$0)}
        var protected=shapePinned
        if let first=cohortPositions.first,first>0 {protected.insert(baselineOrder[first-1])}
        if let last=cohortPositions.last,last+1<baselineOrder.count {protected.insert(baselineOrder[last+1])}
        let planShape=plan.cohort.count==3 && Set(plan.cohort).count==3 && plan.cohort.contains(plan.target) && plan.cohort.contains(plan.neighbor)
            && !plan.cohort.contains(plan.anchor) && plan.target != plan.neighbor && protected.allSatisfy{before[$0]?.identity.processPinned==true}
            && cohortPositions.count==3 && cohortPositions[2]-cohortPositions[0]==2
        func edge(_ t:Rect,_ n:Rect)->Bool {t.y==n.y && t.height==n.height && (plan.returnOnLeft ? t.right==n.x : t.x==n.right)}
        guard planShape,let bt=before[plan.target],let bn=before[plan.neighbor],edge(bt.frame,bn.frame),
              base.scope.display>0,base.scope.space>0,base.scope.bar.valid,base.scope.approvedArea.valid,
              base.sequence>=0,base.uptime.isFinite,base.coherent,base.readerHealthy else {reject(.invalidPlan);return result(nil,false,false,nil,nil)}
        for pair in zip(cohortOrder,cohortOrder.dropFirst()) {
            if before[pair.0]!.frame.right != before[pair.1]!.frame.x {reject(.invalidPlan)}
        }
        if !current.scope.bar.valid || !current.scope.approvedArea.valid || !current.uptime.isFinite {reject(.invalidSnapshot)}
        if current.scope != base.scope {reject(.scopeChanged)}
        if !current.coherent {reject(.tornSnapshot)}
        if !current.readerHealthy {reject(.unhealthyReader)}
        if current.sequence<=base.sequence || current.uptime<=base.uptime {reject(.reusedSequence)}
        if !base.completeDirectory || !current.completeDirectory {reject(.incompleteDirectory)}
        if Set(before.keys) != Set(after.keys) {reject(.missingOrDuplicateWindow)}
        for (id,old) in before {
            guard let now=after[id] else{continue}
            if protected.contains(id) {
                if now.identity != old.identity || !now.identity.processPinned {reject(.identityChanged)}
            } else if now.identity.pid != old.identity.pid {reject(.identityChanged)}
            if now.frame.y != old.frame.y || now.frame.height != old.frame.height {reject(.shapeOrRowChanged)}
        }
        for id in shapePinned {
            if let old=before[id],let now=after[id],!now.frame.sameShapeAndRow(old.frame) {reject(.shapeOrRowChanged)}
        }
        let deltas=plan.cohort.compactMap{id->Double? in guard let old=before[id],let now=after[id] else{return nil};return now.frame.x-old.frame.x}
        let uniform=deltas.count==3 && Set(deltas).count==1
        if !uniform {reject(.singleOrUnequalDisplacement)}
        let relative=after[plan.target].flatMap{t in after[plan.neighbor].map{edge(t.frame,$0.frame)}} ?? false
        if !relative {reject(.wrongNeighborSide)}
        // A partial archive must not invent adjacency across omitted windows.
        // It can classify the captured cohort but always refuses admission.
        if base.completeDirectory && current.completeDirectory {
            let newOrder=ordered(current.members).map{$0.identity.windowID}
            if newOrder != baselineOrder {reject(.orderChanged)}
            // Preserve the entire observed queue's original gaps, including the
            // cohort's external boundaries. Width changes outside the cohort are
            // permitted only if they produce a coherent layout, not a new gap/crossing.
            for pair in zip(baselineOrder,baselineOrder.dropFirst()) {
                if let a=after[pair.0],let b=after[pair.1] {
                    let expected=before[pair.1]!.frame.x-before[pair.0]!.frame.right
                    if b.frame.x-a.frame.right != expected {reject(.gapChanged)}
                }
            }
            if ordered(current.members).last?.frame.right != ordered(base.members).last?.frame.right {reject(.rightBoundaryChanged)}
        }
        if let now=after[plan.target],region(now.frame,current.scope.approvedArea) != region(bt.frame,base.scope.approvedArea) {reject(.regionChanged)}
        let absProtected=shapePinned.allSatisfy{before[$0]?.frame==after[$0]?.frame}
        let absAll=Set(before.keys)==Set(after.keys) && before.allSatisfy{after[$0.key]?.frame==$0.value.frame && after[$0.key]?.identity.pid==$0.value.identity.pid}
        return result(uniform ? deltas.first : nil,relative,uniform,absProtected,absAll)
        func result(_ delta:Double?,_ relative:Bool,_ uniform:Bool,_ absolute:Bool?,_ all:Bool?)->Decision {
            .init(version:version,cohortTranslation:delta,exactOriginalNeighborSide:relative,commonTranslationConsistent:uniform,
                  strictProtectedAbsoluteFrames:absolute,strictAllPeerFrames:all,proposedGeometrySatisfied:rejected.isEmpty,
                  rejections:rejected,provenance:current.provenance,liveAdmission:false,mayMarkJournalReturned:false)
        }
    }
    struct Stability {
        private(set)var count=0,lastSequence = -1,lastUptime = -Double.infinity,lastCounted = -Double.infinity,delta:Double?
        mutating func observe(_ plan:Plan,_ sample:Snapshot,now:Double)->(Decision,Bool) {
            var d=evaluate(plan,sample)
            var extra=d.rejections
            if sample.sequence<=lastSequence || sample.uptime<=lastUptime {extra.append(.reusedSequence)}
            if !now.isFinite || now<sample.uptime || now-sample.uptime>0.25 {extra.append(.staleSample)}
            lastSequence=max(lastSequence,sample.sequence);lastUptime=max(lastUptime,sample.uptime)
            if !extra.isEmpty {
                count=0;delta=nil;lastCounted = -Double.infinity
                d = .init(version:d.version,cohortTranslation:d.cohortTranslation,exactOriginalNeighborSide:d.exactOriginalNeighborSide,
                          commonTranslationConsistent:d.commonTranslationConsistent,strictProtectedAbsoluteFrames:d.strictProtectedAbsoluteFrames,
                          strictAllPeerFrames:d.strictAllPeerFrames,proposedGeometrySatisfied:false,rejections:Array(Set(extra)).sorted{$0.rawValue<$1.rawValue},
                          provenance:d.provenance,liveAdmission:false,mayMarkJournalReturned:false)
                return(d,false)
            }
            if delta != d.cohortTranslation {count=0;lastCounted = -Double.infinity;delta=d.cohortTranslation}
            if sample.uptime-lastCounted>=0.1 {count+=1;lastCounted=sample.uptime}
            return(d,count>=3)
        }
    }
}
