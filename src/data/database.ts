export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          operationName?: string
          query?: string
          variables?: Json
          extensions?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      currencies: {
        Row: {
          description: string
          id: string
          minters: string[]
          name: string
        }
        Insert: {
          description?: string
          id?: string
          minters?: string[]
          name?: string
        }
        Update: {
          description?: string
          id?: string
          minters?: string[]
          name?: string
        }
        Relationships: []
      }
      exchanges: {
        Row: {
          approved: string | null
          approvers: string[]
          currency_from: string
          currency_to: string
          id: string
          kind: Database["public"]["Enums"]["exchange_proposal_kind"] | null
          proposed: string
          ratio: number
        }
        Insert: {
          approved?: string | null
          approvers?: string[]
          currency_from: string
          currency_to: string
          id?: string
          kind?: Database["public"]["Enums"]["exchange_proposal_kind"] | null
          proposed?: string
          ratio: number
        }
        Update: {
          approved?: string | null
          approvers?: string[]
          currency_from?: string
          currency_to?: string
          id?: string
          kind?: Database["public"]["Enums"]["exchange_proposal_kind"] | null
          proposed?: string
          ratio?: number
        }
        Relationships: [
          {
            foreignKeyName: "exchanges_currency_from_fkey"
            columns: ["currency_from"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "exchanges_currency_to_fkey"
            columns: ["currency_to"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["id"]
          },
        ]
      }
      proposals: {
        Row: {
          census: number
          editors: string[]
          id: string
          title: string
          url: string
          venue: string | null
        }
        Insert: {
          census: number
          editors?: string[]
          id?: string
          title?: string
          url?: string
          venue?: string | null
        }
        Update: {
          census?: number
          editors?: string[]
          id?: string
          title?: string
          url?: string
          venue?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "proposals_venue_fkey"
            columns: ["venue"]
            isOneToOne: false
            referencedRelation: "venues"
            referencedColumns: ["id"]
          },
        ]
      }
      roles: {
        Row: {
          amount: number
          description: string
          id: string
          invited: boolean
          name: string
          venueid: string
        }
        Insert: {
          amount: number
          description?: string
          id?: string
          invited: boolean
          name?: string
          venueid: string
        }
        Update: {
          amount?: number
          description?: string
          id?: string
          invited?: boolean
          name?: string
          venueid?: string
        }
        Relationships: [
          {
            foreignKeyName: "roles_venueid_fkey"
            columns: ["venueid"]
            isOneToOne: false
            referencedRelation: "venues"
            referencedColumns: ["id"]
          },
        ]
      }
      scholars: {
        Row: {
          available: boolean
          email: string | null
          id: string
          name: string | null
          orcid: string | null
          status: string
          steward: boolean
          when: string
        }
        Insert: {
          available?: boolean
          email?: string | null
          id: string
          name?: string | null
          orcid?: string | null
          status?: string
          steward?: boolean
          when?: string
        }
        Update: {
          available?: boolean
          email?: string | null
          id?: string
          name?: string | null
          orcid?: string | null
          status?: string
          steward?: boolean
          when?: string
        }
        Relationships: []
      }
      supporters: {
        Row: {
          created: string
          id: string
          message: string
          proposalid: string
          scholarid: string
        }
        Insert: {
          created?: string
          id?: string
          message?: string
          proposalid: string
          scholarid: string
        }
        Update: {
          created?: string
          id?: string
          message?: string
          proposalid?: string
          scholarid?: string
        }
        Relationships: [
          {
            foreignKeyName: "supporters_proposalid_fkey"
            columns: ["proposalid"]
            isOneToOne: false
            referencedRelation: "proposals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "supporters_scholarid_fkey"
            columns: ["scholarid"]
            isOneToOne: false
            referencedRelation: "scholars"
            referencedColumns: ["id"]
          },
        ]
      }
      tokens: {
        Row: {
          currency: string
          id: string
          scholar: string | null
          venue: string | null
        }
        Insert: {
          currency: string
          id?: string
          scholar?: string | null
          venue?: string | null
        }
        Update: {
          currency?: string
          id?: string
          scholar?: string | null
          venue?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "tokens_currency_fkey"
            columns: ["currency"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tokens_scholar_fkey"
            columns: ["scholar"]
            isOneToOne: false
            referencedRelation: "scholars"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tokens_venue_fkey"
            columns: ["venue"]
            isOneToOne: false
            referencedRelation: "venues"
            referencedColumns: ["id"]
          },
        ]
      }
      transactions: {
        Row: {
          currency: string
          from_scholar: string | null
          from_venue: string | null
          id: string
          purpose: string
          to_scholar: string | null
          to_venue: string | null
          tokens: string[]
        }
        Insert: {
          currency: string
          from_scholar?: string | null
          from_venue?: string | null
          id?: string
          purpose: string
          to_scholar?: string | null
          to_venue?: string | null
          tokens?: string[]
        }
        Update: {
          currency?: string
          from_scholar?: string | null
          from_venue?: string | null
          id?: string
          purpose?: string
          to_scholar?: string | null
          to_venue?: string | null
          tokens?: string[]
        }
        Relationships: [
          {
            foreignKeyName: "transactions_currency_fkey"
            columns: ["currency"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "transactions_from_scholar_fkey"
            columns: ["from_scholar"]
            isOneToOne: false
            referencedRelation: "scholars"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "transactions_from_venue_fkey"
            columns: ["from_venue"]
            isOneToOne: false
            referencedRelation: "venues"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "transactions_to_scholar_fkey"
            columns: ["to_scholar"]
            isOneToOne: false
            referencedRelation: "scholars"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "transactions_to_venue_fkey"
            columns: ["to_venue"]
            isOneToOne: false
            referencedRelation: "venues"
            referencedColumns: ["id"]
          },
        ]
      }
      venues: {
        Row: {
          bidding: boolean
          currency: string
          description: string
          editors: string[]
          id: string
          submission_cost: number
          title: string
          url: string
          welcome_amount: number
        }
        Insert: {
          bidding?: boolean
          currency: string
          description?: string
          editors?: string[]
          id?: string
          submission_cost?: number
          title?: string
          url?: string
          welcome_amount: number
        }
        Update: {
          bidding?: boolean
          currency?: string
          description?: string
          editors?: string[]
          id?: string
          submission_cost?: number
          title?: string
          url?: string
          welcome_amount?: number
        }
        Relationships: [
          {
            foreignKeyName: "venues_currency_fkey"
            columns: ["currency"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["id"]
          },
        ]
      }
      volunteers: {
        Row: {
          accepted: Database["public"]["Enums"]["invited"]
          active: boolean
          created: string
          expertise: string
          id: string
          roleid: string
          scholarid: string
        }
        Insert: {
          accepted?: Database["public"]["Enums"]["invited"]
          active?: boolean
          created?: string
          expertise: string
          id?: string
          roleid: string
          scholarid: string
        }
        Update: {
          accepted?: Database["public"]["Enums"]["invited"]
          active?: boolean
          created?: string
          expertise?: string
          id?: string
          roleid?: string
          scholarid?: string
        }
        Relationships: [
          {
            foreignKeyName: "volunteers_roleid_fkey"
            columns: ["roleid"]
            isOneToOne: false
            referencedRelation: "roles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "volunteers_scholarid_fkey"
            columns: ["scholarid"]
            isOneToOne: false
            referencedRelation: "scholars"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      iseditor: {
        Args: {
          _venueid: string
        }
        Returns: boolean
      }
      isminter: {
        Args: {
          _scholarid: string
          _currencyid: string
        }
        Returns: boolean
      }
      issteward: {
        Args: Record<PropertyKey, never>
        Returns: boolean
      }
    }
    Enums: {
      exchange_proposal_kind: "create" | "modify" | "merge"
      invited: "invited" | "accepted" | "declined"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type PublicSchema = Database[Extract<keyof Database, "public">]

export type Tables<
  PublicTableNameOrOptions extends
    | keyof (PublicSchema["Tables"] & PublicSchema["Views"])
    | { schema: keyof Database },
  TableName extends PublicTableNameOrOptions extends { schema: keyof Database }
    ? keyof (Database[PublicTableNameOrOptions["schema"]]["Tables"] &
        Database[PublicTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = PublicTableNameOrOptions extends { schema: keyof Database }
  ? (Database[PublicTableNameOrOptions["schema"]]["Tables"] &
      Database[PublicTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : PublicTableNameOrOptions extends keyof (PublicSchema["Tables"] &
        PublicSchema["Views"])
    ? (PublicSchema["Tables"] &
        PublicSchema["Views"])[PublicTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  PublicTableNameOrOptions extends
    | keyof PublicSchema["Tables"]
    | { schema: keyof Database },
  TableName extends PublicTableNameOrOptions extends { schema: keyof Database }
    ? keyof Database[PublicTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = PublicTableNameOrOptions extends { schema: keyof Database }
  ? Database[PublicTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : PublicTableNameOrOptions extends keyof PublicSchema["Tables"]
    ? PublicSchema["Tables"][PublicTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  PublicTableNameOrOptions extends
    | keyof PublicSchema["Tables"]
    | { schema: keyof Database },
  TableName extends PublicTableNameOrOptions extends { schema: keyof Database }
    ? keyof Database[PublicTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = PublicTableNameOrOptions extends { schema: keyof Database }
  ? Database[PublicTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : PublicTableNameOrOptions extends keyof PublicSchema["Tables"]
    ? PublicSchema["Tables"][PublicTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  PublicEnumNameOrOptions extends
    | keyof PublicSchema["Enums"]
    | { schema: keyof Database },
  EnumName extends PublicEnumNameOrOptions extends { schema: keyof Database }
    ? keyof Database[PublicEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = PublicEnumNameOrOptions extends { schema: keyof Database }
  ? Database[PublicEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : PublicEnumNameOrOptions extends keyof PublicSchema["Enums"]
    ? PublicSchema["Enums"][PublicEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof PublicSchema["CompositeTypes"]
    | { schema: keyof Database },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof Database
  }
    ? keyof Database[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends { schema: keyof Database }
  ? Database[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof PublicSchema["CompositeTypes"]
    ? PublicSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

