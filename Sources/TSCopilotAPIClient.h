/*
 * TSCopilotAPIClient.h
 * TeXForge - Copilot inline completion
 *
 * HTTP client for LLM completions. Supports Claude API, local Ollama,
 * and GitHub Copilot (via OAuth device flow).
 */

#import <Foundation/Foundation.h>

typedef void (^TSCopilotCompletionBlock)(NSString * _Nullable suggestion, NSError * _Nullable error);

@interface TSCopilotAPIClient : NSObject

+ (instancetype)sharedClient;

/// Request a completion. Returns the data task (can be cancelled).
- (NSURLSessionDataTask *)requestCompletionWithPrefix:(NSString *)prefix
                                               suffix:(NSString *)suffix
                                             fileName:(NSString *)fileName
                                           completion:(TSCopilotCompletionBlock)completion;

/// Start GitHub Copilot OAuth device flow. Opens browser for user authorization.
/// Calls completion with YES on success, NO + error on failure.
- (void)startGitHubCopilotSignIn:(void (^)(BOOL success, NSError * _Nullable error))completion;

/// Whether we have a valid (non-expired) GitHub Copilot token.
+ (BOOL)hasValidGitHubCopilotToken;

/// Sign out of GitHub Copilot (delete stored tokens).
+ (void)signOutGitHubCopilot;

@end
