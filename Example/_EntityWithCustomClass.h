// DO NOT EDIT. This file is machine-generated and constantly overwritten.
// Make changes to EntityWithCustomClass.h instead.

#import <CoreData/CoreData.h>


extern const struct EntityWithCustomClassAttributes {
	__unsafe_unretained NSString *name;
} EntityWithCustomClassAttributes;

extern const struct EntityWithCustomClassRelationships {
} EntityWithCustomClassRelationships;

extern const struct EntityWithCustomClassFetchedProperties {
} EntityWithCustomClassFetchedProperties;




@interface EntityWithCustomClassID : NSManagedObjectID {}
@end

@interface _EntityWithCustomClass : NSManagedObject {}
+ (id)insertInManagedObjectContext:(NSManagedObjectContext*)moc_;
+ (NSString*)entityName;
+ (NSEntityDescription*)entityInManagedObjectContext:(NSManagedObjectContext*)moc_;
- (EntityWithCustomClassID*)objectID;





@property (nonatomic, strong) NSString* name;



//- (BOOL)validateName:(id*)value_ error:(NSError**)error_;






@end

@interface _EntityWithCustomClass (CoreDataGeneratedAccessors)

@end

@interface _EntityWithCustomClass (CoreDataGeneratedPrimitiveAccessors)


- (NSString*)primitiveName;
- (void)setPrimitiveName:(NSString*)value;




@end
