/*
 * TSCopilotManager.h
 * TeXShop - Copilot inline completion
 *
 * Singleton that coordinates the entire completion lifecycle:
 * text change detection, debouncing, API requests, and overlay display.
 */

#import <Foundation/Foundation.h>

@class TSTextView;
@class TSCopilotOverlayView;

@interface TSCopilotManager : NSObject

+ (instancetype)sharedManager;

/// Called when text changes in a text view. Starts the debounce timer.
- (void)textDidChangeInTextView:(TSTextView *)textView;

/// Called from keyDown: to attempt Tab acceptance. Returns YES if a suggestion was accepted.
- (BOOL)handleTabKeyInTextView:(TSTextView *)textView;

/// Dismiss the current suggestion in the given text view.
- (void)dismissSuggestionInTextView:(TSTextView *)textView;

/// Attach the overlay to a text view (called lazily from the category).
- (TSCopilotOverlayView *)attachOverlayToTextView:(TSTextView *)textView;

/// Get the overlay for a text view (nil if not yet attached).
- (TSCopilotOverlayView *)overlayForTextView:(TSTextView *)textView;

@end
