//
//  TSVSCodeThemeImporter.m
//  TeXForge
//

#import "TSVSCodeThemeImporter.h"
#import "globals.h"

static NSString * const TSVSCodeImporterErrorDomain = @"TSVSCodeThemeImporter";

#pragma mark - Helpers

// VS Code theme JSON files routinely contain // and /* */ comments, which strict
// JSON rejects. Strip them. Respects strings so tokens inside "..." stay intact.
static NSString *TSStripJSONComments(NSString *input)
{
    NSUInteger len = input.length;
    NSMutableString *out = [NSMutableString stringWithCapacity: len];
    BOOL inString = NO;
    unichar stringDelim = 0;

    for (NSUInteger i = 0; i < len; i++) {
        unichar c = [input characterAtIndex: i];

        if (inString) {
            [out appendFormat: @"%C", c];
            if (c == '\\' && i + 1 < len) {
                [out appendFormat: @"%C", [input characterAtIndex: ++i]];
            } else if (c == stringDelim) {
                inString = NO;
            }
            continue;
        }

        if (c == '"' || c == '\'') {
            inString = YES;
            stringDelim = c;
            [out appendFormat: @"%C", c];
            continue;
        }

        if (c == '/' && i + 1 < len) {
            unichar next = [input characterAtIndex: i + 1];
            if (next == '/') {
                // Line comment — skip to newline.
                i += 2;
                while (i < len && [input characterAtIndex: i] != '\n') i++;
                if (i < len) [out appendFormat: @"%C", [input characterAtIndex: i]];
                continue;
            }
            if (next == '*') {
                // Block comment — skip to closing */
                i += 2;
                while (i + 1 < len && ! ([input characterAtIndex: i] == '*' && [input characterAtIndex: i + 1] == '/')) {
                    i++;
                }
                i++;
                continue;
            }
        }

        [out appendFormat: @"%C", c];
    }

    return out;
}

