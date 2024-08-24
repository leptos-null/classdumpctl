//
//  main.m
//  classdumpctl
//
//  Created by Leptos on 1/10/23.
//  Copyright © 2023 Leptos. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <ClassDump/ClassDump.h>
#import <dlfcn.h>
#import <getopt.h>

#import "ansi-color.h"


typedef NS_ENUM(NSUInteger, CDOutputColorMode) {
    CDOutputColorModeDefault,
    CDOutputColorModeNever,
    CDOutputColorModeAlways,
    
    CDOutputColorModeCaseCount
};

static void printUsage(const char *progname) {
    printf("Usage: %s [options]\n"
           "Options:\n"
           "  -a, --dyld_shared_cache    Interact in the dyld_shared_cache\n"
           "                               by default, dump all classes in the cache\n"
           "  -l, --list                 List all classes in the specified image\n"
           "                               if specified with -a/--dyld_shared_cache\n"
           "                               lists all images in the dyld_shared_cache\n"
           "  -o <p>, --output=<p>       Use path as the output directory\n"
           "                               if specified with -a/--dyld_shared_cache\n"
           "                               the file structure of the cache is written to\n"
           "                               the specified directory, otherwise all classes found\n"
           "                               are written to this directory at the top level\n"
           "  -m <m>, --color=<m>        Set color settings, one of the below\n"
           "                               default: color output only if output is to a TTY\n"
           "                               never: no output is colored\n"
           "                               always: output to TTYs, pipes, and files are colored\n"
           "  -i <p>, --image=<p>        Reference the mach-o image at path\n"
           "                               by default, dump all classes in this image\n"
           "                               otherwise may specify --class or --protocol\n"
           "  -c <s>, --class=<s>        Dump class to stdout (unless -o is specified)\n"
           "  -p <s>, --protocol=<s>     Dump protocol to stdout (unless -o is specified)\n"
           "  -j <N>, --jobs=<N>         Allow N jobs at once\n"
           "                               only applicable when specified with -a/--dyld_shared_cache\n"
           "                               (defaults to number of processing core available)\n"
           "", progname);
}

static CDClassModel *safelyGenerateModelForClass(Class const cls, IMP const blankIMP) {
    Method const initializeMthd = class_getClassMethod(cls, @selector(initialize));
    method_setImplementation(initializeMthd, blankIMP);
    
    return [CDClassModel modelWithClass:cls];
}

static NSString *ansiEscapedColorThemeForSemanticString(CDSemanticString *const semanticString) {
    NSMutableString *build = [NSMutableString string];
    // start with a reset - if there were attributes set before we start writing
    // it might be confusing, when we eventually do reset later
    if (semanticString.length > 0) {
        [build appendString:@ANSI_GRAPHIC_RENDITION(ANSI_GRAPHIC_RESET_CODE)];
    }
    [semanticString enumerateLongestEffectiveRangesUsingBlock:^(NSString *string, CDSemanticType type) {
        NSString *ansiRendition = nil;
        switch (type) {
            case CDSemanticTypeComment:
                ansiRendition = @ANSI_GRAPHIC_RENDITION(ANSI_GRAPHIC_COLOR_TYPE_FAINT);
                break;
            case CDSemanticTypeKeyword:
                ansiRendition = @ANSI_GRAPHIC_COLOR(ANSI_GRAPHIC_COLOR_TYPE_REGULAR,
                                                    ANSI_GRAPHIC_COLOR_ATTRIBUTE_FOREGROUND_NORMAL,
                                                    ANSI_GRAPHIC_COLOR_CODE_RED);
                break;
            case CDSemanticTypeRecordName:
                ansiRendition = @ANSI_GRAPHIC_COLOR(ANSI_GRAPHIC_COLOR_TYPE_REGULAR,
                                                    ANSI_GRAPHIC_COLOR_ATTRIBUTE_FOREGROUND_NORMAL,
                                                    ANSI_GRAPHIC_COLOR_CODE_CYAN);
                break;
            case CDSemanticTypeClass:
                ansiRendition = @ANSI_GRAPHIC_COLOR(ANSI_GRAPHIC_COLOR_TYPE_REGULAR,
                                                    ANSI_GRAPHIC_COLOR_ATTRIBUTE_FOREGROUND_NORMAL,
                                                    ANSI_GRAPHIC_COLOR_CODE_CYAN);
                break;
            case CDSemanticTypeProtocol:
                ansiRendition = @ANSI_GRAPHIC_COLOR(ANSI_GRAPHIC_COLOR_TYPE_REGULAR,
                                                    ANSI_GRAPHIC_COLOR_ATTRIBUTE_FOREGROUND_NORMAL,
                                                    ANSI_GRAPHIC_COLOR_CODE_CYAN);
                break;
            case CDSemanticTypeNumeric:
                ansiRendition = @ANSI_GRAPHIC_COLOR(ANSI_GRAPHIC_COLOR_TYPE_REGULAR,
                                                    ANSI_GRAPHIC_COLOR_ATTRIBUTE_FOREGROUND_NORMAL,
                                                    ANSI_GRAPHIC_COLOR_CODE_PURPLE);
                break;
            default:
                break;
        }
        if (ansiRendition != nil) {
            [build appendString:ansiRendition];
        }
        [build appendString:string];
        if (ansiRendition != nil) {
            [build appendString:@ANSI_GRAPHIC_RENDITION(ANSI_GRAPHIC_RESET_CODE)];
        }
    }];
    return build;
}

