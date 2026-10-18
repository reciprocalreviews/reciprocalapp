import type { RoleID, ScholarID } from '$data/types';
import type { AssignmentLoad } from './CRUD';

/** What an editor needs to know about one scholar's load before assigning them to a
 * role: how many active papers they have in it, against the cap they set for it, plus
 * what they carry in the venue's other roles and in other venues. */
export type Load = {
	/** Approved, uncompleted assignments in this role at this venue. */
	used: number;
	/** The papers cap the scholar set for this role; null when they set none. */
	cap: number | null;
	/** Active assignments in the venue's other roles. */
	otherRoles: number;
	/** Active assignments at other venues, editor seats excluded. */
	elsewhere: number;
};

/** Index public.assignment_loads rows, so each table cell is a lookup. */
export default class Loads {
	readonly #byRole = new Map<string, number>();
	readonly #inVenue = new Map<ScholarID, number>();
	readonly #elsewhere = new Map<ScholarID, number>();

	constructor(rows: AssignmentLoad[]) {
		for (const { scholar, role, count } of rows) {
			if (role === null) this.#elsewhere.set(scholar, count);
			else {
				this.#byRole.set(`${scholar} ${role}`, count);
				this.#inVenue.set(scholar, (this.#inVenue.get(scholar) ?? 0) + count);
			}
		}
	}

	of(scholar: ScholarID, role: RoleID, cap: number | null): Load {
		const used = this.#byRole.get(`${scholar} ${role}`) ?? 0;
		return {
			used,
			cap,
			otherRoles: (this.#inVenue.get(scholar) ?? 0) - used,
			elsewhere: this.#elsewhere.get(scholar) ?? 0
		};
	}
}

/** Whether assigning one more paper would put a scholar past the cap they set. Soft:
 * an editor may still assign, but only by saying the scholar agreed. */
export function atCap(load: Load): boolean {
	return load.cap !== null && load.used >= load.cap;
}
