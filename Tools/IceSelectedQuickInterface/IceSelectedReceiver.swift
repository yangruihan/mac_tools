// Ice-derived transport adapter, GPL-3.0. Public CFRunLoop/Thread receive isolation.
import AppKit

struct IceReceiverKey: Equatable, Sendable {
    let type: UInt32, fields: [Int64]
    init(_ event: CGEvent) {
        type = event.type.rawValue
        fields = IceBaselinePacket.matchFields.map { event.getIntegerValueField($0) }
    }
}
struct IceReceiverAdmission: Equatable, Sendable {
    let endpoint: UUID, route: UUID, nonce: UUID, transaction: UUID, generation: UUID
    let pid: Int32, key: IceReceiverKey, deadline: Double
}
// This is deliberately not Codable: persisted/injected JSON cannot create a native receipt.
struct IceReceiverReceipt: Sendable {
    let admission: IceReceiverAdmission, postedAt: Double, receivedAt: Double
    let key: IceReceiverKey, enabled: Bool
    fileprivate init(_ a: IceReceiverAdmission, _ posted: Double, _ raw: Double, _ key: IceReceiverKey, _ enabled: Bool) {
        admission=a;postedAt=posted;receivedAt=raw;self.key=key;self.enabled=enabled
    }
    func matches(_ expected: IceReceiverAdmission) -> Bool {
        admission == expected && key == expected.key && enabled && postedAt.isFinite && receivedAt.isFinite
        && postedAt <= receivedAt && receivedAt < expected.deadline
    }
}
// All decisions occur under the same lock used by the producer's expiry timer.
// Each endpoint handles one route and settles once, before any actor delivery.
final class IceReceiverState: @unchecked Sendable {
    private let lock=NSLock()
    private var admission:IceReceiverAdmission?,postedAt:Double?,settled=false
    private var fence:IceSelectedFence?
    func arm(_ a:IceReceiverAdmission,_ fence:IceSelectedFence) {
        lock.lock();defer{lock.unlock()};precondition(admission == nil)
        admission=a;self.fence=fence
    }
    func posted(_ key:IceReceiverKey,at:Double) {
        lock.lock();defer{lock.unlock()}
        guard !settled,let a=admission,a.key==key,postedAt==nil,at<a.deadline else{return};postedAt=at
    }
    func receive(_ key:IceReceiverKey,at:Double,enabled:Bool)->IceReceiverReceipt? {
        lock.lock();defer{lock.unlock()}
        guard !settled,let a=admission,let post=postedAt,enabled,key==a.key,
              at.isFinite,post<=at,at<a.deadline,(try? fence?.check()) != nil else{return nil}
        settled=true;return .init(a,post,at,key,enabled)
    }
    func expire(at:Double)->Bool {
        lock.lock();defer{lock.unlock()}
        guard !settled,let a=admission,at>=a.deadline else{return false}
        settled=true;fence?.fail();return true
    }
    func abandon()->Bool {
        lock.lock();defer{lock.unlock()}
        guard !settled,admission != nil else{return false};settled=true;fence?.fail();return true
    }
}
fileprivate final class IceReceiverDelivery: @unchecked Sendable {
    let event:CGEvent,type:CGEventType,receipt:IceReceiverReceipt?,enabled:Bool
    init(_ event:CGEvent,_ type:CGEventType,_ receipt:IceReceiverReceipt?,_ enabled:Bool) {
        self.event=event;self.type=type;self.receipt=receipt;self.enabled=enabled
    }
}
final class IceNativeReceiverWorker: @unchecked Sendable {
    enum Location:Sendable {case pid(Int32),session}
    let endpoint=UUID(),state=IceReceiverState()
    private let location:Location,options:CGEventTapOptions,mask:CGEventMask
    private let lock=NSLock(),ready=DispatchSemaphore(value:0),finished=DispatchSemaphore(value:0)
    private var loop:CFRunLoop?,port:CFMachPort?,source:CFRunLoopSource?,timer:CFRunLoopTimer?
    private var stop=false,done=false,enabled=false,closed=false
    private var thread:Thread?
    private let delivery:@Sendable(IceReceiverDelivery)->Void,timeout:@Sendable()->Void
    fileprivate init(location:Location,options:CGEventTapOptions,types:[CGEventType],delivery:@escaping @Sendable(IceReceiverDelivery)->Void,timeout:@escaping @Sendable()->Void) {
        self.location=location;self.options=options;mask=types.reduce(0){$0 | (1 << $1.rawValue)}
        self.delivery=delivery;self.timeout=timeout
    }
    var isEnabled:Bool {lock.lock();defer{lock.unlock()};return enabled}
    var didClose:Bool {lock.lock();defer{lock.unlock()};return closed}
    func start() {
        let t=Thread{[self] in run()};t.name="MacTools.Ice.RawReceiver";thread=t;t.start()
        if ready.wait(timeout:.now()+1) != .success {close()}
    }
    private func run() {
        let current=CFRunLoopGetCurrent(),context=Unmanaged.passUnretained(self).toOpaque()
        let tap:CFMachPort?
        switch location {
        case .pid(let pid):tap=CGEvent.tapCreateForPid(pid:pid,place:.tailAppendEventTap,options:options,eventsOfInterest:mask,callback:iceNativeReceiverCallback,userInfo:context)
        case .session:tap=CGEvent.tapCreate(tap:.cgSessionEventTap,place:.tailAppendEventTap,options:options,eventsOfInterest:mask,callback:iceNativeReceiverCallback,userInfo:context)
        }
        guard let tap,let input=CFMachPortCreateRunLoopSource(nil,tap,0) else {
            lock.lock();done=true;closed=true;lock.unlock();ready.signal();finished.signal();return
        }
        CGEvent.tapEnable(tap:tap,enable:false)
        let keeper=CFRunLoopTimerCreateWithHandler(nil,CFAbsoluteTimeGetCurrent()+3,0,0,0){_ in}
        CFRunLoopAddTimer(current,keeper,.defaultMode)
        lock.lock();loop=current;port=tap;source=input;lock.unlock();ready.signal()
        let end=ProcessInfo.processInfo.systemUptime+3
        while ProcessInfo.processInfo.systemUptime<end {
            lock.lock();let quit=stop;lock.unlock();if quit{break}
            _=CFRunLoopRunInMode(.defaultMode,0.01,true)
        }
        if state.abandon(){timeout()}
        CGEvent.tapEnable(tap:tap,enable:false);CFRunLoopRemoveSource(current,input,.defaultMode)
        if let timer{CFRunLoopTimerInvalidate(timer)}
        CFRunLoopRemoveTimer(current,keeper,.defaultMode);CFMachPortInvalidate(tap)
        lock.lock();loop=nil;port=nil;source=nil;enabled=false;done=true;closed=true;lock.unlock();finished.signal()
    }
    private func command(_ body:@escaping @Sendable()->Void) {
        lock.lock();let current=loop;lock.unlock();guard let current else{return}
        let complete=DispatchSemaphore(value:0)
        CFRunLoopPerformBlock(current,CFRunLoopMode.defaultMode.rawValue){body();complete.signal()}
        CFRunLoopWakeUp(current)
        if complete.wait(timeout:.now()+1) != .success {if state.abandon(){timeout()}}
    }
    func arm(_ a:IceReceiverAdmission,_ fence:IceSelectedFence) {
        state.arm(a,fence)
        command{[self] in
            let t=CFRunLoopTimerCreateWithHandler(nil,CFAbsoluteTimeGetCurrent()+max(0,a.deadline-ProcessInfo.processInfo.systemUptime),0,0,0){[self] _ in
                if state.expire(at:ProcessInfo.processInfo.systemUptime){setEnabled(false);timeout()}
            }
            timer=t;if let loop{CFRunLoopAddTimer(loop,t,.defaultMode)}
        }
    }
    private func setEnabled(_ value:Bool) {
        guard let port,let source,let loop else{return}
        if value {CFRunLoopAddSource(loop,source,.defaultMode)}
        CGEvent.tapEnable(tap:port,enable:value)
        if !value {CFRunLoopRemoveSource(loop,source,.defaultMode)}
        lock.lock();enabled=CGEvent.tapIsEnabled(tap:port);lock.unlock()
    }
    func enable(){command{[self] in setEnabled(true)}}
    func disable(){command{[self] in setEnabled(false)}}
    func close() {
        lock.lock();let already=done;stop=true;let current=loop;lock.unlock()
        if already{return};if let current{CFRunLoopWakeUp(current)}
        if finished.wait(timeout:.now()+1) == .success {thread=nil}
        else{if state.abandon(){timeout()}}
    }
    fileprivate func receive(_ type:CGEventType,_ event:CGEvent,at:Double) {
        guard let port else{return}
        let actual=CGEvent.tapIsEnabled(tap:port)
        if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
            lock.lock();enabled=actual;lock.unlock()
            if let copy=event.copy(){delivery(.init(copy,type,nil,actual))};return
        }
        let key=IceReceiverKey(event)
        guard let receipt=state.receive(key,at:at,enabled:actual) else{return}
        if let timer{CFRunLoopTimerInvalidate(timer)}
        setEnabled(false)
        guard let copy=event.copy() else{timeout();return}
        delivery(.init(copy,type,receipt,actual))
    }
    fileprivate var consumesNull:Bool {if case .pid=location{return true};return false}
}
private func iceNativeReceiverCallback(_ proxy:CGEventTapProxy,_ type:CGEventType,_ event:CGEvent,_ context:UnsafeMutableRawPointer?)->Unmanaged<CGEvent>? {
    let at=ProcessInfo.processInfo.systemUptime // raw C entry, never event.timestamp
    guard let context else{return Unmanaged.passUnretained(event)}
    let worker=Unmanaged<IceNativeReceiverWorker>.fromOpaque(context).takeUnretainedValue()
    worker.receive(type,event,at:at)
    return worker.consumesNull && type == .null ? nil : Unmanaged.passUnretained(event)
}
@MainActor final class IceNativeReceiverTap:IceBaselineTapControl {
    private var worker:IceNativeReceiverWorker!
    private var expiry:(()->Void)?
    private let callback:IceSelectedNative.TapCallback
    var endpoint:UUID?{worker.endpoint}
    var isEnabled:Bool{worker.isEnabled}
    var receiverClosed:Bool{worker.didClose}
    init(_ options:CGEventTapOptions,_ location:EventTap.Location,_ types:[CGEventType],_ callback:@escaping IceSelectedNative.TapCallback) {
        self.callback=callback
        let native:IceNativeReceiverWorker.Location
        switch location {case .pid(let pid):native = .pid(pid);default:native = .session}
        worker=IceNativeReceiverWorker(location:native,options:options,types:types,delivery:{[weak self] value in
            Task{@MainActor in guard let self else{return};_ = self.callback(Proxy(self,value.receipt,value.enabled),value.type,value.event)}
        },timeout:{[weak self] in Task{@MainActor in self?.expiry?()}})
        worker.start()
    }
    func enable(){worker.enable()};func disable(){worker.disable()};func close(){worker.close()}
    func arm(_ a:IceReceiverAdmission,_ fence:IceSelectedFence,_ expired:@escaping()->Void){expiry=expired;worker.arm(a,fence)}
    func markPosted(_ event:CGEvent,at:Double){worker.state.posted(IceReceiverKey(event),at:at)}
    struct Proxy:IceBaselineTapControl {
        let tap:IceNativeReceiverTap,rawReceipt:IceReceiverReceipt?,isEnabled:Bool
        init(_ tap:IceNativeReceiverTap,_ receipt:IceReceiverReceipt?,_ enabled:Bool){self.tap=tap;rawReceipt=receipt;isEnabled=enabled}
        var endpoint:UUID?{tap.endpoint}
        func enable(){tap.enable()};func disable(){tap.disable()};func close(){tap.close()}
    }
}
