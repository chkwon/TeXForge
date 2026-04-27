/*
 * TSCopilotOverlayView.m
 * TeXShop - Copilot inline completion
 */

#import "TSCopilotOverlayView.h"
#import "TSCopilotPreferences.h"
#import "TSTextView.h"

static CGFloat _sRGBComponentToLinear(CGFloat c) {
    return (c <= 0.04045) ? (c / 12.92) : pow((c + 0.055) / 1.055, 2.4);
}

static CGFloat _sRGBRelativeLuminance(NSColor *color) {
    NSColor *rgb = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    if (!rgb) return 0.5;
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [rgb getRed:&r green:&g blue:&b alpha:&a];
    return 0.2126 * _sRGBComponentToLinear(r)
         + 0.7152 * _sRGBComponentToLinear(g)
         + 0.0722 * _sRGBComponentToLinear(b);
}

@implementation TSCopilotOverlayView {
    NSUInteger _ghostLineCount;
    CGFloat _cursorLineFragmentY;
    CGFloat _extraLineSpacing;
    __weak id<NSLayoutManagerDelegate> _savedLayoutDelegate;
}

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
    // Clean up layout manager delegate if still set
    TSTextView *tv = self.textView;
    NSLayoutManager *lm = [tv layoutManager];
    if (lm.delegate == self) {
        lm.delegate = nil;
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - NSLayoutManagerDelegate

- (CGFloat)layoutManager:(NSLayoutManager *)layoutManager
    lineSpacingAfterGlyphAtIndex:(NSUInteger)glyphIndex
    withProposedLineFragmentRect:(NSRect)rect
{
    if (_extraLineSpacing <= 0) return 0;

    // Add extra spacing after the cursor's line fragment to push text down
    if (fabs(rect.origin.y - _cursorLineFragmentY) < 1.0) {
        return _extraLineSpacing;
    }
    return 0;
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

    // Count lines and set up layout manager delegate for multi-line push-down
    NSArray *lines = [text componentsSeparatedByString:@"\n"];
    _ghostLineCount = lines.count;
    _extraLineSpacing = 0;
    _cursorLineFragmentY = -1;

    TSTextView *tv = self.textView;
    NSLayoutManager *lm = [tv layoutManager];
    NSTextContainer *tc = [tv textContainer];

    if (_ghostLineCount > 1 && lm && tc) {
        NSString *fullText = [tv string];
        NSFont *font = [tv font] ?: [NSFont userFixedPitchFontOfSize:12.0];
        CGFloat lineHeight = [lm defaultLineHeightForFont:font];
        _extraLineSpacing = (_ghostLineCount - 1) * lineHeight;

        // Precompute cursor line fragment Y before installing delegate
        if (location < fullText.length) {
            NSRange glyphRange = [lm glyphRangeForCharacterRange:NSMakeRange(location, 1)
                                            actualCharacterRange:NULL];
            if (glyphRange.location < [lm numberOfGlyphs]) {
                NSRect lineRect = [lm lineFragmentRectForGlyphAtIndex:glyphRange.location
                                                       effectiveRange:NULL];
                _cursorLineFragmentY = lineRect.origin.y;
            }
        } else if ([lm numberOfGlyphs] > 0) {
            // End of text — use last glyph's line fragment
            NSRect lineRect = [lm lineFragmentRectForGlyphAtIndex:[lm numberOfGlyphs] - 1
                                                   effectiveRange:NULL];
            _cursorLineFragmentY = lineRect.origin.y;
        }

        if (_cursorLineFragmentY >= 0) {
            _savedLayoutDelegate = lm.delegate;
            lm.delegate = self;
            NSUInteger textLen = fullText.length;
            if (location < textLen) {
                [lm invalidateLayoutForCharacterRange:NSMakeRange(location, textLen - location)
                                 actualCharacterRange:NULL];
            }
        }
    }

    [self setNeedsDisplay:YES];
}

- (void)dismiss
{
    if (_suggestionText == nil) return;

    // Remove layout manager delegate and restore normal spacing
    TSTextView *tv = self.textView;
    NSLayoutManager *lm = [tv layoutManager];
    if (_extraLineSpacing > 0 && lm && lm.delegate == self) {
        lm.delegate = _savedLayoutDelegate;
        _savedLayoutDelegate = nil;
        NSUInteger textLen = [[tv string] length];
        if (textLen > 0) {
            [lm invalidateLayoutForCharacterRange:NSMakeRange(0, textLen)
                             actualCharacterRange:NULL];
        }
    }

    _suggestionText = nil;
    _suggestionLocation = NSNotFound;
    _ghostLineCount = 0;
    _extraLineSpacing = 0;
    _cursorLineFragmentY = -1;
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

    // Theme-aware ghost color with perceptual contrast compensation.
    // Linear sRGB blending alone makes thin glyphs (`{`, `}`, punctuation) nearly
    // invisible on dark themes — human contrast sensitivity is roughly logarithmic
    // and antialiased fine detail washes out faster against dark backgrounds. We
    // boost the user's chosen ghostAlpha based on the bg's perceptual luminance
    // and the bg→fg luminance span, leaving light themes unchanged.
    NSColor *fgColor = [tv textColor] ?: [NSColor labelColor];
    NSColor *bgColor = [tv backgroundColor] ?: [NSColor textBackgroundColor];

    CGFloat bgLum = _sRGBRelativeLuminance(bgColor);
    CGFloat fgLum = _sRGBRelativeLuminance(fgColor);
    CGFloat span  = fabs(fgLum - bgLum);
    CGFloat effectiveAlpha = alpha;

    if (bgLum < 0.45) {
        effectiveAlpha += (0.45 - bgLum) * 0.6;     // dark-bg boost
    }
    if (span < 0.4) {
        effectiveAlpha += (0.4 - span) * 0.5;       // low-contrast theme boost
    }

    NSColor *bgRGB = [bgColor colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    if (bgRGB && [bgRGB alphaComponent] < 0.99) {
        effectiveAlpha = MAX(effectiveAlpha, 0.6);  // translucent-window floor
    }

    effectiveAlpha = MIN(effectiveAlpha, 0.95);     // never saturate to fg

    NSColor *ghostColor = [bgColor blendedColorWithFraction:effectiveAlpha ofColor:fgColor];
    if (!ghostColor) {
        ghostColor = [fgColor colorWithAlphaComponent:effectiveAlpha];
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

    // Background masking constants
    CGFloat viewWidth = self.bounds.size.width;
    CGFloat leftMargin = containerOrigin.x + textContainer.lineFragmentPadding;

    for (NSUInteger i = 0; i < lines.count; i++) {
        NSString *line = lines[i];

        // Fill background behind ghost text to prevent overlap with existing text
        NSRect bgRect;
        if (i == 0) {
            bgRect = NSMakeRect(x, y, viewWidth - x, lineHeight);
        } else {
            bgRect = NSMakeRect(leftMargin, y, viewWidth - leftMargin, lineHeight);
        }
        [bgColor set];
        NSRectFill(bgRect);

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
