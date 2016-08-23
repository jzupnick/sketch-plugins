// StatesController.m
// Copyright (c) 2016 Eden Vidal
//
// This software may be modified and distributed under the terms
// of the MIT license.  See the LICENSE file for details.

#import "STPage.h"
#import "STSketch.h"
#import "STTextField.h"
#import "STTableRowView.h"
#import "STColorFactory.h"
#import "STTableCellView.h"
#import "NSArray+Indexes.h"
#import "STStatefulArtboard.h"
#import "NSArray+HigherOrder.h"
#import "STStatefulArtboard+Snapshots.h"
#import "StatesController.h"
#import "StatesController+Naming.h"
#import "StatesController+Decisions.h"
#import "StatesController+DragNDrop.h"
#import "StatesController+ContextMenu.h"

@interface StatesController()
<SketchNotificationsListener, STTextFieldFirstResponderDelegate, STTableCellViewDelegate>
@end

@implementation StatesController

+ (instancetype)defaultController
{
	static StatesController *controller = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		controller = [[StatesController alloc] init];
		[[STSketch notificationObserver] addListener: controller];
	});
	return controller;
}

- (NSString *)windowNibName
{
	return @"StatesWindow";
}

- (void)awakeFromNib
{
	[(NSPanel *)self.window setWorksWhenModal: NO];
	[(NSPanel *)self.window setFloatingPanel: YES];

	/// NOTE: these two images are from Sketch
	self.addNewStateButton.image = [NSImage imageNamed: @"pages_add"];
	self.addNewStateButton.alternateImage = [NSImage imageNamed: @"pages_add_pressed"];
	self.addNewStateButton.toolTip = @"Add a new state which will reflect the current artboard parameters";

	self.tableView.menu = [NSMenu new];
	self.tableView.menu.delegate = self;
	self.tableView.action = @selector(singleClicked:);
	self.tableView.doubleAction = @selector(doubleClicked:);
	[self registerTableViewForDragNDrop];

	[self resetArtboard: [STSketch currentArtboard]];
}

- (void)resetArtboard: (STStatefulArtboard *)artboard
{
	_artboard = artboard;
	[self.tableView reloadData];

	if (!_artboard) {
		self.placeholderView.hidden = NO;
		self.addNewStateButton.enabled = NO;
		return;
	}

	self.placeholderView.hidden = YES;
	self.addNewStateButton.enabled = YES;

	// Pre-select the current state (if any)
	NSUInteger currentStateIndex = [_artboard.allStates indexOfObject: _artboard.currentState];
	if (currentStateIndex != NSNotFound) {
		[self.tableView selectRowIndexes: [NSIndexSet indexSetWithIndex: currentStateIndex]
					byExtendingSelection: NO];
	}
}

#pragma mark - SketchNotificationsListener

- (void)currentArtboardDidChange
{
	[self resetArtboard: [STSketch currentArtboard]];
}

- (void)currentArtboardUnselected
{
	[self resetArtboard: nil];
}

- (void)currentDocumentUpdated
{
	if (!_artboard.currentState) {
		return;
	}
	[self resetDirtyMarkOnStates];
}

#pragma mark - Dirty States

- (void)resetDirtyMarkOnStates
{
	// Show or hide an update button depending on a situation
	[_artboard.allStates enumerateObjectsUsingBlock: ^(STStateDescription *state, NSUInteger idx, BOOL *stop) {
		STTableCellView *cell = [self.tableView viewAtColumn: 0 row: idx makeIfNecessary: NO];
		if ([state isEqualTo: _artboard.currentState] && ([self.tableView editedRow] != idx)) {
			cell.updateButton.animator.hidden = [_artboard conformsToState: state];
		} else {
			cell.updateButton.animator.hidden = YES;
		}
	}];
}

#pragma mark - STTableCellViewDelegate

- (BOOL)cellViewRepresentsCurrentItem: (STTableCellView *)cellView
{
	NSInteger idx = [_artboard.allStates indexOfObject: _artboard.currentState];
	if (!_artboard || idx == NSNotFound) {
		return NO;
	}
	return cellView == [self.tableView viewAtColumn: 0 row: idx makeIfNecessary: NO];
}

- (BOOL)isSingleRowSelected
{
	return [self.tableView selectedRowIndexes].count == 1;
}

#pragma mark - User Actions

