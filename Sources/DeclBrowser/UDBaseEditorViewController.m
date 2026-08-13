#import "UDBaseEditorViewController.h"
#import "UDFileItem.h"
#import "UDDeclItem.h"
#import "UDTextEditorViewController.h"
#import "UDImageViewerViewController.h"
#import "UDPDAEditorViewController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@implementation UDBaseEditorViewController

+ (instancetype)editorViewControllerForWorkspaceItem:(UDWorkspaceItem *)item inWorkspace:(UDWorkspace *)workspace {
    
    if (item.kind == UDWorkspaceItemKindGroup) {
        return nil;
    }

    if (item.kind == UDWorkspaceItemKindFile) {
        UDFileItem *fileItem = (UDFileItem *)item;
        NSString *uti = fileItem.fileUTI ?: @"";
        
        // Image types
        if (@available(macOS 11.0, *)) {
            UTType *fileType = [UTType typeWithIdentifier:uti];
            if ([fileType conformsToType:UTTypeImage]) {
                UDImageViewerViewController *vc = [[UDImageViewerViewController alloc] init];
                vc.item = item;
                vc.workspace = workspace;
                return vc;
            }
        } else {
            if (UTTypeConformsTo((__bridge CFStringRef)uti, kUTTypeImage)) {
                UDImageViewerViewController *vc = [[UDImageViewerViewController alloc] init];
                vc.item = item;
                vc.workspace = workspace;
                return vc;
            }
        }
        
        // Default: text editor
        UDTextEditorViewController *vc = [[UDTextEditorViewController alloc] init];
        vc.item = item;
        vc.workspace = workspace;
        return vc;
    }
    
    if (item.kind == UDWorkspaceItemKindDecl) {
        UDDeclItem *declItem = (UDDeclItem *)item;
        
        if (declItem.type == DECL_PDA) {
            // PDA editor
            UDPDAEditorViewController *vc = [[UDPDAEditorViewController alloc] init];
            vc.item = item;
            vc.workspace = workspace;
            return vc;
        } else {
            // Default: text editor
            UDTextEditorViewController *vc = [[UDTextEditorViewController alloc] init];
            vc.item = item;
            vc.workspace = workspace;
            return vc;
        }
    }
    
    return nil;
}

@end
