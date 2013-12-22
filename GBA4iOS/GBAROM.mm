//
//  GBAROM.m
//  GBA4iOS
//
//  Created by Riley Testut on 8/23/13.
//  Copyright (c) 2013 Riley Testut. All rights reserved.
//

#import "GBAROM_Private.h"
#import "FileSHA1Hash.h"

#if !(TARGET_IPHONE_SIMULATOR)
#import "GBAEmulatorCore.h"
#endif

#import <SSZipArchive/minizip/SSZipArchive.h>

@interface GBAROM ()

@property (readwrite, copy, nonatomic) NSString *filepath;
@property (readwrite, assign, nonatomic) GBAROMType type;

@end

@implementation GBAROM

+ (GBAROM *)romWithContentsOfFile:(NSString *)filepath
{
    if (![[NSFileManager defaultManager] fileExistsAtPath:filepath] || !([[[filepath pathExtension] lowercaseString] isEqualToString:@"gb"] || [[[filepath pathExtension] lowercaseString] isEqualToString:@"gbc"] || [[[filepath pathExtension] lowercaseString] isEqualToString:@"gba"]))
    {
        return nil;
    }
    
    GBAROM *rom = [[GBAROM alloc] init];
    rom.filepath = filepath;
    
    if ([[[filepath pathExtension] lowercaseString] isEqualToString:@"gb"] || [[[filepath pathExtension] lowercaseString] isEqualToString:@"gbc"])
    {
        rom.type = GBAROMTypeGBC;
    }
    else
    {
        rom.type = GBAROMTypeGBA;
    }
    
    return rom;
}

+ (GBAROM *)romWithName:(NSString *)name
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    
    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:documentsDirectory error:nil];
    
    for (NSString *filename in contents)
    {
        if (!([[[filename pathExtension] lowercaseString] isEqualToString:@"gb"] || [[[filename pathExtension] lowercaseString] isEqualToString:@"gbc"] || [[[filename pathExtension] lowercaseString] isEqualToString:@"gba"]))
        {
            continue;
        }
        
        if ([[filename stringByDeletingPathExtension] isEqualToString:name])
        {
            return [GBAROM romWithContentsOfFile:[documentsDirectory stringByAppendingPathComponent:filename]];
        }
    }
    
    return nil;
}

+ (GBAROM *)romWithUniqueName:(NSString *)uniqueName
{
    NSMutableDictionary *cachedROMs = [NSMutableDictionary dictionaryWithContentsOfFile:[GBAROM cachedROMsPath]];
    
    __block NSString *romFilename = nil;
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    
    [cachedROMs enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *cachedUniqueName, BOOL *stop) {
        if ([uniqueName isEqualToString:cachedUniqueName])
        {
            NSString *cachedFilepath = [documentsDirectory stringByAppendingPathComponent:key];
            
            if (![[NSFileManager defaultManager] fileExistsAtPath:cachedFilepath])
            {
                [cachedROMs removeObjectForKey:key];
                [cachedROMs writeToFile:[self cachedROMsPath] atomically:YES];
                return;
            }
            
            romFilename = key;
            *stop = YES;
        }
    }];
    
    if (romFilename == nil)
    {
        return nil;
    }
    
    return [GBAROM romWithContentsOfFile:[documentsDirectory stringByAppendingPathComponent:romFilename]];
}

