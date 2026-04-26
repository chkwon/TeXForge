#import "TSGitHubUpdater.h"

#import <CommonCrypto/CommonDigest.h>
#include <sys/sysctl.h>

static NSString * const kTSGitHubOwner = @"chkwon";
static NSString * const kTSGitHubRepo = @"TeXForge";
static NSString * const kTSGitHubAPIVersion = @"2026-03-10";
static NSString * const kTSGitHubLatestReleaseURL = @"https://api.github.com/repos/chkwon/TeXForge/releases/latest";

@interface TSGitHubReleaseAsset : NSObject

@property (copy) NSString *name;
@property (copy) NSString *downloadURLString;
@property (copy) NSString *digest;

@end

@implementation TSGitHubReleaseAsset
@end

@interface TSGitHubRelease : NSObject

@property (copy) NSString *tagName;
@property (copy) NSString *version;
@property (copy) NSString *releaseURLString;
@property (copy) NSString *releaseName;
@property (copy) NSString *releaseBody;
@property (strong) TSGitHubReleaseAsset *asset;

@end

@implementation TSGitHubRelease
@end

@interface TSUpdateProgressWindowController : NSWindowController

@property (copy) void (^cancelHandler)(void);

- (void)setStatus:(NSString *)status;
- (void)setIndeterminate:(BOOL)indeterminate;
- (void)setProgressFraction:(double)fraction;
- (void)setBytesText:(NSString *)text;
- (void)setCancelEnabled:(BOOL)enabled;

@end

@interface TSUpdateProgressWindowController ()

@property (strong) NSTextField *statusField;
@property (strong) NSProgressIndicator *progressBar;
@property (strong) NSTextField *bytesField;
@property (strong) NSButton *cancelButton;

@end

@implementation TSUpdateProgressWindowController

- (instancetype)init
{
    NSRect contentRect = NSMakeRect(0, 0, 440, 150);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:contentRect
                                                   styleMask:NSWindowStyleMaskTitled
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"TeXForge Update";
    window.releasedWhenClosed = NO;
    [window center];

    self = [super initWithWindow:window];
    if (self) {
        [self buildContentView];
    }
    return self;
}

