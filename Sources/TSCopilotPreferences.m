/*
 * TSCopilotPreferences.m
 * TeXShop - Copilot inline completion
 */

#import <Cocoa/Cocoa.h>
#import "TSCopilotPreferences.h"
#import "TSCopilotAPIClient.h"

// --- Preference Keys ---
NSString * const TSCopilotEnabledKey     = @"CopilotEnabled";
NSString * const TSCopilotProviderKey    = @"CopilotProvider";
NSString * const TSCopilotEndpointKey    = @"CopilotEndpoint";
NSString * const TSCopilotModelKey       = @"CopilotModel";
NSString * const TSCopilotDebounceMsKey  = @"CopilotDebounceMs";
NSString * const TSCopilotMaxTokensKey   = @"CopilotMaxTokens";
NSString * const TSCopilotGhostAlphaKey  = @"CopilotGhostAlpha";
NSString * const TSCopilotSystemPromptKey = @"CopilotSystemPrompt";

static NSString * const kCredentialServicePrefix = @"com.TeXForge.Copilot.";

#define SUD [NSUserDefaults standardUserDefaults]

@implementation TSCopilotPreferences

#pragma mark - Auto-register defaults

+ (void)load
{
    NSDictionary *defaults = @{
        TSCopilotEnabledKey:     @NO,
        TSCopilotProviderKey:    @"ollama",
        TSCopilotEndpointKey:    @"http://localhost:11434",
        TSCopilotModelKey:       @"qwen2.5-coder",
        TSCopilotDebounceMsKey:  @500,
        TSCopilotMaxTokensKey:   @128,
        TSCopilotGhostAlphaKey:  @0.4,
        TSCopilotSystemPromptKey: @"",
    };
    [SUD registerDefaults:defaults];
}

#pragma mark - Convenience readers

+ (BOOL)isEnabled
{
    return [SUD boolForKey:TSCopilotEnabledKey];
}

+ (NSString *)provider
{
    return [SUD stringForKey:TSCopilotProviderKey];
}

+ (NSString *)endpoint
{
    return [SUD stringForKey:TSCopilotEndpointKey];
}

+ (NSString *)model
{
    return [SUD stringForKey:TSCopilotModelKey];
}

+ (NSInteger)debounceMs
{
    return [SUD integerForKey:TSCopilotDebounceMsKey];
}

+ (NSInteger)maxTokens
{
    return [SUD integerForKey:TSCopilotMaxTokensKey];
}

+ (CGFloat)ghostAlpha
{
    return [SUD floatForKey:TSCopilotGhostAlphaKey];
}

+ (NSString *)systemPrompt
{
    NSString *custom = [SUD stringForKey:TSCopilotSystemPromptKey];
    if (custom.length > 0) return custom;
    return @"You are a LaTeX code completion assistant. "
           @"Given the document context with the cursor position marked by <|cursor|>, "
           @"predict what the user wants to type next. "
           @"Return ONLY the completion text, with no explanation, no markdown formatting, "
           @"and no repetition of existing text.";
}

#pragma mark - Credential File Storage

+ (NSString *)_credentialsPlistPath
{
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/TeXShop"];
    return [dir stringByAppendingPathComponent:@".copilot_credentials.plist"];
}

+ (NSMutableDictionary *)_readCredentials
{
    NSString *path = [self _credentialsPlistPath];
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
    return dict ? [dict mutableCopy] : [NSMutableDictionary dictionary];
}

+ (BOOL)_writeCredentials:(NSDictionary *)creds
{
    NSString *path = [self _credentialsPlistPath];
    NSString *dir = [path stringByDeletingLastPathComponent];
    NSFileManager *fm = [NSFileManager defaultManager];

    // Ensure directory exists
    if (![fm fileExistsAtPath:dir]) {
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }

    BOOL ok = [creds writeToFile:path atomically:YES];
    if (ok) {
        // Set file permissions to 0600 (owner read/write only)
        [fm setAttributes:@{NSFilePosixPermissions: @0600} ofItemAtPath:path error:nil];
    }
    return ok;
}

+ (NSString *)apiKeyForProvider:(NSString *)provider
{
    NSString *key = [kCredentialServicePrefix stringByAppendingString:provider];
    return [self _readCredentials][key];
}

