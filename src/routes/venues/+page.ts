/** @type {import('./$types').PageLoad} */
export async function load({ parent, params }) {
	const { supabase } = await parent();

	const { data, error } = await supabase.from('proposals').select();

	return {
		proposals: data && error === null ? data : null
	};
}
