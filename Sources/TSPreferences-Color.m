/*
 * TeXShop - TeX editor for Mac OS
 * Copyright (C) 2000-2007 Richard Koch
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 *
 * $Id: TSPreferences.m 254 2007-06-03 21:09:25Z fingolfin $
 *
 * Created by dirk on Thu Dec 07 2000.
 *
 */

#import "TSPreferences.h"
#import "globals.h"
#import "TSColorSupport.h"
#import "TSVSCodeThemeImporter.h"


@implementation TSPreferences (Color)

NSInteger stringSort(id s1, id s2, void *context)
{
    NSComparisonResult result;
    result =  [(NSString *)s1 localizedCaseInsensitiveCompare: (NSString *)s2];
    return result;
}


// Rebuild the contents of the three theme popup buttons from the current state of
// ~/Library/TeXForge/Themes/. Preserves the previously-selected titles when they
// still exist, so the user's choice survives a refresh.
- (void)refreshThemePopups
{
    NSString *prevLite    = [LiteStyle titleOfSelectedItem];
    NSString *prevDark    = [DarkStyle titleOfSelectedItem];
    NSString *prevEditing = [EditingStyle titleOfSelectedItem];

    [LiteStyle removeAllItems];
    [DarkStyle removeAllItems];
    [EditingStyle removeAllItems];

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *filePath = [ColorPath stringByExpandingTildeInPath];
    NSArray *contents = [[fileManager contentsOfDirectoryAtPath: filePath error: nil]
                            sortedArrayUsingFunction: stringSort context: NULL];

    for (NSString *item in contents) {
        if (! [[item pathExtension] isEqualToString: @"plist"]) continue;
        NSString *title = [item stringByDeletingPathExtension];
        [LiteStyle addItemWithTitle: title];
        [DarkStyle addItemWithTitle: title];
        [EditingStyle addItemWithTitle: title];
    }

    if (prevLite    && [LiteStyle    itemWithTitle: prevLite])    [LiteStyle    selectItemWithTitle: prevLite];
    if (prevDark    && [DarkStyle    itemWithTitle: prevDark])    [DarkStyle    selectItemWithTitle: prevDark];
    if (prevEditing && [EditingStyle itemWithTitle: prevEditing]) [EditingStyle selectItemWithTitle: prevEditing];
}


// Insert "Install Theme…" and "Reveal Themes Folder" buttons into the Colors pane
// at runtime. This sidesteps the compiled Preferences.nib, which can only be
// edited in Xcode's Interface Builder. Safe to call repeatedly — the helper
// tags the buttons and won't add duplicates.
- (void)installThemeButtonsIfNeeded
{
    static const NSInteger kInstallButtonTag = 924701;
    if (! EditingStyle) return;
    NSView *pane = EditingStyle.superview;
    if (! pane) return;
    if ([pane viewWithTag: kInstallButtonTag]) return;

    NSRect refFrame = EditingStyle.frame;
    CGFloat buttonHeight = 24.0;
    CGFloat buttonY = NSMinY(refFrame) - buttonHeight - 8.0;
    if (buttonY < 4.0) buttonY = NSMaxY(refFrame) + 8.0;

    NSButton *install = [[NSButton alloc] initWithFrame: NSMakeRect(NSMinX(refFrame), buttonY, 150.0, buttonHeight)];
    install.bezelStyle = NSBezelStyleRounded;
    install.title = NSLocalizedString(@"Install Theme…", @"Colors pane: import a theme from a file");
    install.target = self;
    install.action = @selector(installThemeFromFile:);
    install.tag = kInstallButtonTag;
    install.autoresizingMask = NSViewMinYMargin;
    [pane addSubview: install];

    NSButton *reveal = [[NSButton alloc] initWithFrame: NSMakeRect(NSMinX(refFrame) + 160.0, buttonY, 190.0, buttonHeight)];
    reveal.bezelStyle = NSBezelStyleRounded;
    reveal.title = NSLocalizedString(@"Reveal Themes Folder", @"Colors pane: open the user themes directory");
    reveal.target = self;
    reveal.action = @selector(revealThemesFolder:);
    reveal.autoresizingMask = NSViewMinYMargin;
    [pane addSubview: reveal];
}


- (void)PrepareColorPane:(NSUserDefaults *)defaults;
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    [colorSupport checkAndRestoreDefaults];

    oldLiteStyle = [SUD objectForKey: DefaultLiteThemeKey];
    oldDarkStyle = [SUD objectForKey: DefaultDarkThemeKey];

    [self refreshThemePopups];
    [self installThemeButtonsIfNeeded];

    NSString *liteTitle = [SUD stringForKey:DefaultLiteThemeKey];
    NSString *darkTitle = [SUD stringForKey:DefaultDarkThemeKey];

    // if this file doesn't exist, switch menu to LiteColors
    [LiteStyle selectItemWithTitle: liteTitle];
    [DarkStyle selectItemWithTitle: darkTitle];
    // if this file doesn't exist, switch menu to DarkColors
