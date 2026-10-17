/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDDeclAF.h — articulated figures (idDeclAF).
 */

#import "UDDeclElement.h"

NS_ASSUME_NONNULL_BEGIN

// An idAFVector is kept as its text, as idAFVector::Write writes it less its
// precision: "( x, y, z )", "joint( \"j\" )", "bonecenter( \"a\", \"b\" )",
// "bonedir( \"a\", \"b\" )", each with "-" before it when negated. A contents
// mask is kept as idDeclAF::ContentsToString has it: "solid, corpse", "none".

/// One of an articulated figure's bodies, as idDeclAF::ParseBody reads it:
/// its defaults idDeclAF_Body::SetDefault's (some of them the figure's).
@interface UDAFBody : UDDeclPropertyElement
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *jointName;
/// JointModToString's: orientation, position, both.
@property (nonatomic, copy) NSString *jointMod;
/// The model's type, its keyword: box, octahedron, dodecahedron, cylinder,
/// cone, bone; v1 and v2 its vectors, numSides a cylinder's or a cone's,
/// width a bone's.
@property (nonatomic, copy) NSString *modelType;
@property (nonatomic, copy) NSString *v1;
@property (nonatomic, copy) NSString *v2;
@property (nonatomic) int32_t numSides;
@property (nonatomic) float width;
@property (nonatomic, copy) NSString *origin;
/// Its angles' "( pitch, yaw, roll )".
@property (nonatomic, copy) NSString *angles;
@property (nonatomic) float density;
/// Its inertia scale's nine numbers, space-separated.
@property (nonatomic, copy) NSString *inertiaScale;
@property (nonatomic) float linearFriction;
@property (nonatomic) float angularFriction;
@property (nonatomic) float contactFriction;
@property (nonatomic, copy) NSString *contents;
@property (nonatomic, copy) NSString *clipMask;
@property (nonatomic) BOOL selfCollision;
@property (nonatomic, copy) NSString *containedJoints;
@property (nonatomic, copy) NSString *frictionDirection;
@property (nonatomic, copy) NSString *contactMotorDirection;
@end

/// One of an articulated figure's constraints, as the ParseFixed,
/// ParseBallAndSocketJoint, ParseUniversalJoint, ParseHinge, ParseSlider
/// and ParseSpring that its type (their keyword) names read it.
@interface UDAFConstraint : UDDeclPropertyElement
@property (nonatomic, copy) NSString *name;
/// fixed, ballAndSocketJoint, universalJoint, hinge, slider, spring.
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy) NSString *body1;
@property (nonatomic, copy) NSString *body2;
@property (nonatomic) float friction;
@property (nonatomic) float stretch;
@property (nonatomic) float compress;
@property (nonatomic) float damping;
@property (nonatomic) float restLength;
@property (nonatomic) float minLength;
@property (nonatomic) float maxLength;
@property (nonatomic, copy) NSString *anchor;
@property (nonatomic, copy) NSString *anchor2;
@property (nonatomic, copy) NSString *shaft1;
@property (nonatomic, copy) NSString *shaft2;
@property (nonatomic, copy) NSString *axis;
/// none, cone, pyramid (a hinge's limit is a cone one).
@property (nonatomic, copy) NSString *limit;
@property (nonatomic, copy) NSString *limitAxis;
@property (nonatomic) float limitAngle1;
@property (nonatomic) float limitAngle2;
@property (nonatomic) float limitAngle3;
@end

/// An articulated figure: its settings, as idDeclAF::ParseSettings reads
/// them (FreeData's defaults), and its bodies and constraints, TRANSIENT, as
/// a table's values are.
@interface UDDeclAF : UDDeclBase
@property (nonatomic, copy, nullable) NSString *model;
@property (nonatomic, copy, nullable) NSString *skin;
@property (nonatomic) float defaultLinearFriction;
@property (nonatomic) float defaultAngularFriction;
@property (nonatomic) float defaultContactFriction;
@property (nonatomic) float defaultConstraintFriction;
@property (nonatomic) float totalMass;
@property (nonatomic) float suspendVelocity1;
@property (nonatomic) float suspendVelocity2;
@property (nonatomic) float suspendAcceleration1;
@property (nonatomic) float suspendAcceleration2;
@property (nonatomic) float noMoveTime;
@property (nonatomic) float noMoveTranslation;
@property (nonatomic) float noMoveRotation;
@property (nonatomic) float minMoveTime;
@property (nonatomic) float maxMoveTime;
@property (nonatomic, copy, nullable) NSString *contents;
@property (nonatomic, copy, nullable) NSString *clipMask;
@property (nonatomic) BOOL selfCollision;
@property (nonatomic, copy, nullable) NSArray<UDAFBody *> *bodies;
@property (nonatomic, copy, nullable) NSArray<UDAFConstraint *> *constraints;

/// idDeclAF::NewBody and NewConstraint: a body or a constraint by SetDefault,
/// named @a name, last; DeleteBody, which takes the constraints on the body
/// off too, and DeleteConstraint; RenameBody, which renames it in the
/// constraints too (a body's name set through KVC, a binding's edit, does).
- (void)ud_newBodyNamed:(NSString *)name;
- (void)ud_deleteBodyNamed:(NSString *)name;
- (void)ud_renameBody:(NSString *)oldName to:(NSString *)newName;
- (void)ud_newConstraintNamed:(NSString *)name;
- (void)ud_deleteConstraintNamed:(NSString *)name;

/// idDeclAF::ContentsToString( ContentsFromString( @a text ) ): the
/// contents names it reads, as the writer writes them.
+ (NSString *)ud_normalizedContents:(NSString *)text;
/// The text of the idAFVector @a text reads, or nil when it reads none.
+ (nullable NSString *)ud_normalizedVector:(NSString *)text;
@end

NS_ASSUME_NONNULL_END
