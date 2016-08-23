// STLayerState.h
// Copyright (c) 2016 Eden Vidal
//
// This software may be modified and distributed under the terms
// of the MIT license.  See the LICENSE file for details.

@import Foundation;

@protocol STLayer;

/// Incapsulates a state of a single layer: its frame and visibility status
@interface STLayerState : NSObject

@property (readonly) NSRect frame;
@property (readonly) BOOL visible;

- (instancetype)initWithFrame: (NSRect)aFrame visibilityStatus: (BOOL)visible;
+ (instancetype)stateWithFrame: (NSRect)aFrame visibilityStatus: (BOOL)visible;

- (NSDictionary <NSString *, id> *)dictionaryRepresentation;
- (instancetype)initWithDictionary: (NSDictionary <NSString *, id> *)dictionary;

@end

/// Applies the given layer state to the given layer
@interface STLayerStateApplier : NSObject
+ (void)apply: (STLayerState *)state toLayer: (id <STLayer>)layer;
@end

/// Returns the current layer's state
@interface STLayerStateFetcher : NSObject
+ (STLayerState *)fetchStateFromLayer: (id <STLayer>)layer;
@end

/// Verifies that the given layer conforms to the given state
@interface STLayerStateExaminer : NSObject
+ (BOOL)layer: (id <STLayer>)layer conformsToState: (STLayerState *)state;
@end
