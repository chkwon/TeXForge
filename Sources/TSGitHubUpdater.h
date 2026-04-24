#import <Cocoa/Cocoa.h>

@interface TSGitHubUpdater : NSObject

+ (instancetype)sharedUpdater;
- (void)checkForUpdates;

@end
