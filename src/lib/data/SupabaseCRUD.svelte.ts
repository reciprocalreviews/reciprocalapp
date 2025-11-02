import type { Charge, TransactionID } from '$lib/types/Transaction';
import type { AuthError, PostgrestError, SupabaseClient } from '@supabase/supabase-js';
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
	SubmissionStatus,
	RoleRow,
	AssignmentRow,
	VenueRow
} from '../../data/types';
import CRUD, { NullUUID, type Result } from './CRUD';
import Scholar from './Scholar.svelte';
import type { Database } from '$data/database';
import type { SubmissionID } from '$lib/types/Submission';
import type Locale from '../../locale/Locale';
import { renderEmail, type EmailType } from '../../email/templates';

export default class SupabaseCRUD extends CRUD {
	/** Reference to the database connection. */
	readonly client: SupabaseClient<Database>;

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
	error(id: keyof Locale['error'], error?: AuthError | PostgrestError | null, details?: string) {
		const message = this.locale.error[id] + (details ? `: ${details}` : '');
		console.error(message, error);
		return { error: { message, details: error ?? undefined } };
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
		const { error } = await this.client
			.from('scholars')
			.update({ status, status_time: new Date().toISOString() })
			.eq('id', id);
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
		currency: CurrencyID | null,
		minters: string[],
		census: number,
		message: string
	): Promise<Result<string>> {
		// Make a proposal
		const { data, error: insertError } = await this.client
			.from('proposals')
			.insert({ title, url, editors, census, currency, minters })
			.select()
			.single();

		if (insertError || data === null) return this.error('CreateProposal', insertError);

		const proposalid = data.id;

		const { error } = await this.addVenueProposalSupporter(scholarid, proposalid, message);

		if (error) return { error };

		// Find the stewards to notify
		const { data: stewards } = await this.client.from('scholars').select('id').eq('steward', true);

		if (stewards)
			await this.emailScholars(
				stewards.map((s) => s.id),
				null,
				'ProposalCreatedStewards',
				[title, proposalid]
			);

		// Notify editors
		await this.sendEmail(editors, 'ProposalCreatedEditors', null, [title, proposalid]);

		return { data: proposalid };
	}

	async editVenueProposalTitle(venue: ProposalID, title: string): Promise<Result> {
		const { error } = await this.client.from('proposals').update({ title }).eq('id', venue);
		if (error) return this.error('EditProposalTitle', error);
		else return {};
	}

	async editVenueProposalCensus(venue: ProposalID, census: number): Promise<Result> {
		const { error } = await this.client.from('proposals').update({ census }).eq('id', venue);
		if (error) return this.error('EditProposalCensus', error);
		else return {};
	}

	async editVenueProposalEditors(venue: ProposalID, editors: string[]): Promise<Result> {
		const { error } = await this.client.from('proposals').update({ editors }).eq('id', venue);
		if (error) return this.error('EditProposalEditors', error);
		else return {};
	}

	async editVenueProposalURL(venue: ProposalID, url: string): Promise<Result> {
		const { error } = await this.client.from('proposals').update({ url }).eq('id', venue);
		if (error) return this.error('EditProposalURL', error);
		else return {};
	}

	async deleteVenueProposal(proposal: ProposalID): Promise<Result> {
		const { error } = await this.client.from('proposals').delete().eq('id', proposal);
		if (error) return this.error('DeleteProposal');
		else return {};
	}