- (void)buildContentView
{
    NSView *content = self.window.contentView;

    _statusField = [NSTextField labelWithString:@""];
    _statusField.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    _statusField.lineBreakMode = NSLineBreakByTruncatingTail;
    _statusField.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:_statusField];

    _progressBar = [[NSProgressIndicator alloc] init];
    _progressBar.style = NSProgressIndicatorStyleBar;
    _progressBar.indeterminate = YES;
    _progressBar.minValue = 0.0;
    _progressBar.maxValue = 1.0;
    _progressBar.translatesAutoresizingMaskIntoConstraints = NO;
    [_progressBar startAnimation:nil];
    [content addSubview:_progressBar];

    _bytesField = [NSTextField labelWithString:@""];
    _bytesField.font = [NSFont systemFontOfSize:11];
    _bytesField.textColor = [NSColor secondaryLabelColor];
    _bytesField.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:_bytesField];

    _cancelButton = [NSButton buttonWithTitle:@"Cancel"
                                       target:self
                                       action:@selector(cancelClicked:)];
    _cancelButton.keyEquivalent = @"\033";
    _cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:_cancelButton];

    [NSLayoutConstraint activateConstraints:@[
        [_statusField.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [_statusField.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [_statusField.topAnchor constraintEqualToAnchor:content.topAnchor constant:18],

        [_progressBar.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [_progressBar.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [_progressBar.topAnchor constraintEqualToAnchor:_statusField.bottomAnchor constant:10],

        [_bytesField.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [_bytesField.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [_bytesField.topAnchor constraintEqualToAnchor:_progressBar.bottomAnchor constant:6],

        [_cancelButton.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [_cancelButton.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-15],
    ]];
}

- (void)setStatus:(NSString *)status
{
    self.statusField.stringValue = status ?: @"";
}

- (void)setIndeterminate:(BOOL)indeterminate
{
    self.progressBar.indeterminate = indeterminate;
    if (indeterminate) {
        [self.progressBar startAnimation:nil];
    } else {
        [self.progressBar stopAnimation:nil];
    }
}

- (void)setProgressFraction:(double)fraction
{
    self.progressBar.doubleValue = fraction;
}

- (void)setBytesText:(NSString *)text
{
    self.bytesField.stringValue = text ?: @"";
}

- (void)setCancelEnabled:(BOOL)enabled
{
    self.cancelButton.enabled = enabled;
}

- (void)cancelClicked:(id)sender
{
    if (self.cancelHandler) {
        self.cancelHandler();
    }
}

@end

@interface TSGitHubUpdater () <NSURLSessionDelegate, NSURLSessionTaskDelegate, NSURLSessionDownloadDelegate>

@property (strong) NSURLSession *session;
@property (assign) BOOL isCheckingForUpdates;
@property (assign) BOOL isDownloadingUpdate;
@property (strong) TSUpdateProgressWindowController *progressController;
@property (strong) NSURLSessionDownloadTask *currentDownloadTask;
@property (strong) TSGitHubRelease *currentDownloadRelease;

@end

@implementation TSGitHubUpdater

+ (instancetype)sharedUpdater
{
    static TSGitHubUpdater *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[TSGitHubUpdater alloc] init];
    });
    return instance;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
        configuration.timeoutIntervalForRequest = 15.0;
        configuration.timeoutIntervalForResource = 600.0;
        _session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];
    }
    return self;
}

- (void)checkForUpdates
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.isCheckingForUpdates || self.isDownloadingUpdate) {
            [self showInfoAlertWithTitle:@"Update Already In Progress"
                                 message:@"TeXForge is already checking for or downloading an update."];
            return;
        }
        
        if (![self isAppleSiliconHost]) {
            NSInteger response = [self runAlertWithTitle:@"Apple Silicon Required"
                                                 message:@"Automatic updates currently support Apple Silicon only. Would you like to open the TeXForge releases page instead?"
                                           defaultButton:@"Open Releases"
                                         alternateButton:@"Cancel"
                                             otherButton:nil];
            if (response == NSAlertFirstButtonReturn) {
                [self openReleaseURLString:[self releasesPageURLString]];
            }
            return;
        }
        
        self.isCheckingForUpdates = YES;
        [self fetchLatestRelease];
    });
}

- (void)fetchLatestRelease
{
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kTSGitHubLatestReleaseURL]];
    request.HTTPMethod = @"GET";
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:kTSGitHubAPIVersion forHTTPHeaderField:@"X-GitHub-Api-Version"];
    [request setValue:[self userAgent] forHTTPHeaderField:@"User-Agent"];
    
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            [self finishCheckWithErrorMessage:@"There was an error checking for updates."];
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            [self finishCheckWithErrorMessage:@"There was an error checking for updates."];
            return;
        }
        
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        TSGitHubRelease *release = [self releaseFromJSON:json];
        if (release == nil) {
            [self finishCheckWithErrorMessage:@"TeXForge could not understand the latest release information from GitHub."];
            return;
        }
        
        NSString *currentVersion = [self currentVersion];
        if ([release.version compare:currentVersion options:NSNumericSearch] != NSOrderedDescending) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.isCheckingForUpdates = NO;
                [self showInfoAlertWithTitle:@"TeXForge Is Up to Date"
                                     message:@"You already have the most recent version of TeXForge."];
            });
            return;
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.isCheckingForUpdates = NO;
            [self promptToDownloadRelease:release];
        });
    }];
    [task resume];
}

