import AppKit
import Darwin
import CryptoKit

@main struct AcceptCurrent {
 enum Failure:Error {case refusal}
 static let root=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MacTools/IceInterfaceCandidate/selected-relative-recovery-v2")
 static let expected="fc85c90a92de24eaba34668efd4c7adfc1f54e3a39ed2428bce821fb13de33a8"
 static func hash(_ data:Data)->String {SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
 static func require(_ b:Bool)throws {if !b{throw Failure.refusal}}
 @MainActor static func observe() throws -> [String:Any] {
  let p=try MenuBarProcessSignature.read(7432)
  try require(p.executable=="/Applications/腾讯电脑管家.app/Contents/Library/LoginItems/AEMonitor.app/Contents/MacOS/AEMonitor" && p.identifier=="com.tencent.aegis.monitor" && p.team=="FN2V63AD2J" && p.launch==1789539762.751366 && p.sha256=="c4972c4c68a8eceeed6ff290dc936f65b88ea837707f142911cd061d5de41530")
  try require(Darwin.kill(77570,0)<0 && errno==ESRCH)
  let flags=CGEventSource.flagsState(.combinedSessionState)
  try require(!CGEventSource.buttonState(.hidSystemState,button:.left) && !CGEventSource.buttonState(.combinedSessionState,button:.left) && NSEvent.pressedMouseButtons==0 && flags.intersection([.maskCommand,.maskShift,.maskControl,.maskAlternate,.maskSecondaryFn]).isEmpty)
  guard let rows=CGWindowListCopyWindowInfo(.optionAll,kCGNullWindowID) as? [[String:Any]] else{throw Failure.refusal}
  try require(!rows.contains{let id=($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value;return id==369797 || id==379476})
  try require(!rows.contains{($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value==7432 && ($0[kCGWindowIsOnscreen as String] as? Bool)==true && ($0[kCGWindowLayer as String] as? NSNumber)?.intValue != Int(CGWindowLevelForKey(.statusWindow))})
  let target=rows.filter{($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value==144 && ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value==7432}
  try require(target.count==1)
  guard let bounds=target[0][kCGWindowBounds as String] as? [String:Any],let frame=CGRect(dictionaryRepresentation:bounds as CFDictionary) else{throw Failure.refusal}
  try require(frame.width==42 && frame.height==37 && frame.minY==0 && NSScreen.screens.count==1)
  let process=Process();process.executableURL=URL(fileURLWithPath:"/Applications/MacTools.app/Contents/Resources/IceWorker/Ice Selected Controller.app/Contents/MacOS/IceSelectedController");process.arguments=["--directory"]
  let pipe=Pipe();process.standardOutput=pipe;try process.run();let data=pipe.fileHandleForReading.readDataToEndOfFile();process.waitUntilExit()
  guard process.terminationStatus==0,let directory=try JSONSerialization.jsonObject(with:data) as? [String:Any] else{throw Failure.refusal}
  try require(directory["display"] as? Int==1 && directory["space"] as? Int==4634)
  return ["atUptime":ProcessInfo.processInfo.systemUptime,"targetID":144,"targetFrame":NSStringFromRect(frame),"ownerSignatureMatched":true,"oldControllerGone":true,"oldNeighborAndAnchorAbsent":true,"currentInputReleased":true,"noOwnerInterface":true,"display":1,"space":4634,"nativePosts":0]
 }
 @MainActor static func main() async {
  do {
   try require(CommandLine.arguments.count==2 && ["--observe","--archive-user-accepted-current"].contains(CommandLine.arguments[1]))
   let dir=open(root.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);try require(dir>=0);defer{Darwin.close(dir)}
   var statbuf=stat();try require(fstat(dir,&statbuf)==0 && statbuf.st_uid==getuid() && statbuf.st_mode & 0o777==0o700)
   let lock=openat(dir,".ice-selected.lock",O_RDWR|O_NOFOLLOW|O_CLOEXEC);try require(lock>=0);defer{Darwin.close(lock)};try require(flock(lock,LOCK_EX|LOCK_NB)==0);defer{flock(lock,LOCK_UN)}
   let name="ice-selected-relative-v2.json",url=root.appendingPathComponent(name),original=try Data(contentsOf:url)
   try require(hash(original)==expected)
   let first=try observe();try await Task.sleep(nanoseconds:150_000_000);let second=try observe();try require(first["targetFrame"] as? String==second["targetFrame"] as? String)
   var receipt:[String:Any]=["schemaVersion":1,"nonce":"4944CC26-A257-4BB9-9E50-9FCE37CDA12E","originalEnvelopeSHA256":expected,"disposition":"userAcceptedCurrentPlacementAfterOriginalNeighborRemoved","userAuthorization":"接受当前位置，保留失败后归档","originalFailureRetained":true,"originalReturnUnproven":true,"nativeReturnProven":false,"physicalReleaseProven":false,"nativePosts":0,"first":first,"second":second]
   if CommandLine.arguments[1]=="--archive-user-accepted-current" {
    let final=try observe();try require(final["targetFrame"] as? String==second["targetFrame"] as? String);try require(try Data(contentsOf:url)==original)
    let archive="accepted-current-4944CC26.original.json",record="accepted-current-4944CC26.receipt.json"
    try require(!FileManager.default.fileExists(atPath:root.appendingPathComponent(archive).path) && !FileManager.default.fileExists(atPath:root.appendingPathComponent(record).path))
    receipt["archive"]=root.appendingPathComponent(archive).path;receipt["activeJournalPending"]=false
    let bytes=try JSONSerialization.data(withJSONObject:receipt,options:[.prettyPrinted,.sortedKeys])
    let fd=openat(dir,record,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0o600);try require(fd>=0);defer{Darwin.close(fd)}
    try bytes.withUnsafeBytes{ b in var offset=0;while offset<b.count {let n=Darwin.write(fd,b.baseAddress!.advanced(by:offset),b.count-offset);if n<0 && errno==EINTR{continue};try require(n>0);offset+=n}}
    try require(fsync(fd)==0 && fsync(dir)==0)
    try require(linkat(dir,name,dir,archive,0)==0 && fsync(dir)==0)
    try require(try Data(contentsOf:root.appendingPathComponent(archive))==original)
    try require(unlinkat(dir,name,0)==0 && fsync(dir)==0)
   }
   print(String(decoding:try JSONSerialization.data(withJSONObject:receipt,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
  } catch {fputs("accepted-current reconciliation refused: \(error)\n",stderr);exit(1)}
 }
}
