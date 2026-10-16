/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDDeclManagedObjects.h — NSManagedObject subclasses backing DeclModel.xcdatamodeld.
 *
 * These are the one and only structured representation of decls: the entity
 * classes own the type-specific parse/unparse logic (ported from the old
 * idDecl* subclasses), while idDeclManager stays a dumb text repository.
 * UDDeclIncrementalStore drives the codecs from the managed object model —
 * it derives everything (attributes, child-decl relationships, owned
 * sub-entities like particle stages) from NSEntityDescription introspection.
 *
 * Entity naming convention: the entity for decl type name "x" is named
 * "Decl" + capitalized("x") — material → DeclMaterial, pda → DeclPDA,
 * entityDef → DeclEntityDef.
 *
 * Codec value dictionaries use these shapes:
 *   attribute name                   -> NSString / NSNumber
 *   transient structured attribute   -> whatever the entity defines (e.g.
 *                                       DeclParticle.stages holds
 *                                       NSArray<UDParticleStage *>)
 *   to-many relationship to a decl   -> NSArray<NSString *> of decl names
 */

#import "UDDeclBase.h"
#import "UDDeclElement.h"
#import "UDDeclRawText.h"
#import "UDDeclTable.h"
#import "UDDeclSkin.h"
#import "UDDeclEntityDef.h"
#import "UDDeclSound.h"
#import "UDDeclFX.h"
#import "UDDeclPDA.h"
#import "UDDeclParticle.h"
