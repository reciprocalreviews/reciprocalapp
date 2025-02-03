import type { Charge, TransactionID } from '$lib/types/Transaction';
import type { SupabaseClient } from '@supabase/supabase-js';
import type {
	CurrencyID,
	ProposalID,
	RoleID,
	ScholarID,
	ScholarRow,
	SupporterID,
	VenueID,
	VolunteerID,
	Response,
	TokenID,
	TransactionStatus
} from '../../data/types';
import CRUD, { NullUUID, type ErrorID } from './CRUD';
import Scholar from './Scholar.svelte';
import type { Database } from '$data/database';
import type { SubmissionID } from '$lib/types/Submission';

export default class SupabaseCRUD extends CRUD {
	/** Reference to the database connection. */
	private readonly client: SupabaseClient<Database>;

	/** A set of reactive scholar record states, indexed by ID */
	private readonly scholars: Map<ScholarID, Scholar> = new Map();

	constructor(client: SupabaseClient) {
		super();
		this.client = client;
	}

	async updateSubmissionExpertise(
		submissionID: SubmissionID,
		expertise: string | null
	): Promise<ErrorID | undefined> {
		const { error } = await this.client
			.from('submissions')
			.update({ expertise })
			.eq('id', submissionID);
		if (error) return 'UpdateSubmissionExpertise';
		else return;
	}

	async convertORCIDsToScholars(orcids: string[]) {
		// First, find the scholars with the specified ORCIDs.
		const { data: scholars, error: scholarError } = await this.client
			.from('scholars')
			.select('orcid, id')
			.in('orcid', orcids);
		if (scholars === null) {
			console.error(scholarError);
			return undefined;
		}
		return scholars;
	}

	async verifyCharges(charges: Charge[]): Promise<true | Charge[] | undefined> {
		// First, find the scholars with the specified ORCIDs.
		const scholars = await this.convertORCIDsToScholars(charges.map((charge) => charge.scholar));

		// Find the scholars that weren't found.
		if (scholars === undefined) return undefined;
		if (scholars.length < charges.length)
			return charges.map((charge) => ({
				scholar: charge.scholar,
				payment: scholars.some((s) => s.orcid === charge.scholar) ? charge.payment : undefined
			}));

		const scholarIDs = scholars.map((scholar) => scholar.id);

		// Find all of the tokens owned by the set
		const { data: tokens, error: tokenError } = await this.client
			.from('tokens')
			.select('scholar')
			.in('scholar', scholarIDs);
		if (tokenError) {
			console.error(tokenError);
			return undefined;
		}

		// Sum the tokens possessed by each scholar
		const balances = new Map<string, number>();
		for (const token of tokens) {
			if (token.scholar === null) continue;
			const balance = balances.get(token.scholar) ?? 0;
			balances.set(token.scholar, balance + 1);
		}

		// Compute the deficits
		const deficits = charges.map((charge) => {
			const scholarID = scholars.find((scholar) => scholar.orcid === charge.scholar)?.id;
			const balance = scholarID !== undefined ? (balances.get(scholarID) ?? 0) : 0;
			return {
				scholar: charge.scholar,
				payment:
					balance === undefined || charge.payment === undefined
						? undefined
						: balance - charge.payment
			};
		});

		if (deficits.some((deficit) => deficit.payment === undefined || deficit.payment < 0))
			return deficits;

		// Otherwise, all is good.
		return true;
	}