- (void)downloadRelease:(TSGitHubRelease *)release
{
    NSURL *url = [NSURL URLWithString:release.asset.downloadURLString];
    if (url == nil) {
        [self showErrorAndOpenReleaseIfPossible:@"TeXForge could not determine which release asset to download."
                                        release:release];
        return;
    }

    self.isDownloadingUpdate = YES;
    self.currentDownloadRelease = release;

    self.progressController = [[TSUpdateProgressWindowController alloc] init];
    __weak typeof(self) weakSelf = self;
    self.progressController.cancelHandler = ^{
        [weakSelf cancelDownload];
    };
    [self.progressController setStatus:[NSString stringWithFormat:@"Downloading TeXForge %@…", release.version]];
    [self.progressController setIndeterminate:YES];
    [self.progressController setBytesText:@""];
    [self.progressController setCancelEnabled:YES];
    [self.progressController showWindow:nil];
    [self.progressController.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:[self userAgent] forHTTPHeaderField:@"User-Agent"];

    NSURLSessionDownloadTask *task = [self.session downloadTaskWithRequest:request];
    self.currentDownloadTask = task;
    [task resume];
}

- (void)cancelDownload
{
    NSURLSessionDownloadTask *task = self.currentDownloadTask;
    if (task != nil) {
        [task cancel];
    } else {
        [self closeProgressWindowAndResetState];
    }
}

- (void)closeProgressWindowAndResetState
{
    [self.progressController close];
    self.progressController = nil;
    self.currentDownloadTask = nil;
    self.currentDownloadRelease = nil;
    self.isDownloadingUpdate = NO;
}

- (NSString *)formattedBytesWritten:(int64_t)written total:(int64_t)total
{
    NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
    formatter.countStyle = NSByteCountFormatterCountStyleFile;
    if (total > 0) {
        return [NSString stringWithFormat:@"%@ of %@",
                [formatter stringFromByteCount:written],
                [formatter stringFromByteCount:total]];
    }
    return [formatter stringFromByteCount:written];
}

#pragma mark - NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
    if (downloadTask != self.currentDownloadTask) {
        return;
    }

    BOOL hasTotal = (totalBytesExpectedToWrite > 0);
    double fraction = hasTotal ? ((double)totalBytesWritten / (double)totalBytesExpectedToWrite) : 0.0;
    NSString *bytesText = [self formattedBytesWritten:totalBytesWritten total:totalBytesExpectedToWrite];

    dispatch_async(dispatch_get_main_queue(), ^{
        if (hasTotal) {
            [self.progressController setIndeterminate:NO];
            [self.progressController setProgressFraction:fraction];
        }
        [self.progressController setBytesText:bytesText];
    });
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location
{
    if (downloadTask != self.currentDownloadTask) {
        return;
    }

    TSGitHubRelease *release = self.currentDownloadRelease;

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.progressController setStatus:[NSString stringWithFormat:@"Installing TeXForge %@…", release.version]];
        [self.progressController setIndeterminate:YES];
        [self.progressController setBytesText:@""];
        [self.progressController setCancelEnabled:NO];
    });

    NSError *error = nil;
    NSDictionary *stagedInfo = [self stageDownloadedReleaseAtURL:location release:release error:&error];

    dispatch_async(dispatch_get_main_queue(), ^{
        if (stagedInfo == nil) {
            [self closeProgressWindowAndResetState];
            [self showErrorAndOpenReleaseIfPossible:[error localizedDescription] ?: @"TeXForge could not prepare the downloaded update."
                                            release:release];
            return;
        }

        NSError *installError = nil;
        if (![self launchInstallerForStagedInfo:stagedInfo error:&installError]) {
            [self cleanupStagingRootAtPath:stagedInfo[@"stagingRoot"]];
            [self closeProgressWindowAndResetState];
            [self showErrorAndOpenReleaseIfPossible:[installError localizedDescription] ?: @"TeXForge could not start the installer."
                                            release:release];
            return;
        }

        [NSApp terminate:nil];
    });
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error
{
    if (task != self.currentDownloadTask) {
        return;
    }
    if (error == nil) {
        return;
    }

    BOOL wasCancelled = ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled);
    TSGitHubRelease *release = self.currentDownloadRelease;

    dispatch_async(dispatch_get_main_queue(), ^{
        [self closeProgressWindowAndResetState];
        if (!wasCancelled) {
            [self showErrorAndOpenReleaseIfPossible:@"TeXForge could not download the update."
                                            release:release];
        }
    });
}