+ (BOOL)unzipROMAtPathToROMDirectory:(NSString *)filepath withPreferredROMTitle:(NSString *)preferredName error:(NSError **)error
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    
    NSString *name = [[filepath lastPathComponent] stringByDeletingPathExtension];
    NSString *tempDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    
    [[NSFileManager defaultManager] createDirectoryAtPath:tempDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    
    [SSZipArchive unzipFileAtPath:filepath toDestination:tempDirectory];

    NSString *romFilename = nil;
    NSString *extension = nil;
    
    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:tempDirectory error:nil];
    
    for (NSString *filename in contents)
    {
        if ([[[filename pathExtension] lowercaseString] isEqualToString:@"gba"] || [[[filename pathExtension] lowercaseString] isEqualToString:@"gbc"] ||
            [[[filename pathExtension] lowercaseString] isEqualToString:@"gb"])
        {
            romFilename = [filename stringByDeletingPathExtension];
            extension = [filename pathExtension];
            break;
        }
    }
    
    if (romFilename == nil)
    {
        *error = [NSError errorWithDomain:@"com.rileytestut.GBA4iOS" code:NSFileReadNoSuchFileError userInfo:nil];
        
        [[NSFileManager defaultManager] removeItemAtPath:tempDirectory error:nil];
        
        return NO; // zip file invalid
    }
    
    if (preferredName == nil)
    {
        preferredName = romFilename;
    }
    
    GBAROM *rom = [GBAROM romWithContentsOfFile:[tempDirectory stringByAppendingPathComponent:[romFilename stringByAppendingPathExtension:extension]]];
    NSString *uniqueName = rom.uniqueName;
    
    __block NSMutableDictionary *cachedROMs = [NSMutableDictionary dictionaryWithContentsOfFile:[self cachedROMsPath]];
    
    GBAROM *cachedROM = [GBAROM romWithUniqueName:uniqueName];
    
    if (cachedROM)
    {
        *error = [NSError errorWithDomain:@"com.rileytestut.GBA4iOS" code:NSFileWriteFileExistsError userInfo:nil];
        
        [[NSFileManager defaultManager] removeItemAtPath:tempDirectory error:nil];
        
        return NO;
    }
    
    // Check if another rom happens to have the same name as this ROM
    
    BOOL romNameIsTaken = (cachedROMs[[rom.filepath lastPathComponent]] != nil);
    
    if (romNameIsTaken)
    {
        *error = [NSError errorWithDomain:@"com.rileytestut.GBA4iOS" code:NSFileWriteInvalidFileNameError userInfo:nil];
        
        [[NSFileManager defaultManager] removeItemAtPath:tempDirectory error:nil];
        
        return NO;
    }
    
    NSString *originalFilename = [romFilename stringByAppendingPathExtension:extension];
    NSString *destinationFilename = [preferredName stringByAppendingPathExtension:extension];
    
    [[NSFileManager defaultManager] moveItemAtPath:[tempDirectory stringByAppendingPathComponent:originalFilename] toPath:[documentsDirectory stringByAppendingPathComponent:destinationFilename] error:nil];
    
    [[NSFileManager defaultManager] removeItemAtPath:tempDirectory error:nil];
    
    return YES;
}

- (BOOL)isEqual:(id)object
{
    if (![object isKindOfClass:[GBAROM class]])
    {
        return NO;
    }
    
    GBAROM *otherROM = (GBAROM *)object;
    
    return [self.uniqueName isEqualToString:otherROM.uniqueName]; // Use names, not filepaths, to compare
}

- (NSUInteger)hash
{
    return [self.filepath hash];
}

#pragma mark - Helper Methods

- (NSString *)dropboxSyncDirectoryPath
{
    NSString *libraryDirectory = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) lastObject];
    NSString *dropboxDirectory = [libraryDirectory stringByAppendingPathComponent:@"Dropbox Sync"];
    
    [[NSFileManager defaultManager] createDirectoryAtPath:dropboxDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    
    return dropboxDirectory;
}

- (NSString *)conflictedROMsPath
{
    return [[self dropboxSyncDirectoryPath] stringByAppendingPathComponent:@"conflictedROMs.plist"];
}

- (NSString *)syncingDisabledROMsPath
{
    return [[self dropboxSyncDirectoryPath] stringByAppendingPathComponent:@"syncingDisabledROMs.plist"];
}

+ (NSString *)cachedROMsPath
{
    NSString *libraryDirectory = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) lastObject];
    return [libraryDirectory stringByAppendingPathComponent:@"cachedROMs.plist"];
}

#pragma mark - Getters/Setters

- (NSString *)name
{
    return [[self.filepath lastPathComponent] stringByDeletingPathExtension];
}

- (NSString *)saveFileFilepath
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    
    return [documentsDirectory stringByAppendingPathComponent:[self.name stringByAppendingPathExtension:@"sav"]];
}

- (void)setSyncingDisabled:(BOOL)syncingDisabled
{
    NSMutableSet *syncingDisabledROMs = [NSMutableSet setWithArray:[NSArray arrayWithContentsOfFile:[self syncingDisabledROMsPath]]];
    
    if (syncingDisabledROMs == nil)
    {
        syncingDisabledROMs = [NSMutableSet set];
    }
    
    if (syncingDisabled)
    {
        [syncingDisabledROMs addObject:self.name];
    }
    else
    {
        [syncingDisabledROMs removeObject:self.name];
    }
    
    [[syncingDisabledROMs allObjects] writeToFile:[self syncingDisabledROMsPath] atomically:YES];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:GBAROMSyncingDisabledStateChangedNotification object:self];
    
}