#ifdef MOJAVEORHIGHER
    if ((atLeastMojave) && (_prefsWindow.effectiveAppearance.name == NSAppearanceNameDarkAqua))
    {
        [EditingStyle selectItemWithTitle:darkTitle];
        EditingColors = [colorSupport dictionaryForColorFile: darkTitle];
    }
    else
#endif
    {
        [EditingStyle selectItemWithTitle: liteTitle];
        EditingColors = [colorSupport dictionaryForColorFile: liteTitle];
    }

    // Fill in all the color wells with the colors of these items
    [self FillInColorWells];
}


// OK button pressed in Preferences
// if the OK button is pressed, then the current editing changes for the currently chosen editing style are
// saved. Also the new choices for liteColor and darkColor are activated

- (void)okForColor
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    [self SaveEditedStyle:self];
    
    [SUD setObject:  [LiteStyle titleOfSelectedItem] forKey: DefaultLiteThemeKey];
    [SUD setObject: [DarkStyle titleOfSelectedItem] forKey: DefaultDarkThemeKey];
    [colorSupport     checkAndRestoreDefaults];
    [colorSupport initializeColors];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: nil];
    [[NSColorPanel sharedColorPanel] close];
  
}

// Cancel button pressed in Preferences
// if the cancel button is pressed, then all editing changes are lost EXCEPT those saved using the "Save" button
// also default lite and dark styles do not change

- (void)cancelForColor
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
   [SUD setObject: oldLiteStyle forKey: DefaultLiteThemeKey];
   [SUD setObject: oldDarkStyle forKey: DefaultDarkThemeKey];
    [colorSupport checkAndRestoreDefaults];
    [colorSupport initializeColors];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: nil];
   [[NSColorPanel sharedColorPanel] close];
  
}

// Live-preview helper: load the selected theme, sync the Editing popup and color wells,
// and broadcast so all open documents (and themed window chrome) repaint immediately.
// The permanent Lite/Dark choice is still only persisted in okForColor — Cancel reverts.
- (void)applyLivePreviewForThemeTitle:(NSString *)title
{
    if (title.length == 0) return;
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    NSMutableDictionary *theme = [colorSupport dictionaryForColorFile: title];
    if (! theme) return;

    EditingColors = theme;
    if ([EditingStyle itemWithTitle: title]) {
        [EditingStyle selectItemWithTitle: title];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName: SourceColorChangedNotification
                                                        object: self
                                                      userInfo: EditingColors];
    [self FillInColorWells];
}

- (IBAction)LiteStyleChoice:sender
{
    [self applyLivePreviewForThemeTitle: [LiteStyle titleOfSelectedItem]];
}

- (IBAction)DarkStyleChoice:sender
{
    [self applyLivePreviewForThemeTitle: [DarkStyle titleOfSelectedItem]];
}

- (void)FillInColorWells
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    NSColor *flashColor, *aColor;
    NSColor *footnoteCol, *EntryCol;
    BOOL withDarkColors;
    
    
#ifdef MOJAVEORHIGHER
    if ((atLeastMojave) && (_prefsWindow.effectiveAppearance.name == NSAppearanceNameDarkAqua))
        withDarkColors = YES;
    else
