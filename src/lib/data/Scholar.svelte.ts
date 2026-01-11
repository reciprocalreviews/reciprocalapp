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
		return this.data.created_at;
	}

	isAvailable() {
		return this.data.available;
	}

	setAvailable(available: boolean) {
		this.data = { ...this.data, available };
	}

	getStatus() {
		return this.data.status;
	}

	setStatus(status: string) {
		this.data = { ...this.data, status };
	}

	getStatusTime() {
		return this.data.status_time;
	}

	getEmail() {
		return this.data.email;
	}

	setEmail(email: string) {
		this.data = { ...this.data, email };
	}

	set(state: ScholarRow) {
		this.data = state;
	}

	get() {
		return this.data;
	}
}
