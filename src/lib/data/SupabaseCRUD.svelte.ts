import type { Charge, TransactionID } from '$lib/types/Transaction';
import type { PostgrestError, SupabaseClient } from '@supabase/supabase-js';
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
	TransactionStatus,
	AssignmentID,
	SubmissionStatus
} from '../../data/types';
import CRUD, { NullUUID, type Result } from './CRUD';
import Scholar from './Scholar.svelte';
import type { Database } from '$data/database';
import type { SubmissionID } from '$lib/types/Submission';
import type Locale from '../../locale/Locale';

export default class SupabaseCRUD extends CRUD {
	/** Reference to the database connection. */
	private readonly client: SupabaseClient<Database>;

	/** A set of reactive scholar record states, indexed by ID */
	private readonly scholars: Map<ScholarID, Scholar> = new Map();

	/** The locale for error messages */
	private readonly locale: Locale;

	constructor(client: SupabaseClient, locale: Locale) {
		super();
		this.client = client;
		this.locale = locale;
	}

	/** A helper function for creating a result with an error ID. */
	error(id: keyof Locale['error'], details?: PostgrestError | null) {
		const message = this.locale.error[id];
		console.error(message, details);
		return { error: { message, details: details ?? undefined } };
	}

	/** A helper function for returning data or an error, depending on what was returned. */
	errorOrEmpty(id: keyof Locale['error'], error: PostgrestError | null) {
		return error ? this.error(id, error) : {};
	}

	async updateSubmissionExpertise(
		submissionID: SubmissionID,
		expertise: string | null
	): Promise<Result> {
		const { error } = await this.client
			.from('submissions')
			.update({ expertise })
			.eq('id', submissionID);
		return this.errorOrEmpty('UpdateSubmissionExpertise', error);
	}

	async updateSubmissionTitle(submissionID: SubmissionID, title: string): Promise<Result> {
		const { error } = await this.client
			.from('submissions')
			.update({ title })
			.eq('id', submissionID);
		return this.errorOrEmpty('UpdateSubmissionTitle', error);
	}

	/** Toggle the submission stats */
	async updateSubmissionStatus(
		submissionID: SubmissionID,
		status: SubmissionStatus
	): Promise<Result> {
		const { error } = await this.client
			.from('submissions')
			.update({ status })
			.eq('id', submissionID);
		return this.errorOrEmpty('UpdateSubmissionStatus', error);
	}

	async convertORCIDsToScholars(
		orcids: string[]
	): Promise<Result<{ orcid: string | null; id: string }[]>> {
		// First, find the scholars with the specified ORCIDs.
		const { data: scholars, error: scholarError } = await this.client
			.from('scholars')
			.select('orcid, id')
			.in('orcid', orcids);
		if (scholarError || scholars === null || scholars.length !== orcids.length) {
			console.error(scholarError);
			return this.error('ScholarNotFound', scholarError ?? undefined);
		}
		return { data: scholars };
	}

