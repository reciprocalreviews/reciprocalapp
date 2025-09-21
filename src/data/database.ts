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
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
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
      assignments: {
        Row: {
          approved: boolean
          bid: boolean
          completed: boolean
          id: string
          role: string
          scholar: string
          submission: string
          venue: string
        }
        Insert: {
          approved?: boolean
          bid?: boolean
          completed?: boolean
          id?: string
          role: string
          scholar: string
          submission: string
          venue: string
        }
        Update: {
          approved?: boolean
          bid?: boolean
          completed?: boolean
          id?: string
          role?: string
          scholar?: string
          submission?: string
          venue?: string
        }
        Relationships: [
          {
            foreignKeyName: "assignments_role_fkey"
            columns: ["role"]
            isOneToOne: false
            referencedRelation: "roles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assignments_scholar_fkey"
            columns: ["scholar"]
            isOneToOne: false
            referencedRelation: "scholars"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assignments_submission_fkey"
            columns: ["submission"]
            isOneToOne: false
            referencedRelation: "submissions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assignments_venue_fkey"
            columns: ["venue"]
            isOneToOne: false
            referencedRelation: "venues"
            referencedColumns: ["id"]
          },
        ]
      }
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
      emails: {
        Row: {
          email: string
          event: string
          id: string
          message: string
          scholar: string | null
          subject: string
          time_sent: string
          venue: string | null
        }
        Insert: {
          email: string
          event: string
          id?: string
          message: string
          scholar?: string | null
          subject: string
          time_sent?: string
          venue?: string | null
        }
        Update: {
          email?: string
          event?: string
          id?: string
          message?: string
          scholar?: string | null
          subject?: string
          time_sent?: string
          venue?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "emails_scholar_fkey"
            columns: ["scholar"]
            isOneToOne: false
            referencedRelation: "scholars"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "emails_venue_fkey"
            columns: ["venue"]
            isOneToOne: false
            referencedRelation: "venues"
            referencedColumns: ["id"]
          },
        ]
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
          approver: string | null
          biddable: boolean
          description: string
          id: string
          invited: boolean
          name: string
          priority: number
          venueid: string
        }
        Insert: {
          amount: number
          approver?: string | null
          biddable?: boolean
          description?: string
          id?: string
          invited: boolean
          name?: string
          priority?: number
          venueid: string
        }
        Update: {
          amount?: number
          approver?: string | null
          biddable?: boolean
          description?: string
          id?: string
          invited?: boolean
          name?: string
          priority?: number
          venueid?: string
        }
        Relationships: [
          {
            foreignKeyName: "roles_approver_fkey"
            columns: ["approver"]
            isOneToOne: false
            referencedRelation: "roles"
            referencedColumns: ["id"]
          },
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
          status_reminder_time: string | null
          status_time: string | null
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
          status_reminder_time?: string | null
          status_time?: string | null
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
          status_reminder_time?: string | null
          status_time?: string | null
          steward?: boolean
          when?: string
        }
        Relationships: []
      }
      submissions: {
        Row: {
          authors: string[]
          expertise: string | null
          externalid: string
          id: string
          payments: number[]
          previousid: string | null
          status: Database["public"]["Enums"]["submission_status"]
          title: string
          transactions: string[]
          venue: string
        }
        Insert: {
          authors: string[]
          expertise?: string | null
          externalid: string
          id?: string
          payments: number[]
          previousid?: string | null
          status?: Database["public"]["Enums"]["submission_status"]
          title?: string
          transactions: string[]
          venue: string
        }
        Update: {
          authors?: string[]
          expertise?: string | null
          externalid?: string
          id?: string
          payments?: number[]
          previousid?: string | null
          status?: Database["public"]["Enums"]["submission_status"]
          title?: string
          transactions?: string[]
          venue?: string
        }
        Relationships: [
          {
            foreignKeyName: "submissions_venue_fkey"
            columns: ["venue"]
            isOneToOne: false
            referencedRelation: "venues"
            referencedColumns: ["id"]
          },
        ]
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
          created: string
          creator: string
          currency: string
          from_scholar: string | null
          from_venue: string | null
          id: string
          purpose: string
          status: Database["public"]["Enums"]["transaction_status"]
          to_scholar: string | null
          to_venue: string | null
          tokens: string[]
        }
        Insert: {
          created?: string
          creator: string
          currency: string
          from_scholar?: string | null
          from_venue?: string | null
          id?: string
          purpose: string
          status: Database["public"]["Enums"]["transaction_status"]
          to_scholar?: string | null
          to_venue?: string | null
          tokens: string[]
        }
        Update: {
          created?: string
          creator?: string
          currency?: string
          from_scholar?: string | null
          from_venue?: string | null
          id?: string
          purpose?: string
          status?: Database["public"]["Enums"]["transaction_status"]
          to_scholar?: string | null
          to_venue?: string | null
          tokens?: string[]
        }
        Relationships: [
          {
            foreignKeyName: "transactions_creator_fkey"
            columns: ["creator"]
            isOneToOne: false
            referencedRelation: "scholars"
            referencedColumns: ["id"]
          },
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
          currency: string
          description: string
          edit_amount: number
          editors: string[]
          id: string
          submission_cost: number
          title: string
          url: string
          welcome_amount: number
        }
        Insert: {
          currency: string
          description?: string
          edit_amount?: number
          editors?: string[]
          id?: string
          submission_cost?: number
          title?: string
          url?: string
          welcome_amount: number
        }
        Update: {
          currency?: string
          description?: string
          edit_amount?: number
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
      isapprover: {
        Args: { _roleid: string }
        Returns: boolean
      }
      iseditor: {
        Args: { _venueid: string }
        Returns: boolean
      }
      isminter: {
        Args: { _currencyid: string; _scholarid: string }
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
      submission_status: "reviewing" | "done"
      transaction_status: "proposed" | "approved" | "canceled"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {
      exchange_proposal_kind: ["create", "modify", "merge"],
      invited: ["invited", "accepted", "declined"],
      submission_status: ["reviewing", "done"],
      transaction_status: ["proposed", "approved", "canceled"],
    },
  },
} as const

