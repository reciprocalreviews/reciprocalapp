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
	/** An optional note to show below the select */
	note?: string;
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
		/** Accessible name for the header's total token balance. */
		balance: string;
		link: {
			login: string;
			profile: string;
		};
		feedback: {
			testWarning: string;
		};
	};
	footer: {
		link: {
			brand: string;
			about: string;
			terms: string;
			updates: string;
			/** Knowledge base articles. */
			help: string;
			/** The steward inbox and the people behind it. */
			contact: string;
		};
	};
	banner: {
		beta: {
			/** Lead text explaining that the platform is in beta and wants feedback. */
			lead: string;
		};
		update: {
			/** Message shown when a new version has been deployed. */
			message: string;
			/** Label for the link to the updates page. */
			updates: string;
			/** Button to reload the page and load the new version. */
			refresh: ButtonText;
		};
		email: {
			/** Warning shown when a logged-in scholar has no verified contact email. */
			message: string;
			/** Label for the link to the scholar's profile where they can add one. */
			settings: string;
		};
	};
	notification: {
		emailed: string;
		/** Shown after notifying the shared steward inbox, which is one recipient
		 * rather than a named person. Takes {subject}. */
		emailedStewards: string;
		/** Shown after volunteering or accepting a role invitation. Which one
		 * applies depends on whether a welcome grant actually happened, which
		 * only the database can say — so the RPC reports the amount and the
		 * data layer picks. {amount} is the number of tokens granted. */
		volunteered: string;
		volunteeredWithTokens: string;
		inviteAccepted: string;
		inviteAcceptedWithTokens: string;
		inviteDeclined: string;
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
		subheader: {
			link: string;
		};
		/** The field that resolves typed text to a scholar, by ORCID iD, email
		 * address, or a search of names. Shared by every place one scholar names
		 * another: authors on a submission, venue admins, currency minters, and
		 * role invitations. */
		scholarSearch: {
			/** Searched, and matched nobody. Distinct from having typed nothing. */
			noMatches: string;
			/** Looked up an ORCID iD or email address that belongs to no one here. */
			unknown: string;
			/** Picks one of the offered matches. The scholar's name becomes the label,
			 * and `{name}` in the tip is replaced with it — the tip is the button's
			 * aria-label, and a column of identically-named buttons is unusable. */
			choose: ButtonText;
		};
	};
	page: {
		error: {
			title: string;
		};
		brand: {
			title: string;
			lead: string;
			header: {
				mark: string;
				color: string;
				type: string;
			};
			paragraph: {
				mark: string;
				/** Takes {repo}, a link to the asset folder on GitHub. */
				usage: string;
				color: string;
				type: string;
			};
			/** Labels for the downloadable files. */
			file: {
				logo: string;
				logoWhite: string;
				favicon: string;
				touch: string;
				social: string;
			};
			label: {
				heading: string;
				body: string;
			};
		};
		home: {
			title: string;
			lead: string;
			/** The argument for the platform. Takes {cost}, a rendered token chip. */
			call: string[];
			tip: {
				browse: string;
				/** Takes {newsletter}, the newsletter's URL. */
				about: string;
				track: string;
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
				/** Listed editors no account uses: approval proceeds without them, so they
				 * simply aren't made admins. Takes {addresses}. */
				unknownEditors: string;
				/** Listed minters no account uses: the approving steward ends up holding the
				 * new currency until the venue names someone. Takes {addresses}. */
				unknownMinters: string;
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
				papers: string;
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
			card: {
				reminders: CardText;
			};
			slider: {
				frequency: SliderText;
			};
			tip: {
				remindersOff: string;
			};
		};
		newSubmission: {
			title: string;
			header: {
				details: string;
				payment: string;
				authors: string;
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
				authors: string;
				balance: string;
				approve: string;
				/** Shown when a balance check fails: how to earn the tokens.
				 * {venue} is the venue's URL. */
				earnTokens: string;
			};
			field: {
				authorOrcid: TextFieldText & {
					unknownScholar: string;
					/** Shown on the row that repeats an author named above it. */
					duplicate: string;
				};
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
				previous: OptionsText;
			};
			/** Cost message above the authors form; "{type}" and "{cost}" are substituted. */
			cost: string;
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
				/** Shown when parsed rows had a different number of cells than the
				 * header, which means columns shifted and data was dropped. `{lines}`
				 * is the list of affected line numbers. */
				raggedRows: string;
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
				/** Explains the batch assignment form above the submissions table. */
				batchAssign: string;
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
				/** No scholar matched the email or ORCID typed into the batch form. */
				scholarNotFound: string;
				/** A scholar and role are resolved; per-row assign buttons are live. */
				batchReady: string;
			};
			options: {
				batchRole: OptionsText;
			};
			checkbox: {
				/** Narrows the list to submissions with no editor. */
				needsEditor: string;
			};
			button: {
				batchFind: ButtonText;
				batchAssign: ButtonText;
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
				/** Take on a submission nobody is editing yet. */
				claimEditor: ButtonText;
			};
			headers: {
				payment: string;
				title: string;
				authors: string;
				expertise: string;
				id: string;
				created: string;
				progress: string;
			};
			field: {
				title: NotedTextFieldText & { invalid: string };
				expertise: NotedTextFieldText;
				manuscriptID: NotedTextFieldText & { invalid: string };
				previousID: NotedTextFieldText;
				note: NotedTextFieldText;
				filter: TextFieldText;
				batchAssign: TextFieldText & { invalid: string };
			};
			status: {
				paid: string;
				pending: string;
				/** Submission is still in review. */
				reviewing: string;
				/** Submission has been marked done. */
				done: string;
				/** Nobody holds the venue's editor role on this submission, so no assignment
				 * on it can be approved and it cannot be marked done. */
				needsEditor: string;
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
				/** Shown when the editor can't yet mark done — lists what's
				 * still pending. {count} is substituted. */
				completionBlocked: string;
				/** Shown when the venue lacks tokens to pay all editors. */
				completionInsufficient: string;
				/** Shown when the caller isn't an approved priority-0 editor. */
				completionNotEditor: string;
				/** Shown after a successful completion before notifications. */
				completionSucceeded: string;
				/** Nobody holds the venue's editor role on this submission yet, so nothing on it
				 * can be approved and it cannot be marked done. */
				needsEditor: string;
			};
			button: {
				createAssignment: ButtonText;
				unassign: ConfirmButtonText;
				complete: ConfirmButtonText;
				approve: ButtonText;
				approveBid: ButtonText;
				/** Confirm-style variant used in place of `approve` / `approveBid`
				 * when assigning would push the scholar past their stated
				 * paper-count cap. Button's built-in warn pattern turns this into
				 * a two-click confirmation. */
				approveAnyway: ConfirmButtonText;
				/** Editor button that compensates the editor(s) and marks the
				 * submission done in one atomic action. */
				markDone: ConfirmButtonText;
				/** Take on this submission as the venue's editor. */
				claimEditor: ButtonText;
			};
			field: {
				newAssignment: TextFieldText & { invalid: string };
				note: TextFieldText;
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
				/** Per-candidate active assignment count vs. their stated paper-count cap. */
				load: string;
				action: string;
			};
			/** Author thank-you notes to reviewers (#22). */
			thanks: {
				/** Subheader for the thanks section */
				header: string;
				/** Author panel intro, framed as gratitude (not a rebuttal) */
				intro: string;
				/** Shown to the author after sending, when the venue vets notes */
				pending: string;
				/** Shown to the author after sending, when delivered immediately */
				delivered: string;
				/** Label preceding the reason an editor gave for declining */
				declinedReason: string;
				/** Vetter panel intro */
				review: string;
				/** Prompt above the decline reason field */
				declineReasonPrompt: string;
				/** Heading above notes shown to a recipient reviewer */
				received: string;
				field: {
					message: NotedTextFieldText & { invalid: string };
					declineReason: TextFieldText;
				};
				button: {
					send: ButtonText;
					approve: ButtonText;
					declineInitiate: ButtonText;
					declineConfirm: ButtonText;
				};
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
				startReview: string;
				startReviewFree: string;
				volunteer: string;
				volunteerFree: string;
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
				cost: TextFieldText;
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
				cost: string;
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
				/** Frames Step 1 ("Decide policies") as a critical prerequisite. */
				policies: string;
				inactive: string;
				compensation: string;
				roles: string;
				/** Explains how done_visibility_days controls the list. */
				doneVisibility: string;
				/** Explains what preference levels are for and how the binary
				 * default works when no levels are defined. */
				preferenceLevels: string;
				/** Explains the email-templates section (#113): pick the reviewing
				 * platform first, then paste each snippet into its email template. */
				templates: string;
				/** Explains the bulk-import step. */
				bulkImport: string;
			};
			/** Expandable launch-planning guidance cards under Step 1 (#65):
			 * deeper "why/how" for the most consequential decisions. */
			card: {
				/** How to set welcome/compensation without collapsing the economy. */
				economics: CardText;
				/** How reviewing is organized: anonymity model + bidding vs.
				 * central assignment and preference labels. */
				anonymityAssignment: CardText;
				/** How to decide what counts as a creditable review. */
				reviewQuality: CardText;
				/** Whether to join an existing currency or start one, and how to
				 * choose good minters (only needed for a new currency). */
				minters: CardText;
			};
			header: {
				/** Step 1: community-policy checklist before configuring anything. */
				policies: string;
				status: string;
				roles: string;
				compensation: string;
				visibility: string;
				preferenceLevels: string;
				/** Section header for the email-templates editor (#113). */
				templates: string;
				/** Section header for the bulk-import setup step. */
				bulkImport: string;
			};
			feedback: {
				/** Why a venue that is ready in every other way still cannot be switched live:
				 * one of its admins mints its currency. Permitted while configuring, refused
				 * at launch (RR015). */
				adminMints: string;
				unknownVenue: string;
				logIn: string;
				adminsOnly: string;
				noPreferenceLevels: string;
			};
			field: {
				inactiveMessage: TextFieldText;
				welcomeTokens: TextFieldText;
				preferenceLevelLabel: TextFieldText & { invalid: string };
				newPreferenceLevel: TextFieldText & { invalid: string };
			};
			options: {
				/** Label for the reviewing-platform selector above the email
				 * templates (#113). */
				platform: OptionsText;
			};
			button: {
				addPreferenceLevel: ButtonText;
				deletePreferenceLevel: ConfirmButtonText;
				movePreferenceLevelUp: ButtonText;
				movePreferenceLevelDown: ButtonText;
			};
			checkbox: {
				inactive: string;
				anonymousAssignments: CheckboxOnOff;
				vetThanks: CheckboxOnOff;
				/** `label` is the always-visible checkbox label (checked = payments
				 * on); `note` describes the payment-free state shown when unchecked. */
				paymentFree: { label: string; note: string };
			};
			slider: {
				doneVisibility: SliderText;
			};
			paragraph: {
				/** Top-of-page blurb framing the page as a series of numbered
				 * setup steps the admin works through in order. */
				welcome: string;
				/** Bulleted markdown list of policies the community should
				 * decide on before encoding them in the settings below. */
				policies: string;
				/** Body of the Step 1 "economics" card (#65): how welcome and
				 * compensation levels keep the token economy in balance, with a
				 * worked example. */
				economics: string;
				/** Body of the Step 1 "anonymity & assignment" card (#65): the
				 * anonymity model and bidding-vs-central-assignment tradeoffs. */
				anonymityAssignment: string;
				/** Body of the Step 1 "minters" card (#65): criteria for choosing
				 * good minters. */
				minters: string;
				/** Body of the Step 1 "review quality" card (#65): deciding what
				 * counts as a creditable review and which controls enforce it. */
				reviewQuality: string;
			};
			/** Email-template snippets editors copy into their reviewing platform
			 * (#113). Each entry's `body` is interpolated with `{origin}` (the
			 * environment's own base URL, so a snippet copied from a local or
			 * staging venue links back to it), `{venue}`, `{venueid}`, and
			 * `{manuscriptVar}` (the selected platform's submission-id syntax).
			 *
			 * `{role}` is deliberately NOT interpolated: an editor pastes these
			 * once per role, and reviewing platforms differ too much in how they
			 * expose role names for us to guess. The tip above the snippets says
			 * so — this list previously claimed otherwise, which read as a bug. */
			template: {
				payment: { title: string; body: string };
				acknowledgement: { title: string; body: string };
				compensation: { title: string; body: string };
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
				addEmail: string;
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
			/** The scholar's own data-rights controls: export and erasure. Only ever
			 * shown to the scholar themselves. */
			privacy: {
				header: string;
				about: string;
				export: ButtonText;
				exporting: string;
				erase: ConfirmButtonText;
				erasing: string;
				erased: string;
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
				removeMinter: ConfirmButtonText;
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
				orcid: ButtonText;
				mockOrcid: ButtonText;
				signIn: ButtonText;
				/** A seeded scholar on the local sign-in list; its label is their name. */
				signInAs: ButtonText;
			};
			note: {
				orcid: string;
			};
			/** Column headers for the local-only table of seeded scholars. */
			table: {
				scholar: string;
				email: string;
				roles: string;
			};
			card: {
				/** The local-only control that mints a brand-new scholar. Not a
				 * sign-in — it exists to reach the first-run experience. */
				newScholar: CardText;
			};
			field: {
				email: TextFieldText;
				password: TextFieldText;
				orcidId: TextFieldText;
				name: TextFieldText;
			};
			feedback: {
				orcidError: string;
				mockOrcidError: string;
				passwordDev: string;
				/** The page's single warning that these controls are local-only. */
				seededDev: string;
				signInError: string;
			};
			paragraph: {
				loggedIn: string;
			};
		};
		verify: {
			title: string;
			/** Shown when the token was valid and the email is now verified. */
			verified: string;
			/** Shown when the token has expired (15-minute window elapsed). */
			expired: string;
			/** Shown when the token is unknown or already used. */
			invalid: string;
			/** Shown when the verification RPC itself failed. */
			error: string;
			/** Link label to the scholar's profile (authenticated). */
			profile: string;
			/** Link label prompting sign-in (unauthenticated). */
			login: string;
		};
		proposeVenue: {
			title: string;
			status: {
				notLoggedIn: string;
			};
			button: {
				propose: ButtonText;
			};
			checkbox: {
				paymentFree: CheckboxOnOff;
			};
			section: {
				venueInfo: string;
				team: string;
				rationale: string;
			};
			field: {
				venueName: TextFieldText & { invalid: string };
				/** `unknown` names the listed addresses that belong to no account yet. Takes
				 * {addresses}. Not an error: an editor who hasn't signed up is emailed an
				 * invitation by the proposal itself, which is how communities arrive. */
				editors: TextFieldText & { invalid: string; unknown: string };
				/** As above, but an unlisted minter means the approving steward holds the
				 * currency until the venue names someone. Takes {addresses}. */
				minters: TextFieldText & { invalid: string; unknown: string };
				mintersConflict: string;
				url: TextFieldText & { invalid: string };
				size: TextFieldText & { invalid: string };
				rationale: TextFieldText & { invalid: string };
			};
			options: {
				currency: OptionsText & { createNew: string; note: string };
			};
			paragraph: {
				reviewedBy: string;
				howToPropose: string;
				communitySupport: string;
				emailNotice: string;
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
				/** Shown when the platform has no stewards at all, which is distinct
				 * from failing to load the list. */
				noStewards: string;
			};
			/** Stands in for the name of a steward who has erased their account. */
			anonymous: string;
			card: {
				addSteward: CardText;
			};
			field: {
				steward: TextFieldText;
			};
			button: {
				addSteward: ButtonText;
				removeSteward: ConfirmButtonText;
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
		contact: {
			title: string;
			header: {
				write: string;
				stewards: string;
				elsewhere: string;
			};
			paragraph: {
				/** What the steward inbox is for. Takes {email}. */
				write: string;
				/** Sets expectations about who reads it and how fast. */
				expectations: string;
				/** Introduces the steward list below. */
				stewards: string;
				/** Where to go for things that aren't a support request. */
				elsewhere: string;
			};
			link: {
				help: string;
				discussions: string;
				issues: string;
				newsletter: string;
			};
			feedback: {
				stewardsNotLoaded: string;
			};
		};
		help: {
			title: string;
			paragraph: {
				intro: string;
				/** Shown under the article list, pointing at /contact. */
				more: string;
			};
			feedback: {
				/** Shown when a slug matches no article. */
				missing: string;
			};
		};
		updates: {
			title: string;
			paragraph: {
				intro: string;
			};
		};
		terms: {
			title: string;
			header: {
				terms: string;
				what: string;
				account: string;
				email: string;
				data: string;
				venues: string;
				openSource: string;
				delete: string;
				changes: string;
				privacy: string;
				definitions: string;
				legalBasis: string;
				collect: string;
				retention: string;
				security: string;
				privacyEmail: string;
				rights: string;
				international: string;
				contact: string;
				privacyChanges: string;
			};
			paragraph: {
				intro: string;
				what: string;
				account: string;
				email: string;
				data: string;
				venues: string;
				openSource: string;
				delete: string;
				changes: string;
				privacyIntro: string;
				definitions: string;
				legalBasis: string;
				collect: string;
				retention: string;
				security: string;
				privacyEmail: string;
				rights: string;
				international: string;
				contact: string;
				privacyChanges: string;
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
			/** Templates for the purpose text recorded on transactions the
			 * platform generates automatically. {role}, {title}, {amount},
			 * and {shortfall} are substituted at runtime. */
			purposeTemplate: {
				compensation: string;
				mint: string;
			};
			cell: {
				minted: string;
				pendingApproval: string;
				allLoaded: string;
			};
			button: {
				/** Confirm-style: approval moves tokens and is permanent (RR005),
				 * so it must not be a single click. */
				approve: ConfirmButtonText;
				declineInitiate: ButtonText;
				declineConfirm: ConfirmButtonText;
				loadMore: ButtonText;
			};
			field: {
				declineReason: TextFieldText;
			};
			status: {
				proposed: string;
				approved: string;
				declined: string;
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
				declineReason: string;
			};
		};
		roles: {
			tip: {
				/** Shown to admins on the first role in priority order. Priority zero is not
				 * just presentation: it is what the database checks when deciding who may
				 * approve assignments, edit an author list, and mark a submission done. */
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
				removeCompensation: ConfirmButtonText;
				volunteer: ButtonText;
				accept: ButtonText;
				acceptInvite: ConfirmButtonText;
				decline: ConfirmButtonText;
				stop: ButtonText;
				resume: ButtonText;
				invite: ButtonText;
				deleteRole: ConfirmButtonText;
			};
			field: {
				newRoleName: TextFieldText;
				/** `invalid` when the text is neither an email nor an ORCID iD;
				 * `minter` when it names someone who mints the venue's currency,
				 * which the database forbids an admin from also doing. */
				adminScholar: TextFieldText & { invalid: string; minter: string };
				invite: TextFieldText;
				roleName: TextFieldText;
				roleDescription: TextFieldText;
				compensationRationale: TextFieldText;
				expertise: TextFieldText;
				/** Per-volunteer soft cap on the number of papers the volunteer
				 * is willing to review for this role. Empty = unspecified. */
				papers: TextFieldText & { invalid: string };
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
				invited: string;
				declined: string;
				volunteering: string;
				stopped: string;
			};
		};
		tasks: {
			button: {
				accept: ConfirmButtonText;
				decline: ConfirmButtonText;
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
					/** Completed work whose compensation awaits this approver. */
					pendingCompensation: string;
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
			/** Shown on the toggle while the edit is being written, so a slow save isn't
			 * a second of silence. The button is disabled for the duration. */
			saving: ButtonText;
		};
		header: {
			logout: ButtonText;
		};
		notification: {
			dismiss: ButtonText;
		};
		copyButton: {
			copy: ButtonText;
			copied: ButtonText;
		};
		verifyEmail: {
			field: {
				email: TextFieldText & { invalid: string };
			};
			button: {
				send: ButtonText;
			};
			feedback: {
				sent: string;
				/** Fallback when the server gave no recognizable reason. */
				error: string;
				unchanged: string;
				/** The one-minute rate limit was hit; a link is already on its way. */
				cooldown: string;
				/** This deployment has no `site_url` vault secret, so no link can be built.
				 * A configuration fault, not something the scholar can retry into working. */
				notConfigured: string;
				/** The session ended between loading the page and submitting. */
				signedOut: string;
			};
		};
	};
	error: {
		UpdateScholarStatus: string;
		UpdateScholarName: string;
		UpdateScholarEmail: string;
		VerifyEmail: string;
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
		EditVenueVetThanks: string;
		EditVenueWelcomeAmount: string;
		EditVenuePaymentFree: string;
		EditVenueDoneVisibilityDays: string;
		EditVenueTransactionReminderFrequency: string;
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
		EditSubmissionTypeCost: string;
		DeleteSubmissionType: string;
		CreateCompensation: string;
		EditCompensation: string;
		CreateVolunteer: string;
		AlreadyVolunteered: string;
		UpdateVolunteerActive: string;
		UpdateVolunteerExpertise: string;
		UpdateVolunteerPapers: string;
		UpdateAssignmentPreference: string;
		CreatePreferenceLevel: string;
		EditPreferenceLevel: string;
		ReorderPreferenceLevel: string;
		DeletePreferenceLevel: string;
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
		TransactionNotDeclined: string;
		/** The caller tried to export or erase an account that is not theirs. */
		NotYourAccount: string;
		/** Exporting a scholar's data failed. */
		ExportScholarData: string;
		/** Erasing a scholar's account failed. */
		EraseScholar: string;
		/** RR010: the caller is not a steward, so cannot change who is one. */
		NotSteward: string;
		/** RR012: there must always be one steward, or nobody can appoint another. */
		LastSteward: string;
		/** RR013: stepping down is an act another steward performs. */
		CannotDemoteSelf: string;
		/** The scholar being promoted is already a steward. */
		AlreadySteward: string;
		/** Promoting a scholar to steward failed. */
		PromoteSteward: string;
		/** Removing a scholar as a steward failed. */
		DemoteSteward: string;
		AlreadyApproved: string;
		SelfDealingApproval: string;
		ApproveTransaction: string;
		TransactionApprovalUpdate: string;
		MissingApprovalVenue: string;
		MissingRecipient: string;
		UndeletedTransaction: string;
		InvalidCharges: string;
		NewSubmission: string;
		/** RR009: the caller is neither a listed author nor a venue admin. */
		SubmissionNotAuthor: string;
		UnknownVenue: string;
		MissingSubmissionCharge: string;
		BulkImportSubmissions: string;
		UpdateSubmissionExpertise: string;
		UpdateSubmissionTitle: string;
		UpdateSubmissionNote: string;
		MarkSubmissionDoneRPC: string;
		ApproveAssignment: string;
		CreateAssignment: string;
		CompensationSubmissionNotFound: string;
		CompensationAssignmentCheck: string;
		CompleteAssignmentNotFound: string;
		CompleteAssignmentRoleNotFound: string;
		CompleteAssignmentVenueNotFound: string;
		CompleteAssignmentInsufficientTokens: string;
		CompleteAssignmentRPC: string;
		DeleteAssignment: string;
		EmailScholar: string;
		ApproveProposalNoSupporters: string;
		DeclareConflict: string;
		NoRoleCompensation: string;
		LoadVenue: string;
		LoadCurrency: string;
		LoadScholar: string;
		LoadSubmission: string;
		LoadTransaction: string;
		LoadRole: string;
		LoadAssignment: string;
		LoadVolunteer: string;
		LoadToken: string;
		LoadProposal: string;
		LoadCompensation: string;
		LoadPreferenceLevel: string;
		LoadSubmissionType: string;
		LoadConflict: string;
		ProposeThanks: string;
		ApproveThanks: string;
		DeclineThanks: string;
		LoadThanks: string;
	};
};

export { type LocaleText as default };
