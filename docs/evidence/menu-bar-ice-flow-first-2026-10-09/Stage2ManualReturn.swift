// Copyright (c) 2026 Ryan.AI. MIT.
// Exact interrupted QQ trial only. Administrative archive; no input sender.
import AppKit
import Darwin

@MainActor enum QQV9CrashReconciliation {
    static let oldRoot=URL(fileURLWithPath:"/Users/yangruihan/Library/Application Support/MacTools/IceInterfaceCandidate")
    static let nonce=UUID(uuidString:"5C85917F-5F76-4E98-B4B0-5F3215F694A7")!
    static let transaction=UUID(uuidString:"983E9437-913A-434A-8995-96119FAB6B16")!
    static let originalHash="e86336fcd7fb529c2dad72a4ae92219973dfa67b8333416822e3cda338c09af5"
    static let sessionResultHash="494f1be5d4dc9a28e327f83fdddf3c9bfe4e521069535b20a5af50bfac65becb"
    static let sessionResultURL=URL(fileURLWithPath:"/Users/yangruihan/Library/Application Support/MacTools/IceInterfaceCandidate/session-5C85917F-5F76-4E98-B4B0-5F3215F694A7/result.json")
    static let journalDirectory=oldRoot.appendingPathComponent("selected-relative-recovery-v2")
    static let filename="ice-selected-relative-v2.json"
    enum Failure:Error {case binding,trace,heldInput,menu,position,controller,archive,stale}
    static func require(_ condition:Bool,_ error:Failure)throws {guard condition else{throw error}}
    static func object(_ data:Data)throws->[String:Any] {
        guard data.count<2_000_000,let value=try JSONSerialization.jsonObject(with:data) as? [String:Any] else{throw Failure.binding};return value
    }
    static func validateRecord(_ record:IceSelectedRecord)throws {
        try record.validate();let b=record.binding
        try require(record.transaction==transaction && b.nonce==nonce && record.schemaVersion==4 && record.phase == .stopped && record.contract == .ordinaryIceInterfaceV9 && record.needsRelease && record.returnedEvidenceSHA256==nil,.binding)
        try require(b.owner.pid==58349 && b.owner.identifier=="com.tencent.qq" && b.owner.executable=="/Applications/QQ.app/Contents/MacOS/QQ" && b.owner.team=="FN2V63AD2J" && b.owner.launch==1791499568.56596 && b.target.id==351689,.binding)
        try require(b.controller.pid==96674 && b.controller.executable=="/Users/yangruihan/Workspace/mac_tools/build/ice-interface-product/MacTools Ice Interface Candidate.app/Contents/Resources/IceWorker/Ice Selected Controller.app/Contents/MacOS/IceSelectedController" && b.controller.sha256=="a7a80df4e8a52c56ee515a9968d2eb5ea84221b0a8c6812c43d813b9c4496f2b" && b.controller.launch==1791533061.532764 && b.anchor.id==356903 && b.neighbor.id==354357 && b.returnOnLeft && b.space==4634 && b.display==1,.binding)
        try require(record.gestures.count==3 && record.gestures[0].status == .pairedTransportReturned && record.gestures[1].status == .pairedTransportReturned && record.gestures[2].status == .downReserved && record.gestures[0].routes.count==6 && record.gestures[1].routes.count==2 && record.gestures[2].routes.count==3,.trace)
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
        let archived="stage2-timeout-user-manual-return-original-"+transaction.uuidString+".json"
        let receiptName="stage2-timeout-user-manual-return-receipt-"+transaction.uuidString+".json"
        if FileManager.default.fileExists(atPath:journalDirectory.appendingPathComponent(archived).path) {
            try require(try Data(contentsOf:journalDirectory.appendingPathComponent(archived))==originalBytes,.archive)
        } else {try require(linkat(d,filename,d,archived,0)==0 && fsync(d)==0,.archive)}
        let receipt:[String:Any]=["version":1,"disposition":"manualQQIceNeighborObservedAfterReturnRouteTimeout","originalEnvelopeSHA256":originalHash,"sessionResultSHA256":sessionResultHash,"transaction":transaction.uuidString,"nonce":nonce.uuidString,"originalPhase":"stopped","originalGestureStatus":"downReserved","durablePairedRoutes":8,"historicalActualPosts":10,"historicalPairingConfirmed":false,"terminalResultPublished":true,"recoveryNativePosts":0,"AXActionsRequested":0,"nativeReturnProven":false,"physicalReleaseProven":false,"fullRelativeQueueVerified":false,"currentIceNeighborPositionVerified":true,"userReportedManualReturnComplete":true,"first":first,"second":second,"originalRecord":try JSONSerialization.jsonObject(with:JSONEncoder().encode(record))]
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
        return ["passed":true,"scenarios":6,"malformedRejected":rejected,"nativePosts":0]
    }
}

@main struct QQV9CrashReconciliationMain {
 @MainActor static func main(){
  Task { @MainActor in do {
   let own=try MenuBarProcessSignature.read(ProcessInfo.processInfo.processIdentifier)
   guard own.identifier=="com.ryanai.mactools",own.team=="58TJ64422P",own.executable=="/Users/yangruihan/Workspace/mac_tools/docs/evidence/menu-bar-ice-flow-first-2026-10-09/Stage2ManualReturn.app/Contents/MacOS/Stage2ManualReturn",CommandLine.arguments.count==2 else{throw QQV9CrashReconciliation.Failure.binding}
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