+ (BOOL)setApiKey:(NSString *)apiKey forProvider:(NSString *)provider
{
    NSString *key = [kCredentialServicePrefix stringByAppendingString:provider];
    NSMutableDictionary *creds = [self _readCredentials];
    if (apiKey.length > 0) {
        creds[key] = apiKey;
    } else {
        [creds removeObjectForKey:key];
    }
    return [self _writeCredentials:creds];
}

+ (BOOL)deleteApiKeyForProvider:(NSString *)provider
{
    return [self setApiKey:nil forProvider:provider];
}

#pragma mark - Settings panel (implemented in TSCopilotPreferences+UI section below)

static NSPanel *_settingsPanel = nil;

+ (void)showSettingsPanel
{
    if (_settingsPanel) {
        [_settingsPanel makeKeyAndOrderFront:nil];
        return;
    }
    [self _buildSettingsPanel];
    [_settingsPanel makeKeyAndOrderFront:nil];
}

+ (void)_buildSettingsPanel
{
    NSRect frame = NSMakeRect(0, 0, 480, 400);
    _settingsPanel = [[NSPanel alloc] initWithContentRect:frame
                                                styleMask:(NSWindowStyleMaskTitled |
                                                           NSWindowStyleMaskClosable)
                                                  backing:NSBackingStoreBuffered
                                                    defer:YES];
    [_settingsPanel setTitle:@"Copilot Settings"];
    [_settingsPanel center];
    [_settingsPanel setReleasedWhenClosed:NO];

    NSView *content = [_settingsPanel contentView];
    CGFloat y = frame.size.height - 40;
    CGFloat labelW = 130;
    CGFloat fieldX = labelW + 20;
    CGFloat fieldW = frame.size.width - fieldX - 20;

    // --- Enable checkbox ---
    NSButton *enableCheck = [NSButton checkboxWithTitle:@"Enable Copilot inline completion"
                                                target:self
                                                action:@selector(_toggleEnabled:)];
    enableCheck.frame = NSMakeRect(20, y, 300, 22);
    enableCheck.state = [self isEnabled] ? NSControlStateValueOn : NSControlStateValueOff;
    [content addSubview:enableCheck];
    y -= 35;

    // --- Provider popup ---
    [self _addLabel:@"Provider:" at:NSMakePoint(20, y) toView:content width:labelW];
    NSPopUpButton *providerPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(fieldX, y, fieldW, 25) pullsDown:NO];
    [providerPopup addItemsWithTitles:@[@"ollama", @"claude", @"github-copilot"]];
    [providerPopup selectItemWithTitle:[self provider]];
    providerPopup.target = self;
    providerPopup.action = @selector(_providerChanged:);
    providerPopup.tag = 100;
    [content addSubview:providerPopup];
    y -= 35;

    // --- Endpoint ---
    [self _addLabel:@"Endpoint:" at:NSMakePoint(20, y) toView:content width:labelW];
    NSTextField *endpointField = [self _addTextField:[self endpoint] at:NSMakePoint(fieldX, y) width:fieldW toView:content tag:101];
    endpointField.placeholderString = @"http://localhost:11434";
    y -= 35;

    // --- Model ---
    [self _addLabel:@"Model:" at:NSMakePoint(20, y) toView:content width:labelW];
    NSTextField *modelField = [self _addTextField:[self model] at:NSMakePoint(fieldX, y) width:fieldW toView:content tag:102];
    modelField.placeholderString = @"qwen2.5-coder";
    y -= 35;

    // --- API Key ---
    [self _addLabel:@"API Key:" at:NSMakePoint(20, y) toView:content width:labelW];
    NSSecureTextField *keyField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(fieldX, y, fieldW, 24)];
    NSString *existingKey = [self apiKeyForProvider:[self provider]];
    if (existingKey.length > 0) {
        keyField.placeholderString = @"(key stored in Keychain)";
    } else {
        keyField.placeholderString = @"Enter API key (stored in Keychain)";
    }
    keyField.tag = 103;
    [content addSubview:keyField];
    y -= 35;

    // --- GitHub Sign In button (shown only for github-copilot) ---
    NSButton *signInBtn = [[NSButton alloc] initWithFrame:NSMakeRect(fieldX, y, 180, 30)];
    signInBtn.title = [TSCopilotAPIClient hasValidGitHubCopilotToken]
                      ? @"Signed In (Sign Out)"
                      : @"Sign In with GitHub";
    signInBtn.bezelStyle = NSBezelStyleRounded;
    signInBtn.target = self;
    signInBtn.action = @selector(_gitHubSignIn:);
    signInBtn.tag = 110;
    signInBtn.hidden = ![[self provider] isEqualToString:@"github-copilot"];
    [content addSubview:signInBtn];

    // Also hide API key and model fields when github-copilot is selected
    BOOL isGitHub = [[self provider] isEqualToString:@"github-copilot"];
    keyField.hidden = isGitHub;
    modelField.hidden = isGitHub;
    for (NSView *v in content.subviews) {
        if ([v isKindOfClass:[NSTextField class]] && ![(NSTextField *)v isEditable]) {
            NSString *label = [(NSTextField *)v stringValue];
            if ([label isEqualToString:@"API Key:"] || [label isEqualToString:@"Model:"]) {
                v.hidden = isGitHub;
            }
        }
    }

    y -= 35;

    // --- Debounce ---
    [self _addLabel:@"Debounce (ms):" at:NSMakePoint(20, y) toView:content width:labelW];
    NSTextField *debounceField = [self _addTextField:[NSString stringWithFormat:@"%ld", (long)[self debounceMs]]
                                                  at:NSMakePoint(fieldX, y) width:80 toView:content tag:104];
    debounceField.placeholderString = @"500";
    y -= 35;

    // --- Max tokens ---
    [self _addLabel:@"Max tokens:" at:NSMakePoint(20, y) toView:content width:labelW];
    NSTextField *tokensField = [self _addTextField:[NSString stringWithFormat:@"%ld", (long)[self maxTokens]]
                                                at:NSMakePoint(fieldX, y) width:80 toView:content tag:105];
    tokensField.placeholderString = @"128";
    y -= 35;

    // --- Ghost alpha ---
    [self _addLabel:@"Ghost opacity:" at:NSMakePoint(20, y) toView:content width:labelW];
    NSSlider *alphaSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(fieldX, y, fieldW - 40, 24)];
    alphaSlider.minValue = 0.1;
    alphaSlider.maxValue = 0.9;
    alphaSlider.floatValue = (float)[self ghostAlpha];
    alphaSlider.target = self;
    alphaSlider.action = @selector(_alphaChanged:);
    alphaSlider.tag = 106;
    [content addSubview:alphaSlider];
    y -= 45;

    // --- Save / Cancel ---
    NSButton *saveBtn = [[NSButton alloc] initWithFrame:NSMakeRect(frame.size.width - 100, y, 80, 30)];
    saveBtn.title = @"Save";
    saveBtn.bezelStyle = NSBezelStyleRounded;
    saveBtn.keyEquivalent = @"\r";
    saveBtn.target = self;
    saveBtn.action = @selector(_saveSettings:);
    [content addSubview:saveBtn];

    NSButton *cancelBtn = [[NSButton alloc] initWithFrame:NSMakeRect(frame.size.width - 190, y, 80, 30)];
    cancelBtn.title = @"Cancel";
    cancelBtn.bezelStyle = NSBezelStyleRounded;
    cancelBtn.keyEquivalent = @"\033";
    cancelBtn.target = self;
    cancelBtn.action = @selector(_cancelSettings:);
    [content addSubview:cancelBtn];
}

