#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import <os/log.h>

// SwiftUI wraps a ReferenceFileDocument in its own NSDocument subclasses
// (e.g. SwiftUI.FileWrapperPlatformDocument), which override autosavesInPlace
// to return YES — so patching NSDocument itself has no effect. Patch those
// subclasses directly, so closing an edited window asks "Save / Don't Save /
// Cancel" instead of silently writing into the user's file. Other NSDocument
// subclasses are untouched. SplitEditorController logs a fault if a document
// still autosaves in place, e.g. after an OS update renames these classes.

static BOOL noAutosavesInPlace(id self, SEL _cmd) {
    return NO;
}

// Judged by the framework its superclasses come from. Names don't work: from
// Objective-C a Swift class's name is mangled (_TtC7SwiftUI…), and the
// document's own class is generated at runtime (a generic specialisation), so
// it isn't in any framework image itself.
static BOOL isSwiftUIDocument(id document) {
    for (Class cls = [document class]; cls && cls != [NSDocument class]; cls = class_getSuperclass(cls)) {
        const char *image = class_getImageName(cls);
        if (image && strstr(image, "/SwiftUI.framework/")) return YES;
    }
    return NO;
}

// Without in-place autosave, AppKit writes crash-recovery copies of saved
// documents next to them as "Name (Autosaved).md", where they show up in Finder,
// git and any tool watching the folder. Redirect those writes to
// ~/Library/Autosave Information, reusing the document's file there across
// autosaves. AppKit records wherever the copy was written as
// autosavedContentsFileURL, so restoring after a crash finds it.
static IMP originalSaveToURL = NULL;

static NSURL *autosaveLocation(NSDocument *document) {
    NSURL *folder = [[NSFileManager defaultManager] URLForDirectory:NSAutosavedInformationDirectory
                                                           inDomain:NSUserDomainMask
                                                  appropriateForURL:nil
                                                             create:YES
                                                              error:NULL];
    if (!folder) return nil;
    NSURL *current = document.autosavedContentsFileURL;
    if (current && [current.URLByDeletingLastPathComponent.path isEqualToString:folder.path]) {
        return current;
    }
    NSString *name = document.fileURL.lastPathComponent ?: @"Untitled.md";
    NSString *unique = [NSString stringWithFormat:@"%@ %@", [NSUUID UUID].UUIDString, name];
    return [folder URLByAppendingPathComponent:unique];
}

static void saveToURLKeepingAutosavesAway(NSDocument *self, SEL _cmd, NSURL *url, NSString *type,
                                          NSSaveOperationType operation, void (^handler)(NSError *)) {
    if (operation == NSAutosaveElsewhereOperation && isSwiftUIDocument(self)) {
        url = autosaveLocation(self) ?: url;
    }
    ((void (*)(id, SEL, NSURL *, NSString *, NSSaveOperationType, void (^)(NSError *)))originalSaveToURL)(
        self, _cmd, url, type, operation, handler);
}

static void disableInPlaceAutosaveForSwiftUIDocuments(void) {
    SEL selector = @selector(autosavesInPlace);
    const char *types = method_getTypeEncoding(class_getClassMethod([NSDocument class], selector));
    unsigned int patched = 0;
    unsigned int imageCount = 0;
    const char **images = objc_copyImageNames(&imageCount);
    for (unsigned int i = 0; i < imageCount; i++) {
        if (!strstr(images[i], "/SwiftUI.framework/")) continue;
        unsigned int classCount = 0;
        const char **names = objc_copyClassNamesForImage(images[i], &classCount);
        for (unsigned int j = 0; j < classCount; j++) {
            // Only look up likely candidates; realizing every SwiftUI class is slow.
            if (!strstr(names[j], "Document")) continue;
            Class cls = objc_getClass(names[j]);
            for (Class super = cls ? class_getSuperclass(cls) : Nil; super; super = class_getSuperclass(super)) {
                if (super == [NSDocument class]) {
                    class_replaceMethod(object_getClass(cls), selector, (IMP)noAutosavesInPlace, types);
                    os_log_debug(OS_LOG_DEFAULT, "mded: in-place autosave disabled for %{public}s", names[j]);
                    patched++;
                    break;
                }
            }
        }
        free(names);
    }
    free(images);
    if (patched == 0) {
        os_log_fault(OS_LOG_DEFAULT, "mded: found no SwiftUI NSDocument subclasses to patch");
    }
}

@interface NSDocument (MdedNoAutosave)
@end

@implementation NSDocument (MdedNoAutosave)
// Runs at class load time — after SwiftUI is loaded, before DocumentGroup setup.
+ (void)load {
    disableInPlaceAutosaveForSwiftUIDocuments();

    Method save = class_getInstanceMethod([NSDocument class], @selector(saveToURL:ofType:forSaveOperation:completionHandler:));
    if (save) {
        originalSaveToURL = method_setImplementation(save, (IMP)saveToURLKeepingAutosavesAway);
    }

    // Without in-place autosave, AppKit only autosaves at all when the document
    // controller's autosavingDelay is above zero (default: 0). Those autosaves go
    // to ~/Library/Autosave Information, not the user's file, and are what lets
    // unsaved work come back after a crash. Set it after launch, once SwiftUI has
    // created its document controller; touching it earlier would create one first.
    [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationDidFinishLaunchingNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification * __unused note) {
        [NSDocumentController sharedDocumentController].autosavingDelay = 30;
    }];
}
@end