	async approveVenueProposal(proposal: ProposalID): Promise<Result<string>> {
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

		if (scholarsData === null || scholarsData.length < proposalData.editors.length)
			return this.error('ApproveProposalNoScholars', scholarsError);

		// Build the editor scholar ID list from the editors found.
		let editors: ScholarID[] = scholarsData.map((scholar) => scholar.id);

		// Didn't find a editor?
		if (editors.length === 0) return this.error('ApproveProposalNoScholars');

		let currencyID = proposalData.currency;
		if (currencyID === null) {
			// Verify all minters have accounts
			const { data: mintersData, error: mintersError } = await this.client
				.from('scholars')
				.select()
				.in('email', proposalData.minters);

			if (mintersData === null || mintersData.length < proposalData.minters.length)
				return this.error('ApproveProposalNoMinters', mintersError);

			// Is there a currency proposed for the venue? If not, create a currency for the venue
			const { data: currencyData, error: currencyError } = await this.client
				.from('currencies')
				.insert({
					name: proposalData.title + ' currency',
					minters: mintersData.map((minter) => minter.id)
				})
				.select()
				.single();

			if (currencyError) return this.error('ApproveProposalNoCurrency', currencyError);

			currencyID = currencyData.id;
		}

		// Create the venue with the proposal's title, URL, and scholars.
		const { data: venueData, error: venueError } = await this.client
			.from('venues')
			.insert({
				title: proposalData.title,
				url: proposalData.url,
				editors,
				edit_amount: 1,
				welcome_amount: 10,
				submission_cost: 10,
				currency: currencyID
			})
			.select()
			.single();
		if (venueData === null || venueError !== null)
			return this.error('ApproveProposalNoVenue', venueError);

		const venueID = venueData.id;

		// Update the proposal to link to the venue.
		const { error } = await this.client
			.from('proposals')
			.update({ venue: venueID })
			.eq('id', proposal);
		if (error) return this.error('ApproveProposalCannotUpdateVenue', error);

		// Finally, trigger an email to the editors and supporters notifying them that the venue was approved.
		// First, we get all of the supporters and their emails.
		const { data: supportersData, error: supportersError } = await this.client
			.from('supporters')
			.select('scholarid')
			.eq('proposalid', proposal);
		if (supportersData === null) return this.error('ApproveProposalNoSupporters', supportersError);
		const scholarsToEmail = [...editors, ...supportersData.map((s) => s.scholarid)];

		// Send a notification email to the scholars.
		this.emailScholars(scholarsToEmail, venueID, 'VenueApproved', [proposalData.title, venueID]);

		return { data: venueID };
	}

