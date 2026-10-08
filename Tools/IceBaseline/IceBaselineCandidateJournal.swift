// Copyright (c) 2026 Ryan.AI. MIT. Candidate-only durable responsibility ledger.
// Checksums detect corruption; they do not authenticate another same-user writer.
import Foundation
import CoreGraphics
import CryptoKit
import Darwin

enum IceCandidateContract: String, Codable, Sendable {
    case disabled, isolatedOwnedQuietV1,isolatedOwnedANYV1, productionANY
}
enum IceCandidateFailure: Error { case policy, binding, pendingRecovery, phase, packet, stopped, budget, unresolvedDown }

struct IceCandidateBinding: Codable, Equatable, Sendable {
    struct Process: Codable, Equatable, Sendable {
        let pid: Int32, launch: Double, executable: String, identifier: String, sha256: String
        let team: String?
        init(_ p: MenuBarProcessSignature.Proof) throws {
            guard let launch=p.launch else { throw IceCandidateFailure.binding }
            pid=p.pid;self.launch=launch;executable=p.executable;identifier=p.identifier;sha256=p.sha256;team=p.team
        }
        init(pid:Int32,launch:Double,executable:String,identifier:String,sha256:String,team:String?=nil) {
            self.pid=pid;self.launch=launch;self.executable=executable;self.identifier=identifier;self.sha256=sha256;self.team=team
        }
    }
    struct Rect: Codable, Equatable, Sendable {
        let x:Double,y:Double,width:Double,height:Double
        init(_ f:CGRect) { x=f.minX;y=f.minY;width=f.width;height=f.height }
        var cg:CGRect { CGRect(x:x,y:y,width:width,height:height) }
        var valid:Bool { [x,y,width,height].allSatisfy{$0.isFinite} && width>0 && height>0 }
    }
    struct Item: Codable, Equatable, Sendable {
        let id:UInt32,instance:String,key:String,frame:Rect,screen:UInt32
        init(_ i:IceBaselineLayout.Item) { id=i.id;instance=i.instance;key=i.key;frame=Rect(i.frame);screen=i.screen }
    }
    let nonce:UUID,controller:Process,fixture:Process,display:UInt32,space:UInt,area:Rect
    let target:Item,neighbor:Item,anchor:Item,divider:Item,returnOnLeft:Bool
    init(nonce:UUID,controller:Process,fixture:Process,display:UInt32,space:UInt,area:CGRect,layout:IceBaselineLayout) {
        self.nonce=nonce;self.controller=controller;self.fixture=fixture;self.display=display;self.space=space
        self.area=Rect(area);target=Item(layout.target);neighbor=Item(layout.neighbor);anchor=Item(layout.anchor)
        divider=Item(layout.divider);returnOnLeft=layout.returnOnLeft
    }
    func validate() throws {
        let items=[target,neighbor,anchor,divider]
        guard controller.pid>0,fixture.pid>0,controller.pid  !=  fixture.pid,
              controller.launch.isFinite,controller.launch>0,fixture.launch.isFinite,fixture.launch>0,
              controller.identifier == "com.ryanai.mactools",fixture.identifier == "com.ryanai.mactools.nativetargets",
              controller.executable.hasSuffix("/Ice Baseline Controller.app/Contents/MacOS/IceBaselineController"),
              fixture.executable.hasSuffix("/Ice Baseline Targets.app/Contents/MacOS/IceBaselineTargets"),
              Self.validHash(controller.sha256),Self.validHash(fixture.sha256),controller.team == fixture.team,
              display>0,space>0,area.valid,Set(items.map(\.id)).count == 4,
              Set(items.map(\.instance)).count == 4,
              items.allSatisfy({$0.id>0 && UUID(uuidString:$0.instance)  !=  nil && $0.screen == display && $0.frame.valid}),
              target.key == "mactools_native_acceptance_T",neighbor.key == "mactools_native_acceptance_N",
              anchor.key == "ice_baseline_H_\(nonce.uuidString)",divider.key == "ice_baseline_D_\(nonce.uuidString)",
              area.cg.contains(anchor.frame.cg),target.frame.cg.maxX<=0,neighbor.frame.cg.maxX<=0,
              returnOnLeft ? target.frame.cg.maxX == neighbor.frame.x : target.frame.x == neighbor.frame.cg.maxX,
              items.allSatisfy({$0.frame.y == target.frame.y && $0.frame.height == target.frame.height}),
              anchor.frame.x-target.frame.width>=area.x+20,
              divider.frame.x == max(target.frame.cg.maxX,neighbor.frame.cg.maxX) else { throw IceCandidateFailure.binding }
    }
    static func validHash(_ s:String)->Bool { s.count == 64 && s.allSatisfy{"0123456789abcdef".contains($0)} }
}
struct IceCandidatePacket: Codable, Equatable, Sendable {
    let type:UInt32,flags:UInt64,x:Double,y:Double,pid:Int64,marker:Int64,window:Int64,click:Int64,timestamp:UInt64,sourceState:Int64
    let sourcePID:Int64?,number:Int64?,pointerWindow:Int64?,handlingWindow:Int64?
    init(_ e:CGEvent) {
        type=e.type.rawValue;flags=e.flags.rawValue;x=e.location.x;y=e.location.y
        pid=e.getIntegerValueField(.eventTargetUnixProcessID);marker=e.getIntegerValueField(.eventSourceUserData)
        window=e.getIntegerValueField(CGEventField(rawValue:0x33)!);click=e.getIntegerValueField(.mouseEventClickState)
        timestamp=e.timestamp;sourceState=e.getIntegerValueField(.eventSourceStateID)
        sourcePID=e.getIntegerValueField(.eventSourceUnixProcessID);number=e.getIntegerValueField(.mouseEventNumber)
        pointerWindow=e.getIntegerValueField(.mouseEventWindowUnderMousePointer);handlingWindow=e.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent)
    }
    var valid:Bool { x.isFinite && y.isFinite && marker>0 && [0,1,2].contains(type) }
}
struct IceCandidateRecord: Codable, Equatable, Sendable {
    enum Phase:String,Codable,Sendable { case prepared,moving,visible,opening,menuClosed,restoring,returned,stopped }
    enum Status:String,Codable,Sendable { case registered,downReserved,downReturned,upReserved,pairedTransportReturned }
    struct Route:Codable,Equatable,Sendable {
        let id:UUID,packet:IceCandidatePacket,destination:String
    }
    struct Gesture:Codable,Equatable,Sendable {
        let id:UUID,down:IceCandidatePacket,up:IceCandidatePacket
        var status:Status = .registered
        var routes:[Route] = []
    }
    let schemaVersion:Int,transaction:UUID,generation:UUID,binding:IceCandidateBinding,contract:IceCandidateContract
    var revision:Int=0,phase:Phase = .prepared,gestures:[Gesture]=[],stopReason:String?,returnedEvidenceSHA256:String?
    struct Source:Codable,Equatable,Sendable {let senderPID:Int32,state:Int64}
    var packetSource:Source?
    init(binding:IceCandidateBinding,generation:UUID,contract:IceCandidateContract) {
        schemaVersion=1;transaction=UUID();self.generation=generation;self.binding=binding;self.contract=contract
    }
    // Reservation is conservative: it is NOT evidence that a route was sent.
    var needsRelease:Bool { gestures.contains{[Status.downReserved,.downReturned,.upReserved].contains($0.status)} }
    var hasPossibleEffect:Bool { gestures.contains{ !$0.routes.isEmpty } }
    func validate() throws {
        try binding.validate()
        guard schemaVersion == 1,revision>=0,revision<=10000,[IceCandidateContract.isolatedOwnedQuietV1,.isolatedOwnedANYV1].contains(contract),
              gestures.count<=3,gestures.reduce(0,{$0+$1.routes.count})<=14,
              Set(gestures.map(\.id)).count == gestures.count,
              Set(gestures.flatMap { $0.routes.map(\.id) }).count == gestures.reduce(0,{$0+$1.routes.count}) else { throw IceCandidateFailure.binding }
        if contract == .isolatedOwnedQuietV1 {guard packetSource==nil else{throw IceCandidateFailure.packet}}
        else {guard let packetSource,packetSource.senderPID==binding.controller.pid,packetSource.state>0,packetSource.state != 1 else{throw IceCandidateFailure.packet}}
        for (index,g) in gestures.enumerated() {
            guard g.down.valid,g.up.valid,g.down.type == 1,g.up.type == 2,
                  g.down.pid == Int64(binding.fixture.pid),g.up.pid == g.down.pid,
                  g.down.window == Int64(binding.target.id),
                  [binding.target.id,binding.neighbor.id,binding.anchor.id].contains(UInt32(exactly:g.up.window) ?? 0),
                  validSource(g.down),validSource(g.up),
                  g.down.marker  !=  g.up.marker,g.up.flags == 0,
                  [UInt64(0),CGEventFlags.maskCommand.rawValue].contains(g.down.flags),
                  Set(g.routes.map(\.id)).count == g.routes.count else { throw IceCandidateFailure.packet }
            let opening=index == 1
            guard g.down.flags == (opening ? 0 : CGEventFlags.maskCommand.rawValue),g.down.click == 1,g.up.click == (opening ? 1 : 0),
                  g.up.window == Int64(opening ? binding.target.id : (index == 0 ? binding.anchor.id : binding.neighbor.id)) else { throw IceCandidateFailure.packet }
            if opening {
                guard g.down.x == g.up.x,g.down.y == g.up.y,binding.area.cg.contains(CGPoint(x:g.down.x,y:g.down.y)) else { throw IceCandidateFailure.packet }
            } else {
                guard g.down.x == 20000,g.down.y == 20000,
                      g.up.y == (index == 0 ? binding.anchor.frame.cg.midY : binding.neighbor.frame.cg.midY),
                      index != 0 || g.up.x == binding.anchor.frame.x else { throw IceCandidateFailure.packet }
            }
            guard index == gestures.count-1 || g.status == .pairedTransportReturned else { throw IceCandidateFailure.unresolvedDown }
            let width = g.down.flags == 0 ? 1 : 3
            let expectedCount = g.status == .registered ? 0 : ([Status.downReserved,.downReturned].contains(g.status) ? width : width*2)
            guard g.routes.count == expectedCount else { throw IceCandidateFailure.packet }
            for (offset,r) in g.routes.enumerated() {
                let packet = offset < width ? g.down : g.up
                if width == 3 && offset % width == 0 {
                    guard r.packet.type == 0,r.destination == "PID \(binding.fixture.pid)" else { throw IceCandidateFailure.packet }
                } else {
                    guard r.packet == packet,r.destination == (width == 1 || offset % width == 1 ? "session event tap" : "PID \(binding.fixture.pid)") else { throw IceCandidateFailure.packet }
                }
            }
            for r in g.routes {
                let real=r.packet == g.down || r.packet == g.up
                let null=r.packet.type == 0 && r.packet.marker == IceBaselinePacket.nullMarker
                guard r.packet.valid,(real || null),
                      ["PID \(binding.fixture.pid)","session event tap"].contains(r.destination),
                      !null || r.destination == "PID \(binding.fixture.pid)" else { throw IceCandidateFailure.packet }
            }
        }
        let range:ClosedRange<Int>
        switch phase {
        case .prepared:range=0...0
        case .moving:range=0...1
        case .visible:range=1...1
        case .opening:range=1...2
        case .menuClosed:range=2...2
        case .restoring:range=2...3
        case .returned:range=3...3
        case .stopped:range=0...3
        }
        guard range.contains(gestures.count) else { throw IceCandidateFailure.phase }
        if [.visible,.menuClosed].contains(phase) { guard !needsRelease,gestures.allSatisfy({$0.status == .pairedTransportReturned}) else { throw IceCandidateFailure.unresolvedDown } }
        if phase == .returned { guard !needsRelease,gestures.count == 3,gestures.allSatisfy({$0.status == .pairedTransportReturned}),let hash=returnedEvidenceSHA256,IceCandidateBinding.validHash(hash) else { throw IceCandidateFailure.unresolvedDown } }
        else { guard returnedEvidenceSHA256 == nil else { throw IceCandidateFailure.phase } }
        guard (phase == .stopped) == (stopReason != nil) else { throw IceCandidateFailure.phase }
    }
    func validSource(_ packet:IceCandidatePacket)->Bool {
        if contract == .isolatedOwnedQuietV1{return packet.sourceState==1 && packetSource==nil}
        guard contract == .isolatedOwnedANYV1,let packetSource,packetSource.senderPID==binding.controller.pid,
              packetSource.state>0,packetSource.state != Int64(CGEventSourceStateID.hidSystemState.rawValue),
              packet.sourceState==packetSource.state,packet.sourcePID==Int64(packetSource.senderPID),packet.timestamp>0,
              let number=packet.number,Int16(exactly:number) != nil,
              packet.pointerWindow==packet.window,packet.handlingWindow==packet.window else{return false}
        return true
    }
}

