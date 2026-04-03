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
