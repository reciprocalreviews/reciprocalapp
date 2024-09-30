import type Source from '$lib/types/Source';
import type { SourceID } from '$lib/types/Source';
import type Submission from '$lib/types/Submission';
import type { Charge, TransactionID } from '$lib/types/Transaction';
import type Transaction from '$lib/types/Transaction';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { ProposalID, ScholarID, ScholarRow } from '../../data/types';
import Database, { type ErrorID } from './Database';
import Scholar from './Scholar.svelte';

export default class SupabaseDB extends Database {
	/** Reference to the database connection. */
	private readonly client: SupabaseClient;

	/** A set of reactive scholar record states, indexed by ID */
	private readonly scholars: Map<ScholarID, Scholar> = new Map();

	constructor(client: SupabaseClient) {
		super();
		this.client = client;
	}

	createSubmission(submission: Submission): Promise<Submission> {
		throw new Error('Method not implemented.');
	}
	getSubmission(submissionID: string): Promise<Submission> {
		throw new Error('Method not implemented.');
	}
	updateSubmission(submission: Submission): Promise<Submission> {
		throw new Error('Method not implemented.');
	}
	verifyCharges(charges: Charge[]): Promise<true | Charge[]> {
		throw new Error('Method not implemented.');
	}
	createSource(source: Source): Promise<Source> {
		throw new Error('Method not implemented.');
	}
	getSource(sourceID: string): Promise<Source> {
		throw new Error('Method not implemented.');
	}
	getSources(): Promise<Source[]> {
		throw new Error('Method not implemented.');
	}
	getEditedSources(editor: ScholarID): Promise<Source[]> {
		throw new Error('Method not implemented.');
	}
	updateSource(source: Source): Promise<Source> {
		throw new Error('Method not implemented.');
	}
	getActiveSubmissions(sourceID: SourceID): Promise<Submission[]> {
		throw new Error('Method not implemented.');
	}
	getSourceVolunteers(sourceID: SourceID): Promise<{ scholar: ScholarRow; balance: number }[]> {
		throw new Error('Method not implemented.');
	}

	/** Register a reactive scholar state. */
	registerScholar(row: ScholarRow) {
		let scholar = this.scholars.get(row.id);
		if (scholar === undefined) {
			scholar = new Scholar(row);
			this.scholars.set(row.id, scholar);
		}
		return scholar;
	}

	createScholar(scholar: ScholarRow): Promise<ScholarRow> {
		throw new Error('Method not implemented.');
	}

	async getScholar(scholarID: ScholarID): Promise<Scholar | null> {
		const scholar = this.scholars.get(scholarID);
		if (scholar) return scholar;

		const { data, error } = await this.client
			.from('scholars')
			.select()
			.eq('id', scholarID)
			.single();
		if (error) return null;
		return this.registerScholar(data);
	}

	updateScholar(scholar: ScholarRow): Promise<ScholarRow> {
		throw new Error('Method not implemented.');
	}

	async updateScholarName(id: ScholarID, name: string): Promise<ErrorID | undefined> {
		const { error } = await this.client.from('scholars').update({ name }).eq('id', id);
		if (error) return 'UpdateScholarName';
		else {
			const state = this.scholars.get(id);
			if (state) state.setName(name);
			return undefined;
		}
	}

	async updateScholarAvailability(id: ScholarID, available: boolean): Promise<ErrorID | undefined> {
		const { error } = await this.client.from('scholars').update({ available }).eq('id', id);
		if (error) return 'UpdateScholarAvailability';
		else {
			const state = this.scholars.get(id);
			if (state) state.setAvailable(available);
			return undefined;
		}
	}

	async updateScholarStatus(id: ScholarID, status: string): Promise<ErrorID | undefined> {
		const { error } = await this.client.from('scholars').update({ status }).eq('id', id);
		if (error) return 'UpdateScholarStatus';
		else {
			const state = this.scholars.get(id);
			if (state) state.setStatus(status);
			return undefined;
		}
	}

	async updateScholarEmail(id: ScholarID, email: string): Promise<ErrorID | undefined> {
		const { error } = await this.client.from('scholars').update({ email }).eq('id', id);
		if (error) return 'UpdateScholarName';
		else {
			const state = this.scholars.get(id);
			if (state) state.setEmail(email);
			return undefined;
		}
	}

	getScholarBalance(scholarID: ScholarID): Promise<number> {
		throw new Error('Method not implemented.');
	}
	createTransaction(transaction: Transaction): Promise<Transaction> {
		throw new Error('Method not implemented.');
	}
	getTransaction(id: TransactionID): Promise<Transaction | null> {
		throw new Error('Method not implemented.');
	}
	getScholarTransactions(id: ScholarID): Promise<Transaction[]> {
		throw new Error('Method not implemented.');
	}

	async proposeVenue(
		scholarid: ScholarID,
		title: string,
		emails: string[],
		census: number,
		message: string
	): Promise<ErrorID | ProposalID> {
		// Make a proposal
		const { data, error } = await this.client
			.from('proposals')
			.insert({ title, emails: emails.join(','), census })
			.select()
			.single();

		if (error || data === null) {
			console.error(error);
			return 'CreateProposal';
		}

		const proposalid = data.id;

		// Make the first supporter
		const { error: error2 } = await this.client
			.from('supporters')
			.insert({ proposalid, scholarid, message });

		if (error2) {
			console.error(error);
			return 'CreateSupporter';
		}

		return proposalid;
	}
}