- (TSGitHubRelease *)releaseFromJSON:(NSDictionary *)json
{
    if (![json isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    
    if ([json[@"draft"] boolValue] || [json[@"prerelease"] boolValue]) {
        return nil;
    }
    
    NSString *tagName = [json[@"tag_name"] isKindOfClass:[NSString class]] ? json[@"tag_name"] : nil;
    NSString *version = [self normalizedVersionFromTag:tagName];
    if (version.length == 0) {
        return nil;
    }
    
    NSArray *assetsJSON = [json[@"assets"] isKindOfClass:[NSArray class]] ? json[@"assets"] : nil;
    TSGitHubReleaseAsset *asset = [self preferredAssetFromJSONArray:assetsJSON];
    if (asset == nil) {
        return nil;
    }
    
    TSGitHubRelease *release = [[TSGitHubRelease alloc] init];
    release.tagName = tagName;
    release.version = version;
    release.releaseURLString = [json[@"html_url"] isKindOfClass:[NSString class]] ? json[@"html_url"] : [self releasesPageURLString];
    release.releaseName = [json[@"name"] isKindOfClass:[NSString class]] ? json[@"name"] : tagName;
    release.releaseBody = [json[@"body"] isKindOfClass:[NSString class]] ? json[@"body"] : @"";
    release.asset = asset;
    return release;
}

- (TSGitHubReleaseAsset *)preferredAssetFromJSONArray:(NSArray *)assetsJSON
{
    NSMutableArray *zipAssets = [NSMutableArray array];
    for (NSDictionary *assetJSON in assetsJSON) {
        if (![assetJSON isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        
        NSString *name = [assetJSON[@"name"] isKindOfClass:[NSString class]] ? assetJSON[@"name"] : nil;
        NSString *downloadURLString = [assetJSON[@"browser_download_url"] isKindOfClass:[NSString class]] ? assetJSON[@"browser_download_url"] : nil;
        if (name.length == 0 || downloadURLString.length == 0) {
            continue;
        }
        
        if (![[name lowercaseString] hasSuffix:@".zip"]) {
            continue;
        }
        
        TSGitHubReleaseAsset *asset = [[TSGitHubReleaseAsset alloc] init];
        asset.name = name;
        asset.downloadURLString = downloadURLString;
        asset.digest = [assetJSON[@"digest"] isKindOfClass:[NSString class]] ? assetJSON[@"digest"] : nil;
        [zipAssets addObject:asset];
    }
    
    for (TSGitHubReleaseAsset *asset in zipAssets) {
        if ([[asset.name lowercaseString] containsString:@"arm64"]) {
            return asset;
        }
    }
    
    if (zipAssets.count == 1) {
        return zipAssets.firstObject;
    }
    
    return zipAssets.firstObject;
}

- (NSString *)normalizedVersionFromTag:(NSString *)tagName
{
    if (tagName.length == 0) {
        return nil;
    }
    if ([[tagName lowercaseString] hasPrefix:@"v"]) {
        return [tagName substringFromIndex:1];
    }
    return tagName;
}

- (NSDictionary *)stageDownloadedReleaseAtURL:(NSURL *)location
                                      release:(TSGitHubRelease *)release
                                        error:(NSError **)error
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *stagingRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    NSString *zipPath = [stagingRoot stringByAppendingPathComponent:release.asset.name ?: @"TeXForge-update.zip"];
    NSString *extractPath = [stagingRoot stringByAppendingPathComponent:@"Extracted"];
    
    if (![fileManager createDirectoryAtPath:stagingRoot withIntermediateDirectories:YES attributes:nil error:error]) {
        return nil;
    }
    
    if (![fileManager moveItemAtPath:[location path] toPath:zipPath error:error]) {
        [fileManager removeItemAtPath:stagingRoot error:nil];
        return nil;
    }
    
    if (release.asset.digest.length > 0) {
        NSString *expectedDigest = [self normalizedSHA256Digest:release.asset.digest];
        NSString *actualDigest = [self SHA256DigestForFileAtPath:zipPath error:error];
        if (expectedDigest.length > 0 && actualDigest.length > 0 && ![expectedDigest isEqualToString:actualDigest]) {
            if (error != NULL) {
                *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                             code:NSFileReadCorruptFileError
                                         userInfo:@{NSLocalizedDescriptionKey: @"The downloaded update did not match the expected checksum."}];
            }
            [fileManager removeItemAtPath:stagingRoot error:nil];
            return nil;
        }
    }
    
    if (![fileManager createDirectoryAtPath:extractPath withIntermediateDirectories:YES attributes:nil error:error]) {
        [fileManager removeItemAtPath:stagingRoot error:nil];
        return nil;
    }
    
    if (![self unzipArchiveAtPath:zipPath toDirectory:extractPath error:error]) {
        [fileManager removeItemAtPath:stagingRoot error:nil];
        return nil;
    }
    
    NSString *stagedAppPath = [self findAppBundleInDirectory:extractPath];
    if (stagedAppPath.length == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:NSFileNoSuchFileError
                                     userInfo:@{NSLocalizedDescriptionKey: @"The downloaded archive did not contain a TeXForge.app bundle."}];
        }
        [fileManager removeItemAtPath:stagingRoot error:nil];
        return nil;
    }
    
    return @{
        @"stagingRoot": stagingRoot,
        @"stagedAppPath": stagedAppPath,
    };
}

