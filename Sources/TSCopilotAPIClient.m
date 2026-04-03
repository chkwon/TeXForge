/*
 * TSCopilotAPIClient.m
 * TeXForge - Copilot inline completion
 */

#import <Cocoa/Cocoa.h>
#import "TSCopilotAPIClient.h"
#import "TSCopilotPreferences.h"

static NSString * const kGitHubClientID = @"Iv1.b507a08c87ecfe98";
static NSString * const kKeychainGitHubToken = @"com.TeXForge.Copilot.github-oauth";
static NSString * const kKeychainCopilotToken = @"com.TeXForge.Copilot.github-copilot-session";
static NSString * const kCopilotTokenExpiryKey = @"CopilotGitHubTokenExpiry";

@implementation TSCopilotAPIClient {
    NSURLSession *_session;
    NSString *_cachedCopilotToken;
    NSTimeInterval _cachedTokenExpiry;
}

+ (instancetype)sharedClient
{
    static TSCopilotAPIClient *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[TSCopilotAPIClient alloc] init];
    });
    return instance;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 10.0;
        config.timeoutIntervalForResource = 15.0;
        _session = [NSURLSession sessionWithConfiguration:config];
    }
    return self;
}

#pragma mark - Public

- (NSURLSessionDataTask *)requestCompletionWithPrefix:(NSString *)prefix
                                               suffix:(NSString *)suffix
                                             fileName:(NSString *)fileName
                                           completion:(TSCopilotCompletionBlock)completion
{
    NSString *provider = [TSCopilotPreferences provider];
    if ([provider isEqualToString:@"claude"]) {
        return [self _requestClaudeWithPrefix:prefix suffix:suffix fileName:fileName completion:completion];
    } else if ([provider isEqualToString:@"github-copilot"]) {
        return [self _requestGitHubCopilotWithPrefix:prefix suffix:suffix fileName:fileName completion:completion];
    } else {
        return [self _requestOllamaWithPrefix:prefix suffix:suffix fileName:fileName completion:completion];
    }
}

#pragma mark - Ollama

- (NSURLSessionDataTask *)_requestOllamaWithPrefix:(NSString *)prefix
                                            suffix:(NSString *)suffix
                                          fileName:(NSString *)fileName
                                        completion:(TSCopilotCompletionBlock)completion
{
    NSString *baseURL = [TSCopilotPreferences endpoint];
    NSString *urlString = [baseURL stringByAppendingString:@"/api/generate"];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        [self _callCompletion:completion withSuggestion:nil error:[self _errorWithMessage:@"Invalid Ollama endpoint URL"]];
        return nil;
    }

    NSString *model = [TSCopilotPreferences model];
    NSString *systemPrompt = [TSCopilotPreferences systemPrompt];
    NSString *prompt = [self _buildPromptWithPrefix:prefix suffix:suffix fileName:fileName];

    NSDictionary *body = @{
        @"model": model ?: @"qwen2.5-coder",
        @"prompt": prompt,
        @"system": systemPrompt,
        @"stream": @NO,
        @"options": @{
            @"num_predict": @([TSCopilotPreferences maxTokens]),
            @"temperature": @0.2,
            @"stop": @[@"\n\n\n", @"```"],
        },
    };

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    NSURLSessionDataTask *task = [_session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            [self _callCompletion:completion withSuggestion:nil error:error];
            return;
        }
        NSString *suggestion = [self _parseOllamaResponse:data];
        [self _callCompletion:completion withSuggestion:suggestion error:nil];
    }];
    [task resume];
    return task;
}

- (NSString *)_parseOllamaResponse:(NSData *)data
{
    if (!data) return nil;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSString *response = json[@"response"];
    if ([response isKindOfClass:[NSString class]] && response.length > 0) {
        return [self _cleanSuggestion:response];
    }
    return nil;
}

#pragma mark - Claude API

