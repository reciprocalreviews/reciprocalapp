import type { Database } from '$data/database';
import type { TransactionRow } from '$data/types';
import type { SupabaseClient } from '@supabase/supabase-js';

export default async function getTransactionCurrencies(
	supabase: SupabaseClient<Database>,
	transactions: TransactionRow[]
) {
	return await supabase
		.from('currencies')
		.select('*')
		.in('id', Array.from(new Set(transactions.map((t) => t.currency))));
}
