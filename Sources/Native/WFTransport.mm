// macOS RFCOMM route derived from SonyBridge (MIT), with explicit ownership,
// bounded transactions, checked writes and readback. See THIRD_PARTY_NOTICES.md.
#import "WFTransport.h"
#include <stdexcept>
#include <chrono>
#include <atomic>
#include <fcntl.h>
#include <unistd.h>

static uint64_t nowMs() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
}
static NSString *hex(const wf::Bytes& bytes) {
    NSMutableString *text = [NSMutableString new];
    for (auto b : bytes) [text appendFormat:@"%02x", b];
    return text;
}
static void fail(NSString *message) { throw std::runtime_error(message.UTF8String); }

@implementation WFTransport {
    IOBluetoothDevice *_device;
    IOBluetoothRFCOMMChannel *_channel;
    BOOL _opening, _sdpWaiting;
    IOReturn _openStatus, _sdpStatus;
    wf::StreamDecoder _decoder;
    wf::ReceiveWindow _receive;
    wf::CommandTracker _transaction;
    wf::BatteryState _battery;
    std::optional<wf::AmbientState> _ambient;
    std::optional<wf::EQState> _eq;
    int _logFD;
    size_t _logBytes;
    std::atomic_bool _cancelled;
    NSString *_ioError;
    NSNumber *_channelID;
    BOOL _isV2;
    NSInteger _sourceSwitchResult;
}
- (instancetype)init {
    if ((self=[super init])) {
        _logFD=-1;
        _cancelled.store(false);
        _sourceSwitchResult=-1;
        NSString *path=NSProcessInfo.processInfo.environment[@"WF_PROTOCOL_LOG"];
        if (path.length) {
            // Explicit diagnostic opt-in only. Never overwrite an existing file
            // or follow symlinks; packet logs can contain pairing identifiers.
            _logFD=open(path.fileSystemRepresentation,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);
        }
    }
    return self;
}
- (void)log:(NSString *)kind payload:(const wf::Bytes&)bytes {
    if(_logFD<0) return;
    NSDictionary *event=@{@"time":@([NSDate date].timeIntervalSince1970),@"event":kind,@"hex":hex(bytes)};
    NSData *data=[NSJSONSerialization dataWithJSONObject:event options:0 error:nil];
    const size_t limit=8*1024*1024;
    if(!data || data.length+1>limit-_logBytes || write(_logFD,data.bytes,data.length)!=(ssize_t)data.length || write(_logFD,"\n",1)!=1) {
        ::close(_logFD); _logFD=-1; return;
    }
    _logBytes+=data.length+1;
}
- (void)requestCancellation { _cancelled.store(true); }
- (BOOL)connected { return _channel && _channel.isOpen && !_ioError; }
- (NSString *)address { return _device.addressString?:@""; }
- (NSString *)name { return _device.name?:@"Sony headphones"; }
- (BOOL)isV2 { return _isV2; }
- (NSInteger)sourceSwitchResult { return _sourceSwitchResult; }
- (NSNumber *)channelID { return _channelID?:@0; }
- (void)sdpQueryComplete:(IOBluetoothDevice *)device status:(IOReturn)status {
    if(device!=_device) return;
    _sdpStatus=status; _sdpWaiting=NO;
}
- (void)openAddress:(NSString *)address {
    if(_cancelled.load()) fail(@"OpenSound is shutting down.");
    [self close];
    if (![IOBluetoothHostController defaultController] ||
        [IOBluetoothHostController defaultController].powerState==kBluetoothHCIPowerStateOFF)
        fail(@"Bluetooth is off or unavailable. Enable it in System Settings.");
    _device=[IOBluetoothDevice deviceWithAddressString:address];
    if (!_device) fail(@"Select paired Sony headphones in macOS Bluetooth settings.");
    if (!_device.isConnected) {
        IOReturn rc=[_device openConnection];
        if (rc!=kIOReturnSuccess) fail([NSString stringWithFormat:@"Bluetooth connection failed (0x%x).",rc]);
    }
    unsigned char uuidBytes[]={0x95,0x6c,0x7b,0x26,0xd4,0x9a,0x4b,0xa8,0xb0,0x3f,0xb1,0x7d,0x39,0x3c,0xb6,0xe2};
    IOBluetoothSDPUUID *uuid=[IOBluetoothSDPUUID uuidWithBytes:uuidBytes length:16];
    unsigned char legacyBytes[]={0x96,0xcc,0x20,0x3e,0x50,0x68,0x46,0xad,0xb3,0x2d,0xe3,0x16,0xf5,0xe0,0x69,0xba};
    IOBluetoothSDPUUID *legacyUUID=[IOBluetoothSDPUUID uuidWithBytes:legacyBytes length:16];
    IOBluetoothSDPServiceRecord *service=[_device getServiceRecordForUUID:uuid];
    _isV2=service!=nil;
    if(!service) service=[_device getServiceRecordForUUID:legacyUUID];
    if (!service) {
        _sdpWaiting=YES;
        IOReturn rc=[_device performSDPQuery:self];
        if (rc!=kIOReturnSuccess) fail(@"Sony Bluetooth service discovery could not start.");
        uint64_t deadline=nowMs()+10000;
        while(_sdpWaiting && nowMs()<deadline && !_cancelled.load()) [self pump];
        if(_cancelled.load()) fail(@"OpenSound is shutting down.");
        if (_sdpWaiting || _sdpStatus!=kIOReturnSuccess) fail(@"Sony Bluetooth service discovery timed out.");
        service=[_device getServiceRecordForUUID:uuid]; _isV2=service!=nil;
        if(!service) service=[_device getServiceRecordForUUID:legacyUUID];
    }
    BluetoothRFCOMMChannelID channelID=0;
    if (!service || [service getRFCOMMChannelID:&channelID]!=kIOReturnSuccess || !channelID)
        fail(@"The Sony headphone control service is unavailable. Take both earbuds out of the case and reconnect.");
    _channelID=@(channelID);
    _opening=YES; _openStatus=kIOReturnNotReady;
    IOBluetoothRFCOMMChannel *openedChannel=nil;
    IOReturn rc=[_device openRFCOMMChannelAsync:&openedChannel withChannelID:channelID delegate:self];
    _channel=openedChannel;
    if(rc!=kIOReturnSuccess) { _opening=NO; fail([NSString stringWithFormat:@"RFCOMM could not open (0x%x).",rc]); }
    uint64_t deadline=nowMs()+12000;
    while(_opening && nowMs()<deadline && !_cancelled.load()) [self pump];
    if(_opening || _openStatus!=kIOReturnSuccess || !self.connected) {
        [self close]; fail(@"Sony control connection timed out. Check Bluetooth permission and reconnect the earbuds.");
    }
}
- (void)pump {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}
- (void)rfcommChannelOpenComplete:(IOBluetoothRFCOMMChannel *)channel status:(IOReturn)status {
    if(channel!=_channel) return;
    _openStatus=status; _opening=NO;
}
- (void)rfcommChannelClosed:(IOBluetoothRFCOMMChannel *)channel {
    if(channel!=_channel) return;
    _ioError=@"The earbuds disconnected. Take them out of the case and reconnect.";
    _battery={}; _ambient.reset(); _eq.reset();
}
- (BOOL)writeFrame:(const wf::Frame&)frame {
    if(_cancelled.load()) return NO;
    wf::Bytes encoded=wf::encode(frame);
    if (!_channel.isOpen) { _ioError=@"The Sony control connection is closed."; return NO; }
    size_t mtu=_channel.getMTU;
    if (!mtu) mtu=512;
    for(size_t i=0;i<encoded.size();i+=mtu) {
        size_t length=std::min(mtu,encoded.size()-i);
        IOReturn rc=[_channel writeSync:encoded.data()+i length:(UInt16)length];
        if(rc!=kIOReturnSuccess) { _ioError=[NSString stringWithFormat:@"Bluetooth write failed (0x%x).",rc]; return NO; }
    }
    [self log:frame.type==wf::kAck?@"tx_ack":@"tx" payload:frame.payload];
    return YES;
}
- (void)rfcommChannelData:(IOBluetoothRFCOMMChannel *)channel data:(void *)data length:(size_t)length {
    if(channel!=_channel || _cancelled.load() || !data || !length) return;
    if(length>65536) { _ioError=@"Oversized Bluetooth input."; _battery={}; _ambient.reset(); _eq.reset(); return; }
    const uint8_t *bytes=(const uint8_t*)data;
    try {
        for(const auto& frame:_decoder.feed(wf::Bytes(bytes,bytes+length))) {
            [self log:frame.type==wf::kAck?@"rx_ack":@"rx" payload:frame.payload];
            auto receipt=_receive.observe(frame);
            if(receipt.ack && ![self writeFrame:*receipt.ack]) return;
            // ACK is transport control; retransmitted data is acknowledged again,
            // while only its first delivery updates state and transactions.
            if(frame.type==wf::kAck || receipt.deliver) {
                _transaction.observe(frame);
                // ProtocolV2T2 PeripheralNotifyParamSourceSwitchControl:
                // 39 01 value result; 00 success, 01 fail, 02 calling,
                // 03 A2DP not connected, 04 voice-assistant priority.
                if(frame.type==0x0e && frame.payload.size()==4 && frame.payload[0]==0x39 && frame.payload[1]==1 && frame.payload[2]<=1 && frame.payload[3]<=4)
                    _sourceSwitchResult=frame.payload[3];
                if(frame.type==wf::kData && _isV2) [self applyPayload:frame.payload];
                else if(frame.type==wf::kData) [self applyLegacyPayload:frame.payload];
            }
        }
    } catch(const std::exception& e) { _ioError=@(e.what()); _battery={}; _ambient.reset(); _eq.reset(); }
}
- (void)applyLegacyPayload:(const wf::Bytes&)payload {
    if(payload.size()>=2 && (payload[0]==0x11 || payload[0]==0x13)) {
        auto translated=payload; translated[0]=0x23;
        wf::parseBattery(translated,0,wf::BatteryLayout::Single,_battery);
        wf::parseBattery(translated,1,wf::BatteryLayout::LeftRight,_battery);
        wf::parseBattery(translated,2,wf::BatteryLayout::Case,_battery);
    }
    if(auto value=wf::parseLegacyAmbient(payload)) _ambient=value;
    if(payload.size()>1 && payload[1]==1) { auto translated=payload; translated[1]=0; if(auto value=wf::parseEQ(translated)) _eq=value; }
}
- (void)applyPayload:(const wf::Bytes&)payload {
    wf::parseBattery(payload,0,wf::BatteryLayout::Single,_battery);
    wf::parseBattery(payload,0x01,wf::BatteryLayout::LeftRight,_battery);
    wf::parseBattery(payload,0x02,wf::BatteryLayout::Case,_battery);
    if(auto value=wf::parseAmbient(payload)) _ambient=value;
    if(auto value=wf::parseEQ(payload)) _eq=value;
}
- (wf::Bytes)request:(const wf::Bytes&)command reply:(int)reply inquiry:(int)inquiry {
    return [self request:command reply:reply inquiry:inquiry table:1];
}
- (void)invalidateRead:(const wf::Bytes&)command {
    if(command.size()<2) return;
    if(command[0]==0x66) _ambient.reset();
    if(command[0]==0x56) _eq.reset();
    if(command[0]==0x22 || (!_isV2 && command[0]==0x10)) {
        if(command[1]==0) _battery.single.reset();
        if(command[1]==1) { _battery.left.reset(); _battery.right.reset(); }
        if(command[1]==2) _battery.caseBattery.reset();
    }
}
- (wf::Bytes)request:(const wf::Bytes&)command reply:(int)reply inquiry:(int)inquiry table:(int)table {
    if(_cancelled.load()) fail(@"OpenSound is shutting down.");
    if(!self.connected) fail(_ioError?:@"Not connected.");
    if(table==2 && command.size()>=2 && command[0]==0x38 && command[1]==1) _sourceSwitchResult=-1;
    if(table==1) [self invalidateRead:command];
    auto frame=_transaction.begin(command,reply<0?std::nullopt:std::optional<uint8_t>((uint8_t)reply),
        inquiry<0?std::nullopt:std::optional<uint8_t>((uint8_t)inquiry),nowMs(),4000,table==2?0x0e:wf::kData);
    if(![self writeFrame:frame]) fail(_ioError);
    while(_transaction.status()==wf::TransactionStatus::Waiting && self.connected && !_cancelled.load()) {
        [self pump]; _transaction.expire(nowMs());
    }
    if(_cancelled.load()) fail(@"OpenSound is shutting down.");
    if(!self.connected) fail(_ioError?:@"Disconnected.");
    if(_transaction.status()!=wf::TransactionStatus::Complete) {
        // A timed-out GET is unknown, not the last cached successful value.
        if(command.size()>=2) {
            if(command[0]==0x66) _ambient.reset();
            if(command[0]==0x56) _eq.reset();
            if(command[0]==0x22 || (!_isV2 && command[0]==0x10)) {
                if(command[1]==0) _battery.single.reset();
                if(command[1]==1) { _battery.left.reset(); _battery.right.reset(); }
                if(command[1]==2) _battery.caseBattery.reset();
            }
        }
        fail([NSString stringWithFormat:@"Sony command %@ timed out.",hex(command)]);
    }
    auto response=_transaction.response().value_or(wf::Bytes{});
    // An invalid matching RET must not reuse a cached notification or old
    // successful read when the UI verifies a write.
    if(table==1 && reply>=0) {
        [self invalidateRead:command];
        if(_isV2) [self applyPayload:response]; else [self applyLegacyPayload:response];
    }
    return response;
}
- (NSDictionary *)snapshot {
    if(!self.connected) { _battery={}; _ambient.reset(); _eq.reset(); }
    auto battery=[](const std::optional<wf::BatteryValue>& value)->id { return value?@(value->level):NSNull.null; };
    NSMutableDictionary *state=[@{@"connected":@(self.connected),@"name":self.name,@"address":self.address,
        @"channel":self.channelID,@"protocol":_isV2?@"v2":@"v1",@"batterySingle":battery(_battery.single),@"singleCharging":_battery.single && _battery.single->chargingKnown?@(_battery.single->charging):NSNull.null,@"batteryLeft":battery(_battery.left),
        @"batteryRight":battery(_battery.right),@"batteryCase":battery(_battery.caseBattery),
        @"supportsAmbient":@(_ambient.has_value()),@"supportsEQ":@(_eq.has_value())} mutableCopy];
    if(_ambient) {
        state[@"mode"]=_ambient->mode==wf::AmbientMode::Off?@"off":_ambient->mode==wf::AmbientMode::NoiseCancelling?@"anc":@"ambient";
        state[@"ambientLevel"]=@(_ambient->level); state[@"focusOnVoice"]=@(_ambient->focusOnVoice);
        state[@"ncValue"]=@(_ambient->ncValue); state[@"ambientInquiry"]=@(_ambient->inquiry);
    }
    auto charging=[](const std::optional<wf::BatteryValue>& value)->id {
        return value && value->chargingKnown?@(value->charging):NSNull.null;
    };
    state[@"leftCharging"]=charging(_battery.left);
    state[@"rightCharging"]=charging(_battery.right);
    state[@"caseCharging"]=charging(_battery.caseBattery);
    if(_eq) {
        state[@"preset"]=@(_eq->preset);
        state[@"clearBass"]=_eq->clearBass?@(*_eq->clearBass):NSNull.null;
        NSMutableArray *bands=[NSMutableArray new];
        if(_eq->bands) for(int b:*_eq->bands) [bands addObject:@(b)];
        state[@"bands"]=bands;
    }
    return state;
}
- (void)close {
    [_channel setDelegate:nil]; [_channel closeChannel];
    // IOBluetooth close is asynchronous. Drain it before releasing the channel
    // and reopening so a previous control session cannot race the next one.
    uint64_t closeDeadline=nowMs()+1000;
    while(_channel.isOpen && nowMs()<closeDeadline) [self pump];
    _channel=nil; _device=nil;
    _opening=NO; _ioError=nil; _channelID=nil;
    _decoder.reset(); _receive.reset(); _transaction.reset(); _battery={}; _ambient.reset(); _eq.reset();
    _sourceSwitchResult=-1;
}
- (void)clearCaseBattery { _battery.caseBattery.reset(); }
- (void)dealloc { [_channel setDelegate:nil]; [_channel closeChannel]; if(_logFD>=0) ::close(_logFD); }
@end
