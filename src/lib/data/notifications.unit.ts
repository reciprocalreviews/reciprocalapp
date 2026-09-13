import { describe, expect, test } from 'vitest';
import type { Notification } from './CRUD';
import { collapseNotifications, GROUP_MAX } from './notifications';

/** N notifications of one kind, named apart so collapsing is visible in the result. Shaped like
 * what queueEmail actually emits: a singular message plus the plural form with `{count}` still
 * in it, since the producer cannot know the batch size. */
function emails(group: string, count: number, from = 1): Notification[] {
	return Array.from({ length: count }, (_, i) => ({
		message: `Scholar ${from + i} was emailed "${group}"`,
		group,
		collapsed: `Scholar ${from + i} and {count} others were emailed "${group}"`
	}));
}

/** A grouped batch whose producer wrote no plural form, exercising the fallback. */
function unworded(group: string, count: number): Notification[] {
	return Array.from({ length: count }, (_, i) => ({
		message: `Scholar ${i + 1} was emailed "${group}"`,
		group
	}));
}

describe('collapseNotifications', () => {
	test('yields nothing for an empty batch', () => {
		expect(collapseNotifications([])).toEqual([]);
	});

	test('leaves an ungrouped notification alone', () => {
		// Grouping is opt-in, so a producer that has not thought about batching is unchanged.
		const notified = [{ message: 'Thank you for volunteering!' }];
		expect(collapseNotifications(notified)).toEqual([{ message: 'Thank you for volunteering!' }]);
	});

	test('never collapses ungrouped notifications together', () => {
		// Same absent key is not the same news. Four unrelated messages stay four banners.
		const notified = [{ message: 'a' }, { message: 'b' }, { message: 'c' }, { message: 'd' }];
		expect(collapseNotifications(notified)).toHaveLength(4);
	});

	test('shows a group at exactly the maximum individually', () => {
		const banners = collapseNotifications(emails('RoleInvite', GROUP_MAX));
		expect(banners).toHaveLength(GROUP_MAX);
		expect(banners.every((b) => b.others === undefined)).toBe(true);
	});

	test('collapses a group one over the maximum', () => {
		expect(collapseNotifications(emails('RoleInvite', GROUP_MAX + 1))).toHaveLength(1);
	});

	test('renders the producer plural, naming one and counting the rest', () => {
		// 307 recipients read as one name and 306 others — off by one here would overcount every
		// batch in the app, and the count is the only thing left saying how many were reached.
		const banners = collapseNotifications(emails('CallForBids', 307));
		expect(banners).toEqual([{ message: 'Scholar 1 and 306 others were emailed "CallForBids"' }]);
	});

	test('leaves no {count} placeholder behind', () => {
		const banners = collapseNotifications(emails('CallForBids', 10));
		expect(banners[0].message).not.toContain('{count}');
	});

	test('does not set others when the producer wrote a plural', () => {
		// The plural already states the number, so a banner carrying both would say it twice.
		expect(collapseNotifications(emails('CallForBids', 50))[0].others).toBeUndefined();
	});

	test('falls back to counting when the producer wrote no plural', () => {
		// Worse prose, but still true. Showing the first message alone would speak for 49 people
		// without mentioning them.
		const banners = collapseNotifications(unworded('CallForBids', 50));
		expect(banners).toEqual([{ message: 'Scholar 1 was emailed "CallForBids"', others: 49 }]);
	});

	test('names the first notification of a collapsed group', () => {
		expect(collapseNotifications(emails('CallForBids', 10))[0].message).toContain('Scholar 1');
	});

	test('keeps distinct groups distinct', () => {
		// Creating a submission charges its co-authors AND tells an editor. That is two pieces of
		// news; collapsing by count alone would silently drop one of them.
		const notified = [...emails('SubmissionCharged', 8), ...emails('SubmissionNeedsEditor', 6)];
		const banners = collapseNotifications(notified);
		expect(banners).toHaveLength(2);
		expect(banners.map((b) => b.message)).toEqual([
			'Scholar 1 and 7 others were emailed "SubmissionCharged"',
			'Scholar 1 and 5 others were emailed "SubmissionNeedsEditor"'
		]);
	});

	test('collapses a large group while leaving a small one expanded', () => {
		const notified = [...emails('CallForBids', 50), ...emails('SubmissionsNeedEditors', 2)];
		expect(collapseNotifications(notified)).toHaveLength(1 + 2);
	});

	test('places a collapsed group where its first notification was', () => {
		// The banners should read in the order the action produced them, so a collapsed group
		// cannot drift to the end of the list.
		const notified = [{ message: 'first' }, ...emails('CallForBids', 5), { message: 'last' }];
		expect(collapseNotifications(notified).map((b) => b.message)).toEqual([
			'first',
			'Scholar 1 and 4 others were emailed "CallForBids"',
			'last'
		]);
	});

	test('collapses a group whose entries are interleaved with other news', () => {
		// inviteToRole emits one send per invitee in a loop, so a group's entries are not
		// guaranteed to be contiguous once results are merged.
		const notified = [
			{ message: 'x', group: 'A', collapsed: 'x and {count} others' },
			{ message: 'y', group: 'B' },
			{ message: 'z', group: 'A', collapsed: 'z and {count} others' },
			{ message: 'w', group: 'A', collapsed: 'w and {count} others' },
			{ message: 'v', group: 'A', collapsed: 'v and {count} others' }
		];
		const banners = collapseNotifications(notified);
		expect(banners).toEqual([{ message: 'x and 3 others' }, { message: 'y' }]);
	});

	test('always produces at least one banner for a non-empty batch', () => {
		// Most handle() call sites pass no success string, so these notifications are the only
		// evidence the action did anything. Collapsing to nothing would look like a dead click.
		for (const count of [1, GROUP_MAX, GROUP_MAX + 1, 300])
			expect(collapseNotifications(emails('CallForBids', count)).length).toBeGreaterThan(0);
	});

	test('honours a caller-supplied maximum', () => {
		expect(collapseNotifications(emails('A', 5), 10)).toHaveLength(5);
		expect(collapseNotifications(emails('A', 5), 1)).toHaveLength(1);
	});
});
