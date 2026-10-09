// Copyright (c) 2026 Ryan.AI. MIT.
// Exact interrupted QQ trial only. Administrative archive; no input sender.
import AppKit
import Darwin

@MainActor enum QQV9CrashReconciliation {
    static let oldRoot=URL(fileURLWithPath:"/Users/yangruihan/Library/Application Support/MacTools/IceInterfaceCandidate")
    static let nonce=UUID(uuidString:"C21AAC11-C095-4392-8DF9-2CDE8DCBB101")!
    static let transaction=UUID(uuidString:"01463608-6572-4F7C-8914-54DE4926DF52")!
    static let originalHash="5a2f553d74f97e3efb7919b238ea3aee5734a108c9f12dfc6fbea21ef033c388"
    static let sessionResultHash="5c08fc5cca40ff43283cf885f1fe1c24807c911ba366b65f64d94107ca6fe0be"
    static let sessionResultURL=URL(fileURLWithPath:"/Users/yangruihan/Library/Application Support/MacTools/IceInterfaceCandidate/session-C21AAC11-C095-4392-8DF9-2CDE8DCBB101/result.json")
    static let journalDirectory=oldRoot.appendingPathComponent("selected-relative-recovery-v2")
    static let filename="ice-selected-relative-v2.json"
    enum Failure:Error {case binding,trace,heldInput,menu,position,controller,archive,stale}
    static func require(_ condition:Bool,_ error:Failure)throws {guard condition else{throw error}}
    static func object(_ data:Data)throws->[String:Any] {
        guard data.count<2_000_000,let value=try JSONSerialization.jsonObject(with:data) as? [String:Any] else{throw Failure.binding};return value
    }
    static func validateRecord(_ record:IceSelectedRecord)throws {
        try record.validate();let b=record.binding
        try require(record.transaction==transaction && b.nonce==nonce && record.schemaVersion==4 && record.phase == .stopped && record.contract == .ordinaryIceInterfaceV9 && !record.needsRelease && record.returnedEvidenceSHA256==nil,.binding)
        try require(b.owner.pid==35462 && b.owner.identifier=="com.tencent.QQMusicMac" && b.owner.executable=="/Applications/QQMusic.app/Contents/MacOS/QQMusic" && b.owner.team=="FN2V63AD2J" && b.owner.launch==1791024996.18447 && b.target.id==310606,.binding)
        try require(b.controller.pid==1717 && b.controller.executable=="/Applications/MacTools.app/Contents/Resources/IceWorker/Ice Selected Controller.app/Contents/MacOS/IceSelectedController" && b.controller.sha256=="b4f07c7612a4c7382157e5065e894ecb0c60f64a068823ee0c8f3eb53ddadf8d" && b.controller.launch==1791567902.198381 && b.anchor.id==363136 && b.neighbor.id==359308 && b.returnOnLeft && b.space==4634 && b.display==1,.binding)
        try require(record.gestures.count==2 && record.gestures.allSatisfy{$0.status == .pairedTransportReturned} && record.gestures[0].routes.count==6 && record.gestures[1].routes.count==2,.trace)
    }
    static func original()throws->(IceSelectedRecord,Data) {
        let bytes=try Data(contentsOf:journalDirectory.appendingPathComponent(filename))
        try require(IceSelectedJournal.hash(bytes)==originalHash,.binding)
        let envelope=try object(bytes)
        guard envelope["version"] as? Int==1,let encoded=envelope["payload"] as? String,let payload=Data(base64Encoded:encoded),
              envelope["checksum"] as? String==IceSelectedJournal.hash(payload) else{throw Failure.binding}
        let record=try JSONDecoder().decode(IceSelectedRecord.self,from:payload);try validateRecord(record)
        let session=oldRoot.appendingPathComponent("session-"+nonce.uuidString)
        let prepared=try JSONDecoder().decode(IceSelectedSession.Prepared.self,from:Data(contentsOf:session.appendingPathComponent("session.json")))
        try require(!prepared.selfOwned && prepared.nonce==nonce && prepared.selected?.owner.pid==record.binding.owner.pid && prepared.selected?.windowID==record.binding.target.id && prepared.controllerSHA256==record.binding.controller.sha256,.binding)
        try require(FileManager.default.fileExists(atPath:session.appendingPathComponent("result.json").path) && FileManager.default.fileExists(atPath:session.appendingPathComponent("cleanup.json").path),.trace)
        let crash=try Data(contentsOf:sessionResultURL);try require(IceSelectedJournal.hash(crash)==sessionResultHash,.trace)
        return (record,bytes)
    }
    static func gone(_ pid:Int32)->Bool {Darwin.kill(pid,0)<0 && errno==ESRCH}
    static func sample(_ record:IceSelectedRecord,controllerGone:Bool)throws->[String:Any] {
        let b=record.binding
        let runtime=try IceSelectedRuntime([b.owner,b.neighbor.process]);try runtime.checkFullSignatures();try runtime.check()
        let windows=try IceBaselineWindows()
        let screens=NSScreen.screens,actualDisplay=(screens.first?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        let actualSpace=windows.activeSpace(windows.connection())
        if screens.count != 1 || actualDisplay != b.display || actualSpace != b.space {
            let facts:[String:Any]=["check":"recovery-scope","atUptime":ProcessInfo.processInfo.systemUptime,"screenCount":screens.count,
                "expectedDisplay":b.display,"actualDisplay":actualDisplay,"expectedSpace":b.space,"actualSpace":actualSpace]
            fputs(String(decoding:try JSONSerialization.data(withJSONObject:facts,options:[.sortedKeys]),as:UTF8.self)+"\n",stderr)
            throw Failure.binding
        }
        guard let all=CGWindowListCopyWindowInfo(.optionAll,kCGNullWindowID) as? [[String:Any]] else{throw Failure.binding}
        let visible=all.filter{($0[kCGWindowIsOnscreen as String] as? Bool)==true}
        try require(!visible.contains{($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value==b.owner.pid && ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value != b.target.id},.menu)
        let hid=CGEventSource.buttonState(.hidSystemState,button:.left),combined=CGEventSource.buttonState(.combinedSessionState,button:.left)
        let modifiers:CGEventFlags=[.maskCommand,.maskShift,.maskControl,.maskAlternate,.maskSecondaryFn]
        try require(!hid && !combined && NSEvent.pressedMouseButtons==0 && CGEventSource.flagsState(.hidSystemState).intersection(modifiers).isEmpty && CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty,.heldInput)
        func frame(_ item:IceSelectedBinding.Item)throws->CGRect {
            let matching=all.filter{($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value==item.id && ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value==item.process.pid && ($0[kCGWindowLayer as String] as? NSNumber)?.intValue==Int(CGWindowLevelForKey(.statusWindow))}
            guard matching.count==1,let bounds=matching[0][kCGWindowBounds as String] as? [String:Any],let publicFrame=CGRect(dictionaryRepresentation:bounds as CFDictionary) else{throw Failure.binding}
            let privateFrame=try windows.frame(.init(windowID:item.id,pid:item.process.pid,key:"recovery-read-only"))
            try require(publicFrame==privateFrame,.position);return privateFrame
        }
        let t=try frame(b.target),n=try frame(b.neighbor)
        try require(IceSelectedPlan.quickPosition(t,n,onLeft:b.returnOnLeft),.position)
        if controllerGone {
            try require(gone(b.controller.pid) && !all.contains{($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value==b.controller.pid || ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value==b.anchor.id},.controller)
        } else {
            let own=try IceSelectedBinding.Process(MenuBarProcessSignature.read(b.controller.pid));try require(own==b.controller,.controller)
        }
        return ["atUptime":ProcessInfo.processInfo.systemUptime,"targetFrame":NSStringFromRect(t),"neighborFrame":NSStringFromRect(n),"targetID":b.target.id,"neighborID":b.neighbor.id,"sameIdentityAndScope":true,"originalNeighborSameSide":true,"noVisibleOwnerPopup":true,"noVisibleOwnerInterface":true,"hidLeftDown":hid,"combinedLeftDown":combined,"pressedMouseButtons":0,"commandShiftControlOptionFnDown":false,"controllerGone":controllerGone,"nativePosts":0,"physicalReleaseProven":false]
    }
    static func syncedWrite(_ bytes:Data,directoryFD:Int32,name:String)throws {
        let temp=".qq-reconcile-"+UUID().uuidString
        let fd=openat(directoryFD,temp,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0o600)
        try require(fd>=0,.archive);defer{Darwin.close(fd);unlinkat(directoryFD,temp,0)}
        try bytes.withUnsafeBytes{buffer in var offset=0;while offset<buffer.count {
            let n=Darwin.write(fd,buffer.baseAddress!.advanced(by:offset),buffer.count-offset)
            if n<0 && errno==EINTR{continue};try require(n>0,.archive);offset+=n
        }}
        try require(fsync(fd)==0 && linkat(directoryFD,temp,directoryFD,name,0)==0 && unlinkat(directoryFD,temp,0)==0 && fsync(directoryFD)==0,.archive)
    }
    static func reconcile()async throws->[String:Any] {
        let (record,originalBytes)=try original()
        let first=try sample(record,controllerGone:true)
        try await Task.sleep(nanoseconds:150_000_000)
        let second=try sample(record,controllerGone:true)
        try require(first["targetFrame"] as? String==second["targetFrame"] as? String && first["neighborFrame"] as? String==second["neighborFrame"] as? String,.position)
        let d=open(journalDirectory.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);try require(d>=0,.archive);defer{Darwin.close(d)}
        let lock=openat(d,".ice-selected.lock",O_RDWR|O_NOFOLLOW|O_CLOEXEC);try require(lock>=0,.archive);defer{Darwin.close(lock)}
        var lockInfo=stat();try require(fstat(lock,&lockInfo)==0 && lockInfo.st_uid==getuid() && (lockInfo.st_mode & S_IFMT)==S_IFREG && lockInfo.st_nlink==1,.archive)
        try require(flock(lock,LOCK_EX|LOCK_NB)==0,.archive);defer{flock(lock,LOCK_UN)}
        let activeFD=openat(d,filename,O_RDONLY|O_NOFOLLOW|O_CLOEXEC);try require(activeFD>=0,.archive);defer{Darwin.close(activeFD)}
        var info=stat();try require(fstat(activeFD,&info)==0 && info.st_uid==getuid() && (info.st_mode & S_IFMT)==S_IFREG && info.st_size==originalBytes.count && info.st_nlink<=2,.archive)
        try require(try Data(contentsOf:journalDirectory.appendingPathComponent(filename))==originalBytes,.stale)
        let archived="qqmusic-interface-observation-manual-return-original-"+transaction.uuidString+".json"
        let receiptName="qqmusic-interface-observation-manual-return-receipt-"+transaction.uuidString+".json"
        if FileManager.default.fileExists(atPath:journalDirectory.appendingPathComponent(archived).path) {
            try require(try Data(contentsOf:journalDirectory.appendingPathComponent(archived))==originalBytes,.archive)
        } else {try require(linkat(d,filename,d,archived,0)==0 && fsync(d)==0,.archive)}
        let receipt:[String:Any]=["version":1,"disposition":"userConfirmedQQMusicNeighborObservedAfterInterfaceObservationStop","originalEnvelopeSHA256":originalHash,"sessionResultSHA256":sessionResultHash,"transaction":transaction.uuidString,"nonce":nonce.uuidString,"originalPhase":"stopped","originalGestureStatus":"pairedTransportReturned","durablePairedRoutes":8,"historicalActualPosts":8,"historicalPairingConfirmed":true,"terminalResultPublished":true,"recoveryNativePosts":0,"AXActionsRequested":0,"nativeReturnProven":false,"physicalReleaseProven":false,"fullRelativeQueueVerified":false,"currentIceNeighborPositionVerified":true,"userReportedManualReturnComplete":true,"first":first,"second":second,"originalRecord":try JSONSerialization.jsonObject(with:JSONEncoder().encode(record))]
        let bytes=try JSONSerialization.data(withJSONObject:receipt,options:[.prettyPrinted,.sortedKeys])
        if !FileManager.default.fileExists(atPath:journalDirectory.appendingPathComponent(receiptName).path) {try syncedWrite(bytes,directoryFD:d,name:receiptName)}
        else {let saved=try object(Data(contentsOf:journalDirectory.appendingPathComponent(receiptName)));try require(saved["originalEnvelopeSHA256"] as? String==originalHash && saved["sessionResultSHA256"] as? String==sessionResultHash,.archive)}
        let final=try sample(record,controllerGone:true)
        try require(final["targetFrame"] as? String==second["targetFrame"] as? String && final["neighborFrame"] as? String==second["neighborFrame"] as? String,.position)
        try require(try Data(contentsOf:journalDirectory.appendingPathComponent(filename))==originalBytes && IceSelectedJournal.hash(try Data(contentsOf:journalDirectory.appendingPathComponent(archived)))==originalHash,.stale)
        try require(!CGEventSource.buttonState(.hidSystemState,button:.left) && !CGEventSource.buttonState(.combinedSessionState,button:.left) && NSEvent.pressedMouseButtons==0 && gone(record.binding.controller.pid),.heldInput)
        try Task.checkCancellation()
        try require(unlinkat(d,filename,0)==0 && fsync(d)==0,.archive)
        return ["reconciled":true,"disposition":receipt["disposition"]!,"activeJournalPending":false,"originalArchive":journalDirectory.appendingPathComponent(archived).path,"receipt":journalDirectory.appendingPathComponent(receiptName).path,"receiptSHA256":IceSelectedJournal.hash(try Data(contentsOf:journalDirectory.appendingPathComponent(receiptName))),"final":final,"nativePosts":0,"nativeReturnProven":false,"physicalReleaseProven":false]
    }
    static func traceTests()throws->[String:Any] {
        let(record,_)=try original();let encoder=JSONEncoder();let original=try object(encoder.encode(record));var rejected=0
        for field in ["transaction","phase","contract","schemaVersion"] {
            var bad=original
            if field=="transaction" {bad[field]=UUID().uuidString}
            if field=="phase" {bad[field]="restoring"}
            if field=="contract" {bad[field]="ordinaryIceQuickV4"}
            if field=="schemaVersion" {bad[field]=3}
            do {try validateRecord(JSONDecoder().decode(IceSelectedRecord.self,from:JSONSerialization.data(withJSONObject:bad)))}catch{rejected+=1}
        }
        var bad=original;var gestures=original["gestures"] as! [[String:Any]];gestures[1]["status"]="downReturned";bad["gestures"]=gestures
        do {try validateRecord(JSONDecoder().decode(IceSelectedRecord.self,from:JSONSerialization.data(withJSONObject:bad)))}catch{rejected+=1}
        try require(rejected==5,.trace)
        let originalFrame=record.binding.target.frame.cg
        let wider=CGRect(x:originalFrame.minX-12,y:originalFrame.minY,width:originalFrame.width+12,height:originalFrame.height)
        let neighbor=record.binding.neighbor.frame.cg
        try require(IceSelectedPlan.quickPosition(wider,neighbor,onLeft:true),.position)
        try require(!IceSelectedPlan.quickPosition(wider.offsetBy(dx:1,dy:0),neighbor,onLeft:true),.position)
        return ["passed":true,"scenarios":8,"malformedRejected":rejected,"badgeWidthGrowthNeighborAccepted":true,"wrongEdgeRejected":true,"nativePosts":0]
    }
}

@main struct QQV9CrashReconciliationMain {
 @MainActor static func main(){
  Task { @MainActor in do {
   let own=try MenuBarProcessSignature.read(ProcessInfo.processInfo.processIdentifier)
   guard own.identifier=="com.ryanai.mactools",own.team=="58TJ64422P",own.executable=="/Users/yangruihan/Workspace/mac_tools/docs/evidence/menu-bar-ice-flow-first-2026-10-09/MusicManualReturn.app/Contents/MacOS/MusicManualReturn",CommandLine.arguments.count==2 else{throw QQV9CrashReconciliation.Failure.binding}
   let mode=CommandLine.arguments[1];var result:[String:Any]
   if mode=="--observe" {let (record,_)=try QQV9CrashReconciliation.original();result=try QQV9CrashReconciliation.sample(record,controllerGone:true)}
   else if mode=="--reconcile-user-confirmed-manual-return" {result=try await QQV9CrashReconciliation.reconcile()}
   else if mode=="--trace-tests" {result=try QQV9CrashReconciliation.traceTests()}
   else {throw QQV9CrashReconciliation.Failure.binding}
   print(String(decoding:try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self));exit(0)
  }catch{fputs("v9 crash reconciliation refused: \(error)\n",stderr);exit(1)}}
  RunLoop.main.run()
 }
}
