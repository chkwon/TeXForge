/*
 * TSTextView+Copilot.m
 * TeXShop - Copilot inline completion
 */

#import "TSTextView+Copilot.h"
#import "TSCopilotManager.h"
#import "TSCopilotOverlayView.h"
#import "TSCopilotPreferences.h"
#import <objc/runtime.h>

static const void *kCopilotOverlayKey = &kCopilotOverlayKey;

@implementation TSTextView (Copilot)

#pragma mark - Swizzle awakeFromNib

+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = [self class];
        SEL originalSel = @selector(awakeFromNib);
        SEL swizzledSel = @selector(copilot_awakeFromNib);

        Method originalMethod = class_getInstanceMethod(cls, originalSel);
        Method swizzledMethod = class_getInstanceMethod(cls, swizzledSel);

        BOOL didAdd = class_addMethod(cls, originalSel,
                                      method_getImplementation(swizzledMethod),
                                      method_getTypeEncoding(swizzledMethod));
        if (didAdd) {
            class_replaceMethod(cls, swizzledSel,
                                method_getImplementation(originalMethod),
                                method_getTypeEncoding(originalMethod));
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod);
        }

        // Also swizzle didChangeText to detect edits.
        // TSTextView does not override didChangeText, so class_addMethod must
        // install our override on TSTextView itself; exchanging the inherited
        // Method would hijack NSTextView.didChangeText for every text view in
        // the app (field editors, the find bar) and break their change
        // notifications.
        SEL origTextDidChange = @selector(didChangeText);
        SEL swizTextDidChange = @selector(copilot_didChangeText);
        Method origTDC = class_getInstanceMethod(cls, origTextDidChange);
        Method swizTDC = class_getInstanceMethod(cls, swizTextDidChange);
        if (origTDC && swizTDC) {
            BOOL didAddTDC = class_addMethod(cls, origTextDidChange,
                                             method_getImplementation(swizTDC),
                                             method_getTypeEncoding(swizTDC));
            if (didAddTDC) {
                class_replaceMethod(cls, swizTextDidChange,
                                    method_getImplementation(origTDC),
                                    method_getTypeEncoding(origTDC));
            } else {
                method_exchangeImplementations(origTDC, swizTDC);
            }
        }

        // Inject "Copilot Settings..." menu item after app finishes launching
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_copilotAppDidFinishLaunching:)
                                                     name:NSApplicationDidFinishLaunchingNotification
                                                   object:nil];
    });
}

- (void)copilot_awakeFromNib
{
    // Call the original awakeFromNib (swizzled)
    [self copilot_awakeFromNib];

    // Lazily attach overlay when Copilot is enabled
    if ([TSCopilotPreferences isEnabled]) {
        [[TSCopilotManager sharedManager] attachOverlayToTextView:self];
    }
}

- (void)copilot_didChangeText
{
    // Call original didChangeText first
    [self copilot_didChangeText];

    // Notify Copilot of the change
    if ([TSCopilotPreferences isEnabled]) {
        [[TSCopilotManager sharedManager] textDidChangeInTextView:self];
    }
}

#pragma mark - Public Methods

- (BOOL)copilotHandleTabKey:(NSEvent *)theEvent
{
    if (![TSCopilotPreferences isEnabled]) return NO;

    // Only handle Tab key (keyCode 48)
    if ([theEvent keyCode] != 48) return NO;

    // Don't intercept if modifier keys are held (Shift-Tab, etc.)
    NSEventModifierFlags mods = [theEvent modifierFlags] &
        (NSEventModifierFlagShift | NSEventModifierFlagControl |
         NSEventModifierFlagOption | NSEventModifierFlagCommand);
    if (mods != 0) return NO;

    return [[TSCopilotManager sharedManager] handleTabKeyInTextView:self];
}

- (void)copilotTextDidChange
{
    [[TSCopilotManager sharedManager] textDidChangeInTextView:self];
}

- (void)copilotDismiss
{
    [[TSCopilotManager sharedManager] dismissSuggestionInTextView:self];
}

- (TSCopilotOverlayView *)copilotOverlayView
{
    TSCopilotOverlayView *overlay = objc_getAssociatedObject(self, kCopilotOverlayKey);
    if (!overlay) {
        overlay = [[TSCopilotManager sharedManager] attachOverlayToTextView:self];
        objc_setAssociatedObject(self, kCopilotOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return overlay;
}

#pragma mark - Menu Item Injection

+ (void)_copilotAppDidFinishLaunching:(NSNotification *)note
{
    // Add "Copilot Settings..." to the Edit menu
    NSMenu *mainMenu = [NSApp mainMenu];
    NSMenuItem *editMenuItem = nil;

    // Find the Edit menu
    for (NSMenuItem *item in mainMenu.itemArray) {
        if ([item.title isEqualToString:@"Edit"] ||
            [item.title isEqualToString:NSLocalizedString(@"Edit", nil)]) {
            editMenuItem = item;
            break;
        }
    }

    if (!editMenuItem) {
        // Fallback: try by index (Edit is typically the 3rd menu)
        if (mainMenu.itemArray.count > 2) {
            editMenuItem = mainMenu.itemArray[2];
        }
    }

    if (editMenuItem && editMenuItem.submenu) {
        NSMenu *editMenu = editMenuItem.submenu;
        [editMenu addItem:[NSMenuItem separatorItem]];

        NSMenuItem *copilotItem = [[NSMenuItem alloc] initWithTitle:@"Copilot Settings..."
                                                             action:@selector(_showCopilotSettings:)
                                                      keyEquivalent:@""];
        copilotItem.target = self;
        [editMenu addItem:copilotItem];
    }

    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSApplicationDidFinishLaunchingNotification
                                                  object:nil];
}

+ (void)_showCopilotSettings:(id)sender
{
    [TSCopilotPreferences showSettingsPanel];
}

@end
