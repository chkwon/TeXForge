/*
 * TSCopilotManager.m
 * TeXShop - Copilot inline completion
 */

#import "TSCopilotManager.h"
#import "TSCopilotPreferences.h"
#import "TSCopilotOverlayView.h"
#import "TSCopilotAPIClient.h"
#import "TSTextView.h"
#import "TSDocument.h"

static const NSUInteger kPrefixMaxChars  = 1500;
static const NSUInteger kSuffixMaxChars  = 500;

@implementation TSCopilotManager {
    NSMapTable<TSTextView *, TSCopilotOverlayView *> *_overlays;
    NSTimer *_debounceTimer;
    NSURLSessionDataTask *_currentTask;
    __weak TSTextView *_pendingTextView;
    NSUInteger _requestGeneration; // Incremented on each request to detect stale responses
}

+ (instancetype)sharedManager
{
    static TSCopilotManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[TSCopilotManager alloc] init];
    });
    return instance;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _overlays = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsWeakMemory
                                         valueOptions:NSPointerFunctionsStrongMemory];
        _requestGeneration = 0;

        // Listen for window resign to dismiss suggestions
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_windowResigned:)
                                                     name:NSWindowDidResignKeyNotification
                                                   object:nil];
        // Listen for selection changes to dismiss stale suggestions
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_selectionDidChange:)
                                                     name:NSTextViewDidChangeSelectionNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_debounceTimer invalidate];
}

#pragma mark - Overlay Management

- (TSCopilotOverlayView *)attachOverlayToTextView:(TSTextView *)textView
{
    TSCopilotOverlayView *existing = [_overlays objectForKey:textView];
    if (existing) return existing;

    TSCopilotOverlayView *overlay = [[TSCopilotOverlayView alloc] initWithTextView:textView];
    [textView addSubview:overlay];
    [_overlays setObject:overlay forKey:textView];
    return overlay;
}

- (TSCopilotOverlayView *)overlayForTextView:(TSTextView *)textView
{
    return [_overlays objectForKey:textView];
}

#pragma mark - Text Change Handling

- (void)textDidChangeInTextView:(TSTextView *)textView
{
    if (![TSCopilotPreferences isEnabled]) return;
    if (!textView) return;

    // Don't suggest during IME composition
    if ([textView hasMarkedText]) return;

    // Dismiss any current suggestion
    [self dismissSuggestionInTextView:textView];

    // Cancel in-flight request
    [_currentTask cancel];
    _currentTask = nil;

    // Reset debounce timer
    [_debounceTimer invalidate];
    _pendingTextView = textView;

    NSTimeInterval debounce = [TSCopilotPreferences debounceMs] / 1000.0;
    _debounceTimer = [NSTimer scheduledTimerWithTimeInterval:debounce
                                                      target:self
                                                    selector:@selector(_debounceTimerFired:)
                                                    userInfo:nil
                                                     repeats:NO];
}

#pragma mark - Tab Key Handling

- (BOOL)handleTabKeyInTextView:(TSTextView *)textView
{
    if (![TSCopilotPreferences isEnabled]) return NO;

    TSCopilotOverlayView *overlay = [self overlayForTextView:textView];
    if (!overlay || ![overlay hasSuggestion]) return NO;

    // Check if existing command completion is active (wasCompleted ivar)
    BOOL wasCompleted = [[textView valueForKey:@"wasCompleted"] boolValue];
    if (wasCompleted) return NO;

    // Accept the suggestion
    NSString *text = [overlay acceptSuggestion];
    if (text.length == 0) return NO;

    // Cancel any pending request
    [_debounceTimer invalidate];
    [_currentTask cancel];
    _currentTask = nil;

    // Insert the suggestion text using standard NSTextView insertion
    // This properly registers with undo manager
    [textView insertText:text replacementRange:textView.selectedRange];

    return YES;
}

#pragma mark - Dismiss

- (void)dismissSuggestionInTextView:(TSTextView *)textView
{
    TSCopilotOverlayView *overlay = [self overlayForTextView:textView];
    [overlay dismiss];
}

