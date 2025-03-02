import type { Database } from '$data/database';
import type { VenueID } from '$data/types';
import type { SupabaseClient } from '@supabase/supabase-js';

export default async function getVenueRoles(db: SupabaseClient<Database>, venue: VenueID) {
	return await db.from('roles').select('*').eq('venueid', venue);
}
