#import "WFTransport.h"
#include <stdexcept>
#include <cstdio>

static void require(bool value,const char *reason) { if(!value) throw std::runtime_error(reason); }
static NSString *hexBytes(const wf::Bytes& bytes) {
    NSMutableString *s=[NSMutableString new]; for(auto b:bytes) [s appendFormat:@"%02x",b]; return s;
}
int main(int argc,const char **argv) {
    @autoreleasepool {
        WFTransport *transport=[WFTransport new];
        wf::Bytes originalAmbient,originalEQ;
        NSMutableArray *checks=[NSMutableArray new];
        BOOL changed=NO,restored=NO;
        NSString *error=nil,*restoreError=nil;
        NSString *address=nil;
        for(IOBluetoothDevice *device in [IOBluetoothDevice pairedDevices])
            if([device.name containsString:@"WF-1000XM4"]) { address=device.addressString; break; }
        auto restore=[&] {
            if(!transport.connected) [transport openAddress:address];
            auto ambient=originalAmbient; ambient[0]=0x68; ambient[2]=1;
            [transport request:ambient reply:-1 inquiry:-1];
            if(originalEQ[2]==0xa0) {
                auto eq=originalEQ;eq[0]=0x58;[transport request:eq reply:-1 inquiry:-1];
            } else [transport request:wf::setEQPreset(originalEQ[2]) reply:-1 inquiry:-1];
            auto a=[transport request:wf::Bytes{0x66,0x15} reply:0x67 inquiry:0x15];
            auto e=[transport request:wf::Bytes{0x56,0} reply:0x57 inquiry:0];
            require(a==originalAmbient,"Original ANC readback differs after restoration");
            require(e==originalEQ,"Original EQ readback differs after restoration");
            restored=YES;
        };
        try {
            require(address!=nil,"WF-1000XM4 not paired");
            [transport openAddress:address];
            [transport request:wf::Bytes{0,0} reply:1 inquiry:-1];
            [transport request:wf::Bytes{6,0} reply:7 inquiry:0];
            originalAmbient=[transport request:wf::Bytes{0x66,0x15} reply:0x67 inquiry:0x15];
            originalEQ=[transport request:wf::Bytes{0x56,0} reply:0x57 inquiry:0];
            require(wf::parseAmbient(originalAmbient).has_value(),"Original ANC not parseable");
            require(wf::parseEQ(originalEQ).has_value(),"Original EQ not parseable");
            NSDictionary *baseline=@{@"ambient":hexBytes(originalAmbient),@"eq":hexBytes(originalEQ),@"snapshot":[transport snapshot]};
            NSData *baselineJSON=[NSJSONSerialization dataWithJSONObject:baseline options:NSJSONWritingPrettyPrinted error:nil];
            require([baselineJSON writeToFile:@"analysis/hardware-baseline.json" atomically:YES],"Could not save restore baseline");
            auto cap=wf::parseAmbientCapabilities([transport request:wf::Bytes{0x60,0x15} reply:0x61 inquiry:0x15]);
            require(cap.has_value(),"ANC capability unavailable");
            auto eqcap=wf::parseEQCapabilities([transport request:wf::Bytes{0x50,0} reply:0x51 inquiry:0]);
            require(eqcap && eqcap->supportsEditor(),"Manual EQ capability not supported");
            auto battery=[transport request:wf::Bytes{0x22,1} reply:0x23 inquiry:1];
            [transport request:wf::Bytes{0x22,2} reply:0x23 inquiry:2];
            require(battery.size()==6,"L/R battery response invalid");
            [checks addObject:@"Read left/right/case battery"];
            for(auto mode:{wf::AmbientMode::NoiseCancelling,wf::AmbientMode::Ambient,wf::AmbientMode::Off}) {
                auto desired=*wf::parseAmbient(originalAmbient); desired.mode=mode; desired.level=16;
                changed=YES;
                [transport request:wf::setAmbient(desired) reply:-1 inquiry:-1];
                auto response=wf::parseAmbient([transport request:wf::Bytes{0x66,0x15} reply:0x67 inquiry:0x15]);
                require(response && response->mode==mode,"ANC mode write/readback mismatch");
                [checks addObject:mode==wf::AmbientMode::NoiseCancelling?@"ANC write/readback":mode==wf::AmbientMode::Ambient?@"Ambient write/readback":@"Off write/readback"];
            }
            [transport request:wf::setEQPreset(0) reply:-1 inquiry:-1];
            auto eq=wf::parseEQ([transport request:wf::Bytes{0x56,0} reply:0x57 inquiry:0]);
            require(eq && eq->preset==0,"EQ preset write/readback mismatch");
            [checks addObject:@"EQ off preset write/readback"];
            const std::array<int,5> bands={-1,1,0,3,4};
            [transport request:wf::setEQCustom(7,bands) reply:-1 inquiry:-1];
            eq=wf::parseEQ([transport request:wf::Bytes{0x56,0} reply:0x57 inquiry:0]);
            require(eq && eq->preset==0xa0 && eq->clearBass==7 && eq->bands==bands,"Manual EQ write/readback mismatch");
            [checks addObject:@"Manual EQ five bands + Clear Bass write/readback"];
            restore(); [checks addObject:@"Original ANC and EQ restored byte-for-byte"];
            [transport close];
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
            [transport openAddress:address];
            [transport request:wf::Bytes{0,0} reply:1 inquiry:-1];
            auto reconnected=[transport request:wf::Bytes{0x66,0x15} reply:0x67 inquiry:0x15];
            require(reconnected==originalAmbient,"ANC changed after reconnect");
            require([transport request:wf::Bytes{0x56,0} reply:0x57 inquiry:0]==originalEQ,"EQ changed after reconnect");
            [checks addObject:@"Disconnect/reconnect retains confirmed state"];
        } catch(const std::exception& e) { error=@(e.what()); }
        if(changed && !restored) {
            try { restore(); } catch(const std::exception& e) { restoreError=@(e.what()); }
        }
        NSDictionary *report=@{@"checks":checks,@"ok":@(!error && restored),@"restored":@(restored),
            @"error":error?:NSNull.null,@"restoreError":restoreError?:NSNull.null,@"snapshot":[transport snapshot]};
        NSData *json=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];
        [json writeToFile:@"analysis/hardware-tests.json" atomically:YES];
        fwrite(json.bytes,1,json.length,stdout); puts("");
        [transport close]; return error?1:0;
    }
}
