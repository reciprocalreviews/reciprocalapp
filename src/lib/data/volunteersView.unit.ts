import { describe, expect, test } from 'vitest';
import {
	expertiseTags,
	TAG_LIMIT,
	volunteersView,
	type ExpertiseTag,
	type ViewVolunteer,
	type VolunteersViewContext
} from './volunteersView';

function volunteer(
	over: Partial<Omit<ViewVolunteer, 'scholars'>> & {
		name?: string | null;
		email?: string | null;
	} = {}
): ViewVolunteer {
	const { name, email, ...rest } = over;
	return {
		expertise: '',
		active: true,
		scholars: {
			name: name === undefined ? 'Ann Lee' : name,
			email: email === undefined ? 'ann@uni.edu' : email
		},
		...rest
	};
}

function view(over: Partial<VolunteersViewContext> = {}) {
	return volunteersView({ filter: '', selected: new Map<string, string>(), ...over });
}

const names = (rows: ViewVolunteer[]) => rows.map((r) => r.scholars.name);
const chips = (tags: ExpertiseTag[]) => tags.map((t) => `${t.label} (${t.count})`);

describe('expertiseTags', () => {
	test('splits on commas and trims', () => {
		// The page used to render the raw split, so every tag after the first
		// arrived with a leading space.
		expect(expertiseTags('Peer review, HCI ')).toEqual(['Peer review', 'HCI']);
	});

	test('drops empty entries', () => {
		expect(expertiseTags('a,,b')).toEqual(['a', 'b']);
		expect(expertiseTags('a, ,b')).toEqual(['a', 'b']);
	});

	test('no expertise is no tags', () => {
		expect(expertiseTags('')).toEqual([]);
		expect(expertiseTags('  ')).toEqual([]);
	});
});

describe('matchesFilter', () => {
	test('an empty search keeps everyone', () => {
		expect(view().matchesFilter(volunteer({ name: 'Zoe' }))).toBe(true);
	});

	test('a whitespace-only search keeps everyone', () => {
		expect(view({ filter: '   ' }).matchesFilter(volunteer({ name: 'Zoe' }))).toBe(true);
	});

	test('matches the name, case-insensitively', () => {
		expect(view({ filter: 'ANN' }).matchesFilter(volunteer())).toBe(true);
	});

	test('matches the expertise', () => {
		expect(view({ filter: 'peer' }).matchesFilter(volunteer({ expertise: 'Peer review' }))).toBe(
			true
		);
	});

	test('matches the email', () => {
		expect(view({ filter: 'uni.edu' }).matchesFilter(volunteer())).toBe(true);
	});

	test('a scholar with no name or email does not throw', () => {
		expect(view({ filter: 'ann' }).matchesFilter(volunteer({ name: null, email: null }))).toBe(
			false
		);
	});

	test('unrelated text does not match', () => {
		expect(view({ filter: 'zzz' }).matchesFilter(volunteer())).toBe(false);
	});
});

describe('matchesTags', () => {
	const hci = volunteer({ expertise: 'HCI, education' });

	test('an empty selection keeps everyone', () => {
		// The case that would otherwise silently blank the page.
		expect(view().matchesTags(volunteer({ expertise: '' }))).toBe(true);
	});

	test('one of several selected tags is enough — union, not intersection', () => {
		expect(
			view({
				selected: new Map([
					['hci', 'HCI'],
					['databases', 'databases']
				])
			}).matchesTags(hci)
		).toBe(true);
	});

	test('membership is case-insensitive', () => {
		expect(
			view({ selected: new Map([['peer review', 'peer review']]) }).matchesTags(
				volunteer({ expertise: 'Peer Review' })
			)
		).toBe(true);
	});

	test('an untrimmed source tag still matches', () => {
		expect(
			view({ selected: new Map([['peer review', 'peer review']]) }).matchesTags(
				volunteer({ expertise: 'a, peer review' })
			)
		).toBe(true);
	});

	test('a volunteer with none of them is dropped', () => {
		expect(view({ selected: new Map([['databases', 'databases']]) }).matchesTags(hci)).toBe(false);
	});
});