#endif
        withDarkColors = NO;

    
    SourceTextColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"EditorText"];
    SourceBackgroundColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"EditorBackground"];
    SourceInsertionPointColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"EditorInsertionPoint"];
    PreviewBackgroundColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"PreviewBackground"];
    ConsoleTextColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"ConsoleText"];
    ConsoleBackgroundColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"ConsoleBackground"];
    LogTextColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"LogText"];
    LogBackgroundColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"LogBackground"];
    SyntaxCommentColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"SyntaxComment"];
    SyntaxCommandColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"SyntaxCommand"];
    SyntaxMarkerColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"SyntaxMarker"];
    SyntaxIndexColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"SyntaxIndex"];
    
    //markerParenColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"SyntaxMarkerParen"];
    //markerCurlyColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"SyntaxMarkerCurly"];
    //markerSquareColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"SyntaxMarkerSquare"];
    markerParenColorWell.color = [colorSupport colorForKey: @"SyntaxMarkerParen" isWindowDark: withDarkColors];
    markerCurlyColorWell.color = [colorSupport colorForKey: @"SyntaxMarkerCurly" isWindowDark: withDarkColors];
    markerSquareColorWell.color = [colorSupport colorForKey: @"SyntaxMarkerSquare" isWindowDark: withDarkColors];
    
    
        
    explFunctionColorWell.color = [colorSupport colorForKey: @"explFunction" isWindowDark: withDarkColors];
    explVariableColorWell.color = [colorSupport colorForKey: @"explVariable" isWindowDark: withDarkColors];
    explIntenseFunctionColorWell.color = [colorSupport colorForKey: @"explIntenseFunction" isWindowDark: withDarkColors];
    explIntenseVariableColorWell.color = [colorSupport colorForKey: @"explIntenseVariable" isWindowDark: withDarkColors];
    explmykeyColorWell.color = [colorSupport colorForKey: @"explmykey" isWindowDark: withDarkColors];
    explmykeyArgumentColorWell.color = [colorSupport colorForKey: @"explmykeyArgument" isWindowDark: withDarkColors];
    explmsgColorWell.color = [colorSupport colorForKey: @"explmsg" isWindowDark: withDarkColors];
   
    
    EditorHighlightBracesColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"EditorHighlightBraces"];
    EditorHighlightContentColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"EditorHighlightContent"];
    EditorInvisibleCharColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"EditorInvisibleChar"];
    flashColor = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"EditorFlash"];
    if (flashColor != nil)
        EditorFlashColorWell.color = flashColor;
    else if (withDarkColors)
        // EditorFlashColorWell.color = [NSColor colorWithRed:0.00 green:0.20 blue:0.20 alpha:1.00];
        EditorFlashColorWell.color = [colorSupport darkColorAndAlphaWithKey: @"EditorFlash"];
    else
        // EditorFlashColorWell.color = [NSColor colorWithRed:1 green:0.95 blue:1 alpha:1];
        EditorFlashColorWell.color = [colorSupport liteColorAndAlphaWithKey: @"EditorFlash"];
    
    footnoteCol = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"FootnoteColor"];
    if (footnoteCol == nil)
        footnoteCol = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"SyntaxCommand"];
    FootnoteColorWell.color = footnoteCol;
/*
    else if (withDarkColors)
        // FootnoteColorWell.color = [NSColor colorWithRed:0.75 green:0.75 blue:0.75 alpha:1.00];
        FootnoteColorWell.color = [colorSupport darkColorAndAlphaWithKey: @"FootnoteColor"];
    else
        // FootnoteColorWell.color = [NSColor colorWithRed:0.35 green:0.35 blue:0.35 alpha:1];
        FootnoteColorWell.color = [colorSupport liteColorAndAlphaWithKey: @"FootnoteColor"];
 */
    
   EntryCol = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"EntryColor"];
    if (EntryCol != nil)
        EntryColorWell.color = EntryCol;
    else
        EntryColorWell.color = [colorSupport liteColorAndAlphaWithKey: @"EntryColor"];

        
    EditorReverseSyncColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"EditorReverseSync"];
    PreviewDirectSyncColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"PreviewDirectSync"];
    SourceAlphaColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"SourceAlpha"];
    PreviewAlphaColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"PreviewAlpha"];
    ConsoleAlphaColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"ConsoleAlpha"];
    ImageForegroundColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"ImageForeground"];
    ImageBackgroundColorWell.color = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"ImageBackground"];
    
    aColor = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"XMLComment"];
    if (aColor != nil)
        XMLCommentColorWell.color = aColor;
    else if (withDarkColors)
        XMLCommentColorWell.color = [colorSupport darkColorAndAlphaWithKey: @"XMLComment"];
    else
        XMLCommentColorWell.color = [colorSupport liteColorAndAlphaWithKey: @"XMLComment"];
    
    aColor = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"XMLTag"];
    if (aColor != nil)
        XMLTagColorWell.color = aColor;
    else if (withDarkColors)
        XMLTagColorWell.color = [colorSupport darkColorAndAlphaWithKey: @"XMLTag"];
    else
        XMLTagColorWell.color = [colorSupport liteColorAndAlphaWithKey: @"XMLTag"];
    
    aColor = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"XMLSpecial"];
    if (aColor != nil)
        XMLSpecialColorWell.color = aColor;
    else if (withDarkColors)
        XMLSpecialColorWell.color = [colorSupport darkColorAndAlphaWithKey: @"XMLSpecial"];
    else
        XMLSpecialColorWell.color = [colorSupport liteColorAndAlphaWithKey: @"XMLSpecial"];
    
    aColor = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"XMLParameter"];
    if (aColor != nil)
        XMLParameterColorWell.color = aColor;
    else if (withDarkColors)
        XMLParameterColorWell.color = [colorSupport darkColorAndAlphaWithKey: @"XMLParameter"];
    else
        XMLParameterColorWell.color = [colorSupport liteColorAndAlphaWithKey: @"XMLParameter"];
    
    aColor = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"XMLValue"];
    if (aColor != nil)
        XMLValueColorWell.color = aColor;
    else if (withDarkColors)
        XMLValueColorWell.color = [colorSupport darkColorAndAlphaWithKey: @"XMLValue"];
    else
        XMLValueColorWell.color = [colorSupport liteColorAndAlphaWithKey: @"XMLValue"];
       
    
}