- (NSURLSessionDataTask *)_requestClaudeWithPrefix:(NSString *)prefix
                                            suffix:(NSString *)suffix
                                          fileName:(NSString *)fileName
                                        completion:(TSCopilotCompletionBlock)completion
{
    NSString *apiKey = [TSCopilotPreferences apiKeyForProvider:@"claude"];
    if (apiKey.length == 0) {
        [self _callCompletion:completion withSuggestion:nil
                        error:[self _errorWithMessage:@"No Claude API key configured. Open Copilot Settings to add one."]];
        return nil;
    }

    NSURL *url = [NSURL URLWithString:@"https://api.anthropic.com/v1/messages"];
    NSString *model = [TSCopilotPreferences model];
    if (![model hasPrefix:@"claude"]) {
        model = @"claude-sonnet-4-20250514";
    }

    NSString *systemPrompt = [TSCopilotPreferences systemPrompt];
    NSString *userContent = [self _buildPromptWithPrefix:prefix suffix:suffix fileName:fileName];

    NSDictionary *body = @{
        @"model": model,
        @"max_tokens": @([TSCopilotPreferences maxTokens]),
        @"system": systemPrompt,
        @"messages": @[
            @{@"role": @"user", @"content": userContent},
        ],
        @"temperature": @0.2,
    };

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:apiKey forHTTPHeaderField:@"x-api-key"];
    [request setValue:@"2023-06-01" forHTTPHeaderField:@"anthropic-version"];
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    NSURLSessionDataTask *task = [_session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            [self _callCompletion:completion withSuggestion:nil error:error];
            return;
        }
        NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
        if (httpResp.statusCode != 200) {
            NSString *msg = [NSString stringWithFormat:@"Claude API returned status %ld", (long)httpResp.statusCode];
            [self _callCompletion:completion withSuggestion:nil error:[self _errorWithMessage:msg]];
            return;
        }
        NSString *suggestion = [self _parseClaudeResponse:data];
        [self _callCompletion:completion withSuggestion:suggestion error:nil];
    }];
    [task resume];
    return task;
}

- (NSString *)_parseClaudeResponse:(NSData *)data
{
    if (!data) return nil;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSArray *content = json[@"content"];
    if ([content isKindOfClass:[NSArray class]] && content.count > 0) {
        NSDictionary *block = content[0];
        if ([block[@"type"] isEqualToString:@"text"]) {
            NSString *text = block[@"text"];
            if ([text isKindOfClass:[NSString class]] && text.length > 0) {
                return [self _cleanSuggestion:text];
            }
        }
    }
    return nil;
}

#pragma mark - GitHub Copilot

- (NSURLSessionDataTask *)_requestGitHubCopilotWithPrefix:(NSString *)prefix
                                                   suffix:(NSString *)suffix
                                                 fileName:(NSString *)fileName
                                               completion:(TSCopilotCompletionBlock)completion
{
    // Get cached token (fast, no blocking)
    NSString *copilotToken = [self _cachedCopilotSessionToken];
    if (copilotToken) {
        return [self _sendGitHubCopilotRequestWithToken:copilotToken
                                                 prefix:prefix suffix:suffix
                                               fileName:fileName completion:completion];
    }

    // Need async token exchange — fire completion request when ready
    NSLog(@"[Copilot] No cached token, starting async token exchange...");
    [self _refreshCopilotSessionTokenAsync:^(NSString *token) {
        if (!token) {
            NSLog(@"[Copilot] Async token exchange failed — no token");
            [self _callCompletion:completion withSuggestion:nil
                            error:[self _errorWithMessage:@"Not signed in to GitHub Copilot. Open Copilot Settings to sign in."]];
            return;
        }
        // Token ready — send the completion request (task not trackable for cancellation,
        // but the generation counter in the manager handles stale responses)
        [self _sendGitHubCopilotRequestWithToken:token
                                          prefix:prefix suffix:suffix
                                        fileName:fileName completion:completion];
    }];
    return nil; // Task not available yet; stale detection via generation counter
}