	async createSubmission(
		editor: ScholarID,
		title: string,
		expertise: string,
		venue: VenueID,
		externalID: string,
		previousID: string | null,
		charges: Charge[],
		message: string
	): Promise<undefined | ErrorID> {
		// Verify that the charges are valid.
		const chargeError = await this.verifyCharges(charges);
		if (chargeError !== true) return 'InvalidCharges';

		// First, find the scholars with the specified ORCIDs.
		const scholars = await this.convertORCIDsToScholars(charges.map((charge) => charge.scholar));

		if (scholars === undefined) return 'NewSubmission';

		const authors = charges
			.map((charge) => scholars.find((s) => s.orcid === charge.scholar)?.id)
			.filter((a) => a !== undefined);

		if (authors.length < charges.length) return 'NewSubmission';

		// Create the submission
		const { error } = await this.client.from('submissions').insert({
			title,
			expertise,
			venue,
			externalid: externalID,
			previousid: previousID,
			authors,
			payments: charges.map((charge) => charge.payment ?? 0)
		});
		if (error) {
			console.error(error);
			return 'NewSubmission';
		}

		// Create the proposed transactions
		for (const charge of charges) {
			await this.transferTokens(
				editor,
				charge.scholar,
				'emailorcid',
				venue,
				'venueid',
				charge.payment ?? 0,
				message
			);
		}
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

	async findScholar(emailOrORCID: string) {
		const { data: scholar } = await this.client
			.from('scholars')
			.select('id')
			.or(`orcid.eq.${emailOrORCID},email.eq.${emailOrORCID}`)
			.single();

		return scholar;
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
		const { data: proposalData } = await this.client
			.from('proposals')
			.select()
			.eq('id', proposal)
			.single();

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
				submission_cost: 40,
				currency: currencyData.id
			})
			.select()
			.single();
		if (venueData === null || venueError !== null) return 'ApproveProposalNoVenue';

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

		const scholar = await this.findScholar(emailOrORCID);
		if (scholar === null) return 'ScholarNotFound';

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

	async editVenueWelcomeAmount(id: VenueID, amount: number) {
		const { error } = await this.client
			.from('venues')
			.update({ welcome_amount: amount })
			.eq('id', id);
		if (error) return 'EditVenueWelcomeAmount';
		else return;
	}

	async editVenueSubmissionCost(id: VenueID, amount: number) {
		const { error } = await this.client
			.from('venues')
			.update({ submission_cost: amount })
			.eq('id', id);
		if (error) return 'EditVenueSubmissionCost';
		else return;
	}

	async editVenueBidding(id: VenueID, bidding: boolean) {
		const { error } = await this.client.from('venues').update({ bidding }).eq('id', id);
		if (error) return 'EditVenueBidding';
		else return;
	}

	async createRole(id: VenueID, name: string) {
		const { error } = await this.client
			.from('roles')
			.insert({ venueid: id, amount: 10, invited: true, name });
		if (error) return 'CreateRole';
		else return;
	}

	async editRoleName(id: RoleID, name: string) {
		const { error } = await this.client.from('roles').update({ name }).eq('id', id);
		if (error) return 'UpdateRoleName';
		else return;
	}

	async editRoleDescription(id: RoleID, description: string) {
		const { error } = await this.client.from('roles').update({ description }).eq('id', id);
		if (error) return 'UpdateRoleDescription';
		else return;
	}

	async editRoleInvited(id: RoleID, on: boolean) {
		const { error } = await this.client.from('roles').update({ invited: on }).eq('id', id);
		if (error) return 'UpdateRoleInvited';
		else return;
	}

	async editRoleAmount(id: RoleID, amount: number) {
		const { error } = await this.client.from('roles').update({ amount }).eq('id', id);
		if (error) return 'UpdateRoleAmount';
		else return;
	}

	async deleteRole(id: RoleID) {
		const { error } = await this.client.from('roles').delete().eq('id', id);
		if (error) return 'DeleteRole';
		else return;
	}