/// Off-main I/O is serialized by thread/process locks; write failures poison this
/// store instance. Inspection after restart preserves a valid committed envelope.
final class IceBaselineCandidateJournal: @unchecked Sendable {
    enum Point:Sendable { case temporaryCreated,fileSynced,renamed,directorySynced,removed,archiveFileSynced,archiveLinked,archiveDirectorySynced,retirementRemoved }
    enum Failure:Error { case busy,unsafeFile,corrupt,stale,transition,poisoned,io(Int32) }
    private struct Envelope:Codable { let version:Int,checksum:String,payload:Data }
    let directory:URL
    private let mutex=NSLock(),fault:@Sendable(Point)throws->Void
    private var identity:(dev_t,ino_t)?,poisoned=false
    private let filename="ice-candidate-v1.json",limit=524_288
    init(directory:URL,fault:@escaping @Sendable(Point)throws->Void={_ in}) {
        self.directory=directory.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(directory.lastPathComponent,isDirectory:true)
        self.fault=fault
    }
    func inspect() throws->IceCandidateRecord? { try locked(create:false){fd in fd<0 ? nil : try read(fd)} }
    func persist(_ next:IceCandidateRecord,replacing previous:IceCandidateRecord?) throws->IceCandidateRecord {
        try next.validate()
        return try locked(create:true){fd in
            guard !poisoned else { throw Failure.poisoned }
            let current=try read(fd)
            guard current == previous else { throw Failure.stale }
            if let previous {
                guard next.binding == previous.binding,next.transaction == previous.transaction,next.generation == previous.generation,
                      next.contract == previous.contract,next.packetSource==previous.packetSource,next.revision == previous.revision+1,
                      Self.transition(previous.phase,next.phase),Self.appendOnly(previous,next),
                      previous.phase == next.phase || next.phase == .stopped || (!previous.needsRelease && previous.gestures == next.gestures) else { throw Failure.transition }
            } else { guard next.phase == .prepared,next.revision == 0,next.gestures.isEmpty else { throw Failure.transition } }
            do {
                let parent=open(directory.deletingLastPathComponent().path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
                guard parent>=0 else { throw Failure.unsafeFile };defer{Darwin.close(parent)};try sync(parent)
                let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
                let payload=try encoder.encode(next),bytes=try encoder.encode(Envelope(version:1,checksum:Self.hash(payload),payload:payload))
                guard bytes.count<=limit else { throw Failure.corrupt }
                let temp=".ice-candidate-\(UUID()).tmp",output=openat(fd,temp,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0o600)
                guard output>=0 else { throw Failure.io(errno) };defer{Darwin.close(output);unlinkat(fd,temp,0)}
                try fault(.temporaryCreated)
                try bytes.withUnsafeBytes{buffer in
                    var offset=0
                    while offset<buffer.count {
                        let n=Darwin.write(output,buffer.baseAddress!.advanced(by:offset),buffer.count-offset)
                        if n<0 && errno == EINTR { continue };guard n>0 else { throw Failure.io(errno) };offset+=n
                    }
                }
                try sync(output);try fault(.fileSynced)
                guard renameat(fd,temp,fd,filename) == 0 else { throw Failure.io(errno) }
                try fault(.renamed);try sync(fd);try fault(.directorySynced)
                return next
            } catch { poisoned=true;throw error }
        }
    }
    func clear(_ returned:IceCandidateRecord) throws {
        try returned.validate()
        guard returned.phase == .returned,!returned.needsRelease else { throw Failure.transition }
        try locked(create:false){fd in
            guard !poisoned,fd>=0,try read(fd) == returned else { throw Failure.stale }
            do {
                guard unlinkat(fd,filename,0) == 0 else { throw Failure.io(errno) }
                try fault(.removed);try sync(fd)
            } catch { poisoned=true;throw error }
        }
    }
    /// Explicit disposal retires an extinct owned fixture, never claims native
    /// restoration or physical release. The durable receipt precedes unlink.
    func retireDisposed(_ proof:IceCandidateDisposalProof,receipt:IceCandidateRetirementReceipt)throws->IceCandidateRetirementReceipt {
        let record=proof.record;try record.validate();try receipt.validate(record)
        try proof.validate(record,now:ProcessInfo.processInfo.systemUptime)
        return try locked(create:false){fd in
            guard !poisoned,fd>=0,try read(fd)==record else{throw Failure.stale}
            try proof.validate(record,now:ProcessInfo.processInfo.systemUptime)
            let name="retired-owned-\(record.transaction.uuidString).json"
            func existing()throws->IceCandidateRetirementReceipt? {
                let input=openat(fd,name,O_RDONLY|O_NONBLOCK|O_NOFOLLOW|O_CLOEXEC)
                if input<0{if errno==ENOENT{return nil};throw Failure.unsafeFile};defer{Darwin.close(input)}
                try regular(input);var bytes=Data(),buffer=[UInt8](repeating:0,count:8192)
                while true{let n=buffer.withUnsafeMutableBytes{Darwin.read(input,$0.baseAddress,$0.count)}
                    if n<0 && errno==EINTR{continue};guard n>=0 else{throw Failure.io(errno)};if n==0{break}
                    guard bytes.count+n<=limit else{throw Failure.corrupt};bytes.append(contentsOf:buffer.prefix(n))}
                let saved=try JSONDecoder().decode(IceCandidateRetirementReceipt.self,from:bytes);try saved.validate(record);return saved
            }
            do {
                var saved=try existing()
                if saved==nil {
                    let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys];let bytes=try encoder.encode(receipt)
                    guard bytes.count<=limit else{throw Failure.corrupt}
                    let temp=".ice-retirement-\(UUID()).tmp",output=openat(fd,temp,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0o600)
                    guard output>=0 else{throw Failure.io(errno)};defer{Darwin.close(output);unlinkat(fd,temp,0)}
                    try bytes.withUnsafeBytes{b in var offset=0
                        while offset<b.count{let n=Darwin.write(output,b.baseAddress!.advanced(by:offset),b.count-offset)
                            if n<0 && errno==EINTR{continue};guard n>0 else{throw Failure.io(errno)};offset+=n}}
                    try sync(output);try fault(.archiveFileSynced)
                    guard linkat(fd,temp,fd,name,0)==0 else{throw Failure.io(errno)}
                    guard unlinkat(fd,temp,0)==0 else{throw Failure.io(errno)}
                    try fault(.archiveLinked);try sync(fd);try fault(.archiveDirectorySynced)
                    saved=try existing()
                } else {try sync(fd)}
                guard let saved else{throw Failure.corrupt}
                // Re-observe immediately before clear. A stale proof, re-used
                // window or live PID keeps the original record despite archive.
                try proof.validate(record,now:ProcessInfo.processInfo.systemUptime)
                guard IceBaselineRecovery.sample(record).disposed else{throw IceCandidateFailure.binding}
                guard unlinkat(fd,filename,0)==0 else{throw Failure.io(errno)}
                try fault(.retirementRemoved);try sync(fd);return saved
            }catch{poisoned=true;throw error}
        }
    }
    private static func transition(_ a:IceCandidateRecord.Phase,_ b:IceCandidateRecord.Phase)->Bool {
        if a == b { return a  !=  .stopped && a  !=  .returned }
        if b == .stopped { return a  !=  .returned && a  !=  .stopped }
        switch(a,b) {
        case (.prepared,.moving),(.moving,.visible),(.visible,.opening),(.opening,.menuClosed),(.menuClosed,.restoring),(.restoring,.returned):return true
        default:return false
        }
    }
    private static func appendOnly(_ old:IceCandidateRecord,_ new:IceCandidateRecord)->Bool {
        guard new.gestures.count>=old.gestures.count,new.gestures.count<=old.gestures.count+1 else{return false}
        for (before,after) in zip(old.gestures,new.gestures) {
            guard before.id == after.id,before.down == after.down,before.up == after.up,
                  after.routes.count>=before.routes.count,
                  Array(after.routes.prefix(before.routes.count)) == before.routes else{return false}
            if before.status != after.status {
                let allowed:[IceCandidateRecord.Status:IceCandidateRecord.Status]=[.registered:.downReserved,.downReserved:.downReturned,.downReturned:.upReserved,.upReserved:.pairedTransportReturned]
                guard allowed[before.status] == after.status else{return false}
            }else if before.routes != after.routes{return false}
        }
        if new.gestures.count>old.gestures.count {
            guard old.gestures.last == nil || old.gestures.last?.status == .pairedTransportReturned,
                  new.gestures.last?.status == .registered,new.gestures.last?.routes.isEmpty == true else{return false}
        }
        return true
    }
    private func locked<T>(create:Bool,_ body:(Int32)throws->T)throws->T {
        guard mutex.try() else { throw Failure.busy };defer{mutex.unlock()}
        if create { guard mkdir(directory.path,0o700) == 0 || errno == EEXIST else { throw Failure.io(errno) } }
        let fd=open(directory.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
        if fd<0 && errno == ENOENT && !create { return try body(-1) }
        guard fd>=0 else { throw Failure.unsafeFile };defer{Darwin.close(fd)}
        var s=stat();guard fstat(fd,&s) == 0,s.st_uid == getuid(),s.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),s.st_mode & 0o777 == 0o700 else { throw Failure.unsafeFile }
        if let old=identity { guard old.0 == s.st_dev,old.1 == s.st_ino else { throw Failure.unsafeFile } } else { identity=(s.st_dev,s.st_ino) }
        let lockFD=openat(fd,".ice-candidate.lock",O_RDWR|O_CREAT|O_NONBLOCK|O_NOFOLLOW|O_CLOEXEC,0o600)
        guard lockFD>=0 else { throw Failure.unsafeFile };defer{Darwin.close(lockFD)};try regular(lockFD)
        guard flock(lockFD,LOCK_EX|LOCK_NB) == 0 else { throw Failure.busy };defer{flock(lockFD,LOCK_UN)}
        return try body(fd)
    }
    private func regular(_ fd:Int32)throws {
        var s=stat();guard fstat(fd,&s) == 0,s.st_uid == getuid(),s.st_nlink == 1,s.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),s.st_mode & 0o777 == 0o600,s.st_size>=0,s.st_size<=limit else { throw Failure.unsafeFile }
    }
    private func read(_ fd:Int32)throws->IceCandidateRecord? {
        let input=openat(fd,filename,O_RDONLY|O_NONBLOCK|O_NOFOLLOW|O_CLOEXEC)
        if input<0 { if errno == ENOENT{return nil};throw Failure.unsafeFile };defer{Darwin.close(input)};try regular(input)
        var bytes=Data(),buffer=[UInt8](repeating:0,count:8192)
        while true {
            let n=buffer.withUnsafeMutableBytes{Darwin.read(input,$0.baseAddress,$0.count)}
            if n<0 && errno == EINTR{continue};guard n>=0 else{throw Failure.io(errno)};if n == 0{break}
            guard bytes.count+n<=limit else{throw Failure.corrupt};bytes.append(contentsOf:buffer.prefix(n))
        }
        do {
            let envelope=try JSONDecoder().decode(Envelope.self,from:bytes)
            guard envelope.version == 1,envelope.checksum == Self.hash(envelope.payload) else{throw Failure.corrupt}
            let record=try JSONDecoder().decode(IceCandidateRecord.self,from:envelope.payload);try record.validate();return record
        }catch{throw Failure.corrupt}
    }
    private func sync(_ fd:Int32)throws { while fsync(fd)  !=  0 { if errno  !=  EINTR{throw Failure.io(errno)} } }
    static func hash(_ data:Data)->String { SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined() }
}