- (NSURLSessionDataTask *)_sendGitHubCopilotRequestWithToken:(NSString *)copilotToken
                                                      prefix:(NSString *)prefix
                                                      suffix:(NSString *)suffix
                                                    fileName:(NSString *)fileName
                                                  completion:(TSCopilotCompletionBlock)completion
{
    NSURL *url = [NSURL URLWithString:@"https://copilot-proxy.githubusercontent.com/v1/engines/copilot-codex/completions"];
    NSString *promptPrefix = prefix ?: @"";
    if (fileName.length > 0) {
        promptPrefix = [NSString stringWithFormat:@"// File: %@\n%@", fileName, promptPrefix];
    }

    NSDictionary *body = @{
        @"prompt": promptPrefix,
        @"suffix": suffix ?: @"",
        @"max_tokens": @([TSCopilotPreferences maxTokens]),
        @"temperature": @0.2,
        @"n": @1,
        @"stop": @[@"\n\n\n"],
        @"stream": @YES,
    };

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", copilotToken] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"github-copilot" forHTTPHeaderField:@"Openai-Organization"];
    [request setValue:@"copilot-ghost" forHTTPHeaderField:@"Openai-Intent"];
    [request setValue:@"vscode/1.85.0" forHTTPHeaderField:@"Editor-Version"];
    [request setValue:@"copilot/1.100.0" forHTTPHeaderField:@"Editor-Plugin-Version"];
    [request setValue:@"GithubCopilot/1.100.0" forHTTPHeaderField:@"User-Agent"];
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    NSURLSessionDataTask *task = [_session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            if (error.code != NSURLErrorCancelled) {
                NSLog(@"[Copilot] GitHub Copilot request error: %@", error.localizedDescription);
            }
            [self _callCompletion:completion withSuggestion:nil error:error];
            return;
        }
        NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
        if (httpResp.statusCode == 401) {
            NSLog(@"[Copilot] GitHub Copilot token expired (401)");
            self->_cachedCopilotToken = nil;
            self->_cachedTokenExpiry = 0;
            [TSCopilotAPIClient _setKeychainValue:nil forService:kKeychainCopilotToken];
            [self _callCompletion:completion withSuggestion:nil
                            error:[self _errorWithMessage:@"GitHub Copilot token expired. Please sign in again."]];
            return;
        }
        if (httpResp.statusCode != 200) {
            NSString *respBody = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"(no body)";
            NSLog(@"[Copilot] GitHub Copilot returned status %ld", (long)httpResp.statusCode);
            NSString *msg = [NSString stringWithFormat:@"GitHub Copilot returned status %ld", (long)httpResp.statusCode];
            [self _callCompletion:completion withSuggestion:nil error:[self _errorWithMessage:msg]];
            return;
        }
        NSString *suggestion = [self _parseGitHubCopilotResponse:data];
        NSLog(@"[Copilot] GitHub Copilot response (status 200), suggestion length: %lu", (unsigned long)suggestion.length);
        [self _callCompletion:completion withSuggestion:suggestion error:nil];
    }];
    [task resume];
    return task;
}

/// Parse SSE (Server-Sent Events) streaming response. Each chunk is a "data: {json}\n" line.
- (NSString *)_parseGitHubCopilotResponse:(NSData *)data
{
    if (!data) return nil;
    NSString *raw = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!raw) return nil;

    NSMutableString *result = [NSMutableString string];
    NSArray *lines = [raw componentsSeparatedByString:@"\n"];

    for (NSString *line in lines) {
        if (![line hasPrefix:@"data: "]) continue;
        NSString *payload = [line substringFromIndex:6];
        if ([payload isEqualToString:@"[DONE]"]) break;

        NSData *jsonData = [payload dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
        NSArray *choices = json[@"choices"];
        if ([choices isKindOfClass:[NSArray class]] && choices.count > 0) {
            NSString *text = choices[0][@"text"];
            if ([text isKindOfClass:[NSString class]]) {
                [result appendString:text];
            }
        }
    }

    if (result.length == 0) return nil;
    return [self _cleanSuggestion:result];
}

/// Return cached Copilot session token if still valid (no blocking, no Keychain access).
- (NSString *)_cachedCopilotSessionToken
{
    if (_cachedCopilotToken && [[NSDate date] timeIntervalSince1970] < _cachedTokenExpiry - 60) {
        return _cachedCopilotToken;
    }
    // Check Keychain (fast, no network)
    NSTimeInterval expiry = [[NSUserDefaults standardUserDefaults] doubleForKey:kCopilotTokenExpiryKey];
    if (expiry > 0 && [[NSDate date] timeIntervalSince1970] < expiry - 60) {
        NSString *token = [TSCopilotAPIClient _keychainValueForService:kKeychainCopilotToken];
        if (token) {
            _cachedCopilotToken = token;
            _cachedTokenExpiry = expiry;
            return token;
        }
    }
    return nil;
}