- (IBAction)createNewState: (id)sender
{
	NSString *newStateName = [self newStateNameInStates: _artboard.allStates];
	STStateDescription *state = [[STStateDescription alloc] initWithTitle: newStateName];

	[_artboard insertNewState: state];

	// Update the table view
	NSInteger newIndex = _artboard.allStates.count-1;
	[self.tableView insertRowsAtIndexes: [NSIndexSet indexSetWithIndex: newIndex]
						  withAnimation: NSTableViewAnimationEffectFade];
	// No need to ask user about switching, since the settings are already saved in this new state
	[self.tableView selectRowIndexes: [NSIndexSet indexSetWithIndex: newIndex] byExtendingSelection: NO];
	// HACK: we avoid re-apply the same artboard properties again which can take a lot of time on big
	// artboards by setting the current state directly instead of calling -applyState:.
	// This is a workaround and should be removed as soon as we find a proper solution to our
	// performance issues
	[_artboard setCurrentState: state];
	[self resetDirtyMarkOnStates];
	// Move focus to the row to allow user to immdiately change the title value
	[self.tableView editColumn: 0 row: newIndex withEvent: nil select: YES];
}

- (IBAction)updateCurrentState: (NSMenuItem *)sender
{
	NSInteger idx = [_artboard.allStates indexOfObject: _artboard.currentState];
	NSParameterAssert(idx != NSNotFound);

	STTableCellView *cell = [self.tableView viewAtColumn: 0 row: idx makeIfNecessary: NO];

	// Animations first!
	__block BOOL animationCompleted = NO;
	[cell.updateButton spinWithCompletion: ^{
		[self resetDirtyMarkOnStates];
		animationCompleted = YES;
	}];
	// Then actually update the model
	[_artboard updateCurrentState];
	// Finally we double check that the update button may be hiden safely
	if (animationCompleted) {
		[self resetDirtyMarkOnStates];
	}
}

- (IBAction)duplicateStates: (NSMenuItem *)sender
{
	NSArray <STStateDescription *> *originals = sender.representedObject;
	NSParameterAssert([originals isKindOfClass: [NSArray class]]);
	// Create a copy for every original state passed by sender
	[originals enumerateObjectsUsingBlock: ^(STStateDescription *state, NSUInteger idx, BOOL *stop) {
		NSString *duplicateTitle = [NSString stringWithFormat: @"%@ copy", state.title];
		STStateDescription *duplicate = [[STStateDescription alloc] initWithTitle: duplicateTitle];
		[_artboard insertNewState: duplicate];
		[_artboard copyState: state toState: duplicate];
	}];
	// Update the table view to reveal this new states
	NSRange newStatesRange = NSMakeRange(_artboard.allStates.count-1, originals.count);
	NSIndexSet *newIndexes = [NSIndexSet indexSetWithIndexesInRange: newStatesRange];
	[self.tableView insertRowsAtIndexes: newIndexes
						  withAnimation: NSTableViewAnimationEffectFade];
}

- (void)createPageFromStates: (NSMenuItem *)sender
{
	NSArray <STStateDescription *> *selectedStates = sender.representedObject;
	NSParameterAssert([selectedStates isKindOfClass: [NSArray class]]);

	// 1) Create a new page
	id <STPage> currentPage = [STSketch currentPage];
	id <STPage> newPage = [NSClassFromString(@"MSPage") page];
	NSAssert(newPage != nil, @"+[MSPage page] returned nil. Is this method still available?");

	newPage.name = [self pageNameForStates: selectedStates sourcePage: currentPage];
	// XXX: MSPage's pageDelegate property doesn't exist since 3.9
    if ([newPage respondsToSelector: @selector(pageDelegate)]) {
		newPage.pageDelegate = currentPage.pageDelegate;
    }
	newPage.grid = currentPage.grid;
	newPage.layout = currentPage.layout;

	// 2) for each selected state we create a "snapshot" artboard and copy it to this new page
	NSArray *artboards = [selectedStates st_map: ^id<STArtboard>(STStateDescription *state) {
		return [_artboard snapshotForState: state];
	}];
	// 2.1) we want these artboards to be aligned in a line with a little space in between items
	CGFloat gap = 200.f;
	__block CGPoint location = CGPointZero;
 	[artboards enumerateObjectsUsingBlock: ^(id <STArtboard> artboard, NSUInteger idx, BOOL *stop) {
		if (idx == 0) {
			location = [[artboard absoluteRect] absoluteRect].origin;
		}
		[[artboard absoluteRect] setX: location.x];
		location.x += [[artboard absoluteRect] absoluteRect].size.width + gap;
	}];
	[newPage addLayers: artboards];

	// 3) Insert this new page into the document
	[[[STSketch currentDocument] documentData] addPage: newPage];
	// 3.1) adjust scroll and zoom to match the source page
	newPage.scrollOrigin = currentPage.scrollOrigin;
	newPage.zoomValue = currentPage.zoomValue;
	// 3.2) mark this new page as current
	[STSketch currentDocument].currentPage = newPage;

	// 4) Select the first available artboard on a new page
	if (newPage.artboards.count > 0) {
		[[[STSketch currentDocument] documentData] deselectAllLayers];
		[newPage selectLayers: @[newPage.artboards.firstObject]];
	}
}

