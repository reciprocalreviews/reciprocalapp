import type Source from '$lib/types/Source';
import type { SourceID } from '$lib/types/Source';
import type Submission from '$lib/types/Submission';
import type { Charge, TransactionID } from '$lib/types/Transaction';
import type Transaction from '$lib/types/Transaction';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { CurrencyID, ProposalID, ScholarID, ScholarRow, SupporterID } from '../../data/types';
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
		editors: string[],
		census: number,
		message: string
	): Promise<ErrorID | ProposalID> {
		// Make a proposal
		const { data, error } = await this.client
			.from('proposals')
			.insert({ title, editors, census })
			.select()
			.single();

		if (error || data === null) {
			console.error(error);
			return 'CreateProposal';
		}

		const proposalid = data.id;

		const supportError = await this.addSupporter(scholarid, proposalid, message);

		if (supportError) return supportError;

		return proposalid;
	}

	async editProposalTitle(venue: ProposalID, title: string): Promise<ErrorID | undefined> {
		const { error } = await this.client.from('proposals').update({ title }).eq('id', venue);
		if (error) return 'EditProposalTitle';
		else return;
	}

	async editProposalCensus(venue: ProposalID, census: number): Promise<ErrorID | undefined> {
		const { error } = await this.client.from('proposals').update({ census }).eq('id', venue);
		if (error) return 'EditProposalCensus';
		else return;
	}

	async editProposalEditors(venue: ProposalID, editors: string[]): Promise<ErrorID | undefined> {
		const { error } = await this.client.from('proposals').update({ editors }).eq('id', venue);
		if (error) return 'EditProposalEditors';
		else return;
	}

	async deleteProposal(proposal: ProposalID): Promise<ErrorID | undefined> {
		const { error } = await this.client.from('proposals').delete().eq('id', proposal);
		if (error) return 'DeleteProposal';
		else return;
	}

	async addSupporter(
		scholarid: ScholarID,
		proposalid: ProposalID,
		message: string
	): Promise<ErrorID | undefined> {
		// Make the first supporter
		const { error } = await this.client
			.from('supporters')
			.insert({ proposalid, scholarid, message });

		if (error) {
			console.error(error);
			return 'CreateSupporter';
		}
	}

	async editSupport(support: SupporterID, message: string): Promise<ErrorID | undefined> {
		const { error } = await this.client.from('supporters').update({ message }).eq('id', support);
		if (error) return 'EditSupport';
		else return;
	}

	async deleteSupport(support: SupporterID): Promise<ErrorID | undefined> {
		const { error } = await this.client.from('supporters').delete().eq('id', support);
		if (error) return 'RemoveSupport';
		else return;
	}

	async updateCurrencyName(id: CurrencyID, name: string): Promise<ErrorID | undefined> {
		const { error } = await this.client.from('currencies').update({ name }).eq('id', id);
		if (error) return 'UpdateCurrencyName';
		else return;
	}

	async updateCurrencyDescription(
		id: CurrencyID,
		description: string
	): Promise<ErrorID | undefined> {
		const { error } = await this.client.from('currencies').update({ description }).eq('id', id);
		if (error) return 'UpdateCurrencyDescription';
	}
}
