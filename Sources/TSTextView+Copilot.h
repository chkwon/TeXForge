/*
 * TSTextView+Copilot.h
 * TeXShop - Copilot inline completion
 *
 * Category on TSTextView that adds Copilot methods without modifying
 * the original class interface. Uses method swizzling on awakeFromNib
 * and associated objects for per-instance state.
 */

#import "TSTextView.h"

@class TSCopilotOverlayView;

@interface TSTextView (Copilot)

/// Called from keyDown: hook. Returns YES if Tab was consumed to accept a suggestion.
- (BOOL)copilotHandleTabKey:(NSEvent *)theEvent;

/// Notify the Copilot system that text changed.
- (void)copilotTextDidChange;

/// Dismiss any active suggestion.
- (void)copilotDismiss;

/// Get the overlay view (lazily created).
- (TSCopilotOverlayView *)copilotOverlayView;

@end
