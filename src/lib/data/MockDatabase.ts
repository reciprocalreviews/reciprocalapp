import type { ScholarID } from '$lib/types/Scholar';
import type Scholar from '$lib/types/Scholar';
import type Source from '$lib/types/Source';
import type Submission from '$lib/types/Submission';
import type { Charge, TransactionID } from '$lib/types/Transaction';
import type Transaction from '$lib/types/Transaction';
import Database from './Database';

export default class MockDatabase extends Database {
	private submissions = [...defaultSubmissions];
	private sources = [...defaultSources];
	private scholars = [...defaultScholars];
	private transactions = [...defaultTransactions];

	async createSubmission(submission: Submission): Promise<Submission> {
		this.submissions = [...this.submissions, submission];
		return submission;
	}

	async updateSubmission(submission: Submission): Promise<Submission> {
		this.submissions = this.submissions.map((sub) => (sub.id === submission.id ? submission : sub));
		return submission;
	}

	async createTransaction(transaction: Transaction): Promise<Transaction> {
		this.transactions = [...this.transactions, transaction];
		return transaction;
	}

	async verifyCharges(charges: Charge[]): Promise<true | Charge[]> {
		// Get the balances of each person charged.
		const balances = await Promise.all(
			charges.map((charge) => this.getScholarBalance(charge.scholar))
		);
		// Compute the remaining balances for each scholar.
		const remaining = charges.map((charge, index) => {
			return {
				scholar: charge.scholar,
				payment: balances[index] - charge.payment
			};
		});

		return remaining.every((charge) => charge.payment >= 0) ? true : remaining;
	}

	async getSubmission(submissionID: string): Promise<Submission> {
		const match = this.submissions.find((submission) => submission.id === submissionID);
		if (match === undefined) throw Error('no match');
		else return { ...match };
	}

	async createSource(source: Source): Promise<Source> {
		// Add the new source
		this.sources = [...this.sources, source];
		// Ensure that all of the editors and reviewers are updated
		return source;
	}

	async getSources(): Promise<Source[]> {
		return [...this.sources];
	}

	async getSource(sourceID: string): Promise<Source> {
		const match = this.sources.find((source) => source.id === sourceID);
		if (match === undefined) throw Error('No match');
		return { ...match };
	}

	async getEditedSources(editor: ScholarID): Promise<Source[]> {
		return this.sources.filter((source) => source.editors.includes(editor));
	}

	async updateSource(revised: Source): Promise<Source> {
		this.sources = this.sources.map((source) => (source.id === revised.id ? revised : source));
		return revised;
	}

	async getActiveSubmissions(sourceID: string): Promise<Submission[]> {
		return this.submissions.filter(
			(submission) => submission.sourceID === sourceID && !submission.payment
		);
	}

	async getSourceVolunteers(sourceID: string): Promise<{ scholar: Scholar; balance: number }[]> {
		// Get the volunteers
		const volunteers = this.scholars.filter((scholar) => scholar.sources.includes(sourceID));
		// Get their balances.
		const balances = await Promise.all(
			volunteers.map((volunteer) => this.getScholarBalance(volunteer.id))
		);
		// Return the list.
		return volunteers.map((volunteer, index) => {
			return { scholar: volunteer, balance: balances[index] };
		});
	}

	async createScholar(scholar: Scholar): Promise<Scholar> {
		this.scholars = [...this.scholars, scholar];
		return scholar;
	}

	async getScholar(scholarID: string): Promise<Scholar> {
		const match = this.scholars.find((scholar) => scholar.id === scholarID);
		if (match === undefined) throw Error('No match');
		return { ...match };
	}

	async getScholarBalance(scholarID: string): Promise<number> {
		return this.transactions
			.filter((trans) => trans.scholarID === scholarID)
			.reduce((sum, trans) => sum + trans.amount, 0);
	}

	async updateScholar(scholar: Scholar): Promise<Scholar> {
		this.scholars = this.scholars.map((s) => (s.id === scholar.id ? scholar : s));
		return scholar;
	}

	async getTransaction(id: TransactionID): Promise<Transaction | null> {
		return this.transactions.find((trans) => trans.id === id) ?? null;
	}

	async getScholarTransactions(id: ScholarID): Promise<Transaction[]> {
		return this.transactions.filter((trans) => trans.scholarID === id);
	}
}