- (BOOL)unzipArchiveAtPath:(NSString *)zipPath toDirectory:(NSString *)destinationPath error:(NSError **)error
{
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/ditto";
    task.arguments = @[@"-x", @"-k", zipPath, destinationPath];
    
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    
    @try {
        [task launch];
        [task waitUntilExit];
    }
    @catch (NSException *exception) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:NSExecutableLoadError
                                     userInfo:@{NSLocalizedDescriptionKey: @"TeXForge could not unzip the downloaded update."}];
        }
        return NO;
    }
    
    if ([task terminationStatus] != 0) {
        NSData *outputData = [[pipe fileHandleForReading] readDataToEndOfFile];
        NSString *output = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
        NSString *message = output.length > 0 ? output : @"TeXForge could not unzip the downloaded update.";
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:NSFileReadUnknownError
                                     userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return NO;
    }
    
    return YES;
}

- (NSString *)findAppBundleInDirectory:(NSString *)directoryPath
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDirectoryEnumerator *enumerator = [fileManager enumeratorAtPath:directoryPath];
    NSString *relativePath = nil;
    while ((relativePath = [enumerator nextObject])) {
        if ([[relativePath pathExtension] isEqualToString:@"app"]) {
            return [directoryPath stringByAppendingPathComponent:relativePath];
        }
    }
    return nil;
}

- (void)promptToDownloadRelease:(TSGitHubRelease *)release
{
    NSString *message = [NSString stringWithFormat:@"TeXForge %@ is available. Would you like to download it now?", release.version];
    NSInteger response = [self runAlertWithTitle:@"Update Available"
                                         message:message
                                   defaultButton:@"Download Update"
                                 alternateButton:@"Later"
                                     otherButton:@"View Release"];
    if (response == NSAlertThirdButtonReturn) {
        [self openReleaseURLString:release.releaseURLString];
        return;
    }
    if (response != NSAlertFirstButtonReturn) {
        return;
    }

    if (![self currentInstallationIsWritable]) {
        [self promptForFallbackOpenWithMessage:@"TeXForge can only self-install updates when its current location is writable."
                                       release:release];
        return;
    }
    
    [self downloadRelease:release];
}