#pragma mark - Settings panel helpers

+ (void)_addLabel:(NSString *)text at:(NSPoint)pt toView:(NSView *)view width:(CGFloat)w
{
    NSTextField *label = [NSTextField labelWithString:text];
    label.frame = NSMakeRect(pt.x, pt.y, w, 20);
    label.alignment = NSTextAlignmentRight;
    [view addSubview:label];
}

+ (NSTextField *)_addTextField:(NSString *)value at:(NSPoint)pt width:(CGFloat)w toView:(NSView *)view tag:(NSInteger)tag
{
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(pt.x, pt.y, w, 24)];
    field.stringValue = value ?: @"";
    field.tag = tag;
    [view addSubview:field];
    return field;
}

+ (void)_toggleEnabled:(NSButton *)sender
{
    // Live toggle — saved immediately
    [SUD setBool:(sender.state == NSControlStateValueOn) forKey:TSCopilotEnabledKey];
}

+ (void)_providerChanged:(NSPopUpButton *)sender
{
    NSString *provider = sender.titleOfSelectedItem;
    NSView *content = [_settingsPanel contentView];
    NSSecureTextField *keyField = (NSSecureTextField *)[content viewWithTag:103];
    NSTextField *modelField = (NSTextField *)[content viewWithTag:102];
    NSButton *signInBtn = (NSButton *)[content viewWithTag:110];

    BOOL isGitHub = [provider isEqualToString:@"github-copilot"];

    // Toggle API key and model fields vs GitHub sign-in button
    keyField.hidden = isGitHub;
    modelField.hidden = isGitHub;
    signInBtn.hidden = !isGitHub;

    // Also hide the "API Key:" and "Model:" labels
    for (NSView *v in content.subviews) {
        if ([v isKindOfClass:[NSTextField class]] && ![(NSTextField *)v isEditable]) {
            NSString *label = [(NSTextField *)v stringValue];
            if ([label isEqualToString:@"API Key:"] || [label isEqualToString:@"Model:"]) {
                v.hidden = isGitHub;
            }
        }
    }

    if (!isGitHub) {
        NSString *existingKey = [self apiKeyForProvider:provider];
        if (existingKey.length > 0) {
            keyField.placeholderString = @"(key stored in Keychain)";
        } else {
            keyField.placeholderString = @"Enter API key (stored in Keychain)";
        }
        keyField.stringValue = @"";
    }
}

