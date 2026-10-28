#import "WFBridge.h"
#import "WFTransport.h"
#include <stdexcept>
#include <algorithm>
#include <atomic>

static IOBluetoothSDPUUID *sonyUUID(NSString *text) { uuid_t bytes; [[[NSUUID alloc] initWithUUIDString:text] getUUIDBytes:bytes]; return [IOBluetoothSDPUUID uuidWithBytes:bytes length:16]; }
static NSString *safeText(const std::string& value,NSString *fallback) {
    NSString *text=[[NSString alloc] initWithBytes:value.data() length:value.size() encoding:NSUTF8StringEncoding];
    if(!text.length) return fallback;
    return [[text componentsSeparatedByCharactersInSet:NSCharacterSet.controlCharacterSet] componentsJoinedByString:@" "];
}

@implementation WFBridge {
    NSThread *_thread;
    WFTransport *_transport;
    std::atomic<bool> _stopping;
    NSArray<NSNumber *> *_presets;
    int _maxAmbient;
    BOOL _supportsEditor;
    NSMutableArray *_work;
    NSString *_ambientReason;
    BOOL _v2,_table2,_settingsInitialized,_eqAvailable,_dualBattery,_singleBattery,_caseAvailable;
    uint8_t _ambientInquiry;
    std::vector<uint8_t> _functions;
    std::vector<wf::AmbientRange> _ambientRanges;
    std::vector<wf::SettingSpec> _specs;
    std::vector<wf::AssignmentKey> _assignmentKeys;
    NSMutableDictionary *_settingRows,*_settingReplies;
    BOOL _acceptingWork, _draining;
}
- (instancetype)init {
    if((self=[super init])) {
        _work=[NSMutableArray new]; _settingRows=[NSMutableDictionary new]; _settingReplies=[NSMutableDictionary new];
        _acceptingWork=YES; _stopping=false;
        _thread=[[NSThread alloc] initWithTarget:self selector:@selector(worker) object:nil];
        _thread.name=@"OpenSound Bluetooth"; [_thread start];
    }
    return self;
}
- (void)worker {
    @autoreleasepool {
        [[NSRunLoop currentRunLoop] addPort:[NSMachPort port] forMode:NSDefaultRunLoopMode];
        @synchronized(_work) { _transport=[WFTransport new]; }
        _presets=@[];
        [self drain];
        // Sleep in the run loop until IOBluetooth delivers an event or enqueue
        // wakes this thread; no periodic timer wakeups while idle.
        while(!_stopping.load()) { @autoreleasepool {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:NSDate.distantFuture];
        }}
        [_transport close]; @synchronized(_work) { _transport=nil; }
    }
}
- (void)drain {
    // Transport waits spin the run loop, which can deliver another wake-up
    // while a block is running; the outer drain picks queued work up instead.
    if(_draining) return;
    _draining=YES;
    for(;;) {
        void (^next)(void)=nil;
        @synchronized(_work) {
            if(_work.count) { next=_work.firstObject; [_work removeObjectAtIndex:0]; }
        }
        if(!next) break;
        @autoreleasepool { next(); }
    }
    _draining=NO;
}
- (void)wake {
    if(_thread && !_thread.finished) [self performSelector:@selector(drain) onThread:_thread withObject:nil waitUntilDone:NO];
}
- (void)enqueue:(void (^)(void))block {
    BOOL queued=NO;
    @synchronized(_work) { if(_acceptingWork) { [_work addObject:[block copy]]; queued=YES; } }
    if(queued) [self wake];
}
- (void)finish:(WFCompletion)completion error:(NSString *)error {
    if(!_transport.connected) [_settingRows removeAllObjects];
    NSMutableDictionary *state=[[_transport snapshot] mutableCopy];
    state[@"presets"]=_presets?:@[]; state[@"maxAmbient"]=@(_maxAmbient);
    state[@"supportsAmbient"]=@(_maxAmbient>0 && [state[@"supportsAmbient"] boolValue]);
    state[@"supportsEQ"]=@(_presets.count>0 && [state[@"supportsEQ"] boolValue]);
    state[@"supportsEditor"]=@(_supportsEditor && [state[@"bands"] count]==5);
    state[@"ambientReason"]=_ambientReason?:@"Waiting for headphone status.";
    state[@"settings"]=[[_settingRows allValues] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"title"] compare:b[@"title"]];}];
    NSMutableArray *functions=[NSMutableArray new]; for(auto tag:_functions) [functions addObject:@(tag)];
    state[@"modelCapabilities"]=@{@"protocol":_v2?@"v2":@"v1",@"table2":@(_table2),@"functionIds":functions,@"ambientInquiry":@(_ambientInquiry)};
    dispatch_async(dispatch_get_main_queue(),^{ completion(state,error); });
}
- (void)listDevices:(void (^)(NSArray<NSDictionary *> *))completion {
    [self enqueue:^{
        NSMutableArray *devices=[NSMutableArray new];
        for(IOBluetoothDevice *device in [IOBluetoothDevice pairedDevices])
            if(([device.name hasPrefix:@"WH-"] || [device.name hasPrefix:@"WF-"] || [device.name hasPrefix:@"WI-"] || [device.name hasPrefix:@"MDR-"] || [device.name containsString:@"LinkBuds"] || [device.name localizedCaseInsensitiveContainsString:@"Sony"] || [device.name localizedCaseInsensitiveContainsString:@"ULT"] || [device.name localizedCaseInsensitiveContainsString:@"INZONE"] || [device getServiceRecordForUUID:sonyUUID(@"956C7B26-D49A-4BA8-B03F-B17D393CB6E2")] || [device getServiceRecordForUUID:sonyUUID(@"96CC203E-5068-46AD-B32D-E316F5E069BA")]) && device.addressString)
                [devices addObject:@{@"name":device.name?:@"Sony headphones",@"address":device.addressString,@"connected":@(device.isConnected)}];
        dispatch_async(dispatch_get_main_queue(),^{completion(devices);});
    }];
}
- (void)connectAddress:(NSString *)address completion:(WFCompletion)completion {
    [self enqueue:^{
        NSString *error=nil;
        try {
            self->_presets=@[]; self->_maxAmbient=0; self->_supportsEditor=NO; self->_ambientReason=nil;
            self->_settingsInitialized=NO; self->_ambientRanges.clear(); self->_functions.clear(); self->_specs.clear(); [self->_settingRows removeAllObjects]; [self->_settingReplies removeAllObjects];
            [self->_transport openAddress:address];
            auto protocol=[self->_transport request:wf::Bytes{0,0} reply:1 inquiry:-1];
            self->_v2=self->_transport.isV2;
            auto protocolInfo=wf::parseProtocolInfo(protocol,self->_v2?wf::ProtocolFamily::V2:wf::ProtocolFamily::V1);
            if(!protocolInfo || !protocolInfo->table1) throw std::runtime_error("The Sony service did not advertise a valid Table 1 protocol.");
            self->_table2=protocolInfo->table2;
            auto functions=[self->_transport request:wf::Bytes{0x06,0} reply:7 inquiry:0];
            auto parsed=wf::parseSupportFunctions(functions,self->_v2?wf::ProtocolFamily::V2:wf::ProtocolFamily::V1);
            if(!parsed) throw std::runtime_error("Invalid Sony supported-function table.");
            self->_functions=*parsed;
            auto has=[&](int tag){return std::find(self->_functions.begin(),self->_functions.end(),tag)!=self->_functions.end();};
            self->_ambientInquiry=self->_v2?(has(0x68)?0x15:has(0x6a)?0x16:has(0x6b)?0x17:0):has(0x62)?2:0;
            self->_eqAvailable=has(self->_v2?0x50:0x51); self->_dualBattery=has(self->_v2?0x21:0x15) || (self->_v2 && has(0x29)); self->_caseAvailable=has(self->_v2?0x22:0x18) || (self->_v2 && has(0x2a)); self->_singleBattery=has(self->_v2?0x20:0x11) || (self->_v2 && has(0x28));
            if(self->_eqAvailable) {
                auto capability=[self->_transport request:wf::Bytes{0x50,uint8_t(self->_v2?0:1),0x01} reply:0x51 inquiry:self->_v2?0:1];
                if(!self->_v2 && capability.size()>1) capability[1]=0;
                if(auto eq=wf::parseEQCapabilities(capability)) {
                    NSMutableArray *presets=[NSMutableArray new]; for(const auto& preset:eq->presets) [presets addObject:@(preset.id)];
                    self->_presets=presets; self->_supportsEditor=eq->supportsEditor();
                }
            }
            if(self->_ambientInquiry) {
                auto ambient=[self->_transport request:wf::Bytes{0x60,self->_ambientInquiry} reply:0x61 inquiry:self->_ambientInquiry];
                if(self->_v2) { if(auto cap=wf::parseAmbientCapabilities(ambient)) { self->_ambientRanges=cap->ranges; for(const auto& range:cap->ranges) if(range.mode==0 && range.minimum==1 && range.step==1) self->_maxAmbient=range.maximum; } }
                else if(auto cap=wf::parseLegacyAmbientCapabilities(ambient)) { self->_ambientRanges=cap->ranges; for(const auto& range:cap->ranges) if(range.mode==0) self->_maxAmbient=range.maximum; }
            }
            [self readStatus:YES];
            self->_specs=wf::settingSpecs(self->_v2?wf::ProtocolFamily::V2:wf::ProtocolFamily::V1,self->_functions);
            if(self->_v2 && self->_table2) {
                try {
                    auto table=[self->_transport request:wf::Bytes{6,0} reply:7 inquiry:0 table:2];
                    auto tags=wf::parseSupportFunctions(table,wf::ProtocolFamily::V2);
                    if(tags) {
                        auto has2=[&](int tag){return std::find(tags->begin(),tags->end(),tag)!=tags->end();};
                        if(has2(0x30)||has2(0x32)||has2(0x33)) {
                            uint8_t inquiry=has2(0x30)?0:2;
                            try {
                                auto history=[self->_transport request:wf::Bytes{0x36,inquiry} reply:0x37 inquiry:inquiry table:2];
                                if(auto devices=wf::parsePairedDevices(history)) {
                                    NSMutableArray *names=[NSMutableArray new];
                                    for(auto& device:*devices) { NSString *name=safeText(device.name,@"Unnamed device"); [names addObject:[NSString stringWithFormat:@"%@%@",name,device.status==1?@" (connected)":@""]]; }
                                    self->_settingRows[@"pairingHistory"]=@{@"id":@"pairingHistory",@"title":@"Paired devices",@"section":@"Connections",@"kind":@"readonly",@"value":[NSString stringWithFormat:@"%lu devices",(unsigned long)names.count],@"privateDetails":[names componentsJoinedByString:@", "],@"enabled":@NO,@"options":@[],@"reason":@"Headphone pairing history. Device names are hidden until expanded."};
                                }
                            } catch(const std::exception&) {}
                        }
                        if(has2(0x31)) self->_specs.push_back({"sourceSwitch","Multipoint source switching","Connections",0x31,1,0x36,0x37,0x38,3,2,{{0,"Off"},{1,"On"}},false,false,2});
                        if(has2(0x41)||has2(0x42)) self->_specs.push_back({"voiceGuidance","Voice guidance","System",0x41,1,0x46,0x47,0x48,4,2,{{0,"Off"},{1,"On"}},true,false,2});
                        else if(has2(0x40)) self->_specs.push_back({"voiceGuidance","Voice guidance","System",0x40,0,0x46,0x47,0x48,3,2,{{0,"Off"},{1,"On"}},true,false,2});
                        if(has2(0x42)) self->_specs.push_back({"guidanceVolume","Voice guidance volume","System",0x42,0x20,0x46,0x47,0x48,3,2,{{254,"-2"},{255,"-1"},{0,"Normal"},{1,"+1"},{2,"+2"}},false,false,2});
                    }
                } catch(const std::exception&) {}
            }
            if(self->_v2 && has(0xa1)) {
                try {
                    auto cap=[self->_transport request:wf::Bytes{0xa0,1} reply:0xa1 inquiry:1];
                    if(cap.size()==4 && cap[2]>0) {
                        wf::SettingSpec volume{"volume","Headphone volume","Playback",0xa1,0x20,0xa6,0xa7,0xa8,3,2,{},false,false};
                        for(int value=0;value<=cap[2];++value) volume.options.push_back({value,std::to_string(value)});
                        self->_specs.push_back(volume);
                    }
                } catch(const std::exception&) {}
            }
            self->_assignmentKeys.clear();
            if(self->_v2 && has(0xf3)) {
                try {
                    auto cap=[self->_transport request:wf::Bytes{0xf0,3} reply:0xf1 inquiry:3];
                    auto keys=wf::parseAssignmentCapabilities(cap);
                    if(keys) {
                        auto current=[self->_transport request:wf::Bytes{0xf6,3} reply:0xf7 inquiry:3];
                        if(wf::parseAssignmentValues(*keys,current)) {
                            self->_assignmentKeys=*keys;
                            for(size_t index=0;index<keys->size();++index) {
                                const auto& key=(*keys)[index];
                                wf::SettingSpec assignment{"assignment"+std::to_string(index),key.key==0?"Left touch control":key.key==1?"Right touch control":"Headphone button control","Controls",0xf3,3,0xf6,0xf7,0xf8,current.size(),3+index,{},false,false};
                                for(auto preset:key.presets) {
                                    std::string label=preset==0?"Ambient sound control":preset==0x10?"Volume control":preset==0x20?"Playback control":preset==0x30?"Voice assistant":preset==0xff?"No function":"Preset "+std::to_string(preset);
                                    assignment.options.push_back({preset,label});
                                }
                                self->_specs.push_back(assignment);
                            }
                        }
                    }
                } catch(const std::exception&) {}
            }

            if(self->_v2) {
                for(int tag=0xd1;tag<=0xd4;++tag) if(has(tag)) {
                    try {auto cap=[self->_transport request:wf::Bytes{0xd0,uint8_t(tag),1} reply:0xd1 inquiry:tag]; if(auto spec=wf::parseGeneralCapability(cap)) self->_specs.push_back(*spec);}catch(const std::exception&){}
                }
                if(has(0xf4)) {
                    try {
                        auto cap=[self->_transport request:wf::Bytes{0xf0,4} reply:0xf1 inquiry:4];
                        if(cap.size()>=4 && cap.size()==size_t(4+cap[3])) {
                            wf::SettingSpec assistant{"voiceAssistant","Headphone voice assistant","Controls",0xf4,4,0xf6,0xf7,0xf8,3,2,{},false,false};
                            for(size_t index=4;index<cap.size();++index) { int id=cap[index]; assistant.options.push_back({id,id==0x30?"System voice assistant":id==0x31?"Google Assistant":id==0x32?"Amazon Alexa":id==0xff?"None":"Assistant "+std::to_string(id)}); }
                            self->_specs.push_back(assistant);
                        }
                    }catch(const std::exception&){}
                }
            }
            [self loadSettings];
            [self refreshAssignments];
        } catch(const std::exception& e) { error=@(e.what()); [self->_transport close]; }
        [self finish:completion error:error];
    }];
}
- (void)readStatus:(BOOL)battery {
    if(battery) {
        if(self->_dualBattery) [self->_transport request:wf::Bytes{uint8_t(self->_v2?0x22:0x10),1} reply:self->_v2?0x23:0x11 inquiry:1];
        else if(self->_singleBattery) [self->_transport request:wf::Bytes{uint8_t(self->_v2?0x22:0x10),0} reply:self->_v2?0x23:0x11 inquiry:0];
        [self->_transport clearCaseBattery];
        if(self->_caseAvailable) try { [self->_transport request:wf::Bytes{uint8_t(self->_v2?0x22:0x10),2} reply:self->_v2?0x23:0x11 inquiry:2]; } catch(const std::exception&) {}
    }
    if(self->_ambientInquiry) [self->_transport request:wf::Bytes{0x66,self->_ambientInquiry} reply:0x67 inquiry:self->_ambientInquiry];
    if(self->_eqAvailable) [self->_transport request:wf::Bytes{0x56,uint8_t(self->_v2?0:1)} reply:0x57 inquiry:self->_v2?0:1];
}
- (void)refresh:(WFCompletion)completion {
    [self enqueue:^{
        NSString *error=nil;
        try { [self readStatus:YES]; [self refreshSettings]; }
        catch(const std::exception& e) { error=@(e.what()); [self->_transport close]; }
        [self finish:completion error:error];
    }];
}
- (void)pollStatus:(WFCompletion)completion {
    [self enqueue:^{
        NSString *error=nil;
        try { [self readStatus:YES]; }
        catch(const std::exception& e) { error=@(e.what()); [self->_transport close]; }
        [self finish:completion error:error];
    }];
}
- (void)setMode:(NSString *)mode level:(NSInteger)level voice:(BOOL)voice completion:(WFCompletion)completion {
    [self enqueue:^{
        NSString *error=nil;
        try {
            NSDictionary *before=[self->_transport snapshot];
            if(![before[@"supportsAmbient"] boolValue]) throw std::runtime_error("Ambient control has not been verified for this device.");
            if(level<1 || level>self->_maxAmbient) throw std::runtime_error("Ambient level is outside device capability.");
            bool supportedRange=false;
            for(const auto& range:self->_ambientRanges) if(range.mode==(voice?1:0) && level>=range.minimum && level<=range.maximum && (level-range.minimum)%range.step==0) supportedRange=true;
            if(!supportedRange) throw std::runtime_error("This ambient level or voice mode is not advertised by the headphones.");
            wf::AmbientMode selected;
            if([mode isEqual:@"off"]) selected=wf::AmbientMode::Off;
            else if([mode isEqual:@"anc"]) selected=wf::AmbientMode::NoiseCancelling;
            else if([mode isEqual:@"ambient"]) selected=wf::AmbientMode::Ambient;
            else throw std::runtime_error("Invalid ambient mode.");
            auto raw=[self->_transport request:wf::Bytes{0x66,self->_ambientInquiry} reply:0x67 inquiry:self->_ambientInquiry];
            auto current=self->_v2?wf::parseAmbient(raw):wf::parseLegacyAmbient(raw);
            if(!current) throw std::runtime_error("Invalid current ANC state.");
            current->mode=selected; current->focusOnVoice=voice; current->level=(int)level;
            [self->_transport request:wf::setAmbient(*current) reply:-1 inquiry:-1];
            BOOL confirmed=NO;
            for(int attempt=0;attempt<5;attempt++) {
                if(attempt) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.15]];
                [self->_transport request:wf::Bytes{0x66,self->_ambientInquiry} reply:0x67 inquiry:self->_ambientInquiry];
                NSDictionary *after=[self->_transport snapshot];
                confirmed=[after[@"mode"] isEqual:mode] && (![mode isEqual:@"ambient"] ||
                    ([after[@"ambientLevel"] integerValue]==level && [after[@"focusOnVoice"] boolValue]==voice));
                if(confirmed) break;
            }
            if(!confirmed)
                throw std::runtime_error("The device did not confirm the requested ambient setting.");
        } catch(const std::exception& e) { error=@(e.what()); }
        [self finish:completion error:error];
    }];
}
- (void)setPreset:(NSInteger)preset completion:(WFCompletion)completion {
    [self enqueue:^{
        NSString *error=nil;
        try {
            if(![self->_presets containsObject:@(preset)]) throw std::runtime_error("This EQ preset is not advertised by the device.");
            auto command=wf::setEQPreset((uint8_t)preset); if(!self->_v2) command[1]=1;
            [self->_transport request:command reply:-1 inquiry:-1];
            [self->_transport request:wf::Bytes{0x56,uint8_t(self->_v2?0:1)} reply:0x57 inquiry:self->_v2?0:1];
            NSDictionary *after=[self->_transport snapshot];
            if(![after[@"supportsEQ"] boolValue] || ![after[@"preset"] isKindOfClass:NSNumber.class] || [after[@"preset"] integerValue]!=preset)
                throw std::runtime_error("The device did not confirm the requested EQ preset.");
        } catch(const std::exception& e) { error=@(e.what()); }
        [self finish:completion error:error];
    }];
}
- (void)setCustomBass:(NSInteger)bass bands:(NSArray<NSNumber *> *)bands completion:(WFCompletion)completion {
    [self enqueue:^{
        NSString *error=nil;
        try {
            if(!self->_supportsEditor || ![self->_presets containsObject:@0xa0] || bands.count!=5) throw std::runtime_error("Manual five-band EQ is not advertised by the device.");
            std::array<int,5> values{};
            for(int i=0;i<5;i++) values[i]=bands[i].intValue;
            auto command=wf::setEQCustom((int)bass,values); if(!self->_v2) command[1]=1;
            [self->_transport request:command reply:-1 inquiry:-1];
            [self->_transport request:wf::Bytes{0x56,uint8_t(self->_v2?0:1)} reply:0x57 inquiry:self->_v2?0:1];
            NSDictionary *after=[self->_transport snapshot];
            if([after[@"preset"] integerValue]!=0xa0 || [after[@"clearBass"] integerValue]!=bass || ![after[@"bands"] isEqual:bands])
                throw std::runtime_error("The device did not confirm the requested manual EQ.");
        } catch(const std::exception& e) { error=@(e.what()); }
        [self finish:completion error:error];
    }];
}
- (void)loadSettings {
    for(auto& spec:_specs) {
        NSString *identifier=@(spec.id.c_str());
        NSMutableArray *options=[NSMutableArray new];
        NSMutableDictionary *row=[@{@"id":identifier,@"title":safeText(spec.title,@"Headphone setting"),@"section":safeText(spec.section,@"System"),@"kind":@"choice",@"value":NSNull.null,@"enabled":@NO,@"reason":@"Waiting for a valid device response."} mutableCopy];
        try {
            // Auto-off values must come from the advertised candidate list.
            if(spec.get==0xd6) {
                auto status=[_transport request:wf::Bytes{0xd2,spec.inquiry} reply:0xd3 inquiry:spec.inquiry];
                if(status.size()!=3 || status[2]!=0) throw std::runtime_error("This general setting is currently unavailable.");
            }
            if(spec.capabilityOptions && _v2) {
                auto cap=[_transport request:wf::Bytes{0x20,spec.inquiry} reply:0x21 inquiry:spec.inquiry];
                if(cap.size()<3 || cap.size()!=size_t(3+cap[2])) throw std::runtime_error("Unrecognized automatic power-off capability.");
                auto copy=spec.options; spec.options.clear();
                for(auto& option:copy) if(std::find(cap.begin()+3,cap.end(),option.value)!=cap.end()) spec.options.push_back(option);
                if(spec.options.empty()) throw std::runtime_error("No supported power-off choices were advertised.");
            }
            auto response=[_transport request:wf::Bytes{spec.get,spec.inquiry} reply:spec.reply inquiry:spec.inquiry table:spec.table];
            auto value=wf::settingValue(spec,response);
            if(!value) throw std::runtime_error("This device uses a setting format that is not yet supported.");
            _settingReplies[identifier]=[NSData dataWithBytes:response.data() length:response.size()];
            row[@"value"]=@(*value); row[@"enabled"]=@YES; row[@"reason"]=@"Read from headphones; changes require readback.";
        } catch(const std::exception& e) { row[@"reason"]=@(e.what()); [_settingReplies removeObjectForKey:identifier]; }
        for(auto& option:spec.options) [options addObject:@{@"label":safeText(option.label,@"Unknown option"),@"value":@(option.value)}];
        row[@"options"]=options; _settingRows[identifier]=row;
    }
    // Read-only device information is separate from firmware update functions.
    for(int inquiry:{0,2}) {
        NSString *identifier=inquiry==0?@"modelName":@"firmware";
        try {
            auto response=[_transport request:wf::Bytes{4,uint8_t(inquiry)} reply:5 inquiry:inquiry];
            if(response.size()<3 || response.size()!=size_t(3+response[2])) continue;
            NSString *value=[[NSString alloc] initWithBytes:response.data()+3 length:response[2] encoding:NSUTF8StringEncoding];
            if(value) _settingRows[identifier]=@{@"id":identifier,@"title":inquiry==0?@"Model":@"Firmware version",@"section":@"Device",@"kind":@"readonly",@"value":value,@"enabled":@NO,@"options":@[],@"reason":@"Read-only headphone information."};
        } catch(const std::exception&) {}
    }
    auto has=[&](int tag){return std::find(_functions.begin(),_functions.end(),tag)!=_functions.end();};
    if(has(_v2?0x12:0x13)) {
        try {
            // V2 CommonGetStatus AudioCodec=02; V1 GetCodec=02 shares status
            // command12 but its explicit inquiry is AUDIO_CODEC=02.
            auto response=[_transport request:wf::Bytes{uint8_t(_v2?0x12:0x18),uint8_t(_v2?2:0)} reply:_v2?0x13:0x19 inquiry:_v2?2:0];
            if(response.size()==3) {
                NSString *name=response[2]==1?@"SBC":response[2]==2?@"AAC":response[2]==0x10?@"LDAC":response[2]==0x20?@"aptX":response[2]==0x21?@"aptX HD":@"Unknown";
                _settingRows[@"codec"]=@{@"id":@"codec",@"title":@"Active codec",@"section":@"Audio",@"kind":@"readonly",@"value":name,@"enabled":@NO,@"options":@[],@"reason":@"Codec is negotiated by macOS."};
            }
        } catch(const std::exception&) {}
    }
}
- (void)refreshSettings {
    [self refreshAssignments];
    for(const auto& spec:_specs) {
        if(spec.id.rfind("assignment",0)==0) continue;
        NSString *identifier=@(spec.id.c_str());
        if(![_settingRows[identifier][@"enabled"] boolValue]) continue;
        NSMutableDictionary *row=[_settingRows[identifier] mutableCopy];
        try {
            auto response=[_transport request:wf::Bytes{spec.get,spec.inquiry} reply:spec.reply inquiry:spec.inquiry table:spec.table];
            auto value=wf::settingValue(spec,response);
            if(!value) throw std::runtime_error("Unrecognized device setting response.");
            row[@"value"]=@(*value);
        } catch(const std::exception& e) { row[@"enabled"]=@NO;row[@"value"]=NSNull.null;row[@"reason"]=@(e.what()); }
        _settingRows[identifier]=row;
    }
}
- (void)updateAssignmentRows:(const wf::Bytes&)reply availability:(const std::vector<bool>&)availability {
    auto values=wf::parseAssignmentValues(_assignmentKeys,reply);
    if(!values || availability.size()!=_assignmentKeys.size()) throw std::runtime_error("Unrecognized touch-control response.");
    for(size_t i=0;i<_assignmentKeys.size();++i) {
        NSString *identifier=[NSString stringWithFormat:@"assignment%lu",(unsigned long)i];
        NSMutableDictionary *row=[_settingRows[identifier] mutableCopy];
        if(!row) continue;
        row[@"value"]=@((*values)[i]); row[@"enabled"]=@(bool(availability[i]));
        row[@"reason"]=availability[i]?@"Read from headphones; apply the complete control combination.":@"This button is unavailable. Take both earbuds out of the case and reconnect.";
        _settingRows[identifier]=row;
    }
}
- (void)refreshAssignments {
    if(_assignmentKeys.empty()) return;
    try {
        auto availability=wf::parseAssignmentAvailability(_assignmentKeys.size(),[_transport request:wf::Bytes{0xf2,3} reply:0xf3 inquiry:3]);
        if(!availability) throw std::runtime_error("Unrecognized touch-control availability.");
        auto reply=[_transport request:wf::Bytes{0xf6,3} reply:0xf7 inquiry:3];
        [self updateAssignmentRows:reply availability:*availability];
    } catch(const std::exception& e) {
        for(size_t i=0;i<_assignmentKeys.size();++i) {
            NSString *identifier=[NSString stringWithFormat:@"assignment%lu",(unsigned long)i];
            NSMutableDictionary *row=[_settingRows[identifier] mutableCopy];
            if(row) { row[@"value"]=NSNull.null;row[@"enabled"]=@NO;row[@"reason"]=@(e.what());_settingRows[identifier]=row; }
        }
    }
}
- (void)setTouchAssignments:(NSDictionary<NSString *,NSNumber *> *)values completion:(WFCompletion)completion {
    NSDictionary *requested=[values copy];
    [self enqueue:^{
        NSString *error=nil;
        wf::Bytes original; BOOL attempted=NO;
        try {
            if(!self->_transport.connected || self->_assignmentKeys.empty() || !requested.count) throw std::runtime_error("Touch controls are not available on the connected headphones.");
            auto availability=wf::parseAssignmentAvailability(self->_assignmentKeys.size(),[self->_transport request:wf::Bytes{0xf2,3} reply:0xf3 inquiry:3]);
            if(!availability) throw std::runtime_error("Unrecognized touch-control availability.");
            original=[self->_transport request:wf::Bytes{0xf6,3} reply:0xf7 inquiry:3];
            auto current=wf::parseAssignmentValues(self->_assignmentKeys,original);
            if(!current) throw std::runtime_error("No valid current touch-control list.");
            std::vector<std::optional<uint8_t>> changes(self->_assignmentKeys.size());
            for(NSString *identifier in requested) {
                bool found=false;
                for(size_t i=0;i<changes.size();++i) if([identifier isEqual:[NSString stringWithFormat:@"assignment%lu",(unsigned long)i]]) {
                    NSNumber *number=requested[identifier];
                    if(![number isKindOfClass:NSNumber.class] || number.doubleValue!=number.intValue || number.intValue<0 || number.intValue>255) throw std::runtime_error("Invalid touch action.");
                    if(!(*availability)[i] && number.intValue!=(*current)[i]) throw std::runtime_error("This button is unavailable. Take both earbuds out of the case and reconnect.");
                    changes[i]=uint8_t(number.intValue);found=true;
                }
                if(!found) throw std::runtime_error("Unknown headphone button.");
            }
            auto command=wf::setAssignmentValues(self->_assignmentKeys,original,changes);
            auto expected=command;expected[0]=0xf7;
            if(expected==original) { [self updateAssignmentRows:original availability:*availability]; [self finish:completion error:nil]; return; }
            attempted=YES;
            [self->_transport request:command reply:-1 inquiry:-1];
            wf::Bytes reply;
            for(int attempt=0;attempt<8;++attempt) {
                if(attempt) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.15]];
                reply=[self->_transport request:wf::Bytes{0xf6,3} reply:0xf7 inquiry:3];
                [self updateAssignmentRows:reply availability:*availability];
                if(reply==expected) break;
            }
            if(reply!=expected) {
                if(std::find(expected.begin()+3,expected.end(),0x20)==expected.end())
                    throw std::runtime_error("The headphones rejected this combination. Keep Playback control on one side and apply both sides together.");
                throw std::runtime_error("The headphones did not confirm the complete touch-control combination.");
            }
        } catch(const std::exception& e) {
            error=@(e.what());
            // A rejected or partially applied list must not silently change the other side.
            if(attempted && !original.empty() && self->_transport.connected) {
                try {
                    auto restore=original;restore[0]=0xf8;
                    [self->_transport request:restore reply:-1 inquiry:-1];
                    wf::Bytes reply;
                    for(int attempt=0;attempt<8;++attempt) {
                        if(attempt) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.15]];
                        reply=[self->_transport request:wf::Bytes{0xf6,3} reply:0xf7 inquiry:3];
                        if(reply==original) break;
                    }
                    if(reply!=original) throw std::runtime_error("Previous touch-control combination could not be restored. Reconnect and review both sides.");
                } catch(const std::exception& restoreError) { error=[NSString stringWithFormat:@"%@ %@",error,@(restoreError.what())]; }
            } else if(attempted) {
                error=[NSString stringWithFormat:@"%@ Reconnect and verify both controls; the previous pair could not be confirmed.",error];
            }
            [self refreshAssignments];
        }
        [self finish:completion error:error];
    }];
}
- (void)setSetting:(NSString *)identifier value:(id)value completion:(WFCompletion)completion {
    if([identifier hasPrefix:@"assignment"]) {
        if(!value) value=NSNull.null;
        [self setTouchAssignments:@{identifier:value} completion:completion]; return;
    }
    [self enqueue:^{
        NSString *error=nil;
        try {
            const wf::SettingSpec *found=nullptr;
            for(const auto& spec:self->_specs) if([identifier isEqual:@(spec.id.c_str())]) found=&spec;
            if(!found || ![self->_settingRows[identifier][@"enabled"] boolValue] || ![value isKindOfClass:NSNumber.class]) throw std::runtime_error("This setting is not available on the connected headphones.");
            const auto& spec=*found;
            if(spec.get==0xd6) {
                auto status=[self->_transport request:wf::Bytes{0xd2,spec.inquiry} reply:0xd3 inquiry:spec.inquiry];
                if(status.size()!=3 || status[2]!=0) throw std::runtime_error("This general setting is currently unavailable.");
            }
            auto current=[self->_transport request:wf::Bytes{spec.get,spec.inquiry} reply:spec.reply inquiry:spec.inquiry table:spec.table];
            auto command=wf::settingCommand(spec,current,[value intValue]);
            [self->_transport request:command reply:-1 inquiry:-1 table:spec.table];
            auto response=[self->_transport request:wf::Bytes{spec.get,spec.inquiry} reply:spec.reply inquiry:spec.inquiry table:spec.table];
            auto actual=wf::settingValue(spec,response);
            for(int attempt=0;actual && *actual!=[value intValue] && attempt<4;++attempt) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.15]]; response=[self->_transport request:wf::Bytes{spec.get,spec.inquiry} reply:spec.reply inquiry:spec.inquiry table:spec.table]; actual=wf::settingValue(spec,response); }
            NSMutableDictionary *row=[self->_settingRows[identifier] mutableCopy];
            row[@"value"]=actual?@(*actual):NSNull.null;
            if(!actual) {row[@"enabled"]=@NO;row[@"reason"]=@"Unrecognized device response.";}
            self->_settingRows[identifier]=row;
            if(!actual || *actual!=[value intValue]) {
                if(spec.id=="sourceSwitch") {
                    switch(self->_transport.sourceSwitchResult) {
                        case 2: throw std::runtime_error("The headphones cannot change source switching while a call is active.");
                        case 3: throw std::runtime_error("The headphones require an active Bluetooth audio connection to change source switching.");
                        case 4: throw std::runtime_error("The headphones are giving priority to the voice assistant. Try again when it is finished.");
                        default: break;
                    }
                }
                throw std::runtime_error("The headphones did not confirm the requested setting.");
            }
        } catch(const std::exception& e) {
            error=@(e.what());
            // A lost link or an unusable current value makes the row untrustworthy.
            if(dynamic_cast<const wf::LinkError*>(&e) || dynamic_cast<const std::invalid_argument*>(&e)) {
                NSMutableDictionary *row=[self->_settingRows[identifier] mutableCopy];
                if(row) {row[@"enabled"]=@NO;row[@"value"]=NSNull.null;row[@"reason"]=error;self->_settingRows[identifier]=row;}
            }
        }
        [self finish:completion error:error];
    }];
}
- (void)disconnect:(WFCompletion)completion {
    [self enqueue:^{ [self->_transport close]; self->_presets=@[]; [self->_settingRows removeAllObjects]; self->_functions.clear(); self->_specs.clear(); [self finish:completion error:nil]; }];
}
- (void)stopWorker { [_transport close]; _stopping=true; }
- (void)shutdown {
    if(!_thread || _thread.finished) return;
    @synchronized(_work) {
        _acceptingWork=NO;
        [_transport requestCancellation];
        [_work removeAllObjects];
        __weak WFBridge *weakSelf=self;
        [_work addObject:[^{ [weakSelf stopWorker]; } copy]];
    }
    [self wake];
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:2];
    while(!_thread.finished && deadline.timeIntervalSinceNow>0) [NSThread sleepForTimeInterval:0.01];
}
@end
