#import "WFBridge.h"
#import <IOBluetooth/IOBluetooth.h>
#include <cstdio>
#include <stdexcept>
static NSDictionary *run(void (^action)(WFCompletion), NSString **error) {
    __block BOOL complete=NO; __block NSDictionary *state=nil; __block NSString *failure=nil;
    action(^(NSDictionary *snapshot,NSString *message){state=snapshot;failure=message;complete=YES;});
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:90];
    while(!complete && deadline.timeIntervalSinceNow>0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    if(!complete) throw std::runtime_error("Bridge completion timed out");
    if(error) *error=failure; return state;
}
static NSDictionary *row(NSDictionary *state,NSString *identifier) {
    for(NSDictionary *entry in state[@"settings"]) if([entry[@"id"] isEqual:identifier]) return entry;
    return nil;
}
int main(int argc,const char **argv) { @autoreleasepool {
    WFBridge *bridge=[WFBridge new]; NSString *address=nil,*error=nil;
    for(IOBluetoothDevice *device in [IOBluetoothDevice pairedDevices]) if([device.name containsString:@"WF-1000XM4"]) address=device.addressString;
    if(!address) { fprintf(stderr,"WF-1000XM4 is not paired.\n"); [bridge shutdown]; return 1; }
    NSDictionary *initial=run(^(WFCompletion c){[bridge connectAddress:address completion:c];},&error);
    if(error) { fprintf(stderr,"%s\n",error.UTF8String);[bridge shutdown];return 1; }
    NSMutableArray *tests=[NSMutableArray new]; BOOL allPassed=YES;
    NSArray *identifiers=argc>1?@[@(argv[1])]:@[@"soundQuality",@"autoOff",@"general210",@"sourceSwitch"];
    for(NSString *identifier in identifiers) {
        NSDictionary *before=row(initial,identifier); NSNumber *original=before[@"value"];
        if(![before[@"enabled"] boolValue] || ![original isKindOfClass:NSNumber.class]) {
            [tests addObject:@{@"id":identifier,@"status":@"unavailable"}];continue;
        }
        NSNumber *target=nil;
        for(NSDictionary *option in before[@"options"]) if(![option[@"value"] isEqual:original]) target=option[@"value"];
        if(!target) { [tests addObject:@{@"id":identifier,@"status":@"no alternative"}];continue; }
        NSString *setError=nil,*restoreError=nil,*reconnectError=nil;
        NSDictionary *changed=run(^(WFCompletion c){[bridge setSetting:identifier value:target completion:c];},&setError);
        BOOL readback=[row(changed,identifier)[@"value"] isEqual:target];
        if(![changed[@"connected"] boolValue] || ![row(changed,identifier)[@"enabled"] boolValue]) {
            changed=run(^(WFCompletion c){[bridge connectAddress:address completion:c];},&reconnectError);
            readback=[row(changed,identifier)[@"value"] isEqual:target];
        }
        NSDictionary *restored=run(^(WFCompletion c){[bridge setSetting:identifier value:original completion:c];},&restoreError);
        if(restoreError || ![restored[@"connected"] boolValue]) {
            run(^(WFCompletion c){[bridge connectAddress:address completion:c];},&reconnectError);
            restored=run(^(WFCompletion c){[bridge setSetting:identifier value:original completion:c];},&restoreError);
        }
        BOOL exact=[row(restored,identifier)[@"value"] isEqual:original];
        BOOL passed=readback && exact && !restoreError;
        allPassed&=passed;
        [tests addObject:@{@"id":identifier,@"changedReadback":@(readback),@"restored":@(exact),@"setError":setError?:NSNull.null,@"restoreError":restoreError?:NSNull.null,@"reconnectError":reconnectError?:NSNull.null,@"status":passed?@"passed":@"failed"}];
        if(!exact) { fprintf(stderr,"Restoration failed; stopping: %s\n",identifier.UTF8String);break; }
    }
    NSDictionary *final=run(^(WFCompletion c){[bridge refresh:c];},&error);
    NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"tests":tests,@"baseline":initial,@"final":final?:@{},@"finalError":error?:NSNull.null} options:NSJSONWritingPrettyPrinted error:nil];
    fwrite(data.bytes,1,data.length,stdout);
    run(^(WFCompletion c){[bridge disconnect:c];},nullptr); [bridge shutdown];
    return allPassed && !error?0:2;
}}