- (IBAction)EditingStyleChoice:sender
{
    NSString *newEditingItem = [EditingStyle titleOfSelectedItem];
    
    // Create a new dictionary with the colors of this style
    // Fill in all the color wells with the colors of these items
    
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    EditingColors = [colorSupport dictionaryForColorFile: newEditingItem ];
    // [colorSupport initializeColors];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];
    [self FillInColorWells];
}

- (IBAction)SaveEditedStyle:sender
{
    NSString *theTitle = [EditingStyle titleOfSelectedItem];
    
    NSString *newColorPath = [ColorPath stringByExpandingTildeInPath];
    NSString* ourColorPath = [[[newColorPath stringByAppendingString:@"/"] stringByAppendingString: theTitle] stringByAppendingString: @".plist"];
    
    [EditingColors writeToFile: ourColorPath atomically: YES];
    
    
}

- (IBAction)NewStyleFromPrefs:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    NSInteger result;
    NSString *theTitle;
    NSMutableDictionary *prefsDictionary;
    
    result = [NSApp runModalForWindow: stylePanel];
    // [packageHelpPanel close];
    if (result == 0) {
        theTitle = [styleTitle stringValue];
        [stylePanel close];
    }
    else {
        [stylePanel close];
        return;
    }
    
    if ([theTitle isEqualToString:@""])
        return;
    theTitle = [theTitle stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([theTitle isEqualToString:@""])
        return;
    
    NSString *newColorPath = [ColorPath stringByExpandingTildeInPath];
    NSString* ourColorPath = [[[newColorPath stringByAppendingString:@"/"] stringByAppendingString: theTitle] stringByAppendingString: @".plist"];
    
    if ([fileManager fileExistsAtPath:ourColorPath])
    {
        // dialog asking if should overwrite existing file; return if NO; otherwise continue
        NSAlert *alert = [NSAlert alertWithMessageText:@"Alert" defaultButton:@"Continue" alternateButton:@"Cancel" otherButton:nil informativeTextWithFormat:NSLocalizedString(@"File already exists", @"File already exists")];
        result = [alert runModal];
        if (! result)
            return;
    }
    
    
    prefsDictionary = [NSMutableDictionary dictionaryWithCapacity:19];
    [prefsDictionary setObject: theTitle forKey:@"Title"];
     
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"EditorText" withRed: [SUD doubleForKey:foreground_RKey]
                                          Green: [SUD doubleForKey:foreground_GKey] Blue: [SUD doubleForKey:foreground_BKey] Alpha: 1.0];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"EditorBackground" withRed: [SUD doubleForKey:background_RKey]
                                      Green: [SUD doubleForKey:background_GKey] Blue: [SUD doubleForKey:background_BKey] Alpha: [SUD doubleForKey:backgroundAlphaKey]];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"LogText" withRed: [SUD doubleForKey:foreground_RKey]
                                      Green: [SUD doubleForKey:foreground_GKey] Blue: [SUD doubleForKey:foreground_BKey] Alpha: 1.0];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"LogBackground" withRed: [SUD doubleForKey:background_RKey]
                                      Green: [SUD doubleForKey:background_GKey] Blue: [SUD doubleForKey:background_BKey] Alpha: [SUD doubleForKey:backgroundAlphaKey]];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"ConsoleText" withRed: [SUD doubleForKey:ConsoleForegroundColor_RKey]
                                      Green: [SUD doubleForKey:ConsoleForegroundColor_GKey] Blue: [SUD doubleForKey:ConsoleForegroundColor_BKey] Alpha: 1.0];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"ConsoleBackground" withRed: [SUD doubleForKey:ConsoleBackgroundColor_RKey]
                                      Green: [SUD doubleForKey:ConsoleBackgroundColor_GKey] Blue: [SUD doubleForKey:ConsoleBackgroundColor_BKey] Alpha: [SUD doubleForKey:ConsoleBackgroundAlphaKey]];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"EditorInsertionPoint" withRed: [SUD doubleForKey:insertionpoint_RKey]
                                      Green: [SUD doubleForKey:insertionpoint_GKey] Blue: [SUD doubleForKey:insertionpoint_BKey] Alpha: 1.0];
    
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"SyntaxComment" withRed: [SUD doubleForKey:commentredKey]
                                      Green: [SUD doubleForKey:commentgreenKey] Blue: [SUD doubleForKey:commentblueKey] Alpha: 1.0];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"SyntaxCommand" withRed: [SUD doubleForKey:commandredKey]
                                      Green: [SUD doubleForKey:commandgreenKey] Blue: [SUD doubleForKey:commandblueKey] Alpha: 1.0];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"SyntaxMarker" withRed: [SUD doubleForKey:markerredKey]
                                      Green: [SUD doubleForKey:markergreenKey] Blue: [SUD doubleForKey:markerblueKey] Alpha: 1.0];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"SyntaxIndex" withRed: [SUD doubleForKey:indexredKey]
                                      Green: [SUD doubleForKey:indexgreenKey] Blue: [SUD doubleForKey:indexblueKey] Alpha: 1.0];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"FootnoteColor" withRed: 0.35
                                      Green: 0.35 Blue: 0.35 Alpha: 1.0];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"EntryColor" withRed: 0.9
                                      Green: 0.99 Blue: 0.99 Alpha: 1.0];
    
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"EditorHighlightBraces" withRed: [SUD doubleForKey:highlightBracesRedKey]
                                      Green: [SUD doubleForKey:highlightBracesGreenKey] Blue: [SUD doubleForKey:highlightBracesBlueKey] Alpha: 1.0];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"EditorHighlightContent" withRed: [SUD doubleForKey:highlightContentRedKey]
                                      Green: [SUD doubleForKey:highlightContentGreenKey] Blue: [SUD doubleForKey:highlightContentBlueKey] Alpha: 1.0];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"EditorInvisibleChar" withRed: [SUD doubleForKey:invisibleCharRedKey]
                                      Green: [SUD doubleForKey:invisibleCharGreenKey] Blue: [SUD doubleForKey:invisibleCharBlueKey] Alpha: 1.0];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"EditorFlash" withRed: 1.0 Green: 0.95 Blue: 1.0 Alpha:1.0];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"EditorReverseSync" withRed: [SUD doubleForKey:reverseSyncRedKey]
                                      Green: [SUD doubleForKey:reverseSyncGreenKey] Blue: [SUD doubleForKey:reverseSyncBlueKey] Alpha: 1.0];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"PreviewDirectSync" withRed: 1.0 Green: 1.0 Blue: 0.0 Alpha: 1.0];
    
    
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"PreviewBackground" withRed: [SUD doubleForKey:PdfPageBack_RKey]
                                      Green: [SUD doubleForKey:PdfPageBack_GKey] Blue: [SUD doubleForKey:PdfPageBack_BKey] Alpha: 1.0];
    
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"SourceAlpha" withRed: 1.0
                                      Green: 1.0 Blue: 1.0 Alpha: [SUD doubleForKey: SourceWindowAlphaKey]];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"PreviewAlpha" withRed: 1.0
                                      Green: 1.0  Blue: 2.0 Alpha: [SUD doubleForKey: PreviewWindowAlphaKey]];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"ConsoleAlpha" withRed: 1.0
                                      Green: 1.0 Blue: 1.0 Alpha: [SUD doubleForKey: ConsoleWindowAlphaKey]];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"ImageForeground" withRed: [SUD doubleForKey:PdfFore_RKey]
                                      Green: [SUD doubleForKey:PdfFore_GKey] Blue: [SUD doubleForKey:PdfFore_BKey]
                                      Alpha: [SUD doubleForKey:PdfFore_AKey]];
    [colorSupport setColorValueInDictionary: prefsDictionary forKey: @"ImageBackground" withRed: [SUD doubleForKey:PdfBack_RKey]
                                      Green: [SUD doubleForKey:PdfBack_GKey] Blue: [SUD doubleForKey:PdfBack_BKey]
                                      Alpha: [SUD doubleForKey:PdfBack_AKey]];
    
    
    [prefsDictionary writeToFile: ourColorPath atomically: YES];
    
    [LiteStyle addItemWithTitle: theTitle];
    [DarkStyle addItemWithTitle: theTitle];
    [EditingStyle addItemWithTitle: theTitle];
    [EditingStyle selectItemWithTitle: theTitle];

    
}