#pragma mark - Debounce Timer

- (void)_debounceTimerFired:(NSTimer *)timer
{
    TSTextView *textView = _pendingTextView;
    if (!textView) return;
    if (![TSCopilotPreferences isEnabled]) return;
    if ([textView hasMarkedText]) return;

    // Don't request if cursor has a selection
    NSRange selection = [textView selectedRange];
    if (selection.length > 0) return;

    // Build context from the document
    NSString *fullText = [textView string];
    if (fullText.length == 0) return;

    NSUInteger cursorPos = selection.location;
    NSString *prefix = [self _prefixFromText:fullText cursorPosition:cursorPos];
    NSString *suffix = [self _suffixFromText:fullText cursorPosition:cursorPos];

    // In code-only mode, skip if cursor is in a prose context
    if ([TSCopilotPreferences isCodeOnly] && ![self _isLaTeXContextInPrefix:prefix]) {
        return;
    }

    // Get file name for context
    NSString *fileName = nil;
    if ([textView respondsToSelector:@selector(document)]) {
        TSDocument *doc = [(TSTextView *)textView document];
        fileName = [[doc fileURL] lastPathComponent];
    }

    // Track generation to detect stale responses
    _requestGeneration++;
    NSUInteger thisGeneration = _requestGeneration;

    __weak typeof(self) weakSelf = self;
    __weak TSTextView *weakTV = textView;

    _currentTask = [[TSCopilotAPIClient sharedClient]
                    requestCompletionWithPrefix:prefix
                                         suffix:suffix
                                       fileName:fileName
                                     completion:^(NSString *suggestion, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        __strong TSTextView *strongTV = weakTV;
        if (!strongSelf || !strongTV) return;

        // Ignore stale responses
        if (thisGeneration != strongSelf->_requestGeneration) {
            NSLog(@"[Copilot] Ignoring stale response (gen %lu vs current %lu)",
                  (unsigned long)thisGeneration, (unsigned long)strongSelf->_requestGeneration);
            return;
        }

        if (error) {
            NSLog(@"[Copilot] API error: %@", error.localizedDescription);
            return;
        }

        if (suggestion.length == 0) {
            NSLog(@"[Copilot] Empty suggestion returned");
            return;
        }

        // Verify cursor hasn't moved
        NSRange currentSelection = [strongTV selectedRange];
        if (currentSelection.location != cursorPos || currentSelection.length > 0) {
            NSLog(@"[Copilot] Cursor moved, discarding suggestion");
            return;
        }

        // Show the suggestion
        TSCopilotOverlayView *overlay = [strongSelf overlayForTextView:strongTV];
        if (!overlay) {
            NSLog(@"[Copilot] No overlay, creating one");
            overlay = [strongSelf attachOverlayToTextView:strongTV];
        }
        NSLog(@"[Copilot] Showing suggestion (%lu chars) at location %lu, overlay frame: %@, hidden: %d, superview: %@",
              (unsigned long)suggestion.length, (unsigned long)cursorPos,
              NSStringFromRect(overlay.frame), overlay.isHidden, overlay.superview);
        [overlay showSuggestion:suggestion atLocation:cursorPos];
    }];
}

#pragma mark - Context Extraction

- (NSString *)_prefixFromText:(NSString *)text cursorPosition:(NSUInteger)pos
{
    if (pos == 0) return @"";
    NSUInteger start = (pos > kPrefixMaxChars) ? (pos - kPrefixMaxChars) : 0;
    return [text substringWithRange:NSMakeRange(start, pos - start)];
}

- (NSString *)_suffixFromText:(NSString *)text cursorPosition:(NSUInteger)pos
{
    if (pos >= text.length) return @"";
    NSUInteger remaining = text.length - pos;
    NSUInteger len = MIN(remaining, kSuffixMaxChars);
    return [text substringWithRange:NSMakeRange(pos, len)];
}

#pragma mark - Code-Only Context Detection

