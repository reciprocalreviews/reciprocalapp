/**
 * Reviewing-platform registry used by the venue settings "Email templates"
 * section (#113). Each platform has its own placeholder-variable syntax in
 * its email templates; we interpolate the right token into RR's deep-link
 * URLs so editors can paste a snippet directly into their reviewing
 * platform without hand-editing the URL.
 *
 * `submissionVar` values were checked against each platform's public docs
 * where possible. HotCRP (`{{PID}}`) and OJS (`{$submissionId}`) were
 * confirmed; the others are best-effort and worth re-verifying if a venue
 * reports the deep-link expanding wrong. Update the registry here — every
 * call site reads from it.
 */
export type ReviewingPlatform = {
	/** Stable id used by the selector and tests. */
	id:
		| 'hotcrp'
		| 'easychair'
		| 'scholarone'
		| 'editorial_manager'
		| 'ojs'
		| 'openreview'
		| 'pcs'
		| 'generic';
	/** Display name in the selector — proper noun, not localized. */
	name: string;
	/** The literal string the editor's reviewing platform will expand to the
	 * manuscript ID when it sends the email. RR substitutes this verbatim
	 * into both the snippet body and the embedded deep-link URL. */
	submissionVar: string;
	/** Public docs page editors can click for the platform's full variable
	 * reference. Optional. */
	docs?: string;
};

export const PLATFORMS: ReviewingPlatform[] = [
	{
		id: 'hotcrp',
		name: 'HotCRP',
		submissionVar: '{{PID}}',
		docs: 'https://help.hotcrp.com/'
	},
	{
		id: 'easychair',
		name: 'EasyChair',
		submissionVar: '{submission_id}',
		docs: 'https://easychair.org/docs/email_to_authors'
	},
	{
		id: 'scholarone',
		name: 'ScholarOne Manuscripts',
		submissionVar: '##DOCUMENT_ID##',
		docs: 'http://mchelp.manuscriptcentral.com/'
	},
	{
		id: 'editorial_manager',
		name: 'Editorial Manager',
		submissionVar: '%MANUSCRIPT_NUMBER%'
	},
	{
		id: 'ojs',
		name: 'Open Journal Systems (OJS / PKP)',
		submissionVar: '{$submissionId}',
		docs: 'https://docs.pkp.sfu.ca/learning-ojs/'
	},
	{
		id: 'openreview',
		name: 'OpenReview',
		submissionVar: '{{submission_number}}',
		docs: 'https://docs.openreview.net/'
	},
	{
		id: 'pcs',
		name: 'Precision Conference (PCS)',
		submissionVar: '${submission}'
	},
	{
		id: 'generic',
		name: 'Plain text / other',
		submissionVar: '{SUBMISSION_ID}'
	}
];
