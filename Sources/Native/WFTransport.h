#import <Foundation/Foundation.h>
#import <IOBluetooth/IOBluetooth.h>
#include "../Core/WFProtocol.h"

// Called exclusively on one thread with an active NSRunLoop.
@interface WFTransport : NSObject <IOBluetoothRFCOMMChannelDelegate>
@property(nonatomic, readonly) BOOL connected;
@property(nonatomic, readonly) NSString *address;
@property(nonatomic, readonly) NSString *name;
@property(nonatomic, readonly) NSNumber *channelID;
@property(nonatomic, readonly) BOOL isV2;
@property(nonatomic, readonly) NSInteger sourceSwitchResult;
- (void)openAddress:(NSString *)address;
- (void)close;
// Thread-safe cancellation flag; channel operations remain on the owner thread.
- (void)requestCancellation;
- (void)clearCaseBattery;
- (wf::Bytes)request:(const wf::Bytes&)command reply:(int)reply inquiry:(int)inquiry;
- (wf::Bytes)request:(const wf::Bytes&)command reply:(int)reply inquiry:(int)inquiry table:(int)table;
- (NSDictionary *)snapshot;
@end
