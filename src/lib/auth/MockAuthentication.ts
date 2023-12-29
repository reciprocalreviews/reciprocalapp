import { Auth } from '$lib/Context';
import type { ScholarID } from '$lib/types/Scholar';
import Authentication from './Authentication';

export default class MockAuthentication extends Authentication {
	readonly id: ScholarID;

	constructor(id: ScholarID) {
		super();
		this.id = id;
		Auth.set(this);
	}

	getScholarID() {
		return this.id;
	}

	logout() {
		Auth.set(null);
	}
}
