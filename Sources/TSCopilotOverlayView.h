/*
 * TSCopilotOverlayView.h
 * TeXShop - Copilot inline completion
 *
 * Transparent overlay view that draws ghost text (inline suggestions)
 * on top of a TSTextView. Passes all mouse events through.
 */

#import <Cocoa/Cocoa.h>

@class TSTextView;

@interface TSCopilotOverlayView : NSView <NSLayoutManagerDelegate>

@property (weak) TSTextView *textView;
@property (copy, readonly) NSString *suggestionText;
@property (readonly) NSUInteger suggestionLocation;

- (instancetype)initWithTextView:(TSTextView *)textView;
- (void)showSuggestion:(NSString *)text atLocation:(NSUInteger)location;
- (void)dismiss;
- (BOOL)hasSuggestion;
- (NSString *)acceptSuggestion;

@end