static NSString *linesForSemanticStringColorMode(CDSemanticString *const semanticString, CDOutputColorMode const colorMode, BOOL const isOutputTTY) {
    BOOL shouldColor = NO;
    switch (colorMode) {
        case CDOutputColorModeDefault:
            shouldColor = isOutputTTY;
            break;
        case CDOutputColorModeNever:
            shouldColor = NO;
            break;
        case CDOutputColorModeAlways:
            shouldColor = YES;
            break;
        default:
            NSCAssert(NO, @"Unknown case: %lu", (unsigned long)colorMode);
            break;
    }
    if (shouldColor) {
        return ansiEscapedColorThemeForSemanticString(semanticString);
    }
    return [semanticString string];
}

int main(int argc, char *argv[]) {
    BOOL dyldSharedCacheFlag = NO;
    BOOL listFlag = NO;
    NSString *outputDir = nil;
    CDOutputColorMode outputColorMode = CDOutputColorModeDefault;
    NSMutableArray<NSString *> *requestImageList = [NSMutableArray array];
    NSMutableArray<NSString *> *requestClassList = [NSMutableArray array];
    NSMutableArray<NSString *> *requestProtocolList = [NSMutableArray array];
    NSUInteger maxJobs = NSProcessInfo.processInfo.processorCount;
    
    struct option const options[] = {
        { "dyld_shared_cache", no_argument,       NULL, 'a' },
        { "list",              no_argument,       NULL, 'l' },
        { "output",            required_argument, NULL, 'o' },
        { "color",             required_argument, NULL, 'm' },
        { "image",             required_argument, NULL, 'i' },
        { "class",             required_argument, NULL, 'c' },
        { "protocol",          required_argument, NULL, 'p' },
        { "jobs",              required_argument, NULL, 'j' },
        { NULL,                0,                 NULL,  0  }
    };
    
    int ch;
    while ((ch = getopt_long(argc, argv, ":alo:m:i:c:p:j:", options, NULL)) != -1) {
        switch (ch) {
            case 'a':
                dyldSharedCacheFlag = YES;
                break;
            case 'l':
                listFlag = YES;
                break;
            case 'o':
                outputDir = @(optarg);
                break;
            case 'm': {
                const char *stringyOption = optarg;
                if (stringyOption == NULL) {
                    printUsage(argv[0]);
                    return 1;
                } else if (strcmp(stringyOption, "default") == 0) {
                    outputColorMode = CDOutputColorModeDefault;
                } else if (strcmp(stringyOption, "never") == 0) {
                    outputColorMode = CDOutputColorModeNever;
                } else if (strcmp(stringyOption, "always") == 0) {
                    outputColorMode = CDOutputColorModeAlways;
                } else {
                    printUsage(argv[0]);
                    return 1;
                }
            } break;
            case 'i':
                [requestImageList addObject:@(optarg)];
                break;
            case 'c':
                [requestClassList addObject:@(optarg)];
                break;
            case 'p':
                [requestProtocolList addObject:@(optarg)];
                break;
            case 'j':
                maxJobs = strtoul(optarg, NULL, 10);
                break;
            default: {
                printUsage(argv[0]);
                return 1;
            } break;
        }
    }
    
    BOOL const hasImageRequests = (requestImageList.count > 0);
    BOOL const hasSpecificDumpRequests = (requestClassList.count > 0) || (requestProtocolList.count > 0);
    if (!hasImageRequests && !hasSpecificDumpRequests && !dyldSharedCacheFlag) {
        printUsage(argv[0]);
        return 1;
    }
    
    CDGenerationOptions *const generationOptions = [CDGenerationOptions new];
    generationOptions.stripSynthesized = YES;
    
    IMP const blankIMP = imp_implementationWithBlock(^{ }); // returns void, takes no parameters
    
    // just doing this once before we potentially delete some class initializers
    [[CDClassModel modelWithClass:NSClassFromString(@"NSObject")] semanticLinesWithOptions:generationOptions];
    [[CDProtocolModel modelWithProtocol:NSProtocolFromString(@"NSObject")] semanticLinesWithOptions:generationOptions];
    
    if (hasImageRequests && (outputDir == nil)) {
        fprintf(stderr, "-o/--output required to dump all classes in an image\n");
        return 1;
    }
    if ((hasImageRequests || hasSpecificDumpRequests) && outputDir != nil) {
        NSFileManager *const fileManager = NSFileManager.defaultManager;
        BOOL isDir = NO;
        if ([fileManager fileExistsAtPath:outputDir isDirectory:&isDir]) {
            if (!isDir) {
                fprintf(stderr, "%s is not a directory\n", outputDir.fileSystemRepresentation);
                return 1;
            }
        } else {
            NSError *dirError = nil;
            if (![fileManager createDirectoryAtPath:outputDir withIntermediateDirectories:YES attributes:nil error:&dirError]) {
                NSLog(@"createDirectoryError: %@", dirError);
                return 1;
            }
        }
    }
    
    for (NSString *requestImage in requestImageList) {
        dlerror(); // clear
        void *imageHandle = dlopen(requestImage.fileSystemRepresentation, RTLD_NOW);
        const char *dlerr = dlerror();
        if (dlerr != NULL) {
            fprintf(stderr, "dlerror: %s\n", dlerr);
        }
        if (imageHandle == NULL) {
            continue;
        }
        
        if (listFlag || !hasSpecificDumpRequests) {
            unsigned int classCount = 0;
            const char **classNames = objc_copyClassNamesForImage(requestImage.fileSystemRepresentation, &classCount);
            for (unsigned int classIndex = 0; classIndex < classCount; classIndex++) {
                if (listFlag) {
                    printf("%s\n", classNames[classIndex]);
                    continue;
                }
                Class const cls = objc_getClass(classNames[classIndex]);
                CDClassModel *model = safelyGenerateModelForClass(cls, blankIMP);
                CDSemanticString *semanticString = [model semanticLinesWithOptions:generationOptions];
                NSString *lines = linesForSemanticStringColorMode(semanticString, outputColorMode, NO);
                NSString *headerName = [NSStringFromClass(cls) stringByAppendingPathExtension:@"h"];
                
                NSString *headerPath = [outputDir stringByAppendingPathComponent:headerName];
                
                NSError *writeError = nil;
                if (![lines writeToFile:headerPath atomically:NO encoding:NSUTF8StringEncoding error:&writeError]) {
                    NSLog(@"writeToFileError: %@", writeError);
                }
            }
        }
        // we don't close `imageHandle` since we might dump specific classes later
    }
    
    BOOL const isOutputTTY = (outputDir == nil) && isatty(STDOUT_FILENO);
    
    for (NSString *requestClassName in requestClassList) {
        Class const cls = NSClassFromString(requestClassName);
        if (cls == nil) {
            fprintf(stderr, "Class named %s not found\n", requestClassName.UTF8String);
            continue;
        }
        CDClassModel *model = safelyGenerateModelForClass(cls, blankIMP);
        if (model == nil) {
            fprintf(stderr, "Unable to message class named %s\n", requestClassName.UTF8String);
            continue;
        }
        CDSemanticString *string = [model semanticLinesWithOptions:generationOptions];
        NSString *lines = linesForSemanticStringColorMode(string, outputColorMode, isOutputTTY);
        NSData *encodedLines = [lines dataUsingEncoding:NSUTF8StringEncoding];
        
        if (outputDir != nil) {
            NSString *headerName = [requestClassName stringByAppendingPathExtension:@"h"];
            NSString *headerPath = [outputDir stringByAppendingPathComponent:headerName];
            
            [encodedLines writeToFile:headerPath atomically:NO];
        } else {
            [NSFileHandle.fileHandleWithStandardOutput writeData:encodedLines];
        }
    }
    
    for (NSString *requestProtocolName in requestProtocolList) {
        Protocol *const prcl = NSProtocolFromString(requestProtocolName);
        if (prcl == nil) {
            fprintf(stderr, "Protocol named %s not found\n", requestProtocolName.UTF8String);
            continue;
        }
        CDProtocolModel *model = [CDProtocolModel modelWithProtocol:prcl];
        CDSemanticString *string = [model semanticLinesWithOptions:generationOptions];
        NSString *lines = linesForSemanticStringColorMode(string, outputColorMode, isOutputTTY);
        NSData *encodedLines = [lines dataUsingEncoding:NSUTF8StringEncoding];
        
        if (outputDir != nil) {
            NSString *headerName = [requestProtocolName stringByAppendingPathExtension:@"h"];
            NSString *headerPath = [outputDir stringByAppendingPathComponent:headerName];
            
            [encodedLines writeToFile:headerPath atomically:NO];
        } else {
            [NSFileHandle.fileHandleWithStandardOutput writeData:encodedLines];
        }
    }
    
    if (dyldSharedCacheFlag) {
        NSArray<NSString *> *const imagePaths = [CDUtilities dyldSharedCacheImagePaths];
        if (listFlag) {
            for (NSString *imagePath in imagePaths) {
                printf("%s\n", imagePath.fileSystemRepresentation);
            }
            return 0;
        }
        
        if (outputDir == nil) {
            fprintf(stderr, "-o/--output required to dump all classes in the dyld_shared_cache\n");
            return 1;
        }
        
        NSFileManager *const fileManager = NSFileManager.defaultManager;
        
        if ([fileManager fileExistsAtPath:outputDir]) {
            fprintf(stderr, "%s already exists\n", outputDir.fileSystemRepresentation);
            return 1;
        }
        
        NSMutableDictionary<NSNumber *, NSString *> *const pidToPath = [NSMutableDictionary dictionaryWithCapacity:maxJobs];
        
        NSUInteger activeJobs = 0;
        NSUInteger badExitCount = 0;
        NSUInteger finishedImageCount = 0;
        
        NSUInteger const imagePathCount = imagePaths.count;
        for (NSUInteger imageIndex = 0; (imageIndex < imagePathCount) || (activeJobs > 0); imageIndex++) {
            BOOL const hasImagePath = (imageIndex < imagePathCount);
            
            if (!hasImagePath || (activeJobs >= maxJobs)) {
                int childStatus = 0;
                pid_t const childPid = wait(&childStatus);
                activeJobs--;
                
                if (childPid < 0) {
                    perror("wait");
                    return 1;
                }
                NSNumber *key = @(childPid);
                NSString *path = pidToPath[key];
                [pidToPath removeObjectForKey:key];
                finishedImageCount++;
                
                if (WIFEXITED(childStatus)) {
                    int const exitStatus = WEXITSTATUS(childStatus);
                    if (exitStatus != 0) {
                        printf("Child for '%s' exited with status %d\n", path.fileSystemRepresentation, exitStatus);
                        badExitCount++;
                    }
                } else if (WIFSIGNALED(childStatus)) {
                    printf("Child for '%s' signaled with signal %d\n", path.fileSystemRepresentation, WTERMSIG(childStatus));
                    badExitCount++;
                } else {
                    printf("Child for '%s' did not finish cleanly\n", path.fileSystemRepresentation);
                    badExitCount++;
                }
                printf("  %lu/%lu\r", finishedImageCount, imagePathCount);
                fflush(stdout); // important to flush after using '\r', but also critical to flush (if needed) before calling `fork`
            }
            if (hasImagePath) {
                NSString *imagePath = imagePaths[imageIndex];
                
                pid_t const forkStatus = fork();
                if (forkStatus < 0) {
                    perror("fork");
                    return 1;
                }
                if (forkStatus == 0) {
                    // child
                    NSString *topDir = [outputDir stringByAppendingPathComponent:imagePath];
                    
                    NSError *error = nil;
                    if (![fileManager createDirectoryAtPath:topDir withIntermediateDirectories:YES attributes:nil error:&error]) {
                        NSLog(@"createDirectoryAtPathError: %@", error);
                        return 1;
                    }
                    NSString *logPath = [topDir stringByAppendingPathComponent:@"log.txt"];
                    
                    int const logHandle = open(logPath.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL, 0644);
                    assert(logHandle >= 0);
                    dup2(logHandle, STDOUT_FILENO);
                    dup2(logHandle, STDERR_FILENO);
                    
                    dlerror(); // clear
                    void *imageHandle = dlopen(imagePath.fileSystemRepresentation, RTLD_NOW);
                    const char *dlerr = dlerror();
                    if (dlerr != NULL) {
                        fprintf(stderr, "dlerror: %s\n", dlerr);
                    }
                    if (imageHandle == NULL) {
                        return 1;
                    }
                    
                    // use a group so we can make sure all the work items finish before we exit the program
                    dispatch_group_t const linesWriteGroup = dispatch_group_create();
                    // perform file system writes on another thread so we don't unnecessarily block our CPU work
                    dispatch_queue_t const linesWriteQueue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
                    
                    unsigned int classCount = 0;
                    const char **classNames = objc_copyClassNamesForImage(imagePath.fileSystemRepresentation, &classCount);
                    for (unsigned int classIndex = 0; classIndex < classCount; classIndex++) {
                        Class const cls = objc_getClass(classNames[classIndex]);
                        // creating the model and generating the "lines" both use
                        // functions that grab the objc runtime lock, so putting either of
                        // these on another thread is not efficient, as they would just be blocked
                        CDClassModel *model = safelyGenerateModelForClass(cls, blankIMP);
                        if (model == nil) {
                            continue;
                        }
                        CDSemanticString *semanticString = [model semanticLinesWithOptions:generationOptions];
                        
                        NSString *lines = linesForSemanticStringColorMode(semanticString, outputColorMode, NO);
                        NSString *headerName = [NSStringFromClass(cls) stringByAppendingPathExtension:@"h"];
                        
                        dispatch_group_async(linesWriteGroup, linesWriteQueue, ^{
                            NSString *headerPath = [topDir stringByAppendingPathComponent:headerName];
                            [lines writeToFile:headerPath atomically:NO encoding:NSUTF8StringEncoding error:NULL];
                        });
                    }
                    
                    dispatch_group_wait(linesWriteGroup, DISPATCH_TIME_FOREVER);
                    
                    free(classNames);
                    dlclose(imageHandle);
                    
                    close(logHandle);
                    unlink(logPath.fileSystemRepresentation);
                    
                    return 0; // exit child process
                }
                
                pidToPath[@(forkStatus)] = imagePath;
                activeJobs++;
            }
        }
        
        printf("%lu images in dyld_shared_cache\n", (unsigned long)imagePaths.count);
        printf("Failed to load %lu images\n", (unsigned long)badExitCount);
    }
    return 0;
}
