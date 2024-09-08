import type { Database } from './database';

type Tables = Database['public']['Tables'];
export type ScholarRow = Tables['scholars']['Row'];
export type ScholarID = ScholarRow['id'];