- (IBAction)SaveNewStyle:sender
{
    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSInteger result;
    NSString *theTitle;
    
    result = [NSApp runModalForWindow: stylePanel];
    // [packageHelpPanel close];
    if (result == 0) {
        theTitle = [styleTitle stringValue];
        [stylePanel close];
    }
    else {
        [stylePanel close];
        return;
    }
    
    if ([theTitle isEqualToString:@""])
        return;
    theTitle = [theTitle stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([theTitle isEqualToString:@""])
        return;
    
    NSString *newColorPath = [ColorPath stringByExpandingTildeInPath];
    NSString* ourColorPath = [[[newColorPath stringByAppendingString:@"/"] stringByAppendingString: theTitle] stringByAppendingString: @".plist"];
    
    if ([fileManager fileExistsAtPath:ourColorPath])
    {
        // dialog asking if should overwrite existing file; return if NO; otherwise continue
        NSAlert *alert = [NSAlert alertWithMessageText:@"Alert" defaultButton:@"Continue" alternateButton:@"Cancel" otherButton:nil informativeTextWithFormat:NSLocalizedString(@"File already exists", @"File already exists")];
        result = [alert runModal];
        if (! result)
            return;
    }
    
    
    [EditingColors setObject: theTitle forKey: @"Title"];
    [EditingColors writeToFile: ourColorPath atomically: YES];
    
    [LiteStyle addItemWithTitle: theTitle];
    [DarkStyle addItemWithTitle: theTitle];
    [EditingStyle addItemWithTitle: theTitle];
    [EditingStyle selectItemWithTitle: theTitle];
    
}

- (void) okForStylePanel: sender
{
    [NSApp stopModalWithCode: 0];
}

- (void) cancelForStylePanel: sender
{
    [NSApp stopModalWithCode:1];
}



// Actual Colors
- (IBAction)SourceTextColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"EditorText"];
        ((NSColorWell *)sender).color = oldColor;
    }

    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"EditorText" fromColorWell:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];
    
}

