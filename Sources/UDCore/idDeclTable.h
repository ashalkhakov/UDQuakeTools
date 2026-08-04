// Copyright (C) 2004 Id Software, Inc.
//

#import "idDeclManager.h"

/*
===============================================================================

    tables are used to map a floating point input value to a floating point
    output value, with optional wrap / clamp and interpolation

===============================================================================
*/

@interface idDeclTable : idDecl

-(float)tableLookupByIndex:(float)index;

@property (assign, nonatomic) BOOL clamp;
@property (assign, nonatomic) BOOL snap;

// RAVEN BEGIN
// jscott: for BSE
@property (assign, nonatomic) float minValue;
@property (assign, nonatomic) float maxValue;
// RAVEN END

@end

idDeclTable *idDeclTable_Allocator(void);
