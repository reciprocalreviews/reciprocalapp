import { describe, expect, test } from 'vitest';
import canViewSubmission, { type SubmissionViewerContext } from './canViewSubmission';

const SUBMISSION = { id: 's1', authors: ['author'] };

function context(over: Partial<SubmissionViewerContext> = {}): SubmissionViewerContext {
	return {
		uid: 'viewer',
		venueAdmins: [],
		roles: [
			{ id: 'editor', biddable: false },
			{ id: 'reviewer', biddable: true }
		],
		viewerVolunteering: [],
		assignments: [],
		approvesRole: () => false,
		...over
	};
}

describe('canViewSubmission', () => {
	test('an anonymous visitor cannot', () => {
		expect(canViewSubmission(SUBMISSION, context({ uid: null }))).toBe(false);
	});

	test('an unrelated scholar cannot', () => {
		expect(canViewSubmission(SUBMISSION, context())).toBe(false);
	});

	// Branch 1
	test('a venue admin can', () => {
		expect(canViewSubmission(SUBMISSION, context({ venueAdmins: ['viewer'] }))).toBe(true);
	});

	// Branch 2
	test('an author can', () => {
		expect(canViewSubmission(SUBMISSION, context({ uid: 'author' }))).toBe(true);
	});

	// Branch 3 — the one a naive "is assigned" gate would break.
	test('an accepted volunteer on a biddable role can, without any assignment', () => {
		expect(
			canViewSubmission(
				SUBMISSION,
				context({ viewerVolunteering: [{ roleid: 'reviewer', accepted: 'accepted' }] })
			)
		).toBe(true);
	});

	test('a volunteer on a NON-biddable role cannot on that basis alone', () => {
		expect(
			canViewSubmission(
				SUBMISSION,
				context({ viewerVolunteering: [{ roleid: 'editor', accepted: 'accepted' }] })
			)
		).toBe(false);
	});

	test('a merely invited volunteer on a biddable role cannot', () => {
		expect(
			canViewSubmission(
				SUBMISSION,
				context({ viewerVolunteering: [{ roleid: 'reviewer', accepted: 'invited' }] })
			)
		).toBe(false);
	});

	// The policy tests `accepted` only, never `active`, so an inactive volunteer
	// keeps their read access and must not be locked out here either.
	test('an inactive but accepted volunteer on a biddable role can', () => {
		expect(
			canViewSubmission(
				SUBMISSION,
				context({ viewerVolunteering: [{ roleid: 'reviewer', accepted: 'accepted' }] })
			)
		).toBe(true);
	});

	// Branch 4
	test('an approved assignee can', () => {
		expect(
			canViewSubmission(
				SUBMISSION,
				context({
					assignments: [{ submission: 's1', scholar: 'viewer', role: 'reviewer', approved: true }]
				})
			)
		).toBe(true);
	});

	test('an unapproved bid alone does not grant access under the assignee branch', () => {
		expect(
			canViewSubmission(
				SUBMISSION,
				context({
					viewerVolunteering: [],
					assignments: [{ submission: 's1', scholar: 'viewer', role: 'reviewer', approved: false }]
				})
			)
		).toBe(false);
	});

	test('an approved assignment on a DIFFERENT submission does not grant access', () => {
		expect(
			canViewSubmission(
				SUBMISSION,
				context({
					assignments: [
						{ submission: 'other', scholar: 'viewer', role: 'reviewer', approved: true }
					]
				})
			)
		).toBe(false);
	});

	// Branch 5
	test('someone who approves an assigned role can', () => {
		expect(
			canViewSubmission(
				SUBMISSION,
				context({
					assignments: [{ submission: 's1', scholar: 'someone', role: 'reviewer', approved: true }],
					approvesRole: (role) => role === 'reviewer'
				})
			)
		).toBe(true);
	});

	test('approving a role with no assignment here grants nothing', () => {
		expect(
			canViewSubmission(SUBMISSION, context({ assignments: [], approvesRole: () => true }))
		).toBe(false);
	});

	test('tolerates unloaded roles, volunteering and assignments', () => {
		expect(
			canViewSubmission(
				SUBMISSION,
				context({ roles: null, viewerVolunteering: null, assignments: null })
			)
		).toBe(false);
	});
});