- (IBAction)SourceBackgroundColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"EditorBackground"];
        ((NSColorWell *)sender).color = oldColor;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"EditorBackground" fromColorWell:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];
    
}

- (IBAction)SourceInsertionPointColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"EditorInsertionPoint"];
        ((NSColorWell *)sender).color = oldColor;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"EditorInsertionPoint" fromColorWell:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];
    
}

- (IBAction)PreviewBackgroundColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"PreviewBackground"];
        ((NSColorWell *)sender).color = oldColor;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"PreviewBackground" fromColorWell:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object: self userInfo:EditingColors];
    
}

- (IBAction)ConsoleTextColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
   if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"ConsoleText"];
        ((NSColorWell *)sender).color = oldColor;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"ConsoleText" fromColorWell:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];
    
}

- (IBAction)ConsoleBackgroundColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"ConsoleBackground"];
        ((NSColorWell *)sender).color = oldColor;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"ConsoleBackground" fromColorWell:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];
    
}

- (IBAction)LogTextColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
   if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"LogText"];
        ((NSColorWell *)sender).color = oldColor;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"LogText" fromColorWell:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];
    
}

- (IBAction)LogBackgroundColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"LogBackground"];
        ((NSColorWell *)sender).color = oldColor;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"LogBackground" fromColorWell:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];
    
}


- (IBAction)SyntaxCommentColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"SyntaxComment"];
        ((NSColorWell *)sender).color = oldColor;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"SyntaxComment" fromColorWell:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];
    
}

- (IBAction)SyntaxCommandColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
   if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"SyntaxCommand"];
        ((NSColorWell *)sender).color = oldColor;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"SyntaxCommand" fromColorWell:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];
    
}

- (IBAction)SyntaxMarkerColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
   if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"SyntaxMarker"];
        ((NSColorWell *)sender).color = oldColor;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"SyntaxMarker" fromColorWell:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];
    
}

- (IBAction)SyntaxIndexColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"SyntaxIndex"];
        ((NSColorWell *)sender).color = oldColor;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"SyntaxIndex" fromColorWell:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];
    
}

- (IBAction)FootnoteColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"FootnoteColor"];
        if (oldColor != nil)
            ((NSColorWell *)sender).color = oldColor;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"FootnoteColor" fromColorWell:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];
    
}

- (IBAction)EntryColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"EntryColor"];
        if (oldColor != nil)
            ((NSColorWell *)sender).color = oldColor;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"EntryColor" fromColorWell:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];
    
}



