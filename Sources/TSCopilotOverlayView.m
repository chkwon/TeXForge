/*
 * TSCopilotOverlayView.m
 * TeXShop - Copilot inline completion
 */

#import "TSCopilotOverlayView.h"
#import "TSCopilotPreferences.h"
#import "TSTextView.h"

@implementation TSCopilotOverlayView

- (instancetype)initWithTextView:(TSTextView *)textView
{
    self = [super initWithFrame:textView.bounds];
    if (self) {
        _textView = textView;
        _suggestionText = nil;
        _suggestionLocation = NSNotFound;

        self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

        // Observe scroll changes to redraw at correct position
        NSClipView *clipView = textView.enclosingScrollView.contentView;
        if (clipView) {
            clipView.postsBoundsChangedNotifications = YES;
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(_scrollOrResizeChanged:)
                                                         name:NSViewBoundsDidChangeNotification
                                                       object:clipView];
        }
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_scrollOrResizeChanged:)
                                                     name:NSViewFrameDidChangeNotification
                                                   object:textView];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Public API

- (void)showSuggestion:(NSString *)text atLocation:(NSUInteger)location
{
    if (text.length == 0) {
        [self dismiss];
        return;
    }
    _suggestionText = [text copy];
    _suggestionLocation = location;
    [self setNeedsDisplay:YES];
}

- (void)dismiss
{
    if (_suggestionText == nil) return;
    _suggestionText = nil;
    _suggestionLocation = NSNotFound;
    [self setNeedsDisplay:YES];
}

- (BOOL)hasSuggestion
{
    return (_suggestionText.length > 0 && _suggestionLocation != NSNotFound);
}

- (NSString *)acceptSuggestion
{
    NSString *text = [_suggestionText copy];
    [self dismiss];
    return text;
}

#pragma mark - Drawing

- (void)drawRect:(NSRect)dirtyRect
{
    if (![self hasSuggestion]) return;

    TSTextView *tv = self.textView;
    if (!tv) return;

    NSString *fullText = [tv string];
    if (_suggestionLocation > fullText.length) {
        [self dismiss];
        return;
    }

    // Skip drawing if cursor moved, but don't dismiss here
    // (TSCopilotManager handles dismissal via notifications)
    NSUInteger cursorLoc = [tv selectedRange].location;
    if (cursorLoc != _suggestionLocation || [tv selectedRange].length > 0) {
        return;
    }

    NSLayoutManager *layoutManager = [tv layoutManager];
    NSTextContainer *textContainer = [tv textContainer];
    if (!layoutManager || !textContainer) return;

    // Get the rect for the character at the suggestion location
    NSUInteger glyphIndex;
    if (_suggestionLocation < fullText.length) {
        NSRange glyphRange = [layoutManager glyphRangeForCharacterRange:NSMakeRange(_suggestionLocation, 1)
                                                  actualCharacterRange:NULL];
        glyphIndex = glyphRange.location;
    } else {
        // At end of text — use extra fragment rect
        glyphIndex = [layoutManager numberOfGlyphs];
    }

    NSRect insertionRect;
    if (glyphIndex < [layoutManager numberOfGlyphs]) {
        insertionRect = [layoutManager boundingRectForGlyphRange:NSMakeRange(glyphIndex, 1)
                                                 inTextContainer:textContainer];
        // We want the left edge
        insertionRect.size.width = 0;
    } else {
        // Use extra line fragment rect for end-of-text
        NSRect extraRect = [layoutManager extraLineFragmentUsedRect];
        if (NSIsEmptyRect(extraRect)) {
            // Fallback: use last glyph position
            if (glyphIndex > 0) {
                insertionRect = [layoutManager boundingRectForGlyphRange:NSMakeRange(glyphIndex - 1, 1)
                                                        inTextContainer:textContainer];
                insertionRect.origin.x += insertionRect.size.width;
                insertionRect.size.width = 0;
            } else {
                insertionRect = NSMakeRect(0, 0, 0, 14);
            }
        } else {
            insertionRect = extraRect;
            insertionRect.size.width = 0;
        }
    }

    // Adjust for text container origin
    NSPoint containerOrigin = [tv textContainerOrigin];
    insertionRect.origin.x += containerOrigin.x;
    insertionRect.origin.y += containerOrigin.y;

    // Convert from textView coords to our coords (we're a subview, so same coordinate space)
    // But we need to account for the visible rect if using a scroll view
    // Since we match the textView's bounds, coords are the same.

    // Prepare drawing attributes
    NSFont *font = [tv font] ?: [NSFont userFixedPitchFontOfSize:12.0];
    CGFloat alpha = [TSCopilotPreferences ghostAlpha];
    NSColor *ghostColor;
    if (@available(macOS 10.14, *)) {
        // Use a color that adapts to light/dark mode
        ghostColor = [[NSColor secondaryLabelColor] colorWithAlphaComponent:alpha];
    } else {
        ghostColor = [NSColor colorWithCalibratedWhite:0.5 alpha:alpha];
    }

    NSDictionary *attrs = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: ghostColor,
    };

    // Split suggestion into lines and draw
    NSArray<NSString *> *lines = [_suggestionText componentsSeparatedByString:@"\n"];
    CGFloat lineHeight = [layoutManager defaultLineHeightForFont:font];
    CGFloat x = insertionRect.origin.x;
    CGFloat y = insertionRect.origin.y;

    // Get the remaining width on the current line
    NSRect lineFragmentRect;
    if (glyphIndex < [layoutManager numberOfGlyphs]) {
        lineFragmentRect = [layoutManager lineFragmentUsedRectForGlyphAtIndex:glyphIndex
                                                               effectiveRange:NULL];
    } else if (glyphIndex > 0) {
        lineFragmentRect = [layoutManager lineFragmentUsedRectForGlyphAtIndex:glyphIndex - 1
                                                               effectiveRange:NULL];
    } else {
        lineFragmentRect = NSZeroRect;
    }

    NSLog(@"[CopilotOverlay] drawing %lu lines at (%.1f, %.1f)", (unsigned long)lines.count, x, y);

    for (NSUInteger i = 0; i < lines.count; i++) {
        NSString *line = lines[i];
        if (line.length == 0 && i > 0) {
            y += lineHeight;
            continue;
        }

        NSPoint drawPoint;
        if (i == 0) {
            // First line: draw at cursor position
            drawPoint = NSMakePoint(x, y);
        } else {
            // Subsequent lines: draw at the left margin (indented to text container inset)
            CGFloat leftMargin = containerOrigin.x + textContainer.lineFragmentPadding;
            drawPoint = NSMakePoint(leftMargin, y);
        }

        [line drawAtPoint:drawPoint withAttributes:attrs];
        y += lineHeight;
    }
}

#pragma mark - Event pass-through

- (NSView *)hitTest:(NSPoint)point
{
    return nil; // Pass all mouse events through to the text view
}

- (BOOL)acceptsFirstResponder
{
    return NO;
}

- (BOOL)isOpaque
{
    return NO;
}

- (BOOL)isFlipped
{
    return YES;
}

#pragma mark - Notifications

- (void)_scrollOrResizeChanged:(NSNotification *)note
{
    if ([self hasSuggestion]) {
        [self setNeedsDisplay:YES];
    }
}

@end