describe('tags', () => {
	test('groups spellings that differ only in case', () => {
		const tags = view().tags([
			volunteer({ expertise: 'Peer Review' }),
			volunteer({ expertise: 'peer review' })
		]);
		expect(tags).toHaveLength(1);
		expect(tags[0].count).toBe(2);
	});

	test('the label is the spelling the most volunteers wrote', () => {
		expect(
			chips(
				view().tags([
					volunteer({ expertise: 'peer review' }),
					volunteer({ expertise: 'peer review' }),
					volunteer({ expertise: 'Peer review' })
				])
			)
		).toEqual(['peer review (3)']);
	});

	test('the result does not depend on the order the rows arrived in', () => {
		// The commitments query has no `order by`, so a label or a rank chosen by
		// position could change between page loads.
		const rows = [
			volunteer({ expertise: 'Peer review' }),
			volunteer({ expertise: 'peer review' }),
			volunteer({ expertise: 'peer review' }),
			volunteer({ expertise: 'HCI' }),
			volunteer({ expertise: 'hci' }),
			volunteer({ expertise: 'HCI' })
		];
		expect(chips(view().tags(rows))).toEqual(chips(view().tags(rows.toReversed())));
	});

	test('counts volunteers, not mentions', () => {
		expect(chips(view().tags([volunteer({ expertise: 'peer review, Peer Review' })]))).toEqual([
			'peer review (1)'
		]);
	});

	test('ranks by count, descending', () => {
		expect(
			chips(
				view().tags([
					volunteer({ expertise: 'rare' }),
					volunteer({ expertise: 'common' }),
					volunteer({ expertise: 'common' })
				])
			)
		).toEqual(['common (2)', 'rare (1)']);
	});

	test('breaks count ties on the key, ascending', () => {
		expect(
			chips(view().tags([volunteer({ expertise: 'zebra' }), volunteer({ expertise: 'apple' })]))
		).toEqual(['apple (1)', 'zebra (1)']);
	});

	test('counts only the volunteers the search box matched', () => {
		expect(
			chips(
				view({ filter: 'ann' }).tags([
					volunteer({ name: 'Ann Lee', expertise: 'HCI' }),
					volunteer({ name: 'Bob Ray', email: 'bob@uni.edu', expertise: 'HCI' })
				])
			)
		).toEqual(['HCI (1)']);
	});

	test('is not narrowed by the current selection', () => {
		// Otherwise the list collapses to what you already picked and a second
		// chip can never be added.
		expect(
			chips(
				view({ selected: new Map([['hci', 'HCI']]) }).tags([
					volunteer({ expertise: 'HCI' }),
					volunteer({ expertise: 'databases' })
				])
			)
		).toEqual(['databases (1)', 'HCI (1)']);
	});

	test('a selected tag the search counted out is kept, last, at zero, still labelled', () => {
		// The label comes from the selection rather than the key, so a chip that
		// read "Databases" does not become "databases" the moment it hits zero.
		expect(
			chips(
				view({ filter: 'ann', selected: new Map([['databases', 'Databases']]) }).tags([
					volunteer({ name: 'Ann Lee', expertise: 'HCI' }),
					volunteer({ name: 'Bob Ray', email: 'bob@uni.edu', expertise: 'Databases' })
				])
			)
		).toEqual(['HCI (1)', 'Databases (0)']);
	});

	test('a selected tag keeps the label it was picked with when the search re-spells it', () => {
		const rows = [
			volunteer({ name: 'Ann Lee', expertise: 'peer review' }),
			volunteer({ name: 'Bob Ray', email: 'bob@uni.edu', expertise: 'Peer Review' })
		];
		// Narrowing to the one volunteer who capitalized it would otherwise relabel
		// a control the reader is in the middle of using.
		expect(
			chips(view({ filter: 'bob', selected: new Map([['peer review', 'peer review']]) }).tags(rows))
		).toEqual(['peer review (1)']);
		// Unselected, the same narrowing does pick the spelling that survived.
		expect(chips(view({ filter: 'bob' }).tags(rows))).toEqual(['Peer Review (1)']);
	});

	test('volunteers with no expertise contribute nothing', () => {
		expect(view().tags([volunteer({ expertise: '' }), volunteer({ expertise: ' , ' })])).toEqual(
			[]
		);
	});
});

