#import "WFBridge.h"
#import <IOBluetooth/IOBluetooth.h>
#include <cstdio>
#include <stdexcept>

static NSDictionary *run(void (^action)(WFCompletion),NSString **error) {
    __block BOOL done=NO;__block NSDictionary *state=nil;__block NSString *failure=nil;
    action(^(NSDictionary *value,NSString *message){state=value;failure=message;done=YES;});
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:90];
    while(!done && deadline.timeIntervalSinceNow>0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    if(!done) throw std::runtime_error("Bridge completion timed out.");
    if(error) *error=failure;return state;
}
static NSDictionary *actions(NSDictionary *state) {
    NSMutableDictionary *values=[NSMutableDictionary new];
    for(NSDictionary *row in state[@"settings"]) if([row[@"id"] hasPrefix:@"assignment"] && [row[@"value"] isKindOfClass:NSNumber.class]) values[row[@"id"]]=row[@"value"];
    return values;
}
int main(){@autoreleasepool{
    WFBridge *bridge=[WFBridge new];NSString *address=nil,*error=nil;
    for(IOBluetoothDevice *device in [IOBluetoothDevice pairedDevices]) if([device.name containsString:@"WF-1000XM4"]) address=device.addressString;
    if(!address){fprintf(stderr,"WF-1000XM4 is not paired.\n");[bridge shutdown];return 1;}
    auto initial=run(^(WFCompletion c){[bridge connectAddress:address completion:c];},&error);
    NSDictionary *original=actions(initial);
    if(error || original.count!=2){fprintf(stderr,"Touch controls unavailable.\n");[bridge shutdown];return 1;}
    BOOL passed=YES;NSMutableArray *tests=[NSMutableArray new];
    // Keep Playback on one side, testing every basic preset on each side.
    const int combinations[][2]={{0x20,0},{0,0x20},{0x20,0x10},{0x10,0x20},{0x20,0xff},{0xff,0x20}};
    for(auto& pair:combinations){
        NSDictionary *wanted=@{@"assignment0":@(pair[0]),@"assignment1":@(pair[1])};
        auto state=run(^(WFCompletion c){[bridge setTouchAssignments:wanted completion:c];},&error);
        BOOL confirmed=!error && [actions(state) isEqual:wanted];passed&=confirmed;
        [tests addObject:@{@"expected":wanted,@"confirmed":@(confirmed),@"error":error?:NSNull.null}];
        if(!confirmed) break;
    }
    NSDictionary *before=actions(run(^(WFCompletion c){[bridge refresh:c];},&error));
    auto rejected=run(^(WFCompletion c){[bridge setTouchAssignments:@{@"assignment0":@0x10,@"assignment1":@0} completion:c];},&error);
    // This test unit rejected loss of Playback; verify a rejection preserves both sides.
    BOOL rejectedSafely=error && [actions(rejected) isEqual:before];passed&=rejectedSafely;
    [tests addObject:@{@"rejected_pair_preserves_previous":@(rejectedSafely),@"error":error?:NSNull.null}];
    auto restored=run(^(WFCompletion c){[bridge setTouchAssignments:original completion:c];},&error);
    BOOL exact=!error && [actions(restored) isEqual:original];passed&=exact;
    NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"tests":tests,@"original":original,@"restored":@(exact),@"passed":@(passed)} options:NSJSONWritingPrettyPrinted error:nil];
    fwrite(data.bytes,1,data.length,stdout);
    run(^(WFCompletion c){[bridge disconnect:c];},nullptr);[bridge shutdown];
    return passed?0:2;
}}
