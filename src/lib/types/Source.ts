import type Cost from './Cost';
import type { ScholarID } from './Scholar';

type SourceID = string;

type Source = {
	/** A UUID representing a venue. Allows unique identification of venues. */
	id: SourceID;
	/** The name of the venue. Allows human readable display of the venue in  the front end.*/
	name: string;
	/** The short name of the source, usually an acronym. */
	short: string;
	/** The official URL of the source */
	link: string;
	/** Whether this source has been archived */
	archived: boolean;
	/** The prices for submissions on this source */
	cost: Cost;
	/** A set of scholar IDs that have editing permissions for this source */
	editors: ScholarID[];
	/** A Unix timestamp indicating the time at which the venue was created. Supports auditing.*/
	creationtime: number;
};

export type { SourceID, Source as default };
