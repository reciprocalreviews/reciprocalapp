import type { ScholarRow } from '../../data/types';

export default class Scholar {
	private data: ScholarRow = $state({} as ScholarRow);

	constructor(scholar: ScholarRow) {
		this.data = scholar;
	}

	getID() {
		return this.data.id;
	}

	getName() {
		return this.data.name;
	}

	setName(name: string) {
		this.data = { ...this.data, name };
	}

	getORCID() {
		return this.data.orcid;
	}

	getJoined() {
		return this.data.when;
	}

	isAvailable() {
		return this.data.available;
	}

	set(state: ScholarRow) {
		this.data = state;
	}

	get() {
		return this.data;
	}
}