- (IBAction)deleteStates: (NSMenuItem *)sender
{
	NSMutableArray <STStateDescription *> *statesToDelete = [sender.representedObject mutableCopy];
	NSParameterAssert([statesToDelete isKindOfClass: [NSArray class]]);

	// We can not remove the default state so just remove if from the proposed set of states
	[statesToDelete removeObject: _artboard.defaultState];

	if (![self shoulRemoveStates: statesToDelete]) {
		return;
	}
	NSIndexSet *indexesToDelete = [_artboard.allStates st_indexesOfObjects: statesToDelete];
	// 1) remove states from data model
	[statesToDelete enumerateObjectsUsingBlock: ^(STStateDescription *state, NSUInteger idx, BOOL *stop) {
		[_artboard removeState: state];
	}];
	// 2) remove corresponding rows from table view
	[self.tableView removeRowsAtIndexes: indexesToDelete withAnimation: NSTableViewAnimationEffectFade];
	// 3) update table view selection
	NSInteger newCurrentState = [_artboard.allStates indexOfObject: _artboard.currentState];
	if (newCurrentState != NSNotFound) {
		[self.tableView selectRowIndexes: [NSIndexSet indexSetWithIndex: newCurrentState]
					byExtendingSelection: NO];
	}
}

/// Single click switches current state
- (void)singleClicked: (id)sender
{
	// Ignore clicks when multiple rows are selected
	if ([self.tableView selectedRowIndexes].count > 1) {
		return;
	}

	NSInteger row = [self.tableView clickedRow];
	if (row < 0 || row >= _artboard.allStates.count) {
		return;
	}
	STStateDescription *newState = _artboard.allStates[row];
	if (!newState) {
		return;
	}
	// Clicking on the same state will drop any current changes so we ask user about it
	if ([newState isEqualTo: _artboard.currentState]) {
		if ([self shouldSwitchToState: _artboard.currentState fromState: _artboard.currentState]) {
			[_artboard applyState: newState];
		}
		return;
	}
	// -tableView:shouldSelectRow: has been called already so we just check if the target row
	// is selected and apply the new state accordingly.
	if ([self.tableView isRowSelected: row]) {
		[_artboard applyState: newState];
		[self resetDirtyMarkOnStates];
	}
}

/// Double click makes a state title text fiels editable
- (void)doubleClicked: (id)sender
{
	// Ignore clicks when multiple rows are selected
	if ([self.tableView selectedRowIndexes].count > 1) {
		return;
	}

	NSInteger row = [self.tableView clickedRow];
	if (row < 0 || row >= _artboard.allStates.count) {
		return;
	}
	[self.tableView editColumn: 0 row: row withEvent: nil select: YES];
}

#pragma mark User Did Commit New State Title

- (void)controlTextDidEndEditing: (NSNotification *)obj
{
	NSTextView *editor = [obj.userInfo valueForKey: @"NSFieldEditor"];
	NSInteger updatedRow = [self.tableView rowForView: editor];
	if (updatedRow < 0 || updatedRow >= _artboard.allStates.count) {
		return;
	}

	NSString *newTitle = [[editor string] stringByTrimmingCharactersInSet:
						  [NSCharacterSet whitespaceAndNewlineCharacterSet]];
	// We either commit the change or just reset the row if user input is invalid
	if (newTitle.length > 0) {
		[_artboard updateName: newTitle forState: _artboard.allStates[updatedRow]];
	} else {
		[self.tableView reloadDataForRowIndexes: [NSIndexSet indexSetWithIndex: updatedRow]
								  columnIndexes: [NSIndexSet indexSetWithIndex: 0]];
	}
	// Don't forget about the update button we've hidden
	[self resetDirtyMarkOnStates];
}