/// Async token exchange — does NOT block the main thread.
- (void)_refreshCopilotSessionTokenAsync:(void (^)(NSString *token))completion
{
    NSString *githubToken = [TSCopilotAPIClient _keychainValueForService:kKeychainGitHubToken];
    if (!githubToken) {
        NSLog(@"[Copilot] No GitHub OAuth token in Keychain — sign-in may not have completed");
        completion(nil);
        return;
    }
    NSLog(@"[Copilot] Exchanging GitHub OAuth token for Copilot session token (async)...");

    NSURL *url = [NSURL URLWithString:@"https://api.github.com/copilot_internal/v2/token"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:[NSString stringWithFormat:@"token %@", githubToken] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    request.timeoutInterval = 5.0;

    [[_session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"[Copilot] Token exchange network error: %@", error.localizedDescription);
            completion(nil);
            return;
        }
        NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
        NSLog(@"[Copilot] Token exchange HTTP status: %ld", (long)httpResp.statusCode);

        if (!data) {
            completion(nil);
            return;
        }
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *token = json[@"token"];
        NSNumber *expiresAt = json[@"expires_at"];
        if ([token isKindOfClass:[NSString class]] && token.length > 0) {
            NSLog(@"[Copilot] Token exchange succeeded, expires_at: %@", expiresAt);
            self->_cachedCopilotToken = token;
            if ([expiresAt isKindOfClass:[NSNumber class]]) {
                self->_cachedTokenExpiry = expiresAt.doubleValue;
                [[NSUserDefaults standardUserDefaults] setDouble:expiresAt.doubleValue forKey:kCopilotTokenExpiryKey];
            }
            [TSCopilotAPIClient _setKeychainValue:token forService:kKeychainCopilotToken];
            completion(token);
        } else {
            NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSLog(@"[Copilot] Token exchange failed, response: %@", body);
            completion(nil);
        }
    }] resume];
}

#pragma mark - GitHub OAuth Device Flow

- (void)startGitHubCopilotSignIn:(void (^)(BOOL success, NSError *error))completion
{
    NSURL *url = [NSURL URLWithString:@"https://github.com/login/device/code"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    NSDictionary *body = @{@"client_id": kGitHubClientID, @"scope": @"user:email"};
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    [[_session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, error ?: [self _errorWithMessage:@"Failed to start GitHub device flow"]);
            });
            return;
        }
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *deviceCode = json[@"device_code"];
        NSString *userCode = json[@"user_code"];
        NSString *verificationURI = json[@"verification_uri"];
        NSNumber *interval = json[@"interval"] ?: @5;

        if (!deviceCode || !userCode || !verificationURI) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, [self _errorWithMessage:@"Invalid response from GitHub device flow"]);
            });
            return;
        }

        // Open browser and show the user code
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:verificationURI]];
            // Copy user code to clipboard
            [[NSPasteboard generalPasteboard] clearContents];
            [[NSPasteboard generalPasteboard] setString:userCode forType:NSPasteboardTypeString];

            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Enter this code on GitHub";
            alert.informativeText = [NSString stringWithFormat:
                @"Code: %@\n\nThe code has been copied to your clipboard.\n"
                @"A browser window has opened. Paste the code there to authorize TeXForge.\n\n"
                @"Waiting for authorization...", userCode];
            alert.alertStyle = NSAlertStyleInformational;
            [alert addButtonWithTitle:@"Cancel"];

            // Poll in background; use stopModal to unblock runModal when done
            __block BOOL cancelled = NO;
            __block BOOL pollSuccess = NO;
            __block NSError *pollErr = nil;

            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [self _pollForGitHubToken:deviceCode interval:interval.integerValue cancelled:&cancelled completion:^(BOOL success, NSError *error) {
                    pollSuccess = success;
                    pollErr = error;
                    // stopModal can be called from any thread — unblocks runModal
                    [NSApp performSelectorOnMainThread:@selector(stopModal) withObject:nil waitUntilDone:NO];
                }];
            });

            NSModalResponse resp = [alert runModal];
            if (resp == NSAlertFirstButtonReturn) {
                // User clicked Cancel
                cancelled = YES;
                completion(NO, nil);
            } else {
                // Polling completed (stopModal was called)
                completion(pollSuccess, pollErr);
            }
        });
    }] resume];
}