- (BOOL)launchInstallerForStagedInfo:(NSDictionary *)stagedInfo error:(NSError **)error
{
    NSString *stagingRoot = stagedInfo[@"stagingRoot"];
    NSString *stagedAppPath = stagedInfo[@"stagedAppPath"];
    NSString *targetAppPath = [[[NSBundle mainBundle] bundlePath] stringByResolvingSymlinksInPath];
    if (stagingRoot.length == 0 || stagedAppPath.length == 0 || targetAppPath.length == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:NSFileNoSuchFileError
                                     userInfo:@{NSLocalizedDescriptionKey: @"TeXForge could not determine where to install the downloaded update."}];
        }
        return NO;
    }
    
    NSString *scriptPath = [stagingRoot stringByAppendingPathComponent:@"install-update.sh"];
    NSString *script = @"#!/bin/sh\n"
    "PID=\"$1\"\n"
    "STAGED_APP=\"$2\"\n"
    "TARGET_APP=\"$3\"\n"
    "STAGING_ROOT=\"$4\"\n"
    "BACKUP_APP=\"${TARGET_APP}.old.$$\"\n"
    "ATTEMPTS=0\n"
    "\n"
    "while kill -0 \"$PID\" 2>/dev/null; do\n"
    "  sleep 1\n"
    "  ATTEMPTS=$((ATTEMPTS + 1))\n"
    "  if [ \"$ATTEMPTS\" -ge 120 ]; then\n"
    "    exit 1\n"
    "  fi\n"
    "done\n"
    "\n"
    "rm -rf \"$BACKUP_APP\"\n"
    "if [ -e \"$TARGET_APP\" ]; then\n"
    "  mv \"$TARGET_APP\" \"$BACKUP_APP\" || exit 1\n"
    "fi\n"
    "\n"
    "xattr -dr com.apple.quarantine \"$STAGED_APP\" 2>/dev/null || true\n"
    "xattr -dr com.apple.provenance \"$STAGED_APP\" 2>/dev/null || true\n"
    "\n"
    "if ! ditto \"$STAGED_APP\" \"$TARGET_APP\"; then\n"
    "  rm -rf \"$TARGET_APP\"\n"
    "  if [ -e \"$BACKUP_APP\" ]; then\n"
    "    mv \"$BACKUP_APP\" \"$TARGET_APP\"\n"
    "    open \"$TARGET_APP\" 2>/dev/null || true\n"
    "  fi\n"
    "  exit 1\n"
    "fi\n"
    "\n"
    "xattr -dr com.apple.quarantine \"$TARGET_APP\" 2>/dev/null || true\n"
    "xattr -dr com.apple.provenance \"$TARGET_APP\" 2>/dev/null || true\n"
    "rm -rf \"$BACKUP_APP\"\n"
    "open \"$TARGET_APP\"\n"
    "rm -rf \"$STAGING_ROOT\"\n"
    "rm -f \"$0\"\n";
    
    if (![script writeToFile:scriptPath atomically:YES encoding:NSUTF8StringEncoding error:error]) {
        return NO;
    }
    
    NSDictionary *attributes = @{NSFilePosixPermissions: @0700};
    [[NSFileManager defaultManager] setAttributes:attributes ofItemAtPath:scriptPath error:nil];
    
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/bin/sh";
    task.arguments = @[
        scriptPath,
        [NSString stringWithFormat:@"%d", [[NSProcessInfo processInfo] processIdentifier]],
        stagedAppPath,
        targetAppPath,
        stagingRoot,
    ];
    
    @try {
        [task launch];
    }
    @catch (NSException *exception) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:NSExecutableLoadError
                                     userInfo:@{NSLocalizedDescriptionKey: @"TeXForge could not start the installer process."}];
        }
        return NO;
    }
    
    return YES;
}

- (BOOL)currentInstallationIsWritable
{
    NSString *bundlePath = [[[NSBundle mainBundle] bundlePath] stringByResolvingSymlinksInPath];
    NSString *parentDirectory = [bundlePath stringByDeletingLastPathComponent];
    if (![[bundlePath pathExtension] isEqualToString:@"app"]) {
        return NO;
    }
    return [[NSFileManager defaultManager] isWritableFileAtPath:parentDirectory];
}

- (NSString *)SHA256DigestForFileAtPath:(NSString *)path error:(NSError **)error
{
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (fileHandle == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:NSFileReadNoSuchFileError
                                     userInfo:@{NSLocalizedDescriptionKey: @"TeXForge could not read the downloaded update."}];
        }
        return nil;
    }
    
    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    
    @try {
        while (YES) {
            NSData *data = [fileHandle readDataOfLength:64 * 1024];
            if (data.length == 0) {
                break;
            }
            CC_SHA256_Update(&context, [data bytes], (CC_LONG)[data length]);
        }
    }
    @catch (NSException *exception) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:NSFileReadUnknownError
                                     userInfo:@{NSLocalizedDescriptionKey: @"TeXForge could not verify the downloaded update."}];
        }
        return nil;
    }
    @finally {
        [fileHandle closeFile];
    }
    
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);
    
    NSMutableString *result = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
        [result appendFormat:@"%02x", digest[index]];
    }
    return result;
}