	async addVenueProposalSupporter(
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

	async editVenueProposalSupport(support: SupporterID, message: string): Promise<Result> {
		const { error } = await this.client.from('supporters').update({ message }).eq('id', support);
		return this.errorOrEmpty('EditSupport', error);
	}

	async deleteVenueProposalSupport(support: SupporterID): Promise<Result> {
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

	async editVenueEditorCompensation(id: VenueID, amount: number) {
		const { error } = await this.client.from('venues').update({ edit_amount: amount }).eq('id', id);
		return this.errorOrEmpty('EditVenueEditorAmount', error);
	}

	async editVenueSubmissionCost(id: VenueID, amount: number) {
		const { error } = await this.client
			.from('venues')
			.update({ submission_cost: amount })
			.eq('id', id);
		return this.errorOrEmpty('EditVenueSubmissionCost', error);
	}

	async createRole(id: VenueID, name: string) {
		const { data, error } = await this.client
			.from('roles')
			.insert({ venueid: id, amount: 10, invited: true, name })
			.select()
			.single();
		if (error) return this.error('CreateRole', error);
		else return { data };
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

	async editRoleBidding(id: RoleID, biddable: boolean) {
		const { error } = await this.client.from('roles').update({ biddable }).eq('id', id);
		return this.errorOrEmpty('EditRoleBidding', error);
	}

	async editRoleApprover(id: RoleID, approver: RoleID | null) {
		const { error } = await this.client.from('roles').update({ approver }).eq('id', id);
		return this.errorOrEmpty('EditRoleApprover', error);
	}

	async editRoleAmount(id: RoleID, amount: number) {
		const { error } = await this.client.from('roles').update({ amount }).eq('id', id);
		return this.errorOrEmpty('UpdateRoleAmount', error);
	}

	async reorderRole(role: RoleRow, roles: RoleRow[], direction: -1 | 1) {
		// Sort the roles to ensure priority order
		const sorted = roles.toSorted((a, b) => a.priority - b.priority);
		// Find the index of the role
		const index = sorted.findIndex((r) => r.id === role.id);

		// Couldn't find the role? Bail.
		if (index === -1) return this.error('ReorderRole');

		// Swap the roles.
		const swap = sorted[index + direction];
		sorted[index + direction] = role;
		sorted[index] = swap;

		// Renumber the orders.
		for (const [index, role] of sorted.entries()) {
			const { error } = await this.client
				.from('roles')
				.update({ priority: index })
				.eq('id', role.id);
			if (error) return this.error('ReorderRole', error);
		}

		return {};
	}

	async deleteRole(id: RoleID) {
		const { error } = await this.client.from('roles').delete().eq('id', id);
		return this.errorOrEmpty('DeleteRole', error);
	}

	async createVolunteer(
		inviter: ScholarID,
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
		if (volunteer.length === 0 && compensate)
			await this.welcomeVolunteer(inviter, scholarid, roleid, 'Welcome tokens for volunteering');

		return { data: newVolunteer.id };
	}

	async welcomeVolunteer(
		welcomer: ScholarID,
		scholar: ScholarID,
		roleid: RoleID,
		reason: string
	): Promise<Result> {
		// Get the role and the venue.
		const { data: role, error: roleError } = await this.client
			.from('roles')
			.select()
			.eq('id', roleid)
			.single();
		if (role === null) return this.error('WelcomeVolunteer', roleError);
		const venueid = role.venueid;
		const { data: venue, error: venueError } = await this.client
			.from('venues')
			.select()
			.eq('id', venueid)
			.single();
		if (venue === null) return this.error('WelcomeVolunteer', venueError);

		const welcome = venue.welcome_amount;

		// Record an approved transaction to log the gift.
		const { data: transaction, error } = await this.createTransaction(
			welcomer,
			null,
			venueid,
			scholar,
			null,
			// Create a list of null UUIDs to represent that they don't exist yet.
			new Array(welcome).fill(NullUUID),
			venue.currency,
			reason,
			'proposed'
		);
		if (error) return this.error('WelcomeVolunteer', error.details);

		return transaction ? {} : this.error('WelcomeVolunteer');
	}

	async updateVolunteerActive(id: VolunteerID, active: boolean): Promise<Result> {
		const { error } = await this.client.from('volunteers').update({ active }).eq('id', id);
		return this.errorOrEmpty('UpdateVolunteerActive', error);
	}

	async updateVolunteerExpertise(id: VolunteerID, expertise: string): Promise<Result> {
		const { error } = await this.client.from('volunteers').update({ expertise }).eq('id', id);
		return this.errorOrEmpty('UpdateVolunteerExpertise', error);
	}

	async inviteToRole(
		inviter: ScholarID,
		role: RoleRow,
		venue: VenueRow,
		emailsOrORCIDs: string[]
	): Promise<Result<string[]>> {
		const { data: scholars, error: scholarsError } = await this.client
			.from('scholars')
			.select()
			.or(
				'email.in.(' +
					emailsOrORCIDs.map((e) => `"${e}"`).join(',') +
					'), orcid.in.(' +
					emailsOrORCIDs.map((e) => `"${e}"`).join(',') +
					')'
			);
		if (scholarsError) return this.error('InviteToRole', scholarsError);

		const missing = emailsOrORCIDs.filter(
			(id) => !scholars.some((scholar) => scholar.email === id || scholar.orcid === id)
		);
		if (missing.length > 0) return this.error('InviteToRoleMissing', null, missing.join(', '));

		const ids: string[] = [];
		for (const scholar of scholars) {
			const { data, error } = await this.createVolunteer(
				inviter,
				scholar.id,
				role.id,
				false,
				false
			);
			if (error) return { error };
			if (data) {
				ids.push(data);
				this.emailScholars([scholar.id], role.venueid, 'RoleInvite', [
					role.name,
					venue.id,
					venue.title,
					scholar.id
				]);
			}
		}
		return { data: ids };
	}

	async acceptRoleInvite(scholar: ScholarID, id: VolunteerID, response: Response) {
		const { data: volunteer, error: volunteerError } = await this.client
			.from('volunteers')
			.select()
			.eq('scholarid', scholar);
		if (volunteerError) return this.error('AcceptRoleInvite', volunteerError);

		// Mark the volunteer status as
		const { error } = await this.client
			.from('volunteers')
			.update({ active: true, accepted: response })
			.eq('id', id);

		// If the scholar is accepting the role and this is their first role, grant welcome tokens.
		if (
			volunteer &&
			volunteer.length === 1 &&
			volunteer[0].accepted === 'invited' &&
			response === 'accepted'
		)
			await this.welcomeVolunteer(
				scholar,
				scholar,
				volunteer[0].roleid,
				'Welcome tokens for accepting role invite'
			);

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

	async mintTokens(currencyID: CurrencyID, amount: number, to: VenueID): Promise<Result> {
		const rows = Array(amount)
			.fill(0)
			.map(() => ({ currency: currencyID, venue: to, scholar: null }));

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
		purpose: string,
		transaction: TransactionID | undefined
	): Promise<Result<{ transaction: TransactionID; tokens: TokenID[] }>> {
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

		// Update the existing transaction
		if (transaction) {
			const { error } = await this.client
				.from('transactions')
				.update({ status: 'approved', tokens: tokenIDs })
				.eq('id', transaction);
			if (error) return this.error('TransactionApprovalUpdate', error);
			return { data: { transaction, tokens: tokenIDs } };
		}
		// Record an approved transaction to log the gift.
		else {
			const { data: transactionID, error: transactionError } = transaction
				? { data: transaction, error: null }
				: await this.createTransaction(
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
			if (transactionID === undefined || transactionError)
				return this.error('CreateTransaction', transactionError?.details);

			return { data: { transaction: transactionID, tokens: tokenIDs } };
		}
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
	): Promise<Result<TransactionID>> {
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

	async approveTransaction(creator: ScholarID, id: TransactionID) {
		// First, get the transaction.
		const { data: transaction, error: transactionError } = await this.client
			.from('transactions')
			.select()
			.eq('id', id)
			.single();
		if (transactionError) return this.error('UnknownTransaction', transactionError);

		// Verify that the transaction is pending. If it's not, bail.
		if (transaction.status !== 'proposed') return this.error('AlreadyApproved');

		// See if we need to create any tokens by looking for null UUIDs in the token list.
		// If there are already tokens in the transaction, then something is broken.
		if (transaction.tokens.some((id) => id !== NullUUID))
			return this.error('PendingTransactionHasTokens');

		const from = transaction.from_scholar ?? transaction.from_venue;
		const to = transaction.to_scholar ?? transaction.to_venue;
		if (from === null) return this.error('TransactionMissingFrom');
		if (to === null) return this.error('TransactionMissingTo');

		// Create the required tokens so they can be transferred.
		const { error: mintingError } = await this.mintTokens(
			transaction.currency,
			transaction.tokens.length,
			from
		);
		if (mintingError) return this.error('MintTokens', mintingError.details, mintingError.message);

		// Transfer the requested number of tokens to the destination.
		const { error: transferError } = await this.transferTokens(
			creator,
			transaction.currency,
			from,
			from === transaction.from_scholar ? 'scholarid' : 'venueid',
			to,
			to === transaction.to_scholar ? 'scholarid' : 'venueid',
			transaction.tokens.length,
			transaction.purpose,
			transaction.id
		);
		if (transferError)
			return this.error('TransferVenueTokens', transferError.details, transferError.message);

		return { data: undefined };
	}

	async cancelTransaction(id: TransactionID, reason: string): Promise<Result> {
		const { error } = await this.client
			.from('transactions')
			.update({ status: 'canceled', purpose: reason })
			.eq('id', id);
		return this.errorOrEmpty('TransactionNotCanceled', error);
	}

	async approveAssignment(
		assignment: AssignmentRow,
		approved: boolean,
		role: RoleRow,
		approver: ScholarID
	): Promise<Result> {
		const { error: assignmentError } = await this.client
			.from('assignments')
			.update({ approved })
			.eq('id', assignment.id);

		// Notify the assigned
		if (assignmentError === null) {
			const scholar = await this.getScholar(approver);
			if (scholar) {
				this.emailScholars(
					[assignment.scholar],
					assignment.venue,
					approved ? 'AssignmentApproved' : 'AssignmentRemoved',
					[scholar.getName() ?? '', scholar.getEmail() ?? '', role.name, assignment.submission]
				);
			}
		}

		return this.errorOrEmpty('ApproveAssignment', assignmentError);
	}

	async createAssignment(
		submission: SubmissionID,
		scholar: ScholarID,
		roleid: RoleID,
		bid: boolean,
		approved: boolean = false
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
			.insert({ submission, scholar, role: roleid, bid, venue: role.venueid, approved });
		return this.errorOrEmpty('CreateAssignment', error);
	}

	async completeAssignment(assignment: AssignmentID, completer: ScholarID): Promise<Result> {
		// Get the assignment data
		const { data: assignmentData, error: assignmentError } = await this.client
			.from('assignments')
			.select()
			.eq('id', assignment)
			.single();
		if (assignmentData === null) return this.error('CompleteAssignmentNotFound', assignmentError);

		// Get the role data, so we can find the compensation rate.
		const { data: roleData, error: roleError } = await this.client
			.from('roles')
			.select()
			.eq('id', assignmentData.role)
			.single();
		if (roleData === null) return this.error('CompleteAssignmentRoleNotFound', roleError);

		// Get the role data, so we can find the compensation rate.
		const { data: venueData, error: venueError } = await this.client
			.from('venues')
			.select()
			.eq('id', assignmentData.venue)
			.single();
		if (venueData === null) return this.error('CompleteAssignmentVenueNotFound', venueError);

		// Create a transaction to pay the scholar.
		const { error: transactionError } = await this.createTransaction(
			completer,
			null,
			assignmentData.venue,
			assignmentData.scholar,
			null,
			// Create a list of null UUIDs to represent that they don't exist yet.
			new Array(roleData.amount).fill(NullUUID),
			venueData.currency,
			`Compensation for completing the ${roleData.name} role for submission ${assignmentData.submission}.`,
			'proposed'
		);
		if (transactionError) return this.error('CreateTransaction', transactionError.details);

		// Mark the assignment as completed.
		await this.client.from('assignments').update({ completed: true }).eq('id', assignmentData.id);

		return { data: undefined, error: undefined };
	}

	async deleteAssignment(assignment: AssignmentID): Promise<Result> {
		const { error } = await this.client.from('assignments').delete().eq('id', assignment);
		return this.errorOrEmpty('DeleteAssignment', error);
	}

	/** Use the resend edge function to use the Resend API to send a message to the current user. */
	async emailScholars(
		scholars: ScholarID[],
		venue: VenueID | null,
		template: EmailType,
		args: string[]
	): Promise<Result> {
		// Get the email addresses of the specified scholars.
		let { data: scholarData, error: scholarsError } = await this.client
			.from('scholars')
			.select('id, email')
			.in('id', scholars);
		if (scholarData === null) return this.error('EmailScholar', scholarsError);

		// Ignore scholars without an email address.
		const scholarsWithEmail = scholarData.filter(
			(scholar): scholar is { id: string; email: string } => scholar.email !== null
		);

		return this.sendEmail(scholarsWithEmail, template, venue, args);
	}

	/** Email some people who aren't scholars */
	async sendEmail(
		emails: string[] | { id: ScholarID; email: string }[],
		template: EmailType,
		venue: VenueID | null,
		args: string[]
	) {
		// Make sure all the scholar emails have the shape of an email address.
		const missingEmails = emails.filter(
			(email) => !/^.+@.+$/.test(typeof email === 'string' ? email : email.email)
		);
		if (!emails.every((email) => /^.+@.+$/.test(typeof email === 'string' ? email : email.email)))
			return this.error(
				'EmailScholar',
				null,
				`Invalid email addresses: ${missingEmails.map((email) => email).join(', ')}`
			);

		const { subject, message } = renderEmail(template, args);

		// Insert the emails into the database, which will trigger the edge function to send the email via Resend.
		const { error: emailInsertError } = await this.client.from('emails').insert(
			emails.map((email) => ({
				scholar: typeof email === 'string' ? null : email.id,
				email: typeof email === 'string' ? email : email.email,
				event: template,
				venue: null,
				subject: subject,
				message
			}))
		);
		if (emailInsertError) return this.error('EmailScholar', emailInsertError);

		// We rely on an database trigger to call the edge function to send the email after the row is inserted into the emails table.
		// This is slower and less direct, but ensures that the email sending functionality only lives in one place.

		return { data: undefined };
	}
}
