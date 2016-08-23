// StatesController+DragNDrop.h
// Copyright (c) 2016 Eden Vidal
//
// This software may be modified and distributed under the terms
// of the MIT license.  See the LICENSE file for details.

#import "STStatefulArtboard.h"
#import "StatesController+DragNDrop.h"

NSString * const kStatesControllerDraggedType = @"StatesControllerDraggedType";

@implementation StatesController (DragNDrop)

- (void)registerTableViewForDragNDrop;
{
	[self.tableView registerForDraggedTypes: @[kStatesControllerDraggedType]];
}

- (BOOL)tableView: (NSTableView *)tableView writeRowsWithIndexes: (NSIndexSet *)rowIndexes toPasteboard: (NSPasteboard *)pboard
{
	NSData *indexesData = [NSKeyedArchiver archivedDataWithRootObject: rowIndexes];
	[pboard declareTypes: @[kStatesControllerDraggedType] owner: self];
	[pboard setData: indexesData forType: kStatesControllerDraggedType];
	return YES;
}

- (NSDragOperation)tableView: (NSTableView *)tableView validateDrop: (id <NSDraggingInfo>)info proposedRow: (NSInteger)row proposedDropOperation: (NSTableViewDropOperation)dropOperation
{
	if (dropOperation == NSTableViewDropAbove) {
		[info setAnimatesToDestination: YES];
		return NSDragOperationMove;
	}
	return NSDragOperationNone;
}

- (BOOL)tableView: (NSTableView *)tableView acceptDrop: (id <NSDraggingInfo>)info row: (NSInteger)row dropOperation: (NSTableViewDropOperation)dropOperation
{
	NSData *data = [[info draggingPasteboard] dataForType: kStatesControllerDraggedType];
	NSIndexSet *sourceIndexes = [NSKeyedUnarchiver unarchiveObjectWithData: data];
	//
	// FIXME: support dragging multiple items
	//
	NSUInteger destination = MIN(MAX(row, 0), _artboard.allStates.count-1);
	NSMutableArray *states = [_artboard.allStates mutableCopy];
	NSUInteger source = sourceIndexes.firstIndex;

	// 1) model updates
	id draggedState = [states objectAtIndex: source];
	[states removeObjectAtIndex: source];
	[states insertObject: draggedState atIndex: destination];
	[_artboard reorderStates: states];
	// 2) table view updates
	[tableView moveRowAtIndex: source toIndex: destination];

	return YES;
}

@end
