//
//  TSVSCodeThemeImporter.h
//  TeXForge
//
//  Converts a VS Code color theme JSON file into a TeXForge .plist theme and
//  writes it into ~/Library/TeXForge/Themes/. Only a local JSON file is read;
//  this importer does not touch the network.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSVSCodeThemeImporter : NSObject

// Import a local VS Code .json theme. Returns the absolute path of the written
// .plist on success, or nil on failure (with *error populated).
+ (nullable NSString *)importJSONFileAtPath:(NSString *)jsonPath
                                      error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
