#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>

// Save the original IMP so non-SwiftUI document classes keep their normal behavior.
static IMP originalAutosavesInPlace = NULL;

static BOOL scopedAutosavesInPlace(Class cls, SEL _cmd) {
    // Only override for SwiftUI-managed document classes. SwiftUI wraps a
    // ReferenceFileDocument in an internal NSDocument subclass whose class name
    // begins with "SwiftUI." — match on that prefix so unrelated NSDocument
    // subclasses (e.g. from frameworks) keep their stock autosave behavior.
    NSString *name = NSStringFromClass(cls);
    if ([name hasPrefix:@"SwiftUI."]) {
        return NO;
    }
    if (originalAutosavesInPlace) {
        return ((BOOL (*)(Class, SEL))originalAutosavesInPlace)(cls, _cmd);
    }
    return YES;
}

// Runs at class load time — before Swift init, before DocumentGroup setup.
// Patches NSDocument.autosavesInPlace to return NO for SwiftUI's document
// wrapper, so the system shows "Save / Don't Save / Cancel" on window close
// instead of silently autosaving. Other NSDocument subclasses are untouched.
@interface NSDocument (MdedNoAutosave)
@end

@implementation NSDocument (MdedNoAutosave)
+ (void)load {
    Method m = class_getClassMethod([NSDocument class], @selector(autosavesInPlace));
    if (m) {
        originalAutosavesInPlace = method_getImplementation(m);
        method_setImplementation(m, (IMP)scopedAutosavesInPlace);
    }
}
@end