	async verifyCharges(charges: Charge[]): Promise<true | Charge[] | undefined> {
		// First, find the scholars with the specified ORCIDs.
		const { data: scholars } = await this.convertORCIDsToScholars(
			charges.map((charge) => charge.scholar)
		);

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
		creator: ScholarID,
		title: string,
		expertise: string,
		venue: VenueID,
		externalID: string,
		previousID: string | null,
		charges: Charge[]
	): Promise<Result<SubmissionID>> {
		// Verify that the charges are valid.
		const chargeError = await this.verifyCharges(charges);
		if (chargeError !== true) return { error: { message: this.locale.error.InvalidCharges } };

		// First, find the scholars with the specified ORCIDs.
		const { data: scholars, error: scholarsError } = await this.convertORCIDsToScholars(
			charges.map((charge) => charge.scholar)
		);

		// Couldn't find them? Bail.
		if (scholarsError || scholars === undefined)
			return {
				error: { message: this.locale.error.ScholarNotFound, details: scholarsError?.details }
			};

		// Verify that we found a scholar for all charges.
		const authors = charges
			.map((charge) => scholars.find((s) => s.orcid === charge.scholar)?.id)
			.filter((a) => a !== undefined);

		if (authors.length < charges.length)
			return { error: { message: this.locale.error.MissingSubmissionCharge } };

		// Get the requested venue
		const { data: venueData, error: venueError } = await this.client
			.from('venues')
			.select()
			.eq('id', venue)
			.single();
		if (venueError || venue === null)
			return {
				error: { message: this.locale.error.UnknownVenue, details: venueError ?? undefined }
			};

		// Create proposed transactions for all charges.
		const transactions: string[] = [];
		for (let scholarIndex = 0; scholarIndex < charges.length; scholarIndex++) {
			const charge = charges[scholarIndex];
			const scholarID = authors[scholarIndex];
			const { data: proposedScholarTransactionID, error } = await this.createTransaction(
				creator,
				// From this scholar to the given venue
				scholarID,
				null,
				null,
				venue,
				// Represent hypothetical tokens with a list of null UUIDs
				Array.from(new Array(charge.payment ?? 0), () => NullUUID),
				venueData.currency,
				`Payment for submission ${externalID}`,
				'proposed'
			);
			if (error) {
				return {
					error: { message: this.locale.error.CreateTransaction, details: error.details }
				};
			} else if (proposedScholarTransactionID) transactions.push(proposedScholarTransactionID);
		}

		// Create the submission
		const { data: submission, error } = await this.client
			.from('submissions')
			.insert({
				title,
				expertise,
				venue,
				externalid: externalID,
				previousid: previousID,
				authors,
				payments: charges.map((charge) => charge.payment ?? 0),
				// Provide the list of proposed transactions
				transactions: transactions
			})
			.select()
			.single();
		if (error) {
			console.error(error);
			return { error: { message: this.locale.error.NewSubmission, details: error } };
		}

		// Return the transaction IDs.
		return { data: submission.id };
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

	async findScholar(emailOrORCID: string): Promise<Result<string>> {
		const { data: scholar, error } = await this.client
			.from('scholars')
			.select('id')
			.or(`orcid.eq.${emailOrORCID},email.eq.${emailOrORCID}`)
			.single();

		return error || scholar === null ? this.error('ScholarNotFound', error) : { data: scholar.id };
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

	async updateScholarName(id: ScholarID, name: string): Promise<Result> {
		const { error } = await this.client.from('scholars').update({ name }).eq('id', id);
		if (error) return this.error('UpdateScholarName', error);
		else {
			const state = this.scholars.get(id);
			if (state) state.setName(name);
			return {};
		}
	}

	async updateScholarAvailability(id: ScholarID, available: boolean): Promise<Result> {
		const { error } = await this.client.from('scholars').update({ available }).eq('id', id);
		if (error) return this.error('UpdateScholarAvailability', error);
		else {
			const state = this.scholars.get(id);
			if (state) state.setAvailable(available);
			return {};
		}
	}

	async updateScholarStatus(id: ScholarID, status: string): Promise<Result> {
		const { error } = await this.client.from('scholars').update({ status }).eq('id', id);
		if (error) return this.error('UpdateScholarStatus', error);
		else {
			const state = this.scholars.get(id);
			if (state) state.setStatus(status);
			return {};
		}
	}

	async updateScholarEmail(id: ScholarID, email: string): Promise<Result> {
		const { error } = await this.client.from('scholars').update({ email }).eq('id', id);
		if (error) return this.error('UpdateScholarName', error);
		else {
			const state = this.scholars.get(id);
			if (state) state.setEmail(email);
			return {};
		}
	}

	async proposeVenue(
		scholarid: ScholarID,
		title: string,
		url: string,
		editors: string[],
		census: number,
		message: string
	): Promise<Result<string>> {
		// Make a proposal
		const { data, error: insertError } = await this.client
			.from('proposals')
			.insert({ title, url, editors, census })
			.select()
			.single();

		if (insertError || data === null) return this.error('CreateProposal', insertError);

		const proposalid = data.id;

		const { error } = await this.addSupporter(scholarid, proposalid, message);

		if (error) return { error };

		return { data: proposalid };
	}

	async editProposalTitle(venue: ProposalID, title: string): Promise<Result> {
		const { error } = await this.client.from('proposals').update({ title }).eq('id', venue);
		if (error) return this.error('EditProposalTitle', error);
		else return {};
	}

	async editProposalCensus(venue: ProposalID, census: number): Promise<Result> {
		const { error } = await this.client.from('proposals').update({ census }).eq('id', venue);
		if (error) return this.error('EditProposalCensus', error);
		else return {};
	}

	async editProposalEditors(venue: ProposalID, editors: string[]): Promise<Result> {
		const { error } = await this.client.from('proposals').update({ editors }).eq('id', venue);
		if (error) return this.error('EditProposalEditors', error);
		else return {};
	}

	async editProposalURL(venue: ProposalID, url: string): Promise<Result> {
		const { error } = await this.client.from('proposals').update({ url }).eq('id', venue);
		if (error) return this.error('EditProposalURL', error);
		else return {};
	}

	async deleteProposal(proposal: ProposalID): Promise<Result> {
		const { error } = await this.client.from('proposals').delete().eq('id', proposal);
		if (error) return this.error('DeleteProposal');
		else return {};
	}

	async approveProposal(proposal: ProposalID): Promise<Result<string>> {
		// Get the latest proposal data
		const { data: proposalData, error: proposalError } = await this.client
			.from('proposals')
			.select()
			.eq('id', proposal)
			.single();

		// Couldn't get proposal data? Return an error.
		if (proposalData === null) return this.error('ApproveProposalNotFound', proposalError);

		// Find the scholars with the corresponding emails.
		const { data: scholarsData, error: scholarsError } = await this.client
			.from('scholars')
			.select()
			.in('email', proposalData.editors);

		if (scholarsData === null) return this.error('ApproveProposalNoScholars', scholarsError);

		// Build the editor scholar ID list from the editors found.
		let editors: string[] = scholarsData.map((scholar) => scholar.id);

		// Didn't find a editor?
		if (editors.length === 0) return this.error('ApproveProposalNoScholars');

		// Create a currency for the venue
		const { data: currencyData, error: currencyError } = await this.client
			.from('currencies')
			.insert({ name: proposalData.title, minters: editors })
			.select()
			.single();

		if (currencyError) return this.error('ApproveProposalNoCurrency', currencyError);

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
		if (venueData === null || venueError !== null)
			return this.error('ApproveProposalNoVenue', venueError);

		const venue = venueData.id;

		// Update the proposal to link to the venue.
		const { error } = await this.client.from('proposals').update({ venue }).eq('id', proposal);
		if (error) return this.error('ApproveProposalCannotUpdateVenue', error);

		return { data: venue };
	}

	async addSupporter(
		scholarid: ScholarID,
		proposalid: ProposalID,
		message: string
	): Promise<Result> {
		// Make the first supporter
		const { error } = await this.client
			.from('supporters')
			.insert({ proposalid, scholarid, message });

		if (error) return this.error('CreateSupporter', error);
		else return {};
	}

	async editSupport(support: SupporterID, message: string): Promise<Result> {
		const { error } = await this.client.from('supporters').update({ message }).eq('id', support);
		return this.errorOrEmpty('EditSupport', error);
	}

	async deleteSupport(support: SupporterID): Promise<Result> {
		const { error } = await this.client.from('supporters').delete().eq('id', support);
		if (error) return this.error('RemoveSupport', error);
		else return {};
	}

	async updateCurrencyName(id: CurrencyID, name: string): Promise<Result> {
		const { error } = await this.client.from('currencies').update({ name }).eq('id', id);
		return this.errorOrEmpty('UpdateCurrencyName', error);
	}

	async updateCurrencyDescription(id: CurrencyID, description: string) {
		const { error } = await this.client.from('currencies').update({ description }).eq('id', id);
		return this.errorOrEmpty('UpdateCurrencyDescription', error);
	}

	async editVenueDescription(id: VenueID, description: string) {
		const { error } = await this.client.from('venues').update({ description }).eq('id', id);
		return this.errorOrEmpty('EditVenueDescription', error);
	}

	async editVenueEditors(id: VenueID, editors: string[]) {
		const { error } = await this.client
			.from('venues')
			.update({ editors: Array.from(new Set(editors)) })
			.eq('id', id);
		return this.errorOrEmpty('EditVenueEditors', error);
	}

	async addVenueEditor(id: VenueID, emailOrORCID: string): Promise<Result> {
		const { data: venue, error: venueError } = await this.client
			.from('venues')
			.select()
			.eq('id', id)
			.single();

		if (venue === null) return this.error('EditVenueAddEditorVenueNotFound', venueError);

		const { data: scholarID, error: scholarError } = await this.findScholar(emailOrORCID);
		if (scholarID === undefined) return this.error('ScholarNotFound', scholarError?.details);

		if (venue.editors.includes(scholarID))
			return { error: { message: this.locale.error.EditVenueAddEditorAlreadyEditor } };

		return this.editVenueEditors(id, Array.from(new Set([...venue.editors, scholarID])));
	}

	async editVenueTitle(id: VenueID, title: string) {
		const { error } = await this.client.from('venues').update({ title }).eq('id', id);
		return this.errorOrEmpty('EditVenueTitle', error);
	}

	async editVenueURL(id: VenueID, url: string) {
		const { error } = await this.client.from('venues').update({ url }).eq('id', id);
		return this.errorOrEmpty('EditVenueTitle', error);
	}

	async editVenueWelcomeAmount(id: VenueID, amount: number) {
		const { error } = await this.client
			.from('venues')
			.update({ welcome_amount: amount })
			.eq('id', id);
		return this.errorOrEmpty('EditVenueWelcomeAmount', error);
	}

	async editVenueSubmissionCost(id: VenueID, amount: number) {
		const { error } = await this.client
			.from('venues')
			.update({ submission_cost: amount })
			.eq('id', id);
		return this.errorOrEmpty('EditVenueSubmissionCost', error);
	}

	async editVenueBidding(id: VenueID, bidding: boolean) {
		const { error } = await this.client.from('venues').update({ bidding }).eq('id', id);
		return this.errorOrEmpty('EditVenueBidding', error);
	}

	async createRole(id: VenueID, name: string) {
		const { error } = await this.client
			.from('roles')
			.insert({ venueid: id, amount: 10, invited: true, name });
		return this.errorOrEmpty('CreateRole', error);
	}

	async editRoleName(id: RoleID, name: string) {
		const { error } = await this.client.from('roles').update({ name }).eq('id', id);
		return this.errorOrEmpty('UpdateRoleName', error);
	}

	async editRoleDescription(id: RoleID, description: string) {
		const { error } = await this.client.from('roles').update({ description }).eq('id', id);
		return this.errorOrEmpty('UpdateRoleDescription', error);
	}

	async editRoleInvited(id: RoleID, on: boolean) {
		const { error } = await this.client.from('roles').update({ invited: on }).eq('id', id);
		return this.errorOrEmpty('UpdateRoleInvited', error);
	}

	async editRoleAmount(id: RoleID, amount: number) {
		const { error } = await this.client.from('roles').update({ amount }).eq('id', id);
		return this.errorOrEmpty('UpdateRoleAmount', error);
	}

	async deleteRole(id: RoleID) {
		const { error } = await this.client.from('roles').delete().eq('id', id);
		return this.errorOrEmpty('DeleteRole', error);
	}

	async createVolunteer(
		scholarid: ScholarID,
		roleid: RoleID,
		accepted: boolean,
		compensate: boolean
	): Promise<Result<string>> {
		// First, get all of the volunteer records for this scholar.
		const { data: volunteer, error: volunteerError } = await this.client
			.from('volunteers')
			.select()
			.eq('scholarid', scholarid);
		// Couldn't get the volunteer records? Bail.
		if (volunteer === null) return this.error('CreateVolunteer', volunteerError);

		// Already volunteered for this venue? Bail.
		if (volunteer.some((v) => v.roleid === roleid)) return this.error('AlreadyVolunteered');

		// Create the volunteer record.
		const { data: newVolunteer, error: newVolunteerError } = await this.client
			.from('volunteers')
			.insert({
				scholarid,
				roleid,
				active: accepted,
				accepted: accepted ? 'accepted' : 'invited',
				expertise: ''
			})
			.select()
			.single();
		if (newVolunteerError) return this.error('CreateVolunteer', newVolunteerError);

		// If this is their first volunteer role for the venue, grant the number of welcome tokens for the venue.
		if (volunteer.length === 0 && compensate) {
			// Get the role and the venue.
			const { data: role, error: roleError } = await this.client
				.from('roles')
				.select()
				.eq('id', roleid)
				.single();
			if (role === null) return this.error('CreateVolunteer', roleError);
			const venueid = role.venueid;
			const { data: venue, error: venueError } = await this.client
				.from('venues')
				.select()
				.eq('id', venueid)
				.single();
			if (venue === null) return this.error('CreateVolunteer', venueError);
			const welcome = venue.welcome_amount;

			// Record an approved transaction to log the gift.
			const { error } = await this.createTransaction(
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
			if (error) return this.error('CreateTransaction', error.details);
		}

		return { data: newVolunteer.id };
	}

	async updateVolunteerActive(id: VolunteerID, active: boolean): Promise<Result> {
		const { error } = await this.client.from('volunteers').update({ active }).eq('id', id);
		return this.errorOrEmpty('UpdateVolunteerActive', error);
	}

	async updateVolunteerExpertise(id: VolunteerID, expertise: string): Promise<Result> {
		const { error } = await this.client.from('volunteers').update({ expertise }).eq('id', id);
		return this.errorOrEmpty('UpdateVolunteerExpertise', error);
	}

	async inviteToRole(role: RoleID, emails: string[]) {
		const { data: scholars, error: scholarsError } = await this.client
			.from('scholars')
			.select()
			.in('email', emails);
		if (scholars === null) return this.error('InviteToRole', scholarsError);

		for (const scholar of scholars) {
			const { error } = await this.createVolunteer(scholar.id, role, false, false);
			if (error) return error;
		}

		return {};
	}

	async acceptRoleInvite(id: VolunteerID, response: Response) {
		const { error } = await this.client
			.from('volunteers')
			.update({ active: true, accepted: response })
			.eq('id', id);
		return this.errorOrEmpty('AcceptRoleInvite', error);
	}

	async editCurrencyMinters(id: CurrencyID, minters: string[]): Promise<Result> {
		const { error } = await this.client.from('currencies').update({ minters }).eq('id', id);
		return this.errorOrEmpty('EditCurrencyMinters', error);
	}

	async addCurrencyMinter(
		id: CurrencyID,
		minters: string[],
		emailOrORCID: string
	): Promise<Result> {
		const { data: scholarID, error: scholarError } = await this.findScholar(emailOrORCID);
		if (scholarID === undefined) return this.error('ScholarNotFound', scholarError?.details);

		if (minters.includes(scholarID)) return this.error('AlreadyMinter');

		return this.editCurrencyMinters(id, Array.from(new Set([...minters, scholarID])));
	}

	async mintTokens(id: CurrencyID, amount: number, to: VenueID) {
		const rows = Array(amount)
			.fill(0)
			.map(() => {
				return { currency: id, venue: to, scholar: null };
			});

		const { error } = await this.client.from('tokens').insert(rows);
		return this.errorOrEmpty('MintTokens', error);
	}

	async resolveEntityID(
		kind: 'venueid' | 'scholarid' | 'emailorcid',
		id: VenueID | ScholarID | string
	): Promise<VenueID | ScholarID | null> {
		if (kind === 'venueid' || kind === 'scholarid') return id;
		const { data: scholar } = await this.findScholar(id);
		if (scholar === undefined) return null;
		return scholar;
	}

	async transferTokens(
		creator: ScholarID,
		currency: CurrencyID,
		from: VenueID | ScholarID | string,
		fromKind: 'venueid' | 'scholarid' | 'emailorcid',
		to: VenueID | ScholarID,
		toKind: 'venueid' | 'scholarid' | 'emailorcid',
		amount: number,
		purpose: string
	): Promise<Result<TransactionID>> {
		// Find the approriate ID for the from and to entities.
		let fromEntity = await this.resolveEntityID(fromKind, from);
		let toEntity = await this.resolveEntityID(toKind, to);

		if (fromEntity === null) return this.error('ScholarNotFound');
		if (toEntity === null) return this.error('ScholarNotFound');

		// Find tokens owned by the from entity
		const { data: tokens, error: tokensError } = await this.client
			.from('tokens')
			.select()
			.eq(fromKind === 'venueid' ? 'venue' : 'scholar', fromEntity)
			.eq('currency', currency);
		if (tokensError) return this.error('TransferScholarTokens', tokensError);

		// If there aren't enough tokens, bail.
		if (tokens.length < amount) return this.error('TransferTokensInsufficient');

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
			if (error) return this.error('TransferVenueTokens', error);
		}

		// Record an approved transaction to log the gift.
		return await this.createTransaction(
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
	): Promise<Result<string>> {
		if (fromScholar === null && fromVenue === null) return this.error('TransactionMissingFrom');
		if (toScholar === null && toVenue === null) return this.error('TransactionMissingTo');

		const { data, error } = await this.client
			.from('transactions')
			.insert({
				creator,
				from_scholar: fromScholar,
				from_venue: fromVenue,
				to_scholar: toScholar,
				to_venue: toVenue,
				tokens,
				currency,
				purpose,
				status
			})
			.select()
			.single();

		return error ? this.error('CreateTransaction', error) : { data: data.id };
	}

	async approveTransaction(minter: ScholarID, id: TransactionID) {
		// First, get the transaction.
		const { data: transaction, error: transactionError } = await this.client
			.from('transactions')
			.select()
			.eq('id', id)
			.single();
		if (transactionError) return this.error('UnknownTransaction', transactionError);

		// Verify that the transaction is pending. If it's not, bail.
		if (transaction.status !== 'proposed') return this.error('AlreadyApproved');

		// Verify that the transaction is from a venue
		if (transaction.from_venue === null) return this.error('MissingApprovalVenue');
		if (transaction.to_scholar === null) return this.error('MissingRecipient');

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
		const { error: transferError } = await this.transferTokens(
			minter,
			transaction.currency,
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
		return this.errorOrEmpty('UndeletedTransaction', updateError);
	}

	async approveAssignment(assignment: AssignmentID): Promise<Result> {
		const { error } = await this.client
			.from('assignments')
			.update({ bid: false })
			.eq('id', assignment);
		return this.errorOrEmpty('ApproveAssignment', error);
	}

	async createAssignment(
		submission: SubmissionID,
		scholar: ScholarID,
		roleid: RoleID,
		bid: boolean
	): Promise<Result> {
		const { data: role, error: roleError } = await this.client
			.from('roles')
			.select()
			.eq('id', roleid)
			.single();
		if (role === null) {
			console.error(roleError);
			return this.error('CreateAssignment', roleError);
		}

		const { error } = await this.client
			.from('assignments')
			.insert({ submission, scholar, role: roleid, bid, venue: role.venueid });
		return this.errorOrEmpty('CreateAssignment', error);
	}

	async deleteAssignment(assignment: AssignmentID): Promise<Result> {
		const { error } = await this.client.from('assignments').delete().eq('id', assignment);
		return this.errorOrEmpty('DeleteAssignment', error);
	}
}