	async createVolunteer(
		scholarid: ScholarID,
		roleid: RoleID,
		accepted: boolean,
		compensate: boolean
	) {
		// First, get all of the volunteer records for this scholar.
		const { data: volunteer } = await this.client
			.from('volunteers')
			.select()
			.eq('scholarid', scholarid);
		// Couldn't get the volunteer records? Bail.
		if (volunteer === null) return 'CreateVolunteer';

		// Already volunteered for this venue? Bail.
		if (volunteer.some((v) => v.roleid === roleid)) return 'AlreadyVolunteered';

		// Create the volunteer record.
		const { error } = await this.client.from('volunteers').insert({
			scholarid,
			roleid,
			active: accepted,
			accepted: accepted ? 'accepted' : 'invited',
			expertise: ''
		});
		if (error) {
			console.error(error);
			return 'CreateVolunteer';
		}

		// If this is their first volunteer role for the venue, grant the number of welcome tokens for the venue.
		if (volunteer.length === 0 && compensate) {
			// Get the role and the venue.
			const { data: role } = await this.client.from('roles').select().eq('id', roleid).single();
			if (role === null) return 'CreateVolunteer';
			const venueid = role.venueid;
			const { data: venue } = await this.client.from('venues').select().eq('id', venueid).single();
			if (venue === null) return 'CreateVolunteer';
			const welcome = venue.welcome_amount;

			// TODO Finish after tokens and transactions table are created.
			// Record an approved transaction to log the gift.
			const error = await this.createTransaction(
				scholarid,
				null,
				venueid,
				scholarid,
				null,
				// Create a list of null UUIDs to represent that they don't exist yet.
				new Array(welcome).fill(NullUUID),
				venue.currency,
				'Welcome tokens for volunteering for the venue. Aproved by minter.',
				'proposed'
			);
			if (error) return 'CreateTransaction';
		}
	}

	async updateVolunteerActive(id: VolunteerID, active: boolean): Promise<ErrorID | undefined> {
		const { error } = await this.client.from('volunteers').update({ active }).eq('id', id);
		if (error) return 'UpdateVolunteerActive';
		else return;
	}

	async updateVolunteerExpertise(id: VolunteerID, expertise: string): Promise<ErrorID | undefined> {
		const { error } = await this.client.from('volunteers').update({ expertise }).eq('id', id);
		if (error) return 'UpdateVolunteerExpertise';
		else return;
	}

	async inviteToRole(role: RoleID, emails: string[]) {
		const { data: scholars } = await this.client.from('scholars').select().in('email', emails);
		if (scholars === null) return 'InviteToRole';

		for (const scholar of scholars) {
			const error = await this.createVolunteer(scholar.id, role, false, false);
			if (error) return error;
		}
	}

	async acceptRoleInvite(id: VolunteerID, response: Response) {
		const { error } = await this.client
			.from('volunteers')
			.update({ active: true, accepted: response })
			.eq('id', id);
		if (error) {
			console.log(error);
			return 'AcceptRoleInvite';
		}
	}

	async editCurrencyMinters(id: CurrencyID, minters: string[]): Promise<ErrorID | undefined> {
		const { error } = await this.client.from('currencies').update({ minters }).eq('id', id);
		if (error) {
			console.error(error);
			return 'EditCurrencyMinters';
		}
	}

	async addCurrencyMinter(
		id: CurrencyID,
		minters: string[],
		emailOrORCID: string
	): Promise<ErrorID | undefined> {
		const scholar = await this.findScholar(emailOrORCID);
		if (scholar === null) return 'ScholarNotFound';

		if (minters.includes(scholar.id)) return 'AlreadyMinter';

		return this.editCurrencyMinters(id, Array.from(new Set([...minters, scholar.id])));
	}

	async mintTokens(id: CurrencyID, amount: number, to: VenueID) {
		const rows = Array(amount)
			.fill(0)
			.map(() => {
				return { currency: id, venue: to, scholar: null };
			});

		const { error } = await this.client.from('tokens').insert(rows);
		if (error) {
			console.error(error);
			return 'MintTokens';
		}
	}

	async resolveEntityID(
		kind: 'venueid' | 'scholarid' | 'emailorcid',
		id: VenueID | ScholarID | string
	): Promise<VenueID | ScholarID | null> {
		if (kind === 'venueid' || kind === 'scholarid') return id;
		const scholar = await this.findScholar(id);
		if (scholar === null) return null;
		return scholar.id;
	}