- (IBAction)EditorReverseSyncChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"EditorReverseSync"];
        ((NSColorWell *)sender).color = oldColor;
    }
   [colorSupport changeColorValueInDictionary: EditingColors forKey: @"EditorReverseSync" fromColorWell:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];
    
}

- (IBAction)PreviewDirectSyncChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"PreviewDirectSync"];
        ((NSColorWell *)sender).color = oldColor;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"PreviewDirectSync" fromColorWell:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];
    
}


- (IBAction)EditorHighlightBracesChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"EditorHighlightBraces"];
        ((NSColorWell *)sender).color = oldColor;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"EditorHighlightBraces" fromColorWell:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];
    
}

- (IBAction)EditorHighlightContentChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
   if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"EditorHighlightContent"];
        ((NSColorWell *)sender).color = oldColor;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"EditorHighlightContent" fromColorWell:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];
    
}

- (IBAction)EditorInvisibleCharChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"EditorInvisibleChar"];
        ((NSColorWell *)sender).color = oldColor;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"EditorInvisibleChar" fromColorWell:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];
    
}

- (IBAction)EditorFlashChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"EditorFlash"];
        if (oldColor != nil)
            ((NSColorWell *)sender).color = oldColor;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"EditorFlash" fromColorWell:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];
    
}

- (IBAction)SourceAlphaChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"SourceAlpha"];
        ((NSColorWell *)sender).color = oldColor;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"SourceAlpha" fromColorWell:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];
    
}

- (IBAction)PreviewAlphaChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
   if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"PreviewAlpha"];
        ((NSColorWell *)sender).color = oldColor;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"PreviewAlpha" fromColorWell:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];
    
}

- (IBAction)ConsoleAlphaChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorAndAlphaFromDictionary:EditingColors andKey: @"ConsoleAlpha"];
        ((NSColorWell *)sender).color = oldColor;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"ConsoleAlpha" fromColorWell:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];
    
}

- (IBAction)ImageForegroundChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"ImageForeground"];
        ((NSColorWell *)sender).color = oldColor;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"ImageForeground" fromColorWell:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];
    
}

- (IBAction)ImageBackgroundChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"ImageBackground"];
        ((NSColorWell *)sender).color = oldColor;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"ImageBackground" fromColorWell:sender];
     [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];
    
}

- (IBAction)XMLCommentChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"XMLComment"];
        ((NSColorWell *)sender).color = oldColor;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"XMLComment" fromColorWell:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];
    
}

- (IBAction)XMLTagChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"XMLTag"];
        ((NSColorWell *)sender).color = oldColor;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"XMLTag" fromColorWell:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];
    
}

- (IBAction)XMLSpecialChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"XMLSpecial"];
        ((NSColorWell *)sender).color = oldColor;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"XMLSpecial" fromColorWell:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];
    
}

- (IBAction)XMLParameterChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"XMLParameter"];
        ((NSColorWell *)sender).color = oldColor;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"XMLParameter" fromColorWell:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];
    
}

- (IBAction)XMLValueChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"XMLValue"];
        ((NSColorWell *)sender).color = oldColor;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"XMLValue" fromColorWell:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];
    
}

- (IBAction)explFunctionColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"explFunction"];
        ((NSColorWell *)sender).color = oldColor;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"explFunction" fromColorWell:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];

}

- (IBAction)markerParenColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"SyntaxMarkerParen"];
        ((NSColorWell *)sender).color = oldColor;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"SyntaxMarkerParen" fromColorWell:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];

}

- (IBAction)markerCurlyColorChanged:sender
{
    
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"SyntaxMarkerCurly"];
        ((NSColorWell *)sender).color = oldColor;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"SyntaxMarkerCurly" fromColorWell:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];

}

- (IBAction)markerSquareColorChanged:sender
{
    
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"SyntaxMarkerSquare"];
        ((NSColorWell *)sender).color = oldColor;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"SyntaxMarkerSquare" fromColorWell:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];

}



- (IBAction)explVariableColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"explVariable"];
        ((NSColorWell *)sender).color = oldColor;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"explVariable" fromColorWell:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];

}

- (IBAction)explIntenseFunctionColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"explIntenseFunction"];
        ((NSColorWell *)sender).color = oldColor;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"explIntenseFunction" fromColorWell:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];

}

- (IBAction)explIntenseVariableColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"explIntenseVariable"];
        ((NSColorWell *)sender).color = oldColor;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"explIntenseVariable" fromColorWell:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];

}

- (IBAction)explmykeyColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"explmykey"];
        ((NSColorWell *)sender).color = oldColor;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"explmykey" fromColorWell:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];

}