/// Hide an update button when a state title is being edited
- (void)textFieldBecomeFirstResponder: (NSTextField *)textField
{
	NSInteger row = [self.tableView rowForView: textField];
	if (row < 0 || row >= _artboard.allStates.count) {
		return;
	}
	STTableCellView *cell = [self.tableView viewAtColumn: 0 row: row makeIfNecessary:NO];
	cell.updateButton.hidden = YES;
}

#pragma mark - NSTableViewDataSource & NSTableViewDelegate

- (NSInteger)numberOfRowsInTableView: (NSTableView *)tableView
{
	return _artboard.allStates.count;
}

- (NSView *)tableView: (NSTableView *)tableView viewForTableColumn: (NSTableColumn *)tableColumn row: (NSInteger)row
{
	STStateDescription *state = _artboard.allStates[row];
	if (!state) {
		return nil;
	}
	STTableCellView *cellView = [tableView makeViewWithIdentifier: @"StateCell" owner: nil];
	if (!cellView) {
		return nil;
	}
	cellView.delegate = self;
	// Setup text field
	cellView.textField.stringValue = state.title;
	cellView.textField.delegate = self;
	((STTextField *)cellView.textField).firstResponderDelegate = self;
	// Setup update button
	cellView.updateButton.action = @selector(updateCurrentState:);
	cellView.updateButton.target = self;
	// Toggle update button's visibility
	if ([[tableView selectedRowIndexes] containsIndex: row]) {
		cellView.updateButton.hidden = [_artboard conformsToState: state];
	} else {
		cellView.updateButton.hidden = YES;
	}
	return cellView;
}

#pragma mark Selection Filter

- (NSIndexSet *)tableView: (NSTableView *)tableView selectionIndexesForProposedSelection: (NSIndexSet *)proposedSelectionIndexes
{
	// Don't allow table view to reset selection automatically from multiple rows to "nothing". In
	// this case it will select the last row which may not represent the current state
	if ([tableView selectedRowIndexes].count > 1 && proposedSelectionIndexes.count == 0) {
		NSInteger currentRow = [_artboard.allStates indexOfObject: _artboard.currentState];
		if (currentRow != NSNotFound) {
			return [NSIndexSet indexSetWithIndex: currentRow];
		} else {
			return [NSIndexSet indexSet];
		}
	}
	// Redraw the already selected row when we're dropping multiselection to just this one row
	if ([tableView selectedRowIndexes].count > 1 && proposedSelectionIndexes.count == 1) {
		STStateDescription *newState = _artboard.allStates[proposedSelectionIndexes.firstIndex];
		if (![self shouldSwitchToState: newState fromState: _artboard.currentState]) {
			return [NSIndexSet indexSet];
		}
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
									 (int64_t)(0 * NSEC_PER_SEC)), dispatch_get_main_queue(),
		^{
			[self.tableView rowViewAtRow: proposedSelectionIndexes.firstIndex
						 makeIfNecessary: NO].needsDisplay = YES;
		});
		return proposedSelectionIndexes;
	}

	// Always allow to expand selection. Note that we don't switch states in this case
	if (proposedSelectionIndexes.count > 1) {
		return proposedSelectionIndexes;
	}
	// Always allow initial selection
	if (self.tableView.selectedRowIndexes.count == 0) {
		return proposedSelectionIndexes;
	}
	// Don't allow to drop selection from one row to zero
	if (proposedSelectionIndexes.count == 0) {
		return [NSIndexSet indexSet];
	}
	// So we're switching from one state to another; ask user about this
	STStateDescription *oldState = _artboard.allStates[tableView.selectedRowIndexes.firstIndex];
	STStateDescription *newState = _artboard.allStates[proposedSelectionIndexes.firstIndex];
	if ([self shouldSwitchToState: newState fromState: oldState]) {
		return proposedSelectionIndexes;
	}

	return [NSIndexSet indexSet];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	// Update cell views for current selection state (e.g. set text color, etc)
	[_artboard.allStates enumerateObjectsUsingBlock: ^(id obj, NSUInteger idx, BOOL * stop) {
		NSTableCellView *view = [self.tableView viewAtColumn: 0 row: idx makeIfNecessary: NO];
		view.backgroundStyle = view.backgroundStyle;
	}];
}

#pragma mark Row Coloring

- (NSTableRowView *)tableView: (NSTableView *)tableView rowViewForRow: (NSInteger)row
{
	return [[STTableRowView alloc] initWithTableView: tableView];
}

@end