// VS Code uses #RGB, #RRGGBB, #RRGGBBAA. Returns a 4-element NSArray of doubles
// (0..1) matching the format every TeXForge theme plist uses, or nil on failure.
static NSArray<NSNumber *> * _Nullable TSParseHexColor(NSString *hex)
{
    if (! [hex isKindOfClass: [NSString class]]) return nil;
    hex = [hex stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([hex hasPrefix: @"#"]) hex = [hex substringFromIndex: 1];

    NSString *r, *g, *b, *a;
    if (hex.length == 3) {
        // #RGB -> expand each nibble
        r = [NSString stringWithFormat: @"%C%C", [hex characterAtIndex: 0], [hex characterAtIndex: 0]];
        g = [NSString stringWithFormat: @"%C%C", [hex characterAtIndex: 1], [hex characterAtIndex: 1]];
        b = [NSString stringWithFormat: @"%C%C", [hex characterAtIndex: 2], [hex characterAtIndex: 2]];
        a = @"FF";
    } else if (hex.length == 6) {
        r = [hex substringWithRange: NSMakeRange(0, 2)];
        g = [hex substringWithRange: NSMakeRange(2, 2)];
        b = [hex substringWithRange: NSMakeRange(4, 2)];
        a = @"FF";
    } else if (hex.length == 8) {
        r = [hex substringWithRange: NSMakeRange(0, 2)];
        g = [hex substringWithRange: NSMakeRange(2, 2)];
        b = [hex substringWithRange: NSMakeRange(4, 2)];
        a = [hex substringWithRange: NSMakeRange(6, 2)];
    } else {
        return nil;
    }

    unsigned int ri = 0, gi = 0, bi = 0, ai = 0;
    if (! [[NSScanner scannerWithString: r] scanHexInt: &ri]) return nil;
    if (! [[NSScanner scannerWithString: g] scanHexInt: &gi]) return nil;
    if (! [[NSScanner scannerWithString: b] scanHexInt: &bi]) return nil;
    if (! [[NSScanner scannerWithString: a] scanHexInt: &ai]) return nil;

    return @[@(ri / 255.0), @(gi / 255.0), @(bi / 255.0), @(ai / 255.0)];
}

// Sanitize a display name for use as a filename basename. Keeps alphanumerics,
// space, dash, underscore, dot; collapses everything else to '-'.
static NSString *TSSanitizeThemeBasename(NSString *raw)
{
    if (raw.length == 0) return @"Imported Theme";
    NSMutableString *clean = [NSMutableString stringWithCapacity: raw.length];
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 -_."];
    for (NSUInteger i = 0; i < raw.length; i++) {
        unichar c = [raw characterAtIndex: i];
        if ([allowed characterIsMember: c]) {
            [clean appendFormat: @"%C", c];
        } else {
            [clean appendString: @"-"];
        }
    }
    NSString *trimmed = [clean stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
    return trimmed.length ? trimmed : @"Imported Theme";
}

// VS Code scopes can be a string or an array of strings. Normalize to array.
static NSArray<NSString *> *TSNormalizeScopes(id scope)
{
    if ([scope isKindOfClass: [NSString class]]) {
        // Scopes can also be comma-separated.
        NSArray *parts = [(NSString *)scope componentsSeparatedByString: @","];
        NSMutableArray *out = [NSMutableArray arrayWithCapacity: parts.count];
        for (NSString *p in parts) {
            NSString *t = [p stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (t.length) [out addObject: t];
        }
        return out;
    }
    if ([scope isKindOfClass: [NSArray class]]) {
        return (NSArray *)scope;
    }
    return @[];
}

// Walk tokenColors looking for the first entry that matches any of the requested
// TextMate scope prefixes. "Match" means the scope string starts with the prefix
// (so "keyword.control" matches "keyword" and "keyword.control.import" matches
// "keyword.control"). Returns the hex color string from settings.foreground, or nil.
static NSString * _Nullable TSFindTokenColor(NSArray *tokenColors, NSArray<NSString *> *scopePrefixes)
{
    for (NSString *prefix in scopePrefixes) {
        for (NSDictionary *entry in tokenColors) {
            if (! [entry isKindOfClass: [NSDictionary class]]) continue;
            NSDictionary *settings = entry[@"settings"];
            NSString *fg = [settings isKindOfClass: [NSDictionary class]] ? settings[@"foreground"] : nil;
            if (! [fg isKindOfClass: [NSString class]]) continue;

            NSArray *scopes = TSNormalizeScopes(entry[@"scope"]);
            for (NSString *scope in scopes) {
                if ([scope isEqualToString: prefix] ||
                    [scope hasPrefix: [prefix stringByAppendingString: @"."]])
                {
                    return fg;
                }
            }
        }
    }
    return nil;
}

// Simple luminance test for deciding dark vs light when the theme's "type" field is missing.
static BOOL TSColorIsDark(NSArray<NSNumber *> *rgba)
{
    if (rgba.count < 3) return NO;
    double r = [rgba[0] doubleValue];
    double g = [rgba[1] doubleValue];
    double b = [rgba[2] doubleValue];
    double luminance = 0.299 * r + 0.587 * g + 0.114 * b;
    return luminance < 0.5;
}

#pragma mark - Mapping

// Assign an [R,G,B,A] value to key in dest, parsing a hex string. If hex is nil or unparseable,
// copy the fallback (another key already in dest, or a hardcoded default).
static void TSAssign(NSMutableDictionary *dest, NSString *key, NSString * _Nullable hex, NSArray<NSNumber *> * _Nullable fallback)
{
    NSArray<NSNumber *> *rgba = TSParseHexColor(hex);
    if (rgba) {
        dest[key] = rgba;
        return;
    }
    if (fallback) {
        dest[key] = fallback;
    }
}

@implementation TSVSCodeThemeImporter

+ (nullable NSString *)importJSONFileAtPath:(NSString *)jsonPath
                                      error:(NSError * _Nullable * _Nullable)error
{
    NSString *raw = [NSString stringWithContentsOfFile: jsonPath
                                              encoding: NSUTF8StringEncoding
                                                 error: error];
    if (! raw) return nil;

    NSString *stripped = TSStripJSONComments(raw);
    NSData *data = [stripped dataUsingEncoding: NSUTF8StringEncoding];
    id parsed = [NSJSONSerialization JSONObjectWithData: data options: 0 error: error];
    if (! [parsed isKindOfClass: [NSDictionary class]]) {
        if (error && ! *error) {
            *error = [NSError errorWithDomain: TSVSCodeImporterErrorDomain
                                         code: 1
                                     userInfo: @{NSLocalizedDescriptionKey: @"Theme file is not a JSON object."}];
        }
        return nil;
    }
    NSDictionary *theme = (NSDictionary *)parsed;

    NSDictionary *colors = [theme[@"colors"] isKindOfClass: [NSDictionary class]] ? theme[@"colors"] : @{};
    NSArray *tokenColors = [theme[@"tokenColors"] isKindOfClass: [NSArray class]] ? theme[@"tokenColors"] : @[];

    // Name / title
    NSString *displayName = [theme[@"name"] isKindOfClass: [NSString class]] ? theme[@"name"] : nil;
    if (displayName.length == 0) {
        displayName = [[jsonPath lastPathComponent] stringByDeletingPathExtension];
    }
    NSString *basename = TSSanitizeThemeBasename(displayName);

    // Dark vs light — affects which fallback defaults we use.
    NSString *typeField = [theme[@"type"] isKindOfClass: [NSString class]] ? theme[@"type"] : nil;
    NSArray<NSNumber *> *bg = TSParseHexColor(colors[@"editor.background"]);
    BOOL isDark;
    if ([typeField isEqualToString: @"dark"]) isDark = YES;
    else if ([typeField isEqualToString: @"light"]) isDark = NO;
    else isDark = TSColorIsDark(bg);

    NSArray<NSNumber *> *defaultBg = isDark ? @[@0.11, @0.12, @0.16, @1.0] : @[@1.0, @1.0, @1.0, @1.0];
    NSArray<NSNumber *> *defaultFg = isDark ? @[@0.96, @0.96, @0.94, @1.0] : @[@0.0, @0.0, @0.0, @1.0];
    NSArray<NSNumber *> *grey      = @[@0.5, @0.5, @0.5, @1.0];

    NSMutableDictionary *dest = [NSMutableDictionary dictionary];
    dest[@"Title"] = displayName;

    // Editor / UI
    TSAssign(dest, @"EditorBackground",        colors[@"editor.background"],                            defaultBg);
    TSAssign(dest, @"EditorText",              colors[@"editor.foreground"],                            defaultFg);
    TSAssign(dest, @"EditorInsertionPoint",    colors[@"editorCursor.foreground"],                      dest[@"EditorText"]);
    TSAssign(dest, @"EditorInvisibleChar",     colors[@"editorWhitespace.foreground"],                  grey);
    TSAssign(dest, @"EditorFlash",             colors[@"editor.findMatchHighlightBackground"],          isDark ? @[@0.0, @0.2, @0.2, @1.0] : @[@1.0, @0.95, @1.0, @1.0]);

    NSString *braceBg = colors[@"editorBracketMatch.background"];
    if (! [braceBg isKindOfClass: [NSString class]]) braceBg = colors[@"editor.selectionBackground"];
    TSAssign(dest, @"EditorHighlightBraces",   braceBg,                                                  isDark ? @[@1.0, @0.64, @0.01, @1.0] : @[@0.9, @0.9, @0.0, @1.0]);
    TSAssign(dest, @"EditorHighlightContent",  braceBg,                                                  dest[@"EditorHighlightBraces"]);

    TSAssign(dest, @"EditorReverseSync",       colors[@"editor.wordHighlightBackground"],               isDark ? @[@0.99, @0.23, @0.27, @1.0] : @[@1.0, @0.4, @0.4, @1.0]);

    // Preview / log / console surfaces — the PDF preview should stay light so page contents remain legible.
    dest[@"PreviewBackground"] = @[@1.0, @1.0, @1.0, @1.0];
    TSAssign(dest, @"PreviewDirectSync",       colors[@"editor.selectionBackground"],                   @[@1.0, @1.0, @0.0, @0.6]);
    dest[@"PreviewAlpha"] = dest[@"EditorBackground"];
    dest[@"SourceAlpha"]  = dest[@"EditorText"];
    dest[@"LogBackground"]    = dest[@"EditorBackground"];
    dest[@"LogText"]          = dest[@"EditorText"];

    NSString *termBg = colors[@"terminal.background"];
    NSString *termFg = colors[@"terminal.foreground"];
    TSAssign(dest, @"ConsoleBackground",       termBg,                                                  dest[@"EditorBackground"]);
    TSAssign(dest, @"ConsoleText",             termFg,                                                  dest[@"EditorText"]);
    dest[@"ConsoleAlpha"] = dest[@"EditorText"];

    dest[@"ImageForeground"] = @[@0, @0, @0, @0];
    dest[@"ImageBackground"] = @[@0, @0, @0, @0];

    // Syntax — map LaTeX semantics onto TextMate scopes.
    NSString *commentColor = TSFindTokenColor(tokenColors, @[@"comment"]);
    NSString *commandColor = TSFindTokenColor(tokenColors, @[@"keyword.control", @"keyword", @"storage.type", @"storage", @"support.function"]);
    NSString *indexColor   = TSFindTokenColor(tokenColors, @[@"entity.name.type", @"entity.name.class", @"support.class", @"support.type", @"entity.name.function"]);
    NSString *markerColor  = TSFindTokenColor(tokenColors, @[@"keyword.operator", @"punctuation.definition", @"punctuation"]);
    NSString *stringColor  = TSFindTokenColor(tokenColors, @[@"string"]);

    TSAssign(dest, @"SyntaxComment",  commentColor, grey);
    TSAssign(dest, @"SyntaxCommand",  commandColor, defaultFg);
    TSAssign(dest, @"SyntaxIndex",    indexColor,   dest[@"SyntaxCommand"]);
    TSAssign(dest, @"SyntaxMarker",   markerColor,  dest[@"SyntaxCommand"]);

    // Bracket-specific marker colors fall back to SyntaxMarker if the theme doesn't differentiate.
    dest[@"SyntaxMarkerParen"]  = dest[@"SyntaxMarker"];
    dest[@"SyntaxMarkerCurly"]  = dest[@"SyntaxMarker"];
    dest[@"SyntaxMarkerSquare"] = dest[@"SyntaxMarker"];

    // Misc TeXForge-specific keys.
    TSAssign(dest, @"FootnoteColor", commandColor, dest[@"SyntaxCommand"]);
    dest[@"EntryColor"] = isDark ? @[@0.1, @0.01, @0.01, @1.0] : @[@0.9, @0.99, @0.99, @1.0];

    // XML highlighting — reuse tag/string/attribute scopes.
    NSString *xmlTag   = TSFindTokenColor(tokenColors, @[@"entity.name.tag"]);
    NSString *xmlAttr  = TSFindTokenColor(tokenColors, @[@"entity.other.attribute-name"]);
    NSString *xmlValue = stringColor;
    TSAssign(dest, @"XMLComment",   commentColor, grey);
    TSAssign(dest, @"XMLTag",       xmlTag,       dest[@"SyntaxCommand"]);
    TSAssign(dest, @"XMLSpecial",   markerColor,  dest[@"SyntaxMarker"]);
    TSAssign(dest, @"XMLParameter", xmlAttr,      dest[@"SyntaxIndex"]);
    TSAssign(dest, @"XMLValue",     xmlValue,     dest[@"SyntaxCommand"]);

    // Write to ~/Library/TeXForge/Themes/<Name>.plist, picking a non-colliding name if needed.
    NSString *userThemesDir = [ColorPath stringByExpandingTildeInPath];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (! [fm fileExistsAtPath: userThemesDir]) {
        [fm createDirectoryAtPath: userThemesDir withIntermediateDirectories: YES attributes: nil error: nil];
    }

    NSString *destPath = [[userThemesDir stringByAppendingPathComponent: basename] stringByAppendingPathExtension: @"plist"];
    NSUInteger suffix = 2;
    while ([fm fileExistsAtPath: destPath]) {
        NSString *candidate = [NSString stringWithFormat: @"%@ %lu", basename, (unsigned long)suffix++];
        destPath = [[userThemesDir stringByAppendingPathComponent: candidate] stringByAppendingPathExtension: @"plist"];
    }

    if (! [dest writeToFile: destPath atomically: YES]) {
        if (error) {
            *error = [NSError errorWithDomain: TSVSCodeImporterErrorDomain
                                         code: 2
                                     userInfo: @{NSLocalizedDescriptionKey: @"Could not write theme plist."}];
        }
        return nil;
    }

    return destPath;
}

@end