/// Returns YES if the prefix text suggests the cursor is in a LaTeX code context
/// (after a command, inside braces/brackets, in math mode, at line start with backslash, etc.)
/// Returns NO if the cursor appears to be in a prose/text context.
- (BOOL)_isLaTeXContextInPrefix:(NSString *)prefix
{
    if (prefix.length == 0) return YES; // Empty document — allow completion

    // Scan backwards from cursor to find the nearest context clue
    NSUInteger len = prefix.length;
    NSUInteger scanLimit = MIN(len, (NSUInteger)80); // Look back at most 80 chars

    // Track state
    BOOL inMath = NO;
    NSInteger braceDepth = 0;
    NSInteger bracketDepth = 0;

    // Check if we're inside a math environment by scanning for unmatched $ or \[ or \(
    // (simplified: just check for recent $ on the same line)
    NSRange lastNewline = [prefix rangeOfString:@"\n" options:NSBackwardsSearch];
    NSString *currentLine = (lastNewline.location != NSNotFound)
        ? [prefix substringFromIndex:lastNewline.location + 1]
        : prefix;

    // Count $ signs on current line (odd count = inside math mode)
    NSUInteger dollarCount = 0;
    for (NSUInteger i = 0; i < currentLine.length; i++) {
        unichar c = [currentLine characterAtIndex:i];
        if (c == '$' && (i == 0 || [currentLine characterAtIndex:i - 1] != '\\')) {
            dollarCount++;
        }
    }
    if (dollarCount % 2 == 1) return YES; // Inside inline math

    // Scan backwards from end of prefix
    for (NSUInteger i = 0; i < scanLimit; i++) {
        NSUInteger pos = len - 1 - i;
        unichar c = [prefix characterAtIndex:pos];

        // Skip whitespace
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') continue;

        // LaTeX command context: cursor is right after or inside a command
        if (c == '\\') return YES;                     // \command|
        if (c == '{' || c == '}') return YES;          // \cmd{|  or after closing }
        if (c == '[' || c == ']') return YES;          // \cmd[|  or after closing ]
        if (c == '$') return YES;                      // Math mode boundary
        if (c == '%') return YES;                      // Comment line
        if (c == '&') return YES;                      // Table alignment
        if (c == '~') return YES;                      // Non-breaking space (LaTeX)
        if (c == '#') return YES;                      // Macro parameter

        // Check if this non-whitespace char is part of a LaTeX command argument
        // by looking further back for an opening brace
        // e.g., \section{Some Title| — cursor after prose inside braces is still code context
        NSString *scannedBack = [prefix substringFromIndex:pos];
        if ([scannedBack rangeOfString:@"{"].location != NSNotFound) {
            // There's an unclosed brace before the cursor on this segment
            NSUInteger opens = 0, closes = 0;
            for (NSUInteger j = 0; j < scannedBack.length; j++) {
                unichar bc = [scannedBack characterAtIndex:j];
                if (bc == '{') opens++;
                else if (bc == '}') closes++;
            }
            if (opens > closes) return YES; // Inside a brace group
        }

        // If we hit a regular letter/digit without any LaTeX syntax, it's prose
        return NO;
    }

    // If we scanned the full limit without finding anything, assume prose
    return NO;
}

#pragma mark - Notifications

- (void)_windowResigned:(NSNotification *)note
{
    // Dismiss all suggestions when any window loses focus
    for (TSTextView *tv in _overlays) {
        [self dismissSuggestionInTextView:tv];
    }
    [_debounceTimer invalidate];
    [_currentTask cancel];
    _currentTask = nil;
}

- (void)_selectionDidChange:(NSNotification *)note
{
    NSTextView *textView = note.object;
    if ([textView isKindOfClass:[TSTextView class]]) {
        TSCopilotOverlayView *overlay = [self overlayForTextView:(TSTextView *)textView];
        if ([overlay hasSuggestion]) {
            // The overlay's drawRect will auto-dismiss if cursor moved,
            // but let's be proactive
            NSUInteger cursorLoc = [textView selectedRange].location;
            if (cursorLoc != overlay.suggestionLocation || [textView selectedRange].length > 0) {
                [overlay dismiss];
            }
        }
    }
}

@end
