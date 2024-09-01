import type { Database } from './database';

type Tables = Database['public']['Tables'];
export type Scholar = Tables['scholars']['Row'];
export type ScholarID = Scholar['id'];