const defaultSources: Source[] = [
	{
		id: 'ABCDABCDABCDABCDABCD',
		name: 'ACM Transactions on Computing Education',
		short: 'TOCE',
		link: 'https://toce.acm.org',
		archived: false,
		cost: {
			submit: 4,
			review: 1,
			meta: 1,
			edit: 0.1
		},
		editors: ['0000-0001-7461-4783'],
		creationtime: 123123
	},
	{
		id: 'BCDEBCDEBCDEBCDEBCDE',
		name: 'Computer Science Education',
		short: 'CSE',
		link: 'https://www.tandfonline.com/journals/ncse20',
		archived: false,
		cost: {
			submit: 0,
			review: 0,
			meta: 0,
			edit: 0
		},
		editors: ['0000-0001-7461-5000'],
		creationtime: 123123
	},
	{
		id: 'CDEFCDEFCDEFCDEFCDEF',
		name: 'ACM SIGCSE Technical Symposium',
		short: 'SIGCSE TS',
		link: 'https://dl.acm.org/conference/sigcse',
		archived: false,
		cost: {
			submit: 0,
			review: 0,
			meta: 0,
			edit: 0
		},
		editors: ['0000-0001-7461-6000'],
		creationtime: 123123
	},
	{
		id: 'DEFGDEFGDEFGDEFGDEFG',
		name: 'ACM International Computing Education Research Conference',
		short: 'ICER',
		link: 'https://dl.acm.org/conference/icer',
		archived: false,
		cost: {
			submit: 0,
			review: 0,
			meta: 0,
			edit: 0
		},
		editors: ['0000-0001-7461-2032'],
		creationtime: 123123
	}
];

const defaultSubmissions: Submission[] = [
	{
		id: 'one',
		sourceID: 'ABCDABCDABCDABCDABCD',
		externalID: 'TOCE-2023-0001',
		title: 'Formative Assessments in Times of Famine',
		metaID: '0000-0001-7461-4000',
		editorID: '0000-0001-7461-4783',
		charges: ['1'],
		compensation: {
			submit: 4,
			review: 1,
			meta: 1,
			edit: 0.1
		},
		payment: null,
		creationtime: 123123
	},
	{
		id: 'two',
		sourceID: 'ABCDABCDABCDABCDABCD',
		externalID: 'TOCE-2023-0002',
		title: 'Teaching Declarative Front End Development to Newborns',
		metaID: '0000-0001-7461-4783',
		editorID: '0000-0001-2000-3000',
		charges: ['2'],
		compensation: {
			submit: 4,
			review: 1,
			meta: 1,
			edit: 0.1
		},
		payment: null,
		creationtime: 123123
	},
	{
		id: 'three',
		sourceID: 'ABCDABCDABCDABCDABCD',
		externalID: 'TOCE-2023-0003',
		title: 'Elementary Ideas about Elementary Computing for Elementary Minds',
		metaID: '0000-0001-7461-4783',
		editorID: '0000-0001-2000-3000',
		charges: ['3', '4', '5'],
		compensation: {
			submit: 4,
			review: 1,
			meta: 1,
			edit: 0.1
		},
		payment: null,
		creationtime: 123123
	},
	{
		id: 'four',
		sourceID: 'ABCDABCDABCDABCDABCD',
		externalID: 'TOCE-2023-0004',
		title: 'This Should Not Appear in the List',
		metaID: '0000-0001-7461-4783',
		editorID: '0000-0001-2000-3000',
		compensation: {
			submit: 4,
			review: 1,
			meta: 1,
			edit: 0.1
		},
		charges: ['6', '7'],
		payment: null,
		creationtime: 123123
	}
];

const defaultScholars: Scholar[] = [
	{
		id: '0000-0001-7461-4783',
		name: 'Amy J. Ko',
		expertise: ['assessment', 'learning technology', 'equity and justice'],
		reviewing: true,
		minimum: 5,
		sources: ['ABCDABCDABCDABCDABCD'],
		transactions: [],
		creationtime: 123
	},
	{
		id: '0000-0001-2000-3000',
		name: 'Damon Johnson',
		expertise: ['diversity', 'K-12', 'auto-grading'],
		reviewing: true,
		minimum: 5,
		sources: ['ABCDABCDABCDABCDABCD'],
		transactions: [],
		creationtime: 123
	},
	{
		id: '0000-0001-2000-4000',
		name: 'Ben Tomlinson',
		expertise: ['intro programming', 'qualitative', 'policy'],
		reviewing: true,
		minimum: 3,
		sources: ['ABCDABCDABCDABCDABCD'],
		transactions: [],
		creationtime: 123
	},
	{
		id: '0000-0001-2000-5000',
		name: 'Jessica Dory',
		expertise: ['programming languages', 'quantitative', 'assessment'],
		reviewing: true,
		minimum: 3,
		sources: ['ABCDABCDABCDABCDABCD'],
		transactions: [],
		creationtime: 123
	}
];

const defaultTransactions: Transaction[] = [
	{
		id: crypto.randomUUID(),
		submissionID: null,
		editorID: '0000-0001-7461-4783',
		scholarID: '0000-0001-7461-4783',
		amount: 3,
		purpose: 'gift',
		description: 'Testing with a high balance',
		creationtime: Date.now()
	},
	{
		id: '1',
		submissionID: null,
		editorID: '0000-0001-7461-4783',
		scholarID: '0000-0001-7461-4783',
		amount: 4,
		purpose: 'submission',
		description: 'Thanks for your submission',
		creationtime: Date.now()
	}
];
