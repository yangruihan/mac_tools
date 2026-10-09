// Candidate receiver checks. Replay creates no live receiver or system effects.
import AppKit

@MainActor enum IceReceiverChecks {
    static func admission(_ key:IceReceiverKey,_ endpoint:UUID=UUID(),_ deadline:Double=10.05)->IceReceiverAdmission {
        .init(endpoint:endpoint,route:UUID(),nonce:UUID(),transaction:UUID(),generation:UUID(),pid:20,key:key,deadline:deadline)
    }
    static func replay()throws->Int {
        let event=try IceBaselinePacket.make(.leftMouseUp,move:false,point:.zero,item:.init(windowID:1,pid:20,key:"T"),pid:20,marker:999)
        let key=IceReceiverKey(event),a=admission(key),fence=IceSelectedFence(),state=IceReceiverState()
        var count=0
        func check(_ value:Bool,_ message:String)throws{count+=1;try IceSelectedOfflineChecks.check(value,message)}
        state.arm(a,fence)
        try check(state.receive(key,at:10.001,enabled:true)==nil,"receipt before dispatch cannot ACK")
        state.posted(key,at:10)
        let wrong=event.copy()!;wrong.setIntegerValueField(CGEventField(rawValue:0x33)!,value:2)
        try check(state.receive(IceReceiverKey(wrong),at:10.002,enabled:true)==nil,"wrong field cannot ACK")
        wrong.setIntegerValueField(CGEventField(rawValue:0x33)!,value:1);wrong.type = .leftMouseDown
        try check(state.receive(IceReceiverKey(wrong),at:10.002,enabled:true)==nil,"wrong type cannot ACK")
        try check(state.receive(key,at:10.002,enabled:false)==nil,"disabled source cannot ACK")
        let receipt=state.receive(key,at:10.049,enabled:true)!
        try check(receipt.matches(a),"timely raw receipt captures exact immutable route binding")
        var clock=10.09
        let waiter=IceSelectedReceiptWait(deadline:a.deadline,clock:{clock})
        try check(waiter.received(at:receipt.receivedAt) && waiter.acceptedAt==10.049,"timely raw accepted despite late main consumer")
        try check(state.receive(key,at:10.0495,enabled:true)==nil && !state.expire(at:clock),"duplicate and timer lose after producer settles")
        try check(!receipt.matches(admission(key,a.endpoint)),"different nonce/transaction/generation cannot adopt receipt")
        let swapped=IceReceiverAdmission(endpoint:UUID(),route:a.route,nonce:a.nonce,transaction:a.transaction,generation:a.generation,pid:a.pid,key:a.key,deadline:a.deadline)
        try check(!receipt.matches(swapped),"different endpoint cannot adopt receipt")
        for changes in 0..<5 {
            let altered=IceReceiverAdmission(endpoint:a.endpoint,route:changes==0 ? UUID():a.route,nonce:changes==1 ? UUID():a.nonce,
                 transaction:changes==2 ? UUID():a.transaction,generation:changes==3 ? UUID():a.generation,pid:changes==4 ? 21:a.pid,key:a.key,deadline:a.deadline)
            try check(!receipt.matches(altered),"exact identity component \(changes) required")
        }
        let late=IceReceiverState(),lf=IceSelectedFence();late.arm(a,lf);late.posted(key,at:10)
        try check(late.receive(key,at:10.05,enabled:true)==nil && late.expire(at:10.05),"original absolute deadline exclusive, no extension")
        try check(late.receive(key,at:10.049,enabled:true)==nil && !late.expire(at:10.06),"expired route cannot resurrect or settle twice")
        let cancel=IceReceiverState(),cf=IceSelectedFence();cancel.arm(a,cf);cancel.posted(key,at:10);cf.cancel()
        try check(cancel.receive(key,at:10.001,enabled:true)==nil,"synchronous cancellation rejects raw match")
        _=cancel.expire(at:10.05)
        try check(cf.stop.snapshot.reason == .cancelled,"expiry cannot overwrite cancellation")
        let close=IceReceiverState(),xf=IceSelectedFence();close.arm(a,xf)
        try check(close.abandon() && !close.abandon() && close.receive(key,at:10.001,enabled:true)==nil,"thread disappearance fails once and cannot ACK")
        clock=10.1;waiter.fail(CancellationError())
        try check(waiter.settlementCount==1,"consumer settles once")
        return count
    }
    static func zeroInput()async throws->[String:Any] {
        _ = try IceSelectedSession.verifyPackage();try IceSelectedSession.requireNoOtherWorker()
        var rows:[[String:Any]]=[]
        for cancel in [false,true] {
            let fence=IceSelectedFence()
            // Own listen-only tap control notices are the only forwarded events.
            var receipts=0,timeouts=0,controls=0
            let tap=IceNativeReceiverTap(.listenOnly,.sessionEventTap,[.leftMouseDown,.leftMouseUp]){proxy,type,event in
                if proxy.rawReceipt != nil {receipts+=1}
                if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {controls+=1}
                return event
            }
            guard let endpoint=tap.endpoint else{throw IceBaselineError.tap}
            let e=CGEvent(source:nil)!,start=ProcessInfo.processInfo.systemUptime
            let a=admission(IceReceiverKey(e),endpoint,start+0.05)
            tap.arm(a,fence){timeouts+=1}
            tap.enable();guard tap.isEnabled else{tap.close();throw IceBaselineError.tap}
            if cancel{fence.cancel()}
            usleep(90_000) // Known MainActor blocking; independent timer must settle.
            let sampled=ProcessInfo.processInfo.systemUptime
            let reason=fence.stop.snapshot.reason
            tap.close()
            try await Task.sleep(nanoseconds:20_000_000)
            guard tap.receiverClosed,receipts==0,timeouts==1,reason == (cancel ? .cancelled:.failed) else{throw IceBaselineError.tap}
            rows.append(["cancelled":cancel,"mainBusyMS":(sampled-start)*1000,"producerFenceReasonBeforeConsumer":reason!.rawValue,
                         "inputReceipts":receipts,"expiryConsumptions":timeouts,"ownControlNotices":controls,"threadClosed":tap.receiverClosed])
        }
        return ["passed":true,"scenarios":2,"nativePosts":0,"AXActions":0,"cursorEffects":0,"rows":rows]
    }
}
