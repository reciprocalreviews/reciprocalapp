import type { ScholarID } from '$lib/types/Scholar';
import type Database from './Database';

export default async function createScholar(
	db: Database,
	orcid: ScholarID,
	name: string,
	expertise: string[]
) {
	let scholar = await db.getScholar(orcid);
	// Already have an account? Do nothing.
	if (scholar !== null) return;

	// Otherwise, create a scholar with reasonable defaults. Start by creating a transaction with a welcome gift.
	const welcome = await db.createTransaction({
		id: crypto.randomUUID(),
		submissionID: null,
		editorID: null,
		scholarID: orcid,
		amount: 4,
		purpose: 'gift',
		description: 'Welcome!',
		creationtime: Date.now()
	});

	scholar = await db.createScholar({
		id: orcid,
		name,
		expertise,
		reviewing: true,
		minimum: 8,
		sources: [],
		creationtime: Date.now(),
		transactions: [welcome.id]
	});

	return scholar;
}
