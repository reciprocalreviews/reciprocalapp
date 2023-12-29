type Cost = {
	/** The number of tokens for a submission */
	submit: number;
	/** The number of tokens for a review */
	review: number;
	/** The number of tokens for a meta-review */
	meta: number;
	/** The number of tokens for serving as editor */
	edit: number;
};

export type { Cost as default };
