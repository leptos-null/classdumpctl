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
    CDOutputColorModeHtmlHljs,
    CDOutputColorModeHtmlLsp,
    
    CDOutputColorModeCaseCount
};

typedef NS_ENUM(NSUInteger, CDOptionBoolValue) {
    CDOptionBoolValueStripProtocolConformance = 0x100,
    CDOptionBoolValueStripOverrides,
    CDOptionBoolValueStripDuplicates,
    CDOptionBoolValueStripSynthesized,
    CDOptionBoolValueStripCtorMethod,
    CDOptionBoolValueStripDtorMethod,
    CDOptionBoolValueAddSymbolImageComments,
    
    CDOptionBoolValueCaseEnd
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
           "                               default: color output using ASNI color escapes only if output is to a TTY\n"
           "                               never: no output is colored\n"
           "                               always: color output to files, pipes, and TTYs using ASNI color escapes\n"
           "                               html-hljs: output in HTML format annotated with hljs classes\n"
           "                               html-lsp: output in HTML format annotated with LSP classes\n"
           "  -i <p>, --image=<p>        Reference the mach-o image at path\n"
           "                               by default, dump all classes in this image\n"
           "                               otherwise may specify --class or --protocol\n"
           "  -c <s>, --class=<s>        Dump class to stdout (unless -o is specified)\n"
           "  -p <s>, --protocol=<s>     Dump protocol to stdout (unless -o is specified)\n"
           "  -j <N>, --jobs=<N>         Allow N jobs at once\n"
           "                               only applicable when specified with -a/--dyld_shared_cache\n"
           "                               (defaults to number of processing core available)\n"
           "\n"
           "  --strip-protocol-conformance[=flag]    Hide properties and methods that are required\n"
           "                                           by a protocol the type conforms to\n"
           "                                           (defaults to false)\n"
           "  --strip-overrides[=flag]               Hide properties and methods that are inherited\n"
           "                                           from the class hierachy\n"
           "                                           (defaults to false)\n"
           "  --strip-duplicates[=flag]              Hide duplicate occurrences of a property or method\n"
           "                                           (defaults to false)\n"
           "  --strip-synthesized[=flag]             Hide methods and ivars that are synthesized from a property\n"
           "                                           (defaults to true)\n"
           "  --strip-ctor-method[=flag]             Hide `.cxx_construct` method\n"
           "                                           (defaults to false)\n"
           "  --strip-dtor-method[=flag]             Hide `.cxx_destruct` method\n"
           "                                           (defaults to false)\n"
           "  --add-symbol-comments[=flag]           Add comments above each eligible declaration\n"
           "                                           with the symbol name and image path the object is found in\n"
           "                                           (defaults to false)\n"
           "", progname);
}

