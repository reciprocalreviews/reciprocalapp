export type ButtonText = {
	/** The tooltip and ARIA label for a button */
	tip: string;
	/** The button label to show */
	label: string;
	warn?: string;
};

export type TextFieldText = {
	/** The placeholder to show in the text field */
	placeholder: string;
	/** The optional label to show above the text feild */
	label?: string;
	/** The optional validation error message */
	invalid?: string;
};

export type NotedTextFieldText = TextFieldText & {
	/** The note to show below the text field */
	note: string;
};

/** An optional warning text for confirm buttons */
export type ConfirmButtonText = ButtonText & { warn: string };

/** Text for a checkbox with on/off state variants */
export type CheckboxOnOff = { on: string; off: string };

/** Text for the Options (select) component */
export type OptionsText = {
	/** The optional label to show above the select */
	label?: string;
};

/** Text for the Slider component */
export type SliderText = {
	/** The label describing the slider's purpose */
	label?: string;
	/** Optional suffix text to display after the current value */
	suffix?: string;
};

/** Text for the Card component */
export type CardText = {
	/** The header at the top of the card */
	header: string;
	/** The note below the header */
	note: string;
};

export type LocaleText = {
	$schema: string;
	lang: string;
	shorthand: {
		delete: string;
		confirm: string;
		edit: string;
		filter: string;
		admin: string;
		minter: string;
		steward: string;
		orcid: string;
		empty: string;
	};
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
	notification: {
		emailed: string;
	};
	widget: {
		card: {
			expand: string;
			collapse: string;
		};
		tokens: {
			single: string;
			plural: string;
		};
	};
	page: {
		error: {
			title: string;
		};
		home: {
			title: string;
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
			title: string;
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
			field: {
				title: TextFieldText & { invalid: string };
				editors: TextFieldText & { invalid: string };
				minters: TextFieldText & { invalid: string };
				census: TextFieldText & { invalid: string };
				url: TextFieldText & { invalid: string };
			};
			card: {
				settings: CardText;
			};
		};
		proposal: {
			title: string;
			subtitle: { proposal: string; approved: string };
			feedback: {
				alreadySupported: string;
				logIn: string;
				notFound: string;
			};
			button: {
				deleteSupport: ButtonText;
				deleteProposal: ConfirmButtonText;
				approve: ConfirmButtonText;
				submitSupport: ButtonText;
			};
			note: {
				delete: string;
				editors: string;
			};
			field: {
				support: TextFieldText;
			};
			paragraph: {
				editorsDescription: string;
				approved: string;
				proposed: string;
				census: string;
			};
		};
		volunteers: {
			title: string;
			subtitle: string;
			unavailableTitle: string;
			feedback: {
				unknownVenue: string;
				volunteersNotLoaded: string;
				noVolunteers: string;
			};
			button: {
				exportCSV: ButtonText;
			};
			field: {
				filter: TextFieldText;
			};
			status: {
				active: string;
				inactive: string;
			};
			headers: {
				active: string;
				name: string;
				expertise: string;
			};
			paragraph: {
				intro: string;
			};
		};
		venueTransactions: {
			title: string;
			subtitle: string;
			feedback: {
				transactionsNotLoaded: string;
			};
			paragraph: {
				count: string;
			};
		};
		newSubmission: {
			title: string;
			header: {
				details: string;
				payment: string;
				submit: string;
			};
			paragraph: {
				intro: string;
			};
			feedback: {
				notLoaded: string;
				notLoggedIn: string;
				duplicateScholars: string;
				incompletePayment: string;
				sufficientBalance: string;
				onlyAuthors: string;
			};
			button: {
				removeAuthor: ButtonText;
				addAuthor: ButtonText;
				checkBalances: ButtonText;
				submit: ButtonText;
			};
			note: {
				payment: string;
				balance: string;
				approve: string;
			};
			field: {
				authorOrcid: TextFieldText & { unknownScholar: string };
			};
			slider: {
				payment: SliderText;
			};
			table: {
				orcid: string;
				name: string;
				payment: string;
				removeAuthor: string;
			};
			options: {
				submissionType: OptionsText;
			};
			error: {
				balanceCheck: string;
				notFound: string;
				insufficentFunds: string;
			};
		};
		bulkImport: {
			title: string;
			header: {
				csv: string;
				defaults: string;
				rows: string;
				submit: string;
			};
			paragraph: {
				intro: string;
				mintSummary: string;
			};
			note: {
				csv: string;
			};
			feedback: {
				notLoaded: string;
				notAdmin: string;
			};
			field: {
				title: TextFieldText;
				externalID: TextFieldText;
				expertise: TextFieldText;
				previousID: TextFieldText;
				note: TextFieldText;
				csvUpload: { label: string };
				csvPaste: NotedTextFieldText;
				importNote: NotedTextFieldText;
			};
			options: {
				defaultSubmissionType: OptionsText;
				submissionType: OptionsText;
			};
			button: {
				addRow: ButtonText;
				removeRow: ButtonText;
				applyDefault: ButtonText;
				parseCSV: ButtonText;
				submit: ButtonText;
			};
			column: {
				title: string;
				externalID: string;
				expertise: string;
				submissionType: string;
				previousID: string;
				note: string;
			};
			row: {
				invalid: {
					title: string;
					externalID: string;
					duplicateExisting: string;
					duplicateRow: string;
				};
			};
		};
		submissions: {
			title: string;
			tip: {
				bid: string;
			};
			cell: {
				you: string;
				assigned: string;
				conflicted: string;
				bids: string;
				biddingClosed: string;
			};
			feedback: {
				notLoaded: string;
				noSubmissions: string;
				noneFiltered: string;
			};
			button: {
				sortPaymentFirst: ButtonText;
				sortPaymentLast: ButtonText;
				sortTitleAsc: ButtonText;
				sortTitleDesc: ButtonText;
				sortIDAsc: ButtonText;
				sortIDDesc: ButtonText;
				sortCreatedNewest: ButtonText;
				sortCreatedOldest: ButtonText;
				declareConflict: ButtonText;
				bid: ButtonText;
				unbid: ButtonText;
			};
			headers: {
				payment: string;
				title: string;
				expertise: string;
				id: string;
				created: string;
			};
			field: {
				title: NotedTextFieldText & { invalid: string };
				expertise: NotedTextFieldText;
				manuscriptID: NotedTextFieldText & { invalid: string };
				previousID: NotedTextFieldText;
				note: NotedTextFieldText;
				filter: TextFieldText;
			};
			status: {
				paid: string;
				pending: string;
			};
			paragraph: {
				newSubmission: string;
				bulkImport: string;
			};
		};
		submission: {
			title: string;
			subtitle: string;
			tip: {
				newAssignment: string;
			};
			cell: {
				proposesToPay: string;
				paid: string;
				declinedToPay: string;
				nonPaying: string;
				anonymized: string;
				you: string;
			};
			header: {
				authors: string;
				venue: string;
				assignments: string;
				expertise: string;
				note: string;
			};
			feedback: {
				notLoaded: string;
				confidential: string;
				missingAuthors: string;
				noAuthors: string;
				noExpertise: string;
				noNote: string;
				invalidRole: string;
				scholarNotFound: string;
				alreadyAssigned: string;
			};
			button: {
				createAssignment: ButtonText;
				unassign: ButtonText;
				complete: ButtonText;
				approve: ButtonText;
				approveBid: ButtonText;
			};
			field: {
				newAssignment: TextFieldText & { invalid: string };
				note: TextFieldText;
			};
			checkbox: {
				reviewComplete: string;
			};
			status: {
				done: string;
				reviewing: string;
				unknownTransaction: string;
				completed: string;
				assigned: string;
				unassigned: string;
				bidder: string;
			};
			options: {
				submissionType: OptionsText;
				assignmentRole: OptionsText;
			};
			headers: {
				role: string;
				scholar: string;
				expertise: string;
				balance: string;
				action: string;
			};
		};
		venue: {
			title: string;
			subtitle: string;
			unknownTitle: string;
			header: {
				submissionTypes: string;
				roles: string;
			};
			button: {
				newSubmissionType: ButtonText;
				deleteSubmissionType: ConfirmButtonText;
				requestCompensation: ButtonText;
			};
			feedback: {
				viewSettings: string;
				typesNotLoaded: string;
				rolesNotLoaded: string;
				inactive: string;
				inactivePrompt: string;
			};
			field: {
				name: TextFieldText & { invalid: string };
				url: TextFieldText & { invalid: string };
				description: TextFieldText;
				typeName: TextFieldText;
				typeDescription: TextFieldText;
			};
			card: {
				setup: CardText;
				gift: CardText & { purpose: string; success: string };
			};
			options: {
				compensationRole: OptionsText;
			};
			headers: {
				type: string;
				description: string;
				revisionOf: string;
			};
			paragraph: {
				notFound: string;
				submissionTypes: string;
				missingCompensation: string;
				noDescription: string;
				description: string;
				allVolunteers: string;
			};
		};
		settings: {
			title: string;
			subtitle: string;
			tip: {
				inactive: string;
				compensation: string;
				roles: string;
			};
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
			field: {
				inactiveMessage: TextFieldText;
				welcomeTokens: TextFieldText;
				submissionCost: TextFieldText;
			};
			checkbox: {
				inactive: string;
				anonymousAssignments: CheckboxOnOff;
			};
			paragraph: {
				welcome: string;
				setupIntro: string;
				setupSteps: string;
			};
		};
		scholar: {
			title: string;
			tip: {
				status: string;
			};
			subtitle: string;
			header: {
				submissions: string;
				tokens: string;
				settings: string;
				tasks: string;
				volunteering: string;
			};
			feedback: {
				notLoaded: string;
				noName: string;
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
			field: {
				name: TextFieldText & { invalid: string };
				status: TextFieldText;
				email: NotedTextFieldText;
			};
			card: {
				gift: CardText & { purpose: string; success: string };
			};
			checkbox: {
				available: string;
			};
			status: {
				available: string;
				unavailable: string;
			};
			paragraph: {
				youHave: string;
				thisScholarHas: string;
			};
		};
		currency: {
			title: string;
			subtitle: string;
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
			button: {
				mint: ButtonText;
				removeMinter: ButtonText;
				addMinter: ButtonText;
			};
			note: {
				minters: string;
			};
			field: {
				name: TextFieldText & { invalid: string };
				mintPurpose: TextFieldText;
				minter: TextFieldText & { invalidMinter: string; invalidContact: string };
				description: NotedTextFieldText;
			};
			card: {
				mint: CardText;
				addMinter: CardText;
			};
			checkbox: {
				mintConsent: string;
			};
			slider: {
				newTokenCount: SliderText;
			};
			options: {
				tokenOwner: OptionsText;
			};
			paragraph: {
				mintersDescription: string;
				venuesDescription: string;
				allTokens: string;
			};
		};
		currencyTransactions: {
			subtitle: string;
			paragraph: {
				count: string;
			};
		};
		scholarTransactions: {
			subtitle: string;
			paragraph: {
				count: string;
			};
		};
		login: {
			title: string;
			button: {
				sendPassword: ButtonText;
				signIn: ButtonText;
			};
			note: {
				orcid: string;
			};
			field: {
				email: TextFieldText;
				password: TextFieldText;
			};
			feedback: {
				orcidNote: string;
				checkEmail: string;
				sendPasswordError: string;
				signInError: string;
			};
			paragraph: {
				loggedIn: string;
			};
		};
		proposeVenue: {
			title: string;
			status: {
				notLoggedIn: string;
			};
			button: {
				propose: ButtonText;
			};
			field: {
				venueName: TextFieldText;
				editors: TextFieldText;
				minters: TextFieldText;
				mintersConflict: string;
				url: TextFieldText & { invalid: string };
				size: TextFieldText;
				rationale: TextFieldText;
			};
			options: {
				currency: OptionsText & { createNew: string };
			};
			paragraph: {
				reviewedBy: string;
				howToPropose: string;
			};
		};
		about: {
			title: string;
			header: {
				stewards: string;
				change: string;
			};
			feedback: {
				stewardsNotLoaded: string;
			};
			paragraph: {
				community: string;
				stewardsIntro: string;
				currentStewards: string;
				joinStewards: string;
				theoryIntro: string;
				closing: string;
			};
		};
		updates: {
			title: string;
			paragraph: {
				intro: string;
			};
		};
	};
	view: {
		gift: {
			noTokens: string;
			button: {
				giftTokens: ButtonText;
			};
			field: {
				recipient: TextFieldText & { invalid: string };
				purpose: TextFieldText;
			};
			checkbox: {
				consent: string;
			};
			slider: {
				tokenAmount: SliderText;
			};
			options: {
				venue: OptionsText;
				currency: OptionsText;
			};
			fieldset: {
				legend: string;
				scholar: string;
				venue: string;
			};
		};
		transactions: {
			feedback: {
				noTransactions: string;
				notLoaded: string;
			};
			cell: {
				minted: string;
				pendingApproval: string;
				allLoaded: string;
			};
			button: {
				approve: ButtonText;
				cancelInitiate: ButtonText;
				cancelConfirm: ConfirmButtonText;
				loadMore: ButtonText;
			};
			field: {
				cancelReason: TextFieldText;
			};
			status: {
				proposed: string;
				approved: string;
				canceled: string;
			};
			headers: {
				status: string;
				tokens: string;
				scholar: string;
				from: string;
				to: string;
				purpose: string;
				actions: string;
			};
			error: {
				unknownVenue: string;
			};
			paragraph: {
				cancelReason: string;
			};
		};
		roles: {
			tip: {
				highestPriority: string;
			};
			feedback: {
				notInvited: string;
				consult: string;
				noRoles: string;
				notLoaded: string;
			};
			button: {
				createRole: ButtonText;
				removeAdmin: ConfirmButtonText;
				addAdmin: ButtonText;
				priorityUp: ButtonText;
				priorityDown: ButtonText;
				addCompensation: ButtonText;
				removeCompensation: ButtonText;
				volunteer: ButtonText;
				accept: ButtonText;
				stop: ButtonText;
				resume: ButtonText;
				invite: ButtonText;
				deleteRole: ConfirmButtonText;
			};
			field: {
				newRoleName: TextFieldText;
				adminScholar: TextFieldText;
				invite: TextFieldText;
				roleName: TextFieldText;
				roleDescription: TextFieldText;
				compensationRationale: TextFieldText;
				expertise: TextFieldText;
			};
			card: {
				settings: CardText;
				admins: CardText;
				unnamed: string;
			};
			checkbox: {
				invited: CheckboxOnOff;
				anonymousAuthors: CheckboxOnOff;
				biddable: CheckboxOnOff;
			};
			slider: {
				compensation: SliderText;
				desiredAssignments: SliderText;
			};
			options: {
				approver: OptionsText;
			};
			headers: {
				type: string;
				compensation: string;
				rationale: string;
			};
			paragraph: {
				createRole: string;
				adminsDescription: string;
				addAdmin: string;
				inviteDescription: string;
				administeredBy: string;
				roleOpen: string;
				roleInvited: string;
				volunteersCount: string;
				declined: string;
				volunteering: string;
				stopped: string;
			};
		};
		tasks: {
			button: {
				accept: ButtonText;
				decline: ButtonText;
			};
			headers: {
				kind: string;
				task: string;
			};
			tip: {
				tasks: string;
			};
			cell: {
				kind: {
					invitation: string;
					transaction: string;
					review: string;
					pendingAssignment: string;
					outgoingTransaction: string;
				};
				pendingTransactionsAfter: string;
			};
		};
		commitments: {
			headers: {
				venue: string;
				role: string;
			};
		};
	};
	component: {
		dialog: {
			close: ButtonText;
		};
		text: {
			save: ButtonText;
			edit: ButtonText;
			cancel: ButtonText;
		};
		header: {
			logout: ButtonText;
		};
		notification: {
			dismiss: ButtonText;
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
		BulkImportSubmissions: string;
		UpdateSubmissionExpertise: string;
		UpdateSubmissionTitle: string;
		UpdateSubmissionStatus: string;
		UpdateSubmissionNote: string;
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