- (void)_pollForGitHubToken:(NSString *)deviceCode
                   interval:(NSInteger)interval
                  cancelled:(BOOL *)cancelled
                 completion:(void (^)(BOOL success, NSError *error))completion
{
    NSURL *url = [NSURL URLWithString:@"https://github.com/login/oauth/access_token"];

    for (int attempt = 0; attempt < 60 && !*cancelled; attempt++) {
        [NSThread sleepForTimeInterval:MAX(interval, 5)];
        if (*cancelled) break;

        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        request.HTTPMethod = @"POST";
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

        NSDictionary *body = @{
            @"client_id": kGitHubClientID,
            @"device_code": deviceCode,
            @"grant_type": @"urn:ietf:params:oauth:grant-type:device_code",
        };
        request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        __block NSDictionary *responseJSON = nil;

        [[_session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (data) {
                responseJSON = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            }
            dispatch_semaphore_signal(sem);
        }] resume];

        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));

        NSString *accessToken = responseJSON[@"access_token"];
        NSString *errorStr = responseJSON[@"error"];

        if (accessToken && [accessToken isKindOfClass:[NSString class]]) {
            // Success! Store the GitHub OAuth token
            [TSCopilotAPIClient _setKeychainValue:accessToken forService:kKeychainGitHubToken];
            completion(YES, nil);
            return;
        }

        if ([errorStr isEqualToString:@"authorization_pending"]) {
            continue; // User hasn't authorized yet
        } else if ([errorStr isEqualToString:@"slow_down"]) {
            interval += 5; // Back off
            continue;
        } else if ([errorStr isEqualToString:@"expired_token"]) {
            completion(NO, [self _errorWithMessage:@"Device code expired. Please try again."]);
            return;
        } else if ([errorStr isEqualToString:@"access_denied"]) {
            completion(NO, [self _errorWithMessage:@"Authorization denied."]);
            return;
        }
    }

    if (!*cancelled) {
        completion(NO, [self _errorWithMessage:@"Timed out waiting for GitHub authorization."]);
    }
}

+ (BOOL)hasValidGitHubCopilotToken
{
    return [self _keychainValueForService:kKeychainGitHubToken] != nil;
}

+ (void)signOutGitHubCopilot
{
    [self _setKeychainValue:nil forService:kKeychainGitHubToken];
    [self _setKeychainValue:nil forService:kKeychainCopilotToken];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kCopilotTokenExpiryKey];
    TSCopilotAPIClient *client = [self sharedClient];
    client->_cachedCopilotToken = nil;
    client->_cachedTokenExpiry = 0;
}

#pragma mark - Credential File Helpers (GitHub tokens)

+ (NSString *)_keychainValueForService:(NSString *)service
{
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/TeXForge/.copilot_credentials.plist"];
    NSDictionary *creds = [NSDictionary dictionaryWithContentsOfFile:path];
    return creds[service];
}

+ (void)_setKeychainValue:(NSString *)value forService:(NSString *)service
{
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/TeXForge/.copilot_credentials.plist"];
    NSString *dir = [path stringByDeletingLastPathComponent];
    NSFileManager *fm = [NSFileManager defaultManager];

    if (![fm fileExistsAtPath:dir]) {
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }

    NSMutableDictionary *creds = [NSDictionary dictionaryWithContentsOfFile:path].mutableCopy;
    if (!creds) creds = [NSMutableDictionary dictionary];

    if (value.length > 0) {
        creds[service] = value;
    } else {
        [creds removeObjectForKey:service];
    }

    if ([creds writeToFile:path atomically:YES]) {
        [fm setAttributes:@{NSFilePosixPermissions: @0600} ofItemAtPath:path error:nil];
    }
}

#pragma mark - Prompt Construction

- (NSString *)_buildPromptWithPrefix:(NSString *)prefix
                              suffix:(NSString *)suffix
                            fileName:(NSString *)fileName
{
    NSMutableString *prompt = [NSMutableString string];
    if (fileName.length > 0) {
        [prompt appendFormat:@"File: %@\n\n", fileName];
    }
    [prompt appendString:prefix ?: @""];
    [prompt appendString:@"<|cursor|>"];
    [prompt appendString:suffix ?: @""];
    return prompt;
}

#pragma mark - Helpers

- (NSString *)_cleanSuggestion:(NSString *)raw
{
    // Trim leading/trailing whitespace only if the suggestion is a single line
    NSString *trimmed = raw;

    // Remove markdown code fences if the model wrapped the response
    if ([trimmed hasPrefix:@"```"]) {
        NSRange firstNewline = [trimmed rangeOfString:@"\n"];
        if (firstNewline.location != NSNotFound) {
            trimmed = [trimmed substringFromIndex:firstNewline.location + 1];
        }
        if ([trimmed hasSuffix:@"```"]) {
            trimmed = [trimmed substringToIndex:trimmed.length - 3];
        }
        trimmed = [trimmed stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    }

    // Don't return empty suggestions
    if (trimmed.length == 0) return nil;

    return trimmed;
}

- (void)_callCompletion:(TSCopilotCompletionBlock)completion
         withSuggestion:(NSString *)suggestion
                  error:(NSError *)error
{
    if (!completion) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(suggestion, error);
    });
}

- (NSError *)_errorWithMessage:(NSString *)message
{
    return [NSError errorWithDomain:@"TSCopilot" code:-1
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

@end
