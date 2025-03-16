/** A rudimentary encapsulation of locale strings. We'll modernize this when we localize. */
export const enUS = {
	error: {
		UpdateScholarStatus: 'Unable to update your status',
		UpdateScholarName: 'Unable to update your name',
		UpdateScholarEmail: 'Unable to update your email',
		UpdateScholarAvailability: 'Unable to update your availability',
		CreateProposal: 'Unable to create a venue proposal',
		EditProposalTitle: 'Unable to edit the proposal title',
		EditProposalCensus: 'Unable to edit the proposal census',
		EditProposalEditors: 'Unable to edit the proposal editors',
		EditProposalURL: 'Unable to edit the proposal URL',
		CreateSupporter: 'Unable to create a supporter',
		UpdateCurrencyName: 'Unable to update the currency name',
		UpdateCurrencyDescription: 'Unable to update the currency description',
		EditSupport: 'Unable to edit your support',
		RemoveSupport: 'Unable to remove your support',
		DeleteProposal: 'Unable to delete the proposal',
		ApproveProposalNotFound: "Unable to approve the proposal: couldn't find proposal.",
		ApproveProposalNoScholars:
			"Unable to approve the proposal: couldn't find any of the specified editors with accounts. As them to create accounts with the specified email addresses and then approve.",
		ApproveProposalNoVenue: "Unable to approve the proposal: couldn't create the venue.",
		ApproveProposalCannotUpdateVenue:
			"Unable to approve the proposal: couldn't update the venue with the proposal.",
		ApproveProposalNoCurrency:
			"Unable to approve the proposal: couldn't create a currency for the venue.",
		EditVenueDescription: 'Unable to edit the venue description',
		EditVenueEditors: 'Unable to edit the venue editors',
		EditVenueAddEditorVenueNotFound: 'Unable to find venue',
		ScholarNotFound: 'Unable to find scholar by this email or ORCID',
		EditVenueAddEditorAlreadyEditor: 'Scholar is already an editor',
		EditVenueTitle: 'Unable to edit the venue title',
		EditVenueURL: 'Unable to edit the venue URL',
		EditVenueWelcomeAmount: 'Unable to edit the welcome amount',
		EditVenueEditorAmount: 'Unable to edit the editor compensation',
		EditVenueSubmissionCost: 'Unable to edit the submission cost',
		EditRoleBidding: 'Unable to toggle bidding',
		EditRoleApprover: 'Unable to set approver',
		CreateRole: 'Unable to create new role.',
		UpdateRoleName: 'Unable to update role name',
		UpdateRoleDescription: 'Unable to update role description',
		UpdateRoleInvited: 'Unable to update invited status of role',
		UpdateRoleAmount: 'Unable to update role compensation',
		ReorderRole: 'Unable to reorder roles',
		DeleteRole: 'Unable to delete role',
		CreateVolunteer: 'Unable to add volunteer commitment',
		AlreadyVolunteered: 'Already created a volunteer commitment for this role.',
		UpdateVolunteerActive: 'Unable to update volunteer commitment',
		UpdateVolunteerExpertise: 'Unable to update your expertise',
		InviteToRole: 'Unable to invite to role',
		InviteToRoleMissing: 'Unknown scholars',
		AcceptRoleInvite: 'Unable to accept role invite',
		EditCurrencyMinters: 'Unable to edit minters',
		AddCurrencyMinter: 'Unable to add minter',
		AlreadyMinter: 'This scholar is already a minter',
		MintTokens: 'Unable to mint tokens',
		TransferVenueTokens: 'Unable to transfer tokens',
		TransferScholarTokens: 'Unable to find scholar tokens to transfer',
		TransferTokensInsufficient: 'Insufficient number tokens to transfer',
		CreateTransaction: 'Unable to create transaction',
		TransactionMissingFrom: 'No source provided for transaction',
		TransactionMissingTo: 'No destination provided for transaction',
		PendingTransactionHasTokens:
			'This pending transaction already has tokens that were transferred.',
		UnknownTransaction: 'Unable to find this transaction',
		TransactionNotCanceled: 'Unable to cancel this transaction',
		AlreadyApproved: 'This transaction is already approved',
		TransactionApprovalUpdate: 'Unable to update the proposed transaction',
		MissingApprovalVenue: 'The proposed transaction has no venue to transfer from.',
		MissingRecipient: 'The proposed transaction has no scholar recipient.',
		UndeletedTransaction: "The proposed transaction couldn't be deleted.",
		InvalidCharges: "The proposed transaction's charges are invalid.",
		NewSubmission: 'Unable to create a new submission',
		UnknownVenue: 'Unable to find venue',
		MissingSubmissionCharge: "Didn't receive enough charge amounts for the authors given",
		UpdateSubmissionExpertise: 'Unable to update the submission expertise',
		UpdateSubmissionTitle: "Unable to update the submission's title",
		UpdateSubmissionStatus: "Unable to update the submission's status",
		ApproveAssignment: 'Unable to approve the assignment',
		CreateAssignment: 'Unable to create this assignment',
		DeleteAssignment: 'Unable to delete this assignment'
	}
};

type Locale = typeof enUS;
export { type Locale as default };
