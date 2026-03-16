export type LocaleText = {
	$schema: string;
	lang: string;
	header: {
		home: string;
		venues: string;
		saved: string;
		link: {
			login: string;
		};
		feedback: {
			testWarning: string;
		};
	};
	footer: {
		link: {
			about: string;
			updates: string;
			feedback: string;
		};
	};
	page: {
		home: {
			lead: string;
			call: string[];
			tip: {
				browse: string;
				about: string;
				track: string;
			};
			feedback: {
				beta: string;
			};
		};
		venues: {
			description: string;
			header: {
				proposed: string;
				active: string;
			};
			link: {
				propose: string;
			};
			feedback: {
				noVenues: string;
				venuesNotLoaded: string;
				noProposals: string;
				proposalsNotLoaded: string;
			};
		};
		proposal: {
			feedback: {
				alreadySupported: string;
				logIn: string;
				notFound: string;
			};
		};
		volunteers: {
			feedback: {
				unknownVenue: string;
				volunteersNotLoaded: string;
				noVolunteers: string;
			};
		};
		venueTransactions: {
			feedback: {
				transactionsNotLoaded: string;
			};
		};
		newSubmission: {
			feedback: {
				notLoaded: string;
				duplicateScholars: string;
				incompletePayment: string;
			};
		};
		submissions: {
			feedback: {
				notLoaded: string;
				noSubmissions: string;
				noneFiltered: string;
			};
		};
		submission: {
			header: {
				authors: string;
				venue: string;
				assignments: string;
				expertise: string;
			};
			feedback: {
				notLoaded: string;
				confidential: string;
				missingAuthors: string;
				noAuthors: string;
				noExpertise: string;
			};
		};
		venue: {
			header: {
				submissionTypes: string;
				roles: string;
			};
			feedback: {
				viewSettings: string;
				typesNotLoaded: string;
				rolesNotLoaded: string;
				inactive: string;
				inactivePrompt: string;
			};
		};
		settings: {
			header: {
				status: string;
				roles: string;
				compensation: string;
			};
			feedback: {
				unknownVenue: string;
				logIn: string;
				adminsOnly: string;
			};
		};
		scholar: {
			header: {
				submissions: string;
				tokens: string;
				settings: string;
				tasks: string;
				volunteering: string;
			};
			feedback: {
				notLoaded: string;
				noStatus: string;
				submissionsNotLoaded: string;
				tokensNotLoaded: string;
				noTasks: string;
				commitmentsNotLoaded: string;
				notVolunteeringFirst: string;
				notVolunteeringThird: string;
				volunteeringFirst: string;
				volunteeringThird: string;
			};
		};
		currency: {
			feedback: {
				notLoaded: string;
			};
			tip: {
				mintWarning: string;
			};
			header: {
				minters: string;
				venues: string;
				tokens: string;
			};
		};
		about: {
			header: {
				stewards: string;
				change: string;
			};
			feedback: {
				stewardsNotLoaded: string;
			};
		};
	};
	view: {
		gift: {
			noTokens: string;
		};
		transactions: {
			feedback: {
				noTransactions: string;
				notLoaded: string;
			};
		};
		roles: {
			feedback: {
				notInvited: string;
				consult: string;
				noRoles: string;
				notLoaded: string;
			};
		};
	};
	error: {
		UpdateScholarStatus: string;
		UpdateScholarName: string;
		UpdateScholarEmail: string;
		UpdateScholarAvailability: string;
		CreateProposal: string;
		EditProposalTitle: string;
		EditProposalCensus: string;
		EditProposalEditors: string;
		EditProposalMinters: string;
		EditProposalURL: string;
		CreateSupporter: string;
		UpdateCurrencyName: string;
		UpdateCurrencyDescription: string;
		EditSupport: string;
		RemoveSupport: string;
		DeleteProposal: string;
		ApproveProposalNotFound: string;
		ApproveProposalNoScholars: string;
		ApproveProposalNoMinters: string;
		ApproveProposalNoVenue: string;
		ApproveProposalCannotUpdateVenue: string;
		ApproveProposalNoCurrency: string;
		EditVenueDescription: string;
		EditVenueAdmins: string;
		EditVenueAddEditorVenueNotFound: string;
		ScholarNotFound: string;
		EditVenueAddEditorAlreadyEditor: string;
		EditVenueTitle: string;
		EditVenueURL: string;
		EditVenueInactive: string;
		EditVenueAnonymousAssignments: string;
		EditVenueWelcomeAmount: string;
		EditVenueSubmissionCost: string;
		EditRoleBidding: string;
		EditRoleDesiredAssignments: string;
		EditRoleAnonymousAuthors: string;
		EditRoleApprover: string;
		CreateRole: string;
		UpdateRoleName: string;
		UpdateRoleDescription: string;
		UpdateRoleInvited: string;
		UpdateRoleAmount: string;
		ReorderRole: string;
		DeleteRole: string;
		UpdateSubmissionType: string;
		CreateSubmissionType: string;
		EditSubmissionType: string;
		DeleteSubmissionType: string;
		CreateCompensation: string;
		EditCompensation: string;
		CreateVolunteer: string;
		WelcomeVolunteer: string;
		AlreadyVolunteered: string;
		UpdateVolunteerActive: string;
		UpdateVolunteerExpertise: string;
		InviteToRole: string;
		InviteToRoleMissing: string;
		InviteToRoleSuccess: string;
		AcceptRoleInvite: string;
		EditCurrencyMinters: string;
		AddCurrencyMinter: string;
		AlreadyMinter: string;
		MintTokens: string;
		TransferVenueTokens: string;
		TransferScholarTokens: string;
		TransferTokensInsufficient: string;
		CreateTransaction: string;
		GetScholarTransactions: string;
		TransactionMissingFrom: string;
		TransactionMissingTo: string;
		PendingTransactionHasTokens: string;
		UnknownTransaction: string;
		TransactionNotCanceled: string;
		AlreadyApproved: string;
		TransactionApprovalUpdate: string;
		MissingApprovalVenue: string;
		MissingRecipient: string;
		UndeletedTransaction: string;
		InvalidCharges: string;
		NewSubmission: string;
		UnknownVenue: string;
		MissingSubmissionCharge: string;
		UpdateSubmissionExpertise: string;
		UpdateSubmissionTitle: string;
		UpdateSubmissionStatus: string;
		ApproveAssignment: string;
		CreateAssignment: string;
		CompensationSubmissionNotFound: string;
		CompensationAssignmentCheck: string;
		CompleteAssignmentNotFound: string;
		CompleteAssignmentRoleNotFound: string;
		CompleteAssignmentVenueNotFound: string;
		DeleteAssignment: string;
		EmailScholar: string;
		ApproveProposalNoSupporters: string;
		DeclareConflict: string;
		NoRoleCompensation: string;
	};
};

export { type LocaleText as default };