+ (void)_gitHubSignIn:(NSButton *)sender
{
    if ([TSCopilotAPIClient hasValidGitHubCopilotToken]) {
        // Sign out
        [TSCopilotAPIClient signOutGitHubCopilot];
        sender.title = @"Sign In with GitHub";
        return;
    }

    sender.title = @"Signing in...";
    sender.enabled = NO;

    [[TSCopilotAPIClient sharedClient] startGitHubCopilotSignIn:^(BOOL success, NSError *error) {
        sender.enabled = YES;
        if (success) {
            sender.title = @"Signed In (Sign Out)";
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"GitHub Copilot connected";
            alert.informativeText = @"You are now signed in to GitHub Copilot.";
            alert.alertStyle = NSAlertStyleInformational;
            [alert runModal];
        } else {
            sender.title = @"Sign In with GitHub";
            if (error) {
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = @"Sign in failed";
                alert.informativeText = error.localizedDescription;
                alert.alertStyle = NSAlertStyleWarning;
                [alert runModal];
            }
        }
    }];
}

+ (void)_alphaChanged:(NSSlider *)sender
{
    // Live update
}

+ (void)_saveSettings:(id)sender
{
    NSView *content = [_settingsPanel contentView];
    NSPopUpButton *providerPopup = (NSPopUpButton *)[content viewWithTag:100];
    NSTextField *endpointField = [content viewWithTag:101];
    NSTextField *modelField = [content viewWithTag:102];
    NSSecureTextField *keyField = (NSSecureTextField *)[content viewWithTag:103];
    NSTextField *debounceField = [content viewWithTag:104];
    NSTextField *tokensField = [content viewWithTag:105];
    NSSlider *alphaSlider = (NSSlider *)[content viewWithTag:106];

    [SUD setObject:providerPopup.titleOfSelectedItem forKey:TSCopilotProviderKey];
    [SUD setObject:endpointField.stringValue forKey:TSCopilotEndpointKey];
    [SUD setObject:modelField.stringValue forKey:TSCopilotModelKey];
    [SUD setInteger:debounceField.integerValue forKey:TSCopilotDebounceMsKey];
    [SUD setInteger:tokensField.integerValue forKey:TSCopilotMaxTokensKey];
    [SUD setFloat:alphaSlider.floatValue forKey:TSCopilotGhostAlphaKey];

    // Save API key to Keychain if user entered one
    NSString *newKey = keyField.stringValue;
    if (newKey.length > 0) {
        [self setApiKey:newKey forProvider:providerPopup.titleOfSelectedItem];
    }

    [_settingsPanel close];
}

+ (void)_cancelSettings:(id)sender
{
    [_settingsPanel close];
}

@end