- (BOOL)syncingDisabled
{
    NSMutableSet *disabledROMs = [NSMutableSet setWithArray:[NSArray arrayWithContentsOfFile:[self syncingDisabledROMsPath]]];
    return [disabledROMs containsObject:self.name];
}

- (void)setConflicted:(BOOL)conflicted
{
    NSMutableSet *conflictedROMs = [NSMutableSet setWithArray:[NSArray arrayWithContentsOfFile:[self conflictedROMsPath]]];
    
    if (conflictedROMs == nil)
    {
        conflictedROMs = [NSMutableSet set];
    }
    
    BOOL previouslyConflicted = [conflictedROMs containsObject:self.name];
    
    if (previouslyConflicted == conflicted)
    {
        return;
    }
    
    if (conflicted)
    {
        [conflictedROMs addObject:self.name];
        [self setNewlyConflicted:YES];
    }
    else
    {
        [conflictedROMs removeObject:self.name];
        [self setNewlyConflicted:NO];
    }
    
    [[conflictedROMs allObjects] writeToFile:[self conflictedROMsPath] atomically:YES];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:GBAROMConflictedStateChangedNotification object:self];
}

- (BOOL)conflicted
{
    NSMutableSet *conflictedROMs = [NSMutableSet setWithArray:[NSArray arrayWithContentsOfFile:[self conflictedROMsPath]]];
    return [conflictedROMs containsObject:self.name];
}

- (BOOL)newlyConflicted
{
    if (![self conflicted])
    {
        [self setNewlyConflicted:NO];
        
        return NO;
    }
    
    NSSet *newlyConflictedROMs = [NSSet setWithArray:[[NSUserDefaults standardUserDefaults] arrayForKey:@"newlyConflictedROMs"]];
    
    return [newlyConflictedROMs containsObject:self.name];
}

- (void)setNewlyConflicted:(BOOL)newlyConflicted
{
    NSMutableSet *newlyConflictedROMs = [NSMutableSet setWithArray:[[NSUserDefaults standardUserDefaults] arrayForKey:@"newlyConflictedROMs"]];
    
    if (newlyConflictedROMs == nil)
    {
        newlyConflictedROMs = [NSMutableSet set];
    }
    
    if (newlyConflicted)
    {
        [newlyConflictedROMs addObject:self.name];
    }
    else
    {
        [newlyConflictedROMs removeObject:self.name];
    }
    
    [[NSUserDefaults standardUserDefaults] setObject:[newlyConflictedROMs allObjects] forKey:@"newlyConflictedROMs"];
}

- (NSString *)uniqueName
{
    // MUST remain alloc] init] format. Or else bad EXC_BAD_ACCESS crashes on iPad mini
    NSDictionary *cachedROMs = [[NSDictionary alloc] initWithContentsOfFile:[GBAROM cachedROMsPath]];
    
    if (cachedROMs == nil)
    {
        // MUST remain alloc] init] format. Or else bad EXC_BAD_ACCESS crashes on iPad mini
        cachedROMs = [[NSDictionary alloc] init];
    }
    
    NSString *uniqueName = cachedROMs[[self.filepath lastPathComponent]];
    
    if (uniqueName)
    {
        // copy Fixes rare EXC_BAD_ACCESS
        return [uniqueName copy];
    }
    
#if !(TARGET_IPHONE_SIMULATOR)
    // First ARC bug I've encountered. On iPhone 5s, if we don't copy this string, AND check whether it is an empty string, it'll be nil for some reason. Was a bitch to figure out.
    uniqueName = [[GBAEmulatorCore embeddedNameForROM:self] copy];
#else
    NSString *uuid = [[NSUUID UUID] UUIDString];
    uniqueName = uuid;
#endif
    
    if (uniqueName == nil || [uniqueName isEqualToString:@""])
    {
        DLog(@"Something went really really wrong...%@", self.filepath);
        return nil;
    }
    
    uniqueName = [uniqueName stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
    
    CFStringRef fileHash = FileSHA1HashCreateWithPath((__bridge CFStringRef)self.filepath, FileHashDefaultChunkSizeForReadingData);
    uniqueName = [uniqueName stringByAppendingFormat:@"-%@", (__bridge NSString *)fileHash];
    CFRelease(fileHash);
    
    return uniqueName;
}

@end
