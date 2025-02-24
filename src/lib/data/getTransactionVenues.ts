import type { Database } from '$data/database';
import type { TransactionRow } from '$data/types';
import type { SupabaseClient } from '@supabase/supabase-js';

export default async function getTransactionVenues(
	supabase: SupabaseClient<Database>,
	transactions: TransactionRow[]
) {
	return await supabase
		.from('venues')
		.select('*')
		.in(
			'id',
			Array.from(
				new Set(
					transactions
						.map((tr) => [tr.from_venue, tr.to_venue])
						.flat()
						.filter((venueID) => venueID !== null)
				)
			)
		);
}
