#import "UDDeclEditorViewController.h"
#import "UDDeclItem.h"
#import "UDDeclDocument.h"
#import "UDDeclManagedObjects.h"
#import "UDWorkspace.h"
#import "idDeclManager.h"

@interface UDDeclEditorViewController ()
@property (nonatomic, strong, readwrite, nullable) UDDiagnosticStore *diagnosticStore;
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *diagnosticTargets;
@end

static NSString *UDDiagnosticKey(UDDiagnosticItem *diagnostic) {
    return [NSString stringWithFormat:@"%ld:%@", (long)diagnostic.line, diagnostic.message];
}

@implementation UDDeclEditorViewController

- (void)setDocument:(UDDeclDocument *)document {
    _document = document;
    // No `viewLoaded` check: GNUstep's NSViewController doesn't have it, and
    // none is needed — the objectController outlet is nil until the view nib
    // has loaded (reading it does NOT trigger loading), so this assignment is
    // a harmless no-op before then; -viewDidLoad sets the content itself.
    if (document != nil) {
        self.objectController.content = document.declObject;
    }
}

- (__kindof UDDeclBase *)declObject {
    return self.document.declObject;
}

- (NSManagedObjectContext *)editingContext {
    return self.document.editingContext;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    if (self.item == nil || self.item.kind != UDWorkspaceItemKindDecl) {
        return;
    }

    UDDeclItem *declItem = (UDDeclItem *)self.item;
    NSError *error = nil;

    self.document = [[UDDeclDocument alloc] initWithType:declItem.type name:declItem.declName inWorkspace:self.workspace error:&error];
    if (self.document == nil) {
        NSLog(@"%@: failed to open decl of type %@ name %@: %@", [self class], [self.workspace.declManager declTypeName:declItem.type], declItem.declName, error);
        return;
    }

    if (![self.document readFromURL:[NSURL URLWithString:@"http://localhost/unused.txt"] ofType:@"" error:&error]) {
        NSLog(@"%@: failed to read decl of type %@ name %@: %@", [self class], [self.workspace.declManager declTypeName:declItem.type], declItem.declName, error);
    }

    self.objectController.content = self.declObject;
    self.diagnosticStore = [[UDDiagnosticStore alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_editingContextDidChange:)
                                                 name:NSManagedObjectContextObjectsDidChangeNotification
                                               object:self.editingContext];
    [self declDidLoad];
    [self editingContextDidChange];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)_editingContextDidChange:(NSNotification *)notification {
    [self editingContextDidChange];
}

- (NSInteger)lineOfDeclTextContaining:(NSString *)text {
    NSData *source = self.declObject.sourceText;
    NSString *declText = source != nil ? [[NSString alloc] initWithData:source encoding:NSUTF8StringEncoding] : nil;
    NSRange found = [declText rangeOfString:text options:NSCaseInsensitiveSearch];
    if (found.location == NSNotFound) return 1;
    NSInteger line = 1;
    for (NSUInteger i = 0; i < found.location; i++) {
        if ([declText characterAtIndex:i] == '\n') line++;
    }
    return line;
}

- (void)declDidLoad {
}

- (void)editingContextDidChange {
}

- (void)revealDiagnostic:(UDDiagnosticItem *)diagnostic {
}

- (void)setTarget:(id)target forDiagnostic:(UDDiagnosticItem *)diagnostic {
    if (self.diagnosticTargets == nil) self.diagnosticTargets = [NSMutableDictionary dictionary];
    self.diagnosticTargets[UDDiagnosticKey(diagnostic)] = target;
}

- (id)targetForDiagnostic:(UDDiagnosticItem *)diagnostic {
    return self.diagnosticTargets[UDDiagnosticKey(diagnostic)];
}

- (void)removeDiagnosticTargets {
    [self.diagnosticTargets removeAllObjects];
}

@end
