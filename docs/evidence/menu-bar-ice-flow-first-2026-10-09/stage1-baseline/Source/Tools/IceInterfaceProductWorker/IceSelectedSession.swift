// Copyright (c) 2026 Ryan.AI. MIT. Preparation/read-only package binding.
import AppKit
import CryptoKit

@MainActor enum IceSelectedSession {
    static let root = URL(fileURLWithPath:"/tmp/mac-tools-ice-interface-product-candidate-20261009/Worker",isDirectory:true)
    static var journal: IceSelectedJournal { IceSelectedJournal(directory:root.appendingPathComponent("selected-relative-recovery-v2")) }
    struct Prepared: Codable {
        let nonce: UUID, selected: MenuBarIceSelectedTarget?, selfOwned: Bool, controllerSHA256: String
        let preparedAtUnix: Double
    }
    static func hash(_ url: URL) throws -> String { SHA256.hash(data:try Data(contentsOf:url)).map{String(format:"%02x",$0)}.joined() }
    static func verifyPackage() throws -> [String:Any] {
        guard let manifest=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("prepared-build.json"))) as? [String:Any],
              let sources=manifest["sources"] as? [String:String],sources.count>50,
              try hash(URL(fileURLWithPath:"/Applications/MacTools.app/Contents/MacOS/MacTools")) == manifest["installedSHA256"] as? String else{throw IceSelectedFailure.binding}
        for (p,h) in sources {guard p.hasPrefix("/Users/yangruihan/Workspace/mac_tools/"),try hash(URL(fileURLWithPath:p))==h else{throw IceSelectedFailure.binding}}
        let own=try MenuBarProcessSignature.read(ProcessInfo.processInfo.processIdentifier)
        guard own.identifier=="com.ryanai.mactools",own.team=="58TJ64422P",own.sha256==manifest["controllerSHA256"] as? String,
              own.executable==root.appendingPathComponent("Ice Selected Controller.app/Contents/MacOS/IceSelectedController").path,
              try hash(root.appendingPathComponent("Ice Selected Fixture.app/Contents/MacOS/IceSelectedFixture")) == manifest["fixtureSHA256"] as? String else{throw IceSelectedFailure.binding}
        return manifest
    }
    static func requireNoOtherWorker() throws {
        for app in NSWorkspace.shared.runningApplications where app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            let p=app.executableURL?.path ?? ""
            guard !p.hasPrefix("/tmp/mac-tools-ice-baseline-candidate-20261007/Ice Baseline"),
                  !p.hasPrefix("/tmp/mac-tools-ice-selected-candidate-20261008/Ice Selected"),
                  !p.hasPrefix("/tmp/mac-tools-ice-selected-relative-candidate-20261008/Ice Selected"),
                  !p.hasPrefix("/tmp/mac-tools-ice-selected-quick-candidate-20261008/Ice Selected"),
                  !p.hasPrefix("/tmp/mac-tools-ice-selected-relative-wait-candidate-20261008/Ice Selected"),
                  !p.hasPrefix("/tmp/mac-tools-ice-selected-quick-diagnostic-candidate-20261008/Ice Selected"),
                  !p.hasPrefix("/tmp/mac-tools-ice-selected-quick-receipt-candidate-20261008/Ice Selected"),
                  !p.hasPrefix("/tmp/mac-tools-ice-selected-quick-receiver-candidate-20261008/Ice Selected"),
                  !p.hasPrefix("/tmp/mac-tools-ice-selected-quick-menu-trace-candidate-20261009/Ice Selected"),
                  !p.hasPrefix("/tmp/mac-tools-ice-selected-quick-interface-candidate-20261009/Ice Selected"),
                  !p.hasPrefix(root.path+"/Ice Selected") else{throw IceSelectedFailure.pendingRecovery}
        }
        guard try journal.inspect()==nil else{throw IceSelectedFailure.pendingRecovery}
        // Preserve the installed owned worker's independent responsibility.
        for path in ["/tmp/mac-tools-ice-selected-quick-interface-candidate-20261009/Ice Selected Controller.app/Contents/MacOS/IceSelectedController","/tmp/mac-tools-ice-selected-quick-menu-trace-candidate-20261009/Ice Selected Controller.app/Contents/MacOS/IceSelectedController","/tmp/mac-tools-ice-baseline-candidate-20261007/Ice Baseline Controller.app/Contents/MacOS/IceBaselineController",
                     "/tmp/mac-tools-ice-selected-candidate-20261008/Ice Selected Controller.app/Contents/MacOS/IceSelectedController",
                     "/tmp/mac-tools-ice-selected-relative-candidate-20261008/Ice Selected Controller.app/Contents/MacOS/IceSelectedController",
                     "/tmp/mac-tools-ice-selected-quick-candidate-20261008/Ice Selected Controller.app/Contents/MacOS/IceSelectedController",
                     "/tmp/mac-tools-ice-selected-relative-wait-candidate-20261008/Ice Selected Controller.app/Contents/MacOS/IceSelectedController",
                     "/tmp/mac-tools-ice-selected-quick-diagnostic-candidate-20261008/Ice Selected Controller.app/Contents/MacOS/IceSelectedController",
                     "/tmp/mac-tools-ice-selected-quick-receipt-candidate-20261008/Ice Selected Controller.app/Contents/MacOS/IceSelectedController",
                     "/tmp/mac-tools-ice-selected-quick-receiver-candidate-20261008/Ice Selected Controller.app/Contents/MacOS/IceSelectedController"] {
            let process=Process(),out=Pipe();process.executableURL=URL(fileURLWithPath:path)
            process.arguments=["--inspect-recovery"];process.standardOutput=out
            let done=DispatchSemaphore(value:0);process.terminationHandler={_ in done.signal()};try process.run()
            guard done.wait(timeout:.now()+5) == .success else {process.terminate();throw IceSelectedFailure.pendingRecovery}
            let bytes=out.fileHandleForReading.readDataToEndOfFile()
            guard process.terminationStatus==0,let result=try JSONSerialization.jsonObject(with:bytes) as? [String:Any],result["journalPending"] as? Bool==false else{throw IceSelectedFailure.pendingRecovery}
        }
    }
    static func write(_ value: Any, to url: URL) throws {
        let data=try JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys]);try data.write(to:url,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
    }
    static func prepare(windowID: UInt32?) throws -> URL {
        let manifest=try verifyPackage();try requireNoOtherWorker()
        var selected:MenuBarIceSelectedTarget?
        if let windowID {
            let d=try MenuBarIceSelectedTarget.readDirectory()
            guard let row=d.rows.first(where:{$0.id==windowID}) else{throw IceSelectedFailure.binding}
            selected=try MenuBarIceSelectedTarget.capture(row,from:d)
        }
        let nonce=selected?.nonce ?? UUID(),directory=root.appendingPathComponent("session-"+nonce.uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        let prepared=Prepared(nonce:nonce,selected:selected,selfOwned:windowID==nil,controllerSHA256:manifest["controllerSHA256"] as! String,preparedAtUnix:Date().timeIntervalSince1970)
        let data=try JSONEncoder().encode(prepared);try data.write(to:directory.appendingPathComponent("session.json"),options:.withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:directory.appendingPathComponent("session.json").path)
        return directory
    }
    static func load(_ directory: URL) throws -> Prepared {
        let manifest=try verifyPackage()
        guard directory.deletingLastPathComponent().path==root.path,directory.resolvingSymlinksInPath()==directory,
              !FileManager.default.fileExists(atPath:directory.appendingPathComponent("action-consumed.json").path),
              !FileManager.default.fileExists(atPath:directory.appendingPathComponent("result.json").path) else{throw IceSelectedFailure.stopped}
        let data=try Data(contentsOf:directory.appendingPathComponent("session.json"));guard data.count<65536 else{throw IceSelectedFailure.binding}
        let p=try JSONDecoder().decode(Prepared.self,from:data)
        guard directory.lastPathComponent=="session-"+p.nonce.uuidString,p.controllerSHA256==manifest["controllerSHA256"] as? String,
              Date().timeIntervalSince1970-p.preparedAtUnix>=0,Date().timeIntervalSince1970-p.preparedAtUnix<120,
              p.selfOwned==(p.selected==nil),p.selected?.nonce==nil || p.selected?.nonce==p.nonce else{throw IceSelectedFailure.binding}
        return p
    }
}