describe('capped', () => {
	const many = (n: number) =>
		Array.from({ length: n }, (_, i) => ({ key: `t${i}`, label: `t${i}`, count: n - i }));

	test('returns everything at or under the limit', () => {
		const tags = many(TAG_LIMIT);
		expect(view().capped(tags)).toEqual(tags);
	});

	test('truncates above the limit, keeping the head order', () => {
		const tags = many(TAG_LIMIT + 3);
		expect(view().capped(tags)).toEqual(tags.slice(0, TAG_LIMIT));
	});

	test('a selected tag beyond the limit is appended, so it can be unselected', () => {
		const tags = many(TAG_LIMIT + 3);
		const last = tags[tags.length - 1];
		expect(view({ selected: new Map([[last.key, last.label]]) }).capped(tags)).toEqual([
			...tags.slice(0, TAG_LIMIT),
			last
		]);
	});
});

describe('sortedAndFiltered', () => {
	test('active before inactive, whatever their names', () => {
		expect(
			names(
				view().sortedAndFiltered([
					volunteer({ name: 'Ann Adams', active: false }),
					volunteer({ name: 'Zoe Zeta' })
				])
			)
		).toEqual(['Zoe Zeta', 'Ann Adams']);
	});

	test('orders by family name, not given name', () => {
		expect(
			names(
				view().sortedAndFiltered([
					volunteer({ name: 'Adam Zeta' }),
					volunteer({ name: 'Zoe Adams' })
				])
			)
		).toEqual(['Zoe Adams', 'Adam Zeta']);
	});

	test('breaks a family-name tie on the full name', () => {
		expect(
			names(
				view().sortedAndFiltered([volunteer({ name: 'Bob Lee' }), volunteer({ name: 'Ann Lee' })])
			)
		).toEqual(['Ann Lee', 'Bob Lee']);
	});

	test('breaks a full-name tie on the email', () => {
		const rows = view().sortedAndFiltered([
			volunteer({ name: 'Ann Lee', email: 'b@uni.edu' }),
			volunteer({ name: 'Ann Lee', email: 'a@uni.edu' })
		]);
		expect(rows.map((r) => r.scholars.email)).toEqual(['a@uni.edu', 'b@uni.edu']);
	});

	test('a scholar with no name orders by the email the row shows', () => {
		// Not by the empty string, which would sort them above every A.
		expect(
			names(
				view().sortedAndFiltered([
					volunteer({ name: 'Ann Mead' }),
					volunteer({ name: null, email: 'zed@uni.edu' })
				])
			)
		).toEqual(['Ann Mead', null]);
	});

	test('the search box and the expertise chips are ANDed', () => {
		expect(
			names(
				view({ filter: 'ann', selected: new Map([['hci', 'HCI']]) }).sortedAndFiltered([
					volunteer({ name: 'Ann Lee', expertise: 'HCI' }),
					volunteer({ name: 'Ann Ray', expertise: 'databases' }),
					volunteer({ name: 'Bob Ray', email: 'bob@uni.edu', expertise: 'HCI' })
				])
			)
		).toEqual(['Ann Lee']);
	});

	test('an inactive volunteer that matches is shown, just last', () => {
		// Volunteering is a permanent record that deactivates rather than
		// disappears, so hiding them would be a behavior change.
		expect(
			names(
				view({ filter: 'ann' }).sortedAndFiltered([volunteer({ name: 'Ann Lee', active: false })])
			)
		).toEqual(['Ann Lee']);
	});

	test('does not mutate the array it was given', () => {
		const rows = [volunteer({ name: 'Zoe Zeta' }), volunteer({ name: 'Ann Adams' })];
		view().sortedAndFiltered(rows);
		expect(names(rows)).toEqual(['Zoe Zeta', 'Ann Adams']);
	});
});
