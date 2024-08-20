#import <Foundation/Foundation.h>
#import <ClassDump/ClassDump.h>

static CDClassModel *safelyGenerateModelForClass(Class const cls, IMP const blankIMP) {
    Method const initializeMthd = class_getClassMethod(cls, @selector(initialize));
    method_setImplementation(initializeMthd, blankIMP);
    
    return [CDClassModel modelWithClass:cls];
}

static void dumpHeader(NSString *requestImage, NSString *outputDir) {
    IMP const blankIMP = imp_implementationWithBlock(^{ }); // returns void, takes no parameters
    
    CDGenerationOptions *const generationOptions = [CDGenerationOptions new];
    generationOptions.stripSynthesized = YES;

    unsigned int classCount = 0;
    const char **classNames = objc_copyClassNamesForImage(requestImage.fileSystemRepresentation, &classCount);
    for (unsigned int classIndex = 0; classIndex < classCount; classIndex++) {
        Class const cls = objc_getClass(classNames[classIndex]);
        CDClassModel *model = safelyGenerateModelForClass(cls, blankIMP);
        CDSemanticString *semanticString = [model semanticLinesWithOptions:generationOptions];
        NSString *lines = [semanticString string];
        NSString *headerName = [NSStringFromClass(cls) stringByAppendingPathExtension:@"h"];
        
        NSString *headerPath = [outputDir stringByAppendingPathComponent:headerName];
        
        NSError *writeError = nil;
        if (![lines writeToFile:headerPath atomically:NO encoding:NSUTF8StringEncoding error:&writeError]) {
            NSLog(@"writeToFileError: %@", writeError);
        }
    }
}

%ctor {
	dumpHeader(@"TODO", @"TODO");
}
