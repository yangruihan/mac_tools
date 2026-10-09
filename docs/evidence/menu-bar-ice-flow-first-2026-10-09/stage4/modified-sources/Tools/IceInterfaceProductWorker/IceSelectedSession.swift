// Copyright (c) 2026 Ryan.AI. MIT. Preparation/read-only package binding.
import AppKit
import CryptoKit
import Security

@MainActor enum IceSelectedSession {
    static let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MacTools/IceInterfaceCandidate", isDirectory: true)
    static let packageRoot = Bundle.main.bundleURL.deletingLastPathComponent()
    static var journal: IceSelectedJournal { IceSelectedJournal(directory:root.appendingPathComponent("selected-relative-recovery-v2")) }
    struct Prepared: Codable {
        let nonce: UUID, selected: MenuBarIceSelectedTarget?, selfOwned: Bool, controllerSHA256: String
        let preparedAtUnix: Double
    }
    static func hash(_ url: URL) throws -> String { SHA256.hash(data:try Data(contentsOf:url)).map{String(format:"%02x",$0)}.joined() }
    static func verifyPackage() throws -> [String:Any] {
        let product=packageRoot.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var code:SecStaticCode?,info:CFDictionary?
        guard packageRoot==product.appendingPathComponent("Contents/Resources/IceWorker",isDirectory:true),
              SecStaticCodeCreateWithPath(product as CFURL,[],&code)==errSecSuccess,let code,
              SecStaticCodeCheckValidity(code,SecCSFlags(rawValue:kSecCSStrictValidate),nil)==errSecSuccess,
              SecCodeCopySigningInformation(code,SecCSFlags(rawValue:kSecCSSigningInformation),&info)==errSecSuccess,
              let signed=info as? [String:Any],["com.ryanai.mactools.iceinterfacecandidate","com.ryanai.mactools"].contains(signed[kSecCodeInfoIdentifier as String] as? String ?? ""),
              signed[kSecCodeInfoTeamIdentifier as String] as? String=="58TJ64422P",
              let manifest=try JSONSerialization.jsonObject(with:Data(contentsOf:packageRoot.appendingPathComponent("prepared-build.json"))) as? [String:Any],
              let sources=manifest["sources"] as? [String:String],sources.count>50 else{throw IceSelectedFailure.binding}
        let sourceRoot=packageRoot.appendingPathComponent("Source",isDirectory:true)
        for (p,h) in sources {
            let file=sourceRoot.appendingPathComponent(p).resolvingSymlinksInPath()
            guard !p.hasPrefix("/"),!p.split(separator:"/").contains(".."),file.path.hasPrefix(sourceRoot.path+"/"),try hash(file)==h else{throw IceSelectedFailure.binding}
        }
        let own=try MenuBarProcessSignature.read(ProcessInfo.processInfo.processIdentifier)
        guard own.identifier=="com.ryanai.mactools",own.team=="58TJ64422P",own.sha256==manifest["controllerSHA256"] as? String,
              own.executable==packageRoot.appendingPathComponent("Ice Selected Controller.app/Contents/MacOS/IceSelectedController").path,
              try hash(packageRoot.appendingPathComponent("Ice Selected Fixture.app/Contents/MacOS/IceSelectedFixture")) == manifest["fixtureSHA256"] as? String else{throw IceSelectedFailure.binding}
        return manifest
    }
    static func requireNoOtherWorker() throws {
        for app in NSWorkspace.shared.runningApplications where app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            let path=app.executableURL?.path ?? ""
            guard !path.hasSuffix("/Ice Selected Controller.app/Contents/MacOS/IceSelectedController"),
                  !path.hasSuffix("/Ice Baseline Controller.app/Contents/MacOS/IceBaselineController") else{throw IceSelectedFailure.pendingRecovery}
        }
        guard try journal.inspect()==nil else{throw IceSelectedFailure.pendingRecovery}
    }
    static func write(_ value: Any, to url: URL) throws {
        let data=try JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys]);try data.write(to:url,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
    }
    static func prepare(windowID: UInt32?) throws -> URL {
        let manifest=try verifyPackage();try requireNoOtherWorker()
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let archive=root.appendingPathComponent("build-history/"+(manifest["controllerSHA256"] as! String),isDirectory:true)
        try FileManager.default.createDirectory(at:archive,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        for (name,file) in [("prepared-build.json","prepared-build.json"),("controller","Ice Selected Controller.app/Contents/MacOS/IceSelectedController"),("fixture","Ice Selected Fixture.app/Contents/MacOS/IceSelectedFixture")] {
            let destination=archive.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath:destination.path) {try Data(contentsOf:packageRoot.appendingPathComponent(file)).write(to:destination,options:.withoutOverwriting)}
        }
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