- (NSString *)normalizedSHA256Digest:(NSString *)digest
{
    if (digest.length == 0) {
        return nil;
    }
    if ([[digest lowercaseString] hasPrefix:@"sha256:"]) {
        return [[digest substringFromIndex:7] lowercaseString];
    }
    return [digest lowercaseString];
}

- (void)finishCheckWithErrorMessage:(NSString *)message
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.isCheckingForUpdates = NO;
        [self showInfoAlertWithTitle:@"Update Check Failed" message:message];
    });
}

- (void)showErrorAndOpenReleaseIfPossible:(NSString *)message release:(TSGitHubRelease *)release
{
    NSInteger response = [self runAlertWithTitle:@"Update Failed"
                                         message:message
                                   defaultButton:@"Open Release Page"
                                 alternateButton:@"OK"
                                     otherButton:nil];
    if (response == NSAlertFirstButtonReturn) {
        [self openReleaseURLString:release.releaseURLString ?: [self releasesPageURLString]];
    }
}

- (void)promptForFallbackOpenWithMessage:(NSString *)message release:(TSGitHubRelease *)release
{
    NSInteger response = [self runAlertWithTitle:@"Open Release Page Instead?"
                                         message:message
                                   defaultButton:@"Open Release Page"
                                 alternateButton:@"Cancel"
                                     otherButton:nil];
    if (response == NSAlertFirstButtonReturn) {
        [self openReleaseURLString:release.releaseURLString];
    }
}

- (void)showInfoAlertWithTitle:(NSString *)title message:(NSString *)message
{
    [self runAlertWithTitle:title
                    message:message
              defaultButton:@"OK"
            alternateButton:nil
                otherButton:nil];
}

- (NSInteger)runAlertWithTitle:(NSString *)title
                       message:(NSString *)message
                 defaultButton:(NSString *)defaultButton
               alternateButton:(NSString *)alternateButton
                   otherButton:(NSString *)otherButton
{
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:title ?: @""];
    [alert setInformativeText:message ?: @""];
    if (defaultButton.length > 0) {
        [alert addButtonWithTitle:defaultButton];
    }
    if (alternateButton.length > 0) {
        [alert addButtonWithTitle:alternateButton];
    }
    if (otherButton.length > 0) {
        [alert addButtonWithTitle:otherButton];
    }
    return [alert runModal];
}

- (void)openReleaseURLString:(NSString *)releaseURLString
{
    NSURL *url = [NSURL URLWithString:releaseURLString ?: [self releasesPageURLString]];
    if (url != nil) {
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
}

- (void)cleanupStagingRootAtPath:(NSString *)stagingRoot
{
    if (stagingRoot.length == 0) {
        return;
    }
    [[NSFileManager defaultManager] removeItemAtPath:stagingRoot error:nil];
}

- (BOOL)isAppleSiliconHost
{
    int arm64 = 0;
    size_t size = sizeof(arm64);
    if (sysctlbyname("hw.optional.arm64", &arm64, &size, NULL, 0) != 0) {
        return NO;
    }
    return (arm64 == 1);
}

- (NSString *)currentVersion
{
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    NSString *version = infoDictionary[@"CFBundleShortVersionString"];
    if (version.length == 0) {
        version = infoDictionary[@"CFBundleVersion"];
    }
    return version ?: @"0";
}

- (NSString *)userAgent
{
    return [NSString stringWithFormat:@"TeXForge/%@", [self currentVersion]];
}

- (NSString *)releasesPageURLString
{
    return [NSString stringWithFormat:@"https://github.com/%@/%@/releases", kTSGitHubOwner, kTSGitHubRepo];
}

@end