- (IBAction)explmykeyArgumentColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
    
    if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"explmykeyArgument"];
        ((NSColorWell *)sender).color = oldColor;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"explmykeyArgument" fromColorWell:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];

}

- (IBAction)explmsgColorChanged:sender
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];

    if ((! _prefsWindow.keyWindow ) && (! [NSColorPanel sharedColorPanel].keyWindow))
    {
        [[NSColorPanel sharedColorPanel] close];
        NSColor *oldColor = [colorSupport colorFromDictionary:EditingColors andKey: @"explmsg"];
        ((NSColorWell *)sender).color = oldColor;
    }
    [colorSupport changeColorValueInDictionary: EditingColors forKey: @"explmsg" fromColorWell:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:SourceColorChangedNotification object:self userInfo: EditingColors];

}


- (IBAction)revealThemesFolder:sender
{
    NSString *dir = [ColorPath stringByExpandingTildeInPath];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (! [fm fileExistsAtPath: dir]) {
        [fm createDirectoryAtPath: dir withIntermediateDirectories: YES attributes: nil error: nil];
    }
    [[NSWorkspace sharedWorkspace] openURL: [NSURL fileURLWithPath: dir isDirectory: YES]];
}


// Validate a plist at url: must parse as a dictionary and must define EditorBackground.
// Keeps garbage (or theme files for unrelated apps) out of the themes folder.
- (BOOL)looksLikeThemeAtPath:(NSString *)path
{
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile: path];
    return (d != nil) && ([d objectForKey: @"EditorBackground"] != nil);
}


- (IBAction)installThemeFromFile:sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = NO;
    panel.canChooseDirectories = NO;
    panel.canChooseFiles = YES;
    panel.allowedFileTypes = @[@"plist", @"json"];
    panel.message = NSLocalizedString(@"Choose a theme file (.plist or VS Code .json) to install.",
                                      @"Install theme open panel prompt");

    [panel beginSheetModalForWindow: _prefsWindow
                  completionHandler: ^(NSModalResponse result) {
        if (result != NSModalResponseOK) return;
        NSURL *chosen = panel.URLs.firstObject;
        if (! chosen) return;

        NSString *ext = [chosen.pathExtension lowercaseString];
        NSString *installedPath = nil;

        if ([ext isEqualToString: @"json"]) {
            NSError *err = nil;
            installedPath = [TSVSCodeThemeImporter importJSONFileAtPath: chosen.path error: &err];
            if (! installedPath) {
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = NSLocalizedString(@"Could not import theme", @"Import failure title");
                alert.informativeText = err.localizedDescription ?: @"";
                [alert runModal];
                return;
            }
        } else {
            // Plist path — validate, then copy (or replace, with confirmation).
            if (! [self looksLikeThemeAtPath: chosen.path]) {
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = NSLocalizedString(@"Not a TeXForge theme", @"Not-a-theme title");
                alert.informativeText = NSLocalizedString(@"The selected .plist does not contain an EditorBackground entry.",
                                                         @"Not-a-theme body");
                [alert runModal];
                return;
            }
            NSString *dir = [ColorPath stringByExpandingTildeInPath];
            NSString *destPath = [dir stringByAppendingPathComponent: chosen.lastPathComponent];
            NSFileManager *fm = [NSFileManager defaultManager];
            if ([fm fileExistsAtPath: destPath]) {
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = NSLocalizedString(@"Replace existing theme?", @"Replace confirmation");
                alert.informativeText = [NSString stringWithFormat:
                    NSLocalizedString(@"A theme named \"%@\" already exists. Replace it?", @"Replace body"),
                    [chosen.lastPathComponent stringByDeletingPathExtension]];
                [alert addButtonWithTitle: NSLocalizedString(@"Replace", @"")];
                [alert addButtonWithTitle: NSLocalizedString(@"Cancel", @"")];
                if ([alert runModal] != NSAlertFirstButtonReturn) return;
                [fm removeItemAtPath: destPath error: nil];
            }
            NSError *err = nil;
            if (! [fm copyItemAtPath: chosen.path toPath: destPath error: &err]) {
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = NSLocalizedString(@"Could not install theme", @"Copy failure title");
                alert.informativeText = err.localizedDescription ?: @"";
                [alert runModal];
                return;
            }
            installedPath = destPath;
        }

        [self refreshThemePopups];

        NSString *newTitle = [installedPath.lastPathComponent stringByDeletingPathExtension];
        if ([EditingStyle itemWithTitle: newTitle]) {
            [EditingStyle selectItemWithTitle: newTitle];
            [self EditingStyleChoice: EditingStyle];
        }
    }];
}


@end
