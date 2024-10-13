import type Source from '$lib/types/Source';
import type { SourceID } from '$lib/types/Source';
import type Submission from '$lib/types/Submission';
import type { Charge, TransactionID } from '$lib/types/Transaction';
import type Transaction from '$lib/types/Transaction';
import type { SupabaseClient } from '@supabase/supabase-js';
import type {
	CurrencyID,
	ProposalID,
	ProposalRow,
	ScholarID,
	ScholarRow,
	SupporterID,
	VenueID
} from '../../data/types';
import CRUD, { type ErrorID } from './CRUD';
import Scholar from './Scholar.svelte';
import type { Database } from '$data/database';

export default class SupabaseCRUD extends CRUD {
	/** Reference to the database connection. */
	private readonly client: SupabaseClient<Database>;

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
		url: string,
		editors: string[],
		census: number,
		message: string
	) {
		// Make a proposal
		const { data, error } = await this.client
			.from('proposals')
			.insert({ title, url, editors, census })
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

	async editProposalTitle(venue: ProposalID, title: string) {
		const { error } = await this.client.from('proposals').update({ title }).eq('id', venue);
		if (error) return 'EditProposalTitle';
		else return;
	}

	async editProposalCensus(venue: ProposalID, census: number) {
		const { error } = await this.client.from('proposals').update({ census }).eq('id', venue);
		if (error) return 'EditProposalCensus';
		else return;
	}

	async editProposalEditors(venue: ProposalID, editors: string[]) {
		const { error } = await this.client.from('proposals').update({ editors }).eq('id', venue);
		if (error) return 'EditProposalEditors';
		else return;
	}

	async editProposalURL(venue: ProposalID, url: string) {
		const { error } = await this.client.from('proposals').update({ url }).eq('id', venue);
		if (error) return 'EditProposalURL';
		else return;
	}

	async deleteProposal(proposal: ProposalID) {
		const { error } = await this.client.from('proposals').delete().eq('id', proposal);
		if (error) return 'DeleteProposal';
		else return;
	}

	async approveProposal(proposal: ProposalID) {
		// Get the latest proposal data
		const { data, error: proposalError } = await this.client
			.from('proposals')
			.select()
			.eq('id', proposal)
			.single();

		// Supabase isn't getting the type correctly from the query above :(
		const proposalData = data as ProposalRow;

		// Couldn't get proposal data? Return an error.
		if (proposalData === null) return 'ApproveProposalNotFound';

		// Find the scholars with the corresponding emails.
		const { data: scholarsData } = await this.client
			.from('scholars')
			.select()
			.in('email', proposalData.editors);

		if (scholarsData === null) return 'ApproveProposalNoScholars';

		// Build the editor scholar ID list from the editors found.
		let editors: string[] = scholarsData.map((scholar) => scholar.id);

		// Didn't find a editor?
		if (editors.length === 0) return 'ApproveProposalNoScholars';

		// Create a currency for the venue
		const { data: currencyData } = await this.client
			.from('currencies')
			.insert({ name: proposalData.title, minters: editors })
			.select()
			.single();

		if (currencyData === null) return 'ApproveProposalNoCurrency';

		// Create default commitments for the venue

		// Create the venue with the proposal's title, URL, and scholars.
		const { data: venueData, error: venueError } = await this.client
			.from('venues')
			.insert({
				title: proposalData.title,
				url: proposalData.url,
				editors,
				welcome_amount: 40,
				currency: currencyData.id
			})
			.select()
			.single();

		if (venueData === null) return 'ApproveProposalNoVenue';

		const venue = venueData.id;

		// Update the proposal to link to the venue.
		const { error } = await this.client.from('proposals').update({ venue }).eq('id', proposal);
		if (error) return 'ApproveProposalCannotUpdateVenue';

		return;
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

	async editSupport(support: SupporterID, message: string) {
		const { error } = await this.client.from('supporters').update({ message }).eq('id', support);
		if (error) return 'EditSupport';
		else return;
	}

	async deleteSupport(support: SupporterID) {
		const { error } = await this.client.from('supporters').delete().eq('id', support);
		if (error) return 'RemoveSupport';
		else return;
	}

	async updateCurrencyName(id: CurrencyID, name: string) {
		const { error } = await this.client.from('currencies').update({ name }).eq('id', id);
		if (error) return 'UpdateCurrencyName';
		else return;
	}

	async updateCurrencyDescription(id: CurrencyID, description: string) {
		const { error } = await this.client.from('currencies').update({ description }).eq('id', id);
		if (error) return 'UpdateCurrencyDescription';
	}

	async editVenueDescription(id: VenueID, description: string) {
		const { error } = await this.client.from('venues').update({ description }).eq('id', id);
		if (error) return 'EditVenueDescription';
		else return;
	}

	async editVenueEditors(id: VenueID, editors: string[]) {
		const { error } = await this.client
			.from('venues')
			.update({ editors: Array.from(new Set(editors)) })
			.eq('id', id);
		if (error) return 'EditVenueEditors';
		else return;
	}

	async addVenueEditor(id: VenueID, emailOrORCID: string) {
		const { data: venue } = await this.client.from('venues').select().eq('id', id).single();

		if (venue === null) return 'EditVenueAddEditorVenueNotFound';

		const { data: scholar } = await this.client
			.from('scholars')
			.select('id')
			.or(`orcid.eq.${emailOrORCID},email.eq.${emailOrORCID}`)
			.single();

		if (scholar === null) return 'EditVenueAddEditorScholarNotFound';

		if (venue.editors.includes(scholar.id)) return 'EditVenueAddEditorAlreadyEditor';

		return this.editVenueEditors(id, Array.from(new Set([...venue.editors, scholar.id])));
	}

	async editVenueTitle(id: VenueID, title: string) {
		const { error } = await this.client.from('venues').update({ title }).eq('id', id);
		if (error) return 'EditVenueTitle';
		else return;
	}

	async editVenueURL(id: VenueID, url: string) {
		const { error } = await this.client.from('venues').update({ url }).eq('id', id);
		if (error) return 'EditVenueTitle';
		else return;
	}
}
