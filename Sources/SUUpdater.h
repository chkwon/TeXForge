#import <Cocoa/Cocoa.h>

@interface SUUpdater : NSObject

+ (instancetype)sharedUpdater;
- (IBAction)checkForUpdates:(id)sender;
- (void)setAutomaticallyChecksForUpdates:(BOOL)automaticallyChecksForUpdates;
- (void)setUpdateCheckInterval:(NSTimeInterval)updateCheckInterval;

@end
