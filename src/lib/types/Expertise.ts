type Expertise = {
	/** A description of the expertise */
	phrase: string;
	/** The type of expertise */
	kind: 'method' | 'topic';
	/** Whether deprecated and no longer relevant */
	deprecated: boolean;
};

export type { Expertise as default };
