#import "SUUpdater.h"

#import "TSAppDelegate.h"

@implementation SUUpdater

+ (instancetype)sharedUpdater
{
    static SUUpdater *sharedUpdater = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedUpdater = [[SUUpdater alloc] init];
    });
    return sharedUpdater;
}

- (IBAction)checkForUpdates:(id)sender
{
    id delegate = [NSApp delegate];
    if ([delegate isKindOfClass:[TSAppDelegate class]]) {
        [(TSAppDelegate *)delegate checkForUpdate:sender];
    }
}

- (void)setAutomaticallyChecksForUpdates:(BOOL)automaticallyChecksForUpdates
{
    (void)automaticallyChecksForUpdates;
}

- (void)setUpdateCheckInterval:(NSTimeInterval)updateCheckInterval
{
    (void)updateCheckInterval;
}

@end