static CDClassModel *safelyGenerateModelForClass(Class const cls, IMP const blankIMP, Method const safeInitializeMethod) {
    Method const initializeMthd = class_getClassMethod(cls, @selector(initialize));
    // `method_setImplementation` is (relatively) expensive, in my testing (on macOS 26.1)
    //   adding these checks improves performance by about 3 times
    if (initializeMthd != safeInitializeMethod) {
        IMP methodIMP = method_getImplementation(initializeMthd);
        if (methodIMP != blankIMP) {
            method_setImplementation(initializeMthd, blankIMP);
        }
    }
    
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

static NSString *sanitizeForHTML(NSString *input) {
    NSMutableString *build = [NSMutableString string];
    // thanks to https://www.w3.org/International/questions/qa-escapes#use
    NSDictionary<NSString *, NSString *> *replacementMap = @{
        @"<": @"&lt;",
        @">": @"&gt;",
        @"&": @"&amp;",
        @"\"": @"&quot;",
        @"'": @"&apos;",
    };
    [input enumerateSubstringsInRange:NSMakeRange(0, input.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
        [build appendString:(replacementMap[substring] ?: substring)];
    }];
    return build;
}

static NSString *hljsHtmlForSemanticString(CDSemanticString *const semanticString) {
    NSMutableString *build = [NSMutableString string];
    // https://highlightjs.readthedocs.io/en/latest/css-classes-reference.html
    [semanticString enumerateLongestEffectiveRangesUsingBlock:^(NSString *string, CDSemanticType type) {
        NSString *htmlCls = nil;
        switch (type) {
            case CDSemanticTypeComment:
                htmlCls = @"hljs-comment";
                break;
            case CDSemanticTypeKeyword:
                htmlCls = @"hljs-keyword";
                break;
            case CDSemanticTypeVariable:
                htmlCls = @"hljs-variable";
                break;
            case CDSemanticTypeRecordName:
                htmlCls = @"hljs-type";
                break;
            case CDSemanticTypeClass:
                // hljs-class is deprecated
                htmlCls = @"hljs-title class";
                break;
            case CDSemanticTypeProtocol:
                // hljs does not officially define `hljs-title.protocol`
                // however `hljs-title` is still a class that themes should style
                htmlCls = @"hljs-title protocol";
                break;
            case CDSemanticTypeNumeric:
                htmlCls = @"hljs-number";
                break;
            default:
                break;
        }
        if (htmlCls != nil) {
            [build appendString:@"<span class=\""];
            [build appendString:htmlCls];
            [build appendString:@"\">"];
        }
        [build appendString:sanitizeForHTML(string)];
        if (htmlCls != nil) {
            [build appendString:@"</span>"];
        }
    }];
    return build;
}

static NSString *lspHtmlForSemanticString(CDSemanticString *const semanticString) {
    NSMutableString *build = [NSMutableString string];
    // https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#semanticTokenTypes
    // https://github.com/leptos-null/LspHighlight/blob/5bce00c/Sources/LspHighlight/LspHighlight.swift#L285
    [semanticString enumerateLongestEffectiveRangesUsingBlock:^(NSString *string, CDSemanticType type) {
        NSString *htmlCls = nil;
        switch (type) {
            case CDSemanticTypeComment:
                htmlCls = @"lsp-type-comment";
                break;
            case CDSemanticTypeKeyword:
                htmlCls = @"lsp-type-keyword";
                break;
            case CDSemanticTypeVariable:
                htmlCls = @"lsp-type-variable";
                break;
            case CDSemanticTypeRecordName:
                htmlCls = @"lsp-type-struct";
                break;
            case CDSemanticTypeClass:
                htmlCls = @"lsp-type-class";
                break;
            case CDSemanticTypeProtocol:
                htmlCls = @"lsp-type-type";
                break;
            case CDSemanticTypeNumeric:
                htmlCls = @"lsp-type-number";
                break;
            default:
                break;
        }
        if (htmlCls != nil) {
            [build appendString:@"<span class=\""];
            [build appendString:htmlCls];
            [build appendString:@"\">"];
        }
        [build appendString:sanitizeForHTML(string)];
        if (htmlCls != nil) {
            [build appendString:@"</span>"];
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
        case CDOutputColorModeHtmlHljs:
            return hljsHtmlForSemanticString(semanticString);
        case CDOutputColorModeHtmlLsp:
            return lspHtmlForSemanticString(semanticString);
        default:
            NSCAssert(NO, @"Unknown case: %lu", (unsigned long)colorMode);
            break;
    }
    if (shouldColor) {
        return ansiEscapedColorThemeForSemanticString(semanticString);
    }
    return [semanticString string];
}

/// - Returns: `0` if `value` should be handled as `NO`,
///            `1` if `value` should be handled as `YES`,
///            `-1` if there's an error processing `value`
static int parseOptargBool(const char *const value) {
    // no value means enable the flag
    if (value == NULL) { return 1; }
    
    if (strcmp(value, "0") == 0) { return 0; }
    if (strcmp(value, "1") == 0) { return 1; }
    if (strcmp(value, "no") == 0) { return 0; }
    if (strcmp(value, "yes") == 0) { return 1; }
    if (strcmp(value, "NO") == 0) { return 0; }
    if (strcmp(value, "YES") == 0) { return 1; }
    if (strcmp(value, "N") == 0) { return 0; }
    if (strcmp(value, "Y") == 0) { return 1; }
    if (strcmp(value, "n") == 0) { return 0; }
    if (strcmp(value, "y") == 0) { return 1; }
    if (strcmp(value, "off") == 0) { return 0; }
    if (strcmp(value, "on") == 0) { return 1; }
    if (strcmp(value, "false") == 0) { return 0; }
    if (strcmp(value, "true") == 0) { return 1; }
    if (strcmp(value, "FALSE") == 0) { return 0; }
    if (strcmp(value, "TRUE") == 0) { return 1; }
    
    return -1;
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
    
    CDGenerationOptions *const generationOptions = [CDGenerationOptions new];
    generationOptions.stripSynthesized = YES;
    
    struct option const options[] = {
        { "dyld_shared_cache", no_argument,       NULL, 'a' },
        { "list",              no_argument,       NULL, 'l' },
        { "output",            required_argument, NULL, 'o' },
        { "color",             required_argument, NULL, 'm' },
        { "image",             required_argument, NULL, 'i' },
        { "class",             required_argument, NULL, 'c' },
        { "protocol",          required_argument, NULL, 'p' },
        { "jobs",              required_argument, NULL, 'j' },
        
        { "strip-protocol-conformance", optional_argument, NULL, CDOptionBoolValueStripProtocolConformance },
        { "strip-overrides",            optional_argument, NULL, CDOptionBoolValueStripOverrides           },
        { "strip-duplicates",           optional_argument, NULL, CDOptionBoolValueStripDuplicates          },
        { "strip-synthesized",          optional_argument, NULL, CDOptionBoolValueStripSynthesized         },
        { "strip-ctor-method",          optional_argument, NULL, CDOptionBoolValueStripCtorMethod          },
        { "strip-dtor-method",          optional_argument, NULL, CDOptionBoolValueStripDtorMethod          },
        { "add-symbol-comments",        optional_argument, NULL, CDOptionBoolValueAddSymbolImageComments   },
        
        { NULL, 0, NULL, 0 }
    };
    
    int optionIndex = 0;
    int ch;
    while ((ch = getopt_long(argc, argv, ":alo:m:i:c:p:j:", options, &optionIndex)) != -1) {
        switch (ch) {
            case CDOptionBoolValueStripProtocolConformance:
            case CDOptionBoolValueStripOverrides:
            case CDOptionBoolValueStripDuplicates:
            case CDOptionBoolValueStripSynthesized:
            case CDOptionBoolValueStripCtorMethod:
            case CDOptionBoolValueStripDtorMethod:
            case CDOptionBoolValueAddSymbolImageComments: {
                struct option const *const option = options + optionIndex;
                // test if we want to consume the next argument.
                //   `optional_argument` only provides `optarg` if the
                //   command line parameter is in the format "--name=value",
                //   this code allows us to consume "--name" "value".
                //   We have to validate "value", otherwise we might accidentally
                //   consume "--name" "--flag"
                if (optarg == NULL && optind < argc) {
                    int const parse = parseOptargBool(argv[optind]);
                    // sucessful parse - consume next arg
                    if (parse >= 0) {
                        optarg = argv[optind];
                        optind++;
                    }
                }
                int const parse = parseOptargBool(optarg);
                if (parse < 0) {
                    fprintf(stderr, "Unknown value for --%s: '%s', expected 'yes', 'no'\n", option->name, optarg);
                    return 1;
                }
                
                BOOL const flag = (parse != 0);
                switch (ch) {
                    case CDOptionBoolValueStripProtocolConformance:
                        generationOptions.stripProtocolConformance = flag;
                        break;
                    case CDOptionBoolValueStripOverrides:
                        generationOptions.stripOverrides = flag;
                        break;
                    case CDOptionBoolValueStripDuplicates:
                        generationOptions.stripDuplicates = flag;
                        break;
                    case CDOptionBoolValueStripSynthesized:
                        generationOptions.stripSynthesized = flag;
                        break;
                    case CDOptionBoolValueStripCtorMethod:
                        generationOptions.stripCtorMethod = flag;
                        break;
                    case CDOptionBoolValueStripDtorMethod:
                        generationOptions.stripDtorMethod = flag;
                        break;
                    case CDOptionBoolValueAddSymbolImageComments:
                        generationOptions.addSymbolImageComments = flag;
                        break;
                    default:
                        break;
                }
            } break;
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
                } else if (strcmp(stringyOption, "none") == 0) { // alias
                    outputColorMode = CDOutputColorModeNever;
                } else if (strcmp(stringyOption, "always") == 0) {
                    outputColorMode = CDOutputColorModeAlways;
                } else if (strcmp(stringyOption, "ansi") == 0) { // alias
                    outputColorMode = CDOutputColorModeAlways;
                } else if (strcmp(stringyOption, "html-hljs") == 0) {
                    outputColorMode = CDOutputColorModeHtmlHljs;
                } else if (strcmp(stringyOption, "html-lsp") == 0) {
                    outputColorMode = CDOutputColorModeHtmlLsp;
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
    
    IMP const blankIMP = imp_implementationWithBlock(^{ }); // returns void, takes no parameters
    Method const safeInitializeMethod = class_getClassMethod([NSObject class], @selector(initialize));
    
    // just doing this once before we potentially delete some class initializers
    [[CDClassModel modelWithClass:NSClassFromString(@"NSObject")] semanticLinesWithOptions:generationOptions];
    [[CDProtocolModel modelWithProtocol:NSProtocolFromString(@"NSObject")] semanticLinesWithOptions:generationOptions];
    
    if (hasImageRequests && !hasSpecificDumpRequests && (outputDir == nil)) {
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
                const char *const className = classNames[classIndex];
                if (listFlag) {
                    printf("%s\n", className);
                    continue;
                }
                // this is the same method `NSStringFromClass` uses
                NSString *const nsClassName = [[NSString alloc] initWithCString:className encoding:NSUTF8StringEncoding];
                if (nsClassName == nil) {
                    // these contain byte sequences that don't map to characters.
                    // NSString doesn't seem to want to represent these sequences.
                    // Since the header contents is broken anyway in this case, skip for now.
                    NSLog(@"Skipping class with unsupported name: '%s'", className);
                    continue;
                }
                Class cls = objc_getClass(className);
                if (cls == NULL) {
                    // Observed consistently for `AOSUIOBTemplateContainerViewController` on macOS 26.1
                    // (not able to reproduce with debugger attached)
                    // `objc_getClass("AOSUIOBTemplateContainerViewController")` returned
                    //   `NULL` on first call, and successfully on second try
                    cls = objc_getClass(className);
                    
                    if (cls == NULL) {
                        NSLog(@"Unable to find class named '%s' (expected in '%@')", className, requestImage);
                        continue;
                    }
                }
                CDClassModel *model = safelyGenerateModelForClass(cls, blankIMP, safeInitializeMethod);
                CDSemanticString *semanticString = [model semanticLinesWithOptions:generationOptions];
                NSString *lines = linesForSemanticStringColorMode(semanticString, outputColorMode, NO);
                NSString *headerName = [nsClassName stringByAppendingPathExtension:@"h"];
                
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
        CDClassModel *model = safelyGenerateModelForClass(cls, blankIMP, safeInitializeMethod);
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
        
//        if ([fileManager fileExistsAtPath:outputDir]) {
//            fprintf(stderr, "%s already exists\n", outputDir.fileSystemRepresentation);
//            return 1;
//        }
        
        NSSet *const skipPaths = [NSSet setWithArray:@[
            @"/usr/lib/dyld",
            /*
             Superclass of CalUISuggestionsWindow at <addr> in /System/Library/PrivateFrameworks/CalendarUI.framework/Versions/A/CalendarUI is set to 0xbad4007, indicating it is missing from an installed root
             */
            @"/System/Library/PrivateFrameworks/CalendarUI.framework/Versions/A/CalendarUI",
            @"/System/Library/PrivateFrameworks/Safari.framework/Versions/A/Safari", // seems to load `CalendarUI`
            @"/System/Library/PrivateFrameworks/SearchUI.framework/Versions/A/SearchUI", // seems to load `CalendarUI`
            @"/System/Library/PrivateFrameworks/RemindersUICore.framework/Versions/A/RemindersUICore", // seems to load `CalendarUI`
            @"/System/Library/PrivateFrameworks/SocialUI.framework/Versions/A/SocialUI", // seems to load `CalendarUI`
            @"/System/Library/PrivateFrameworks/CalendarIntegrationSupport.framework/Versions/A/CalendarIntegrationSupport", // seems to load `CalendarUI`
            @"/System/Library/PrivateFrameworks/CalendarLink.framework/Versions/A/CalendarLink", // seems to load `CalendarUI`
            @"/System/Library/PrivateFrameworks/CalendarUIKitInternal.framework/Versions/A/CalendarUIKitInternal", // seems to load `CalendarUI`
            @"/System/Library/PrivateFrameworks/RemindersIntentsFramework.framework/Versions/A/RemindersIntentsFramework", // seems to load `CalendarUI`
            @"/System/Library/PrivateFrameworks/SiriNotebookUI.framework/Versions/A/SiriNotebookUI", // seems to load `CalendarUI`
            /*
             Superclass of MUIAppleIntelligenceOnboardingViewController at <addr> in /System/Library/PrivateFrameworks/MailUI.framework/Versions/A/MailUI is set to 0xbad4007, indicating it is missing from an installed root
             */
            @"/System/Library/PrivateFrameworks/MailUI.framework/Versions/A/MailUI",
            /*
             Superclass of ILMediaBrowserMovieView at <addr> in /System/Library/PrivateFrameworks/iLifeMediaBrowser.framework/Versions/A/iLifeMediaBrowser is set to 0xbad4007, indicating it is missing from an installed root
             */
            @"/System/Library/Frameworks/ScreenSaver.framework/Versions/A/ScreenSaver",
            /*
             Superclass of SiriUIBuddyGMEnrollmentSplashView at <addr> in /System/Library/PrivateFrameworks/SiriUI.framework/Versions/A/SiriUI is set to 0xbad4007, indicating it is missing from an installed root
             */
            @"/System/Library/PrivateFrameworks/SiriUI.framework/Versions/A/SiriUI",
            /*
             Superclass of ILMediaBrowserMovieView at <addr> in /System/Library/PrivateFrameworks/iLifeMediaBrowser.framework/Versions/A/iLifeMediaBrowser is set to 0xbad4007, indicating it is missing from an installed root
             */
            @"/System/Library/PrivateFrameworks/iLifeMediaBrowser.framework/Versions/A/iLifeMediaBrowser",
            /*
             Superclass of ASBackgroundAssetConsentViewController at <addr> in /System/Library/PrivateFrameworks/AppStoreUI.framework/Versions/A/AppStoreUI is set to 0xbad4007, indicating it is missing from an installed root
             */
            @"/System/Library/PrivateFrameworks/AppStoreKit.framework/Versions/A/AppStoreKit",
            /* Assertion failed: (platformBinary), function +[WFActionKitStaticInitializer load], file ActionKit.m, line 49. */
            @"/System/Library/PrivateFrameworks/ActionKit.framework/Versions/A/ActionKit",
            /* Assertion failed: (platformBinary), function +[WFActionKitStaticInitializer load], file ActionKit.m, line 49. */
            @"/System/Library/PrivateFrameworks/ActionKitUI.framework/Versions/A/ActionKitUI",
            /*
             Superclass of CalUISuggestionsWindow at <addr> in /System/Library/PrivateFrameworks/CalendarUI.framework/Versions/A/CalendarUI is set to 0xbad4007, indicating it is missing from an installed root
             */
            @"/System/Library/PrivateFrameworks/AppPredictionUI.framework/Versions/A/AppPredictionUI",
            /*
             Superclass of ASBackgroundAssetConsentViewController at <addr> in /System/Library/PrivateFrameworks/AppStoreUI.framework/Versions/A/AppStoreUI is set to 0xbad4007, indicating it is missing from an installed root
             */
            @"/System/Library/PrivateFrameworks/AppStoreUI.framework/Versions/A/AppStoreUI",
            /*
             Superclass of BKUIFingerprintEnrollBuddyClientAdapterView at <addr> in /System/Library/PrivateFrameworks/BiometricKitUI.framework/Versions/A/BiometricKitUI is set to 0xbad4007, indicating it is missing from an installed root
             */
            @"/System/Library/PrivateFrameworks/BiometricKitUI.framework/Versions/A/BiometricKitUI",
            /*
             Superclass of ASBackgroundAssetConsentViewController at <addr> in /System/Library/PrivateFrameworks/AppStoreUI.framework/Versions/A/AppStoreUI is set to 0xbad4007, indicating it is missing from an installed root
             */
            @"/System/Library/PrivateFrameworks/GameStoreKit.framework/Versions/A/GameStoreKit",
            /*
             Superclass of SearchUIPersonHeaderViewController at <addr> in /System/Library/PrivateFrameworks/SearchUI.framework/Versions/A/SearchUI is set to 0xbad4007, indicating it is missing from an installed root
             */
            @"/System/Library/PrivateFrameworks/IntelligenceFlowAppIntentsPreviewToolSupport.framework/Versions/A/IntelligenceFlowAppIntentsPreviewToolSupport",
            /*
             Superclass of SearchUIPersonHeaderViewController at <addr> in /System/Library/PrivateFrameworks/SearchUI.framework/Versions/A/SearchUI is set to 0xbad4007, indicating it is missing from an installed root
             */
            @"/System/Library/PrivateFrameworks/IntelligenceFlowContextRuntime.framework/Versions/A/IntelligenceFlowContextRuntime",
            /*
             Superclass of SearchUIPersonHeaderViewController at <addr> in /System/Library/PrivateFrameworks/SearchUI.framework/Versions/A/SearchUI is set to 0xbad4007, indicating it is missing from an installed root
             */
            @"/System/Library/PrivateFrameworks/IntelligenceFlowFeedbackDataCollector.framework/Versions/A/IntelligenceFlowFeedbackDataCollector",
            /*
             Superclass of SearchUIPersonHeaderViewController at <addr> in /System/Library/PrivateFrameworks/SearchUI.framework/Versions/A/SearchUI is set to 0xbad4007, indicating it is missing from an installed root
             */
            @"/System/Library/PrivateFrameworks/IntelligenceFlowPlannerRuntime.framework/Versions/A/IntelligenceFlowPlannerRuntime",
            /*
             Superclass of SearchUIPersonHeaderViewController at <addr> in /System/Library/PrivateFrameworks/SearchUI.framework/Versions/A/SearchUI is set to 0xbad4007, indicating it is missing from an installed root
             */
            @"/System/Library/PrivateFrameworks/IntelligenceFlowPlannerSupport.framework/Versions/A/IntelligenceFlowPlannerSupport",
            /*
             Superclass of SearchUIPersonHeaderViewController at <addr> in /System/Library/PrivateFrameworks/SearchUI.framework/Versions/A/SearchUI is set to 0xbad4007, indicating it is missing from an installed root
             */
            @"/System/Library/PrivateFrameworks/IntelligenceFlowRuntime.framework/Versions/A/IntelligenceFlowRuntime",
            /*
             Superclass of CalUISuggestionsWindow at <addr> in /System/Library/PrivateFrameworks/CalendarUI.framework/Versions/A/CalendarUI is set to 0xbad4007, indicating it is missing from an installed root
             */
            @"/System/Library/PrivateFrameworks/OmniSearch.framework/Versions/A/OmniSearch",
            /*
             Superclass of CalUISuggestionsWindow at <addr> in /System/Library/PrivateFrameworks/CalendarUI.framework/Versions/A/CalendarUI is set to 0xbad4007, indicating it is missing from an installed root
             */
            @"/System/Library/PrivateFrameworks/OmniSearchClient.framework/Versions/A/OmniSearchClient",
            /*
             Superclass of CalUISuggestionsWindow at <addr> in /System/Library/PrivateFrameworks/CalendarUI.framework/Versions/A/CalendarUI is set to 0xbad4007, indicating it is missing from an installed root
             */
            @"/System/Library/PrivateFrameworks/OnDeviceEvalRuntime.framework/Versions/A/OnDeviceEvalRuntime",
            /*
             Superclass of PMCredentialRequestPaneHeader at <addr> in /System/Library/PrivateFrameworks/PasswordManagerUI.framework/Versions/A/PasswordManagerUI is set to 0xbad4007, indicating it is missing from an installed root
             */
            @"/System/Library/PrivateFrameworks/PasswordManagerUI.framework/Versions/A/PasswordManagerUI",
            /*
             Superclass of CalUISuggestionsWindow at <addr> in /System/Library/PrivateFrameworks/CalendarUI.framework/Versions/A/CalendarUI is set to 0xbad4007, indicating it is missing from an installed root
             */
            @"/System/Library/PrivateFrameworks/PersonalSearchService.framework/Versions/A/PersonalSearchService",
            /*
             Superclass of CalUISuggestionsWindow at <addr> in /System/Library/PrivateFrameworks/CalendarUI.framework/Versions/A/CalendarUI is set to 0xbad4007, indicating it is missing from an installed root
             */
            @"/System/Library/PrivateFrameworks/RemindersAppIntents.framework/Versions/A/RemindersAppIntents",
            /*
             Superclass of SearchUIPersonHeaderViewController at <addr> in /System/Library/PrivateFrameworks/SearchUI.framework/Versions/A/SearchUI is set to 0xbad4007, indicating it is missing from an installed root
             */
            @"/System/Library/PrivateFrameworks/Safari.framework/Versions/A/PlugIns/Safari.wkbundle/Contents/MacOS/Safari",
            /*
             Superclass of SearchUIPersonHeaderViewController at <addr> in /System/Library/PrivateFrameworks/SearchUI.framework/Versions/A/SearchUI is set to 0xbad4007, indicating it is missing from an installed root
             */
            @"/System/Library/PrivateFrameworks/SearchUICardKitProviderSupport.framework/Versions/A/SearchUICardKitProviderSupport",
            /*
             Class of category SetupAssistantSupportUI at <addr> in ?? is set to 0xbad4007, indicating it is missing from an installed root
             */
            @"/System/Library/PrivateFrameworks/SetupAssistantSupportUI.framework/Versions/A/SetupAssistantSupportUI",
            /*
             Superclass of SearchUIPersonHeaderViewController at 0x1f90e54a0 in /System/Library/PrivateFrameworks/SearchUI.framework/Versions/A/SearchUI is set to 0xbad4007, indicating it is missing from an installed root
             */
            @"/System/Library/PrivateFrameworks/SiriAppLaunchUIFramework.framework/Versions/A/SiriAppLaunchUIFramework",
            /*
             Superclass of CalUISuggestionsWindow at 0x1f8282378 in /System/Library/PrivateFrameworks/CalendarUI.framework/Versions/A/CalendarUI is set to 0xbad4007, indicating it is missing from an installed root
             */
            @"/System/Library/PrivateFrameworks/SiriNotebook.framework/Versions/A/SiriNotebook",
            /*
             Superclass of SiriUIBuddyGMEnrollmentSplashView at 0x1f930d790 in /System/Library/PrivateFrameworks/SiriUI.framework/Versions/A/SiriUI is set to 0xbad4007, indicating it is missing from an installed root
             */
            @"/System/Library/PrivateFrameworks/SiriSetup.framework/Versions/A/SiriSetup",
            /*
             Superclass of SearchUIPersonHeaderViewController at 0x1f90e54a0 in /System/Library/PrivateFrameworks/SearchUI.framework/Versions/A/SearchUI is set to 0xbad4007, indicating it is missing from an installed root
             */
            @"/System/Library/PrivateFrameworks/SpotlightUIShared.framework/Versions/A/SpotlightUIShared",
            /*
             Superclass of VUIAVPlayerView at 0x2a39c5980 in /System/Library/PrivateFrameworks/VideosUI.framework/Versions/A/VideosUI is set to 0xbad4007, indicating it is missing from an installed root
             */
            @"/System/Library/PrivateFrameworks/VideosUI.framework/Versions/A/VideosUI",
            /*
             Superclass of Welcome.CustomizedAVPlayerView at 0x2a3a2a580 in /System/Library/PrivateFrameworks/Welcome.framework/Versions/A/Welcome is set to 0xbad4007, indicating it is missing from an installed root
             */
            @"/System/Library/PrivateFrameworks/Welcome.framework/Versions/A/Welcome",
            /* Assertion failed: (platformBinary), function +[WFActionKitStaticInitializer load], file ActionKit.m, line 49. */
            @"/System/Library/PrivateFrameworks/WorkflowUI.framework/Versions/A/WorkflowUI",
            /* Invalid dylib load. Clients should not load the unversioned libcrypto dylib as it does not have a stable ABI. */
            @"/usr/lib/libcrypto.dylib",
            /* Invalid dylib load. Clients should not load the unversioned libssl dylib as it does not have a stable ABI. */
            @"/usr/lib/libssl.dylib",
            /* Assertion failed: (platformBinary), function +[WFActionKitStaticInitializer load], file ActionKit.m, line 49. */
            @"/System/iOSSupport/System/Library/PrivateFrameworks/ActionKit.framework/Versions/A/ActionKit",
            /* Assertion failed: (platformBinary), function +[WFActionKitStaticInitializer load], file ActionKit.m, line 49. */
            @"/System/iOSSupport/System/Library/PrivateFrameworks/ActionKitUI.framework/Versions/A/ActionKitUI",
            /* Assertion failed: (platformBinary), function +[WFActionKitStaticInitializer load], file ActionKit.m, line 49. */
            @"/System/iOSSupport/System/Library/PrivateFrameworks/WorkflowUI.framework/Versions/A/WorkflowUI",
            /* Exception thrown while decoding class BSAuditToken for key "_bsAuditToken": +[BSAuditToken supportsSecureCoding]: unrecognized selector sent to class 0x1f8034058 */
            @"/System/Library/PrivateFrameworks/PreviewsInjection.framework/Versions/A/PreviewsInjection",
            @"/System/iOSSupport/System/Library/PrivateFrameworks/PreviewsInjection.framework/Versions/A/PreviewsInjection",
            
            /* -[__NSSetM removeObject:]: object cannot be nil */
            // @"/System/Library/PrivateFrameworks/AOSUI.framework/Versions/A/AOSUI", // TODO: investigate (in `_forwardDeclarableClassReferences`)
            
            // not sure
            @"/System/Library/PrivateFrameworks/UnifiedMessagingKit.framework/Versions/A/UnifiedMessagingKit",
        ]];
        
        NSUInteger const imagePathCount = imagePaths.count;
        for (NSUInteger imageIndex = 0; imageIndex < imagePathCount; imageIndex++) {
                NSString *imagePath = imagePaths[imageIndex];
                    
                    if ([skipPaths containsObject:imagePath]) {
                        NSLog(@"Skipping (%lu) %@", imageIndex, imagePath);
                        continue;
                    }
                    NSLog(@"Processing (%lu) %@", imageIndex, imagePath);
                    
                    NSString *topDir = [outputDir stringByAppendingPathComponent:imagePath];
                    
                    NSError *error = nil;
                    if (![fileManager createDirectoryAtPath:topDir withIntermediateDirectories:YES attributes:nil error:&error]) {
                        NSLog(@"createDirectoryAtPathError: %@", error);
                        return 1;
                    }
                    
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
                        const char *const className = classNames[classIndex];
                        // this is the same method `NSStringFromClass` uses
                        NSString *const nsClassName = [[NSString alloc] initWithCString:className encoding:NSUTF8StringEncoding];
                        if (nsClassName == nil) {
                            // these contain byte sequences that don't map to characters.
                            // NSString doesn't seem to want to represent these sequences.
                            // Since the header contents is broken anyway in this case, skip for now.
                            NSLog(@"Skipping class with unsupported name: '%s'", className);
                            continue;
                        }
                        Class cls = objc_getClass(className);
                        if (cls == NULL) {
                            // Observed consistently for `AOSUIOBTemplateContainerViewController` on macOS 26.1
                            // (not able to reproduce with debugger attached)
                            // `objc_getClass("AOSUIOBTemplateContainerViewController")` returned
                            //   `NULL` on first call, and successfully on second try
                            cls = objc_getClass(className);
                            
                            if (cls == NULL) {
                                NSLog(@"Unable to find class named '%s' (expected in '%@')", className, imagePath);
                                continue;
                            }
                        }
                        CDClassModel *model = safelyGenerateModelForClass(cls, blankIMP, safeInitializeMethod);
                        CDSemanticString *semanticString = [model semanticLinesWithOptions:generationOptions];
                        
                        NSString *lines = linesForSemanticStringColorMode(semanticString, outputColorMode, NO);
                        NSString *headerName = [nsClassName stringByAppendingPathExtension:@"h"];
                        
                        dispatch_group_async(linesWriteGroup, linesWriteQueue, ^{
                            NSString *headerPath = [topDir stringByAppendingPathComponent:headerName];
                            [lines writeToFile:headerPath atomically:NO encoding:NSUTF8StringEncoding error:NULL];
                        });
                    }
                    
                    dispatch_group_wait(linesWriteGroup, DISPATCH_TIME_FOREVER);
                    
                    free(classNames);
                    dlclose(imageHandle);
        }
    }
    return 0;
}
