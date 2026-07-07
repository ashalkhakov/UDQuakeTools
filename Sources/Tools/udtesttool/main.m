#import <Foundation/Foundation.h>
#import "UDGuiModel.h"
#import "UDGuiDocumentCodec.h"

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSLog(@"Starting verification of expressions and if-else parsing...");
        
        NSString *text =
            @"windowDef Desktop {\n"
             "    onAction {\n"
             "        if ( gui::alpha0 == 4 ) { set history1::forecolor 1, 1, 1, 1 ; } else if ( gui::alpha0 == 3 ) { set history1::forecolor 1, 1, 1, 0.875 ; } else { set history1::forecolor 1, 1, 1, 0.5 ; }\n"
             "    }\n"
             "}\n";

        UDGuiDocumentCodec *codec = [[UDGuiDocumentCodec alloc] init];
        NSError *parseError = nil;
        UDGuiDocument *document = [codec parseDocumentFromText:text sourceVirtualPath:@"guis/test.gui" error:&parseError];

        if (parseError) {
            NSLog(@"ERROR during parsing: %@", parseError);
            return 1;
        }

        if (!document) {
            NSLog(@"ERROR: document is nil");
            return 1;
        }

        if (document.rootWindows.count != 1) {
            NSLog(@"ERROR: expected 1 root window, got %lu", (unsigned long)document.rootWindows.count);
            return 1;
        }

        UDGuiWindowNode *root = [document.rootWindows objectAtIndex:0];
        if (root.eventHandlers.count != 1) {
            NSLog(@"ERROR: expected 1 event handler, got %lu", (unsigned long)root.eventHandlers.count);
            return 1;
        }

        UDGuiEventHandler *handler = [root.eventHandlers objectAtIndex:0];
        if (handler.commands.count != 1) {
            NSLog(@"ERROR: expected 1 command, got %lu", (unsigned long)handler.commands.count);
            return 1;
        }

        UDGuiScriptCommand *command = [handler.commands objectAtIndex:0];
        if (![command isKindOfClass:[UDGuiIfCommand class]]) {
            NSLog(@"ERROR: expected command of type UDGuiIfCommand, got %@", NSStringFromClass([command class]));
            return 1;
        }

        UDGuiIfCommand *ifCmd = (UDGuiIfCommand *)command;
        if (ifCmd.branches.count != 3) {
            NSLog(@"ERROR: expected 3 branches, got %lu", (unsigned long)ifCmd.branches.count);
            return 1;
        }

        UDGuiIfBranch *branch1 = [ifCmd.branches objectAtIndex:0];
        if (!branch1.condition) {
            NSLog(@"ERROR: branch 1 condition is nil");
            return 1;
        }
        if (![branch1.condition isKindOfClass:[UDGuiBinaryExpression class]]) {
            NSLog(@"ERROR: expected branch 1 condition to be UDGuiBinaryExpression");
            return 1;
        }
        UDGuiBinaryExpression *binExpr1 = (UDGuiBinaryExpression *)branch1.condition;
        if (![binExpr1.operatorString isEqualToString:@"=="]) {
            NSLog(@"ERROR: expected binExpr1 operator '==', got %@", binExpr1.operatorString);
            return 1;
        }
        
        NSLog(@"Branch 1 condition: %@", [branch1.condition serializedString]);
        NSLog(@"Branch 2 condition: %@", [[ifCmd.branches objectAtIndex:1].condition serializedString]);
        NSLog(@"Branch 3 condition: %@", [ifCmd.branches objectAtIndex:2].condition); // nil

        NSError *serializeError = nil;
        NSString *serialized = [codec serializeDocument:document error:&serializeError];
        if (serializeError) {
            NSLog(@"ERROR during serialization: %@", serializeError);
            return 1;
        }

        NSLog(@"Serialized output:\n%@", serialized);

        if (![serialized containsString:@"if ( gui::alpha0 == 4 ) { set history1::forecolor 1, 1, 1, 1 ; } else if ( gui::alpha0 == 3 ) { set history1::forecolor 1, 1, 1, 0.875 ; } else { set history1::forecolor 1, 1, 1, 0.5 ; }"]) {
            NSLog(@"ERROR: serialized output does not contain the expected if-else structure");
            return 1;
        }

        NSLog(@"Verification successful! Everything works flawlessly.");
    }
    return 0;
}
