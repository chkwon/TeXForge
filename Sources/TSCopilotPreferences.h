/*
 * TSCopilotPreferences.h
 * TeXShop - Copilot inline completion
 *
 * Preference keys and Keychain helpers for the Copilot feature.
 * Self-contained: registers its own defaults in +load.
 */

#import <Foundation/Foundation.h>

// --- Notification posted when Copilot preferences change ---
extern NSString * const TSCopilotPreferencesDidChangeNotification;

// --- Connection status ---
typedef NS_ENUM(NSInteger, TSCopilotConnectionStatus) {
    TSCopilotConnectionStatusDisabled = 0,
    TSCopilotConnectionStatusNotConfigured = 1,
    TSCopilotConnectionStatusReady = 2,
};

// --- Preference Keys (stored in NSUserDefaults) ---
extern NSString * const TSCopilotEnabledKey;       // BOOL, default NO
extern NSString * const TSCopilotProviderKey;       // NSString: "ollama", "claude", or "github-copilot"
extern NSString * const TSCopilotEndpointKey;       // NSString: API base URL
extern NSString * const TSCopilotModelKey;          // NSString: model name
extern NSString * const TSCopilotDebounceMsKey;     // NSInteger: debounce in ms
extern NSString * const TSCopilotMaxTokensKey;      // NSInteger: max tokens per completion
extern NSString * const TSCopilotGhostAlphaKey;     // float: ghost text opacity (0.0-1.0)
extern NSString * const TSCopilotSystemPromptKey;   // NSString: custom system prompt (optional)

@interface TSCopilotPreferences : NSObject

// --- Convenience readers ---
+ (BOOL)isEnabled;
+ (NSString *)provider;
+ (NSString *)endpoint;
+ (NSString *)model;
+ (NSInteger)debounceMs;
+ (NSInteger)maxTokens;
+ (CGFloat)ghostAlpha;
+ (NSString *)systemPrompt;

// --- Keychain API key management ---
+ (NSString *)apiKeyForProvider:(NSString *)provider;
+ (BOOL)setApiKey:(NSString *)key forProvider:(NSString *)provider;
+ (BOOL)deleteApiKeyForProvider:(NSString *)provider;

// --- Connection status ---
+ (TSCopilotConnectionStatus)connectionStatus;

// --- Settings panel ---
+ (void)showSettingsPanel;

@end
