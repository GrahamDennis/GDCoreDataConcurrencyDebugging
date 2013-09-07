// DO NOT EDIT. This file is machine-generated and constantly overwritten.
// Make changes to EntityWithCustomClass.m instead.

#import "_EntityWithCustomClass.h"

const struct EntityWithCustomClassAttributes EntityWithCustomClassAttributes = {
	.name = @"name",
};

const struct EntityWithCustomClassRelationships EntityWithCustomClassRelationships = {
};

const struct EntityWithCustomClassFetchedProperties EntityWithCustomClassFetchedProperties = {
};

@implementation EntityWithCustomClassID
@end

@implementation _EntityWithCustomClass

+ (id)insertInManagedObjectContext:(NSManagedObjectContext*)moc_ {
	NSParameterAssert(moc_);
	return [NSEntityDescription insertNewObjectForEntityForName:@"EntityWithCustomClass" inManagedObjectContext:moc_];
}

+ (NSString*)entityName {
	return @"EntityWithCustomClass";
}

+ (NSEntityDescription*)entityInManagedObjectContext:(NSManagedObjectContext*)moc_ {
	NSParameterAssert(moc_);
	return [NSEntityDescription entityForName:@"EntityWithCustomClass" inManagedObjectContext:moc_];
}

- (EntityWithCustomClassID*)objectID {
	return (EntityWithCustomClassID*)[super objectID];
}

+ (NSSet*)keyPathsForValuesAffectingValueForKey:(NSString*)key {
	NSSet *keyPaths = [super keyPathsForValuesAffectingValueForKey:key];
	

	return keyPaths;
}




@dynamic name;











@end