	async transferTokens(
		creator: ScholarID,
		from: VenueID | ScholarID | string,
		fromKind: 'venueid' | 'scholarid' | 'emailorcid',
		to: VenueID | ScholarID,
		toKind: 'venueid' | 'scholarid' | 'emailorcid',
		amount: number,
		purpose: string
	) {
		// Find the approriate ID for the from and to entities.
		let fromEntity = await this.resolveEntityID(fromKind, from);
		let toEntity = await this.resolveEntityID(toKind, to);

		if (fromEntity === null) return 'ScholarNotFound';
		if (toEntity === null) return 'ScholarNotFound';

		// Find tokens owned by the from entity
		const { data: tokens, error: tokensError } = await this.client
			.from('tokens')
			.select()
			.eq(fromKind === 'venueid' ? 'venue' : 'scholar', fromEntity);
		if (tokensError) return 'TransferScholarTokens';

		// If there aren't enough tokens, bail.
		if (tokens.length < amount) return 'TransferTokensInsufficient';

		// Get the list of token IDs to transfer
		const tokenIDs = tokens.slice(0, amount).map((token) => token.id);

		// Transfer each token
		for (const tokenID of tokenIDs) {
			const { error } = await this.client
				.from('tokens')
				.update({
					venue: toKind === 'venueid' ? toEntity : null,
					scholar: toKind === 'venueid' ? null : toEntity
				})
				.eq('id', tokenID);
			if (error) return 'TransferVenueTokens';
		}

		// Record an approved transaction to log the gift.
		const error = await this.createTransaction(
			creator,
			fromKind === 'venueid' ? null : fromEntity,
			fromKind === 'venueid' ? fromEntity : null,
			toKind === 'venueid' ? null : toEntity,
			toKind === 'venueid' ? toEntity : null,
			tokenIDs,
			tokens[0].currency,
			purpose,
			'approved'
		);
		if (error) return 'CreateTransaction';
	}

	async createTransaction(
		creator: ScholarID,
		fromScholar: ScholarID | null,
		fromVenue: VenueID | null,
		toScholar: ScholarID | null,
		toVenue: VenueID | null,
		tokens: TokenID[],
		currency: CurrencyID,
		purpose: string,
		status: TransactionStatus
	) {
		if (fromScholar === null && fromVenue === null) return 'CreateTransaction';
		if (toScholar === null && toVenue === null) return 'CreateTransaction';

		const { error } = await this.client.from('transactions').insert({
			creator,
			from_scholar: fromScholar,
			from_venue: fromVenue,
			to_scholar: toScholar,
			to_venue: toVenue,
			tokens,
			currency,
			purpose,
			status
		});

		return error ? 'CreateTransaction' : undefined;
	}

	async approveTransaction(minter: ScholarID, id: TransactionID) {
		// First, get the transaction.
		const { data: transaction, error: transactionError } = await this.client
			.from('transactions')
			.select()
			.eq('id', id)
			.single();
		if (transactionError) return 'UnknownTransaction';

		// Verify that the transaction is pending. If it's not, bail.
		if (transaction.status !== 'proposed') return 'AlreadyApproved';

		// Verify that the transaction is from a venue
		if (transaction.from_venue === null) return 'MissingApprovalVenue';
		if (transaction.to_scholar === null) return 'MissingRecipient';

		// See if we need to create any tokens by looking for null UUIDs in the token list.
		const tokensToCreate = transaction.tokens.filter((id) => id === NullUUID);

		// If there are tokens to mint, mint them.
		if (tokensToCreate.length > 0) {
			const mintingError = await this.mintTokens(
				transaction.currency,
				tokensToCreate.length,
				transaction.from_venue
			);
			if (mintingError) return mintingError;
		}

		// Transfer the requested number of tokens to the destination.
		const transferError = await this.transferTokens(
			minter,
			transaction.from_venue,
			'venueid',
			transaction.to_scholar,
			'scholarid',
			transaction.tokens.length,
			transaction.purpose
		);
		if (transferError) return transferError;

		// Delete the old transaction
		const { error: updateError } = await this.client
			.from('transactions')
			.delete()
			.eq('id', transaction.id);
		if (updateError) return 'UndeletedTransaction';
	}
}
