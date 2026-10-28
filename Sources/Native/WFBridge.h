#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
typedef void (^WFCompletion)(NSDictionary * _Nullable snapshot, NSString * _Nullable error);
@interface WFBridge : NSObject
- (void)listDevices:(void (^)(NSArray<NSDictionary *> *devices))completion;
- (void)connectAddress:(NSString *)address completion:(WFCompletion)completion;
- (void)refresh:(WFCompletion)completion;
/// Cheap periodic read: battery, ambient and EQ only; cached settings are not re-read.
- (void)pollStatus:(WFCompletion)completion;
- (void)setSetting:(NSString *)identifier value:(id)value completion:(WFCompletion)completion;
- (void)setTouchAssignments:(NSDictionary<NSString *,NSNumber *> *)values completion:(WFCompletion)completion;
- (void)setMode:(NSString *)mode level:(NSInteger)level voice:(BOOL)voice completion:(WFCompletion)completion;
- (void)setPreset:(NSInteger)preset completion:(WFCompletion)completion;
- (void)setCustomBass:(NSInteger)bass bands:(NSArray<NSNumber *> *)bands completion:(WFCompletion)completion;
- (void)disconnect:(WFCompletion)completion;
- (void)shutdown;
@end
NS_ASSUME_NONNULL_END
