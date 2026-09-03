export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
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
      app_settings: {
        Row: {
          singleton: boolean
          time_zone: string
          updated_at: string
        }
        Insert: {
          singleton?: boolean
          time_zone?: string
          updated_at?: string
        }
        Update: {
          singleton?: boolean
          time_zone?: string
          updated_at?: string
        }
        Relationships: []
      }
      base_foods: {
        Row: {
          aliases: string[]
          always_available: boolean
          archived_at: string | null
          carbs_g: number | null
          created_at: string
          display_unit: string | null
          emoji: string | null
          fat_g: number | null
          fiber_g: number | null
          g_per_count: number | null
          g_per_fl_oz: number | null
          grocery_category: string | null
          id: string
          ingredient_role: string | null
          kcal: number | null
          legacy_firebase_id: string | null
          measure_style: Database["public"]["Enums"]["measure_style"]
          merged_into: string | null
          name: string
          nutrition_basis_qty: number
          nutrition_is_estimated: boolean
          nutrition_source: string | null
          plural: string | null
          protein_g: number | null
          sodium_mg: number | null
          store_aisle: string | null
          sugar_g: number | null
          updated_at: string
        }
        Insert: {
          aliases?: string[]
          always_available?: boolean
          archived_at?: string | null
          carbs_g?: number | null
          created_at?: string
          display_unit?: string | null
          emoji?: string | null
          fat_g?: number | null
          fiber_g?: number | null
          g_per_count?: number | null
          g_per_fl_oz?: number | null
          grocery_category?: string | null
          id?: string
          ingredient_role?: string | null
          kcal?: number | null
          legacy_firebase_id?: string | null
          measure_style: Database["public"]["Enums"]["measure_style"]
          merged_into?: string | null
          name: string
          nutrition_basis_qty?: number
          nutrition_is_estimated?: boolean
          nutrition_source?: string | null
          plural?: string | null
          protein_g?: number | null
          sodium_mg?: number | null
          store_aisle?: string | null
          sugar_g?: number | null
          updated_at?: string
        }
        Update: {
          aliases?: string[]
          always_available?: boolean
          archived_at?: string | null
          carbs_g?: number | null
          created_at?: string
          display_unit?: string | null
          emoji?: string | null
          fat_g?: number | null
          fiber_g?: number | null
          g_per_count?: number | null
          g_per_fl_oz?: number | null
          grocery_category?: string | null
          id?: string
          ingredient_role?: string | null
          kcal?: number | null
          legacy_firebase_id?: string | null
          measure_style?: Database["public"]["Enums"]["measure_style"]
          merged_into?: string | null
          name?: string
          nutrition_basis_qty?: number
          nutrition_is_estimated?: boolean
          nutrition_source?: string | null
          plural?: string | null
          protein_g?: number | null
          sodium_mg?: number | null
          store_aisle?: string | null
          sugar_g?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "base_foods_display_unit_fkey"
            columns: ["display_unit"]
            isOneToOne: false
            referencedRelation: "measure_conversions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "base_foods_grocery_category_fkey"
            columns: ["grocery_category"]
            isOneToOne: false
            referencedRelation: "grocery_categories"
            referencedColumns: ["category"]
          },
          {
            foreignKeyName: "base_foods_merged_into_fkey"
            columns: ["merged_into"]
            isOneToOne: false
            referencedRelation: "base_foods"
            referencedColumns: ["id"]
          },
        ]
      }
      cook_sessions: {
        Row: {
          completed_at: string | null
          id: string
          meal: string | null
          note: string | null
          started_at: string
        }
        Insert: {
          completed_at?: string | null
          id?: string
          meal?: string | null
          note?: string | null
          started_at?: string
        }
        Update: {
          completed_at?: string | null
          id?: string
          meal?: string | null
          note?: string | null
          started_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "cook_sessions_meal_fkey"
            columns: ["meal"]
            isOneToOne: false
            referencedRelation: "meals"
            referencedColumns: ["id"]
          },
        ]
      }
      food_log_replacements: {
        Row: {
          created_at: string
          original_log: string
          replacement_log: string
        }
        Insert: {
          created_at?: string
          original_log: string
          replacement_log: string
        }
        Update: {
          created_at?: string
          original_log?: string
          replacement_log?: string
        }
        Relationships: [
          {
            foreignKeyName: "food_log_replacements_original_log_fkey"
            columns: ["original_log"]
            isOneToOne: false
            referencedRelation: "food_logs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "food_log_replacements_replacement_log_fkey"
            columns: ["replacement_log"]
            isOneToOne: false
            referencedRelation: "food_logs"
            referencedColumns: ["id"]
          },
        ]
      }
      food_logs: {
        Row: {
          acquisition_type: string | null
          carbs_g: number | null
          components: Json
          cost: number | null
          cost_is_estimated: boolean
          cost_source: string | null
          created_at: string
          fat_g: number | null
          fiber_g: number | null
          id: string
          kcal: number | null
          kind: string
          label: string
          legacy_firebase_id: string | null
          note: string | null
          nutrition_estimate: Json | null
          nutrition_is_estimated: boolean
          nutrition_source: string | null
          nutrition_status: string | null
          occurred_at: string
          out_of_pocket_cost: number | null
          paid_by: string | null
          portion_label: string | null
          price_as_of: string | null
          product: string | null
          protein_g: number | null
          recipe: string | null
          servings: number | null
          sodium_mg: number | null
          sugar_g: number | null
          time_precision: string
          total_price: number | null
          voided_at: string | null
        }
        Insert: {
          acquisition_type?: string | null
          carbs_g?: number | null
          components?: Json
          cost?: number | null
          cost_is_estimated?: boolean
          cost_source?: string | null
          created_at?: string
          fat_g?: number | null
          fiber_g?: number | null
          id?: string
          kcal?: number | null
          kind: string
          label: string
          legacy_firebase_id?: string | null
          note?: string | null
          nutrition_estimate?: Json | null
          nutrition_is_estimated?: boolean
          nutrition_source?: string | null
          nutrition_status?: string | null
          occurred_at?: string
          out_of_pocket_cost?: number | null
          paid_by?: string | null
          portion_label?: string | null
          price_as_of?: string | null
          product?: string | null
          protein_g?: number | null
          recipe?: string | null
          servings?: number | null
          sodium_mg?: number | null
          sugar_g?: number | null
          time_precision?: string
          total_price?: number | null
          voided_at?: string | null
        }
        Update: {
          acquisition_type?: string | null
          carbs_g?: number | null
          components?: Json
          cost?: number | null
          cost_is_estimated?: boolean
          cost_source?: string | null
          created_at?: string
          fat_g?: number | null
          fiber_g?: number | null
          id?: string
          kcal?: number | null
          kind?: string
          label?: string
          legacy_firebase_id?: string | null
          note?: string | null
          nutrition_estimate?: Json | null
          nutrition_is_estimated?: boolean
          nutrition_source?: string | null
          nutrition_status?: string | null
          occurred_at?: string
          out_of_pocket_cost?: number | null
          paid_by?: string | null
          portion_label?: string | null
          price_as_of?: string | null
          product?: string | null
          protein_g?: number | null
          recipe?: string | null
          servings?: number | null
          sodium_mg?: number | null
          sugar_g?: number | null
          time_precision?: string
          total_price?: number | null
          voided_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "food_logs_product_fkey"
            columns: ["product"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "food_logs_recipe_fkey"
            columns: ["recipe"]
            isOneToOne: false
            referencedRelation: "recipes"
            referencedColumns: ["id"]
          },
        ]
      }
      gpt_action_requests: {
        Row: {
          completed_at: string | null
          created_at: string
          operation: string
          request_id: string
          result: Json | null
        }
        Insert: {
          completed_at?: string | null
          created_at?: string
          operation: string
          request_id: string
          result?: Json | null
        }
        Update: {
          completed_at?: string | null
          created_at?: string
          operation?: string
          request_id?: string
          result?: Json | null
        }
        Relationships: []
      }
      grocery_categories: {
        Row: {
          category: string
          sort_order: number
        }
        Insert: {
          category: string
          sort_order: number
        }
        Update: {
          category?: string
          sort_order?: number
        }
        Relationships: []
      }
      inventory_events: {
        Row: {
          cook_session: string | null
          created_at: string
          food_log: string | null
          id: string
          lot: string
          note: string | null
          occurred_at: string
          prep: string | null
          quantity_delta: number
          reason: Database["public"]["Enums"]["inventory_event_reason"]
          voided_at: string | null
        }
        Insert: {
          cook_session?: string | null
          created_at?: string
          food_log?: string | null
          id?: string
          lot: string
          note?: string | null
          occurred_at?: string
          prep?: string | null
          quantity_delta: number
          reason: Database["public"]["Enums"]["inventory_event_reason"]
          voided_at?: string | null
        }
        Update: {
          cook_session?: string | null
          created_at?: string
          food_log?: string | null
          id?: string
          lot?: string
          note?: string | null
          occurred_at?: string
          prep?: string | null
          quantity_delta?: number
          reason?: Database["public"]["Enums"]["inventory_event_reason"]
          voided_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "inventory_events_cook_session_fkey"
            columns: ["cook_session"]
            isOneToOne: false
            referencedRelation: "cook_sessions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_events_food_log_fkey"
            columns: ["food_log"]
            isOneToOne: false
            referencedRelation: "food_logs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_events_lot_fkey"
            columns: ["lot"]
            isOneToOne: false
            referencedRelation: "inventory_lots"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_events_prep_fkey"
            columns: ["prep"]
            isOneToOne: false
            referencedRelation: "preps"
            referencedColumns: ["id"]
          },
        ]
      }
      inventory_lots: {
        Row: {
          acquired_at: string
          acquired_time_precision: string
          acquisition_food_log: string | null
          acquisition_type: string | null
          acquisition_void_event: string | null
          cost_is_estimated: boolean
          cost_source: string | null
          created_at: string
          id: string
          initial_qty: number
          is_external: boolean
          legacy_firebase_id: string | null
          location: string | null
          note: string | null
          out_of_pocket_cost: number | null
          paid_by: string | null
          prep: string | null
          price_as_of: string | null
          product: string | null
          remaining_qty: number
          total_cost: number | null
          use_by: string | null
        }
        Insert: {
          acquired_at?: string
          acquired_time_precision?: string
          acquisition_food_log?: string | null
          acquisition_type?: string | null
          acquisition_void_event?: string | null
          cost_is_estimated?: boolean
          cost_source?: string | null
          created_at?: string
          id?: string
          initial_qty: number
          is_external?: boolean
          legacy_firebase_id?: string | null
          location?: string | null
          note?: string | null
          out_of_pocket_cost?: number | null
          paid_by?: string | null
          prep?: string | null
          price_as_of?: string | null
          product?: string | null
          remaining_qty: number
          total_cost?: number | null
          use_by?: string | null
        }
        Update: {
          acquired_at?: string
          acquired_time_precision?: string
          acquisition_food_log?: string | null
          acquisition_type?: string | null
          acquisition_void_event?: string | null
          cost_is_estimated?: boolean
          cost_source?: string | null
          created_at?: string
          id?: string
          initial_qty?: number
          is_external?: boolean
          legacy_firebase_id?: string | null
          location?: string | null
          note?: string | null
          out_of_pocket_cost?: number | null
          paid_by?: string | null
          prep?: string | null
          price_as_of?: string | null
          product?: string | null
          remaining_qty?: number
          total_cost?: number | null
          use_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "inventory_lots_acquisition_food_log_fkey"
            columns: ["acquisition_food_log"]
            isOneToOne: false
            referencedRelation: "food_logs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_lots_acquisition_void_event_fkey"
            columns: ["acquisition_void_event"]
            isOneToOne: false
            referencedRelation: "inventory_event_costs"
            referencedColumns: ["inventory_event_id"]
          },
          {
            foreignKeyName: "inventory_lots_acquisition_void_event_fkey"
            columns: ["acquisition_void_event"]
            isOneToOne: false
            referencedRelation: "inventory_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_lots_location_fkey"
            columns: ["location"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["location"]
          },
          {
            foreignKeyName: "inventory_lots_prep_fkey"
            columns: ["prep"]
            isOneToOne: false
            referencedRelation: "preps"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_lots_product_fkey"
            columns: ["product"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
        ]
      }
      locations: {
        Row: {
          location: string
          sort_order: number
        }
        Insert: {
          location: string
          sort_order: number
        }
        Update: {
          location?: string
          sort_order?: number
        }
        Relationships: []
      }
      meal_plans: {
        Row: {
          cook_session: string | null
          consume_from_inventory: boolean | null
          created_at: string
          daypart: Database["public"]["Enums"]["daypart"]
          emoji: string | null
          group_id: string | null
          id: string
          inventory_lot: string | null
          intent: string
          leftover_of_group_id: string | null
          legacy_firebase_id: string | null
          made_at: string | null
          meal: string | null
          name: string | null
          note: string | null
          plan_date: string
          preparation_tasks: Json
          product: string | null
          recipe: string | null
          scale_factor: number
          scheduled_time: string | null
          status: Database["public"]["Enums"]["plan_status"]
          updated_at: string
        }
        Insert: {
          cook_session?: string | null
          consume_from_inventory?: boolean | null
          created_at?: string
          daypart: Database["public"]["Enums"]["daypart"]
          emoji?: string | null
          group_id?: string | null
          id?: string
          inventory_lot?: string | null
          intent?: string
          leftover_of_group_id?: string | null
          legacy_firebase_id?: string | null
          made_at?: string | null
          meal?: string | null
          name?: string | null
          note?: string | null
          plan_date: string
          preparation_tasks?: Json
          product?: string | null
          recipe?: string | null
          scale_factor?: number
          scheduled_time?: string | null
          status?: Database["public"]["Enums"]["plan_status"]
          updated_at?: string
        }
        Update: {
          cook_session?: string | null
          consume_from_inventory?: boolean | null
          created_at?: string
          daypart?: Database["public"]["Enums"]["daypart"]
          emoji?: string | null
          group_id?: string | null
          id?: string
          inventory_lot?: string | null
          intent?: string
          leftover_of_group_id?: string | null
          legacy_firebase_id?: string | null
          made_at?: string | null
          meal?: string | null
          name?: string | null
          note?: string | null
          plan_date?: string
          preparation_tasks?: Json
          product?: string | null
          recipe?: string | null
          scale_factor?: number
          scheduled_time?: string | null
          status?: Database["public"]["Enums"]["plan_status"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "meal_plans_cook_session_fkey"
            columns: ["cook_session"]
            isOneToOne: false
            referencedRelation: "cook_sessions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meal_plans_inventory_lot_fkey"
            columns: ["inventory_lot"]
            isOneToOne: false
            referencedRelation: "inventory_lots"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meal_plans_meal_fkey"
            columns: ["meal"]
            isOneToOne: false
            referencedRelation: "meals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meal_plans_product_fkey"
            columns: ["product"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meal_plans_recipe_fkey"
            columns: ["recipe"]
            isOneToOne: false
            referencedRelation: "recipes"
            referencedColumns: ["id"]
          },
        ]
      }
      meal_recipes: {
        Row: {
          meal: string
          recipe: string
          scale_factor: number
          sort_order: number
        }
        Insert: {
          meal: string
          recipe: string
          scale_factor?: number
          sort_order?: number
        }
        Update: {
          meal?: string
          recipe?: string
          scale_factor?: number
          sort_order?: number
        }
        Relationships: [
          {
            foreignKeyName: "meal_recipes_meal_fkey"
            columns: ["meal"]
            isOneToOne: false
            referencedRelation: "meals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meal_recipes_recipe_fkey"
            columns: ["recipe"]
            isOneToOne: false
            referencedRelation: "recipes"
            referencedColumns: ["id"]
          },
        ]
      }
      meals: {
        Row: {
          created_at: string
          emoji: string | null
          id: string
          legacy_firebase_id: string | null
          name: string
          notes: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          emoji?: string | null
          id?: string
          legacy_firebase_id?: string | null
          name: string
          notes?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          emoji?: string | null
          id?: string
          legacy_firebase_id?: string | null
          name?: string
          notes?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      measure_conversions: {
        Row: {
          base_to_this_ratio: number
          created_at: string
          full_name: string
          id: string
          measure_style: Database["public"]["Enums"]["measure_style"]
          short_name: string
        }
        Insert: {
          base_to_this_ratio: number
          created_at?: string
          full_name: string
          id?: string
          measure_style: Database["public"]["Enums"]["measure_style"]
          short_name: string
        }
        Update: {
          base_to_this_ratio?: number
          created_at?: string
          full_name?: string
          id?: string
          measure_style?: Database["public"]["Enums"]["measure_style"]
          short_name?: string
        }
        Relationships: []
      }
      personal_settings: {
        Row: {
          allergies: string[]
          calendar_settings: Json
          commute_minutes: number
          default_thaw_hours: number
          dietary_rules: string[]
          dinner_end: string
          dinner_start: string
          dislikes: string[]
          favorites: string[]
          nutrition_calories: number
          nutrition_carbs_g: number
          nutrition_fat_g: number
          nutrition_fiber_g: number
          nutrition_label: string | null
          nutrition_protein_g: number
          nutrition_sodium_mg: number
          planning_notes: string | null
          preparation_buffer_minutes: number
          routine_days: Json
          routine_notes: string | null
          singleton: boolean
          time_zone: string
          updated_at: string
          weekly_food_budget: number
        }
        Insert: {
          allergies?: string[]
          calendar_settings?: Json
          commute_minutes?: number
          default_thaw_hours?: number
          dietary_rules?: string[]
          dinner_end?: string
          dinner_start?: string
          dislikes?: string[]
          favorites?: string[]
          nutrition_calories?: number
          nutrition_carbs_g?: number
          nutrition_fat_g?: number
          nutrition_fiber_g?: number
          nutrition_label?: string | null
          nutrition_protein_g?: number
          nutrition_sodium_mg?: number
          planning_notes?: string | null
          preparation_buffer_minutes?: number
          routine_days?: Json
          routine_notes?: string | null
          singleton?: boolean
          time_zone?: string
          updated_at?: string
          weekly_food_budget?: number
        }
        Update: {
          allergies?: string[]
          calendar_settings?: Json
          commute_minutes?: number
          default_thaw_hours?: number
          dietary_rules?: string[]
          dinner_end?: string
          dinner_start?: string
          dislikes?: string[]
          favorites?: string[]
          nutrition_calories?: number
          nutrition_carbs_g?: number
          nutrition_fat_g?: number
          nutrition_fiber_g?: number
          nutrition_label?: string | null
          nutrition_protein_g?: number
          nutrition_sodium_mg?: number
          planning_notes?: string | null
          preparation_buffer_minutes?: number
          routine_days?: Json
          routine_notes?: string | null
          singleton?: boolean
          time_zone?: string
          updated_at?: string
          weekly_food_budget?: number
        }
        Relationships: []
      }
      planned_consumptions: {
        Row: {
          created_at: string
          food_log: string | null
          id: string
          meal_plan: string
          servings: number
          status: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          food_log?: string | null
          id?: string
          meal_plan: string
          servings: number
          status?: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          food_log?: string | null
          id?: string
          meal_plan?: string
          servings?: number
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "planned_consumptions_food_log_fkey"
            columns: ["food_log"]
            isOneToOne: true
            referencedRelation: "food_logs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "planned_consumptions_meal_plan_fkey"
            columns: ["meal_plan"]
            isOneToOne: true
            referencedRelation: "meal_plans"
            referencedColumns: ["id"]
          },
        ]
      }
      preps: {
        Row: {
          actual_minutes: number
          actual_yield_qty: number | null
          carbs_g: number | null
          components: Json
          cook_session: string | null
          ease_rating: number
          emoji: string | null
          fat_g: number | null
          fiber_g: number | null
          id: string
          kcal: number | null
          label: string | null
          legacy_firebase_id: string | null
          meal_plan: string | null
          note: string | null
          nutrition_estimate: Json | null
          nutrition_is_estimated: boolean
          nutrition_source: string | null
          parent_prep: string | null
          prepped_at: string
          protein_g: number | null
          recipe: string | null
          scale_factor: number
          sodium_mg: number | null
          sugar_g: number | null
          taste_rating: number
          time_precision: string
          voided_at: string | null
        }
        Insert: {
          actual_minutes?: number
          actual_yield_qty?: number | null
          carbs_g?: number | null
          components?: Json
          cook_session?: string | null
          ease_rating?: number
          emoji?: string | null
          fat_g?: number | null
          fiber_g?: number | null
          id?: string
          kcal?: number | null
          label?: string | null
          legacy_firebase_id?: string | null
          meal_plan?: string | null
          note?: string | null
          nutrition_estimate?: Json | null
          nutrition_is_estimated?: boolean
          nutrition_source?: string | null
          parent_prep?: string | null
          prepped_at?: string
          protein_g?: number | null
          recipe?: string | null
          scale_factor?: number
          sodium_mg?: number | null
          sugar_g?: number | null
          taste_rating?: number
          time_precision?: string
          voided_at?: string | null
        }
        Update: {
          actual_minutes?: number
          actual_yield_qty?: number | null
          carbs_g?: number | null
          components?: Json
          cook_session?: string | null
          ease_rating?: number
          emoji?: string | null
          fat_g?: number | null
          fiber_g?: number | null
          id?: string
          kcal?: number | null
          label?: string | null
          legacy_firebase_id?: string | null
          meal_plan?: string | null
          note?: string | null
          nutrition_estimate?: Json | null
          nutrition_is_estimated?: boolean
          nutrition_source?: string | null
          parent_prep?: string | null
          prepped_at?: string
          protein_g?: number | null
          recipe?: string | null
          scale_factor?: number
          sodium_mg?: number | null
          sugar_g?: number | null
          taste_rating?: number
          time_precision?: string
          voided_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "preps_cook_session_fkey"
            columns: ["cook_session"]
            isOneToOne: false
            referencedRelation: "cook_sessions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "preps_meal_plan_fkey"
            columns: ["meal_plan"]
            isOneToOne: false
            referencedRelation: "meal_plans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "preps_parent_prep_fkey"
            columns: ["parent_prep"]
            isOneToOne: false
            referencedRelation: "preps"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "preps_recipe_fkey"
            columns: ["recipe"]
            isOneToOne: false
            referencedRelation: "recipes"
            referencedColumns: ["id"]
          },
        ]
      }
      products: {
        Row: {
          aliases: string[]
          archived_at: string | null
          barcode: string | null
          brand: string | null
          carbs_g: number | null
          cost_as_of: string | null
          cost_source: string | null
          created_at: string
          emoji: string | null
          estimated_cost: number | null
          fat_g: number | null
          fiber_g: number | null
          food: string
          id: string
          kcal: number | null
          last_used_at: string | null
          legacy_firebase_id: string | null
          merged_into: string | null
          name: string
          nutrition_basis_qty: number | null
          nutrition_is_estimated: boolean
          nutrition_source: string | null
          package_qty_base: number
          package_unit: string
          protein_g: number | null
          serving_label: string | null
          serving_qty_base: number | null
          serving_unit: string | null
          servings_per_package: number | null
          sodium_mg: number | null
          sugar_g: number | null
          updated_at: string
          use_count: number
        }
        Insert: {
          aliases?: string[]
          archived_at?: string | null
          barcode?: string | null
          brand?: string | null
          carbs_g?: number | null
          cost_as_of?: string | null
          cost_source?: string | null
          created_at?: string
          emoji?: string | null
          estimated_cost?: number | null
          fat_g?: number | null
          fiber_g?: number | null
          food: string
          id?: string
          kcal?: number | null
          last_used_at?: string | null
          legacy_firebase_id?: string | null
          merged_into?: string | null
          name: string
          nutrition_basis_qty?: number | null
          nutrition_is_estimated?: boolean
          nutrition_source?: string | null
          package_qty_base: number
          package_unit: string
          protein_g?: number | null
          serving_label?: string | null
          serving_qty_base?: number | null
          serving_unit?: string | null
          servings_per_package?: number | null
          sodium_mg?: number | null
          sugar_g?: number | null
          updated_at?: string
          use_count?: number
        }
        Update: {
          aliases?: string[]
          archived_at?: string | null
          barcode?: string | null
          brand?: string | null
          carbs_g?: number | null
          cost_as_of?: string | null
          cost_source?: string | null
          created_at?: string
          emoji?: string | null
          estimated_cost?: number | null
          fat_g?: number | null
          fiber_g?: number | null
          food?: string
          id?: string
          kcal?: number | null
          last_used_at?: string | null
          legacy_firebase_id?: string | null
          merged_into?: string | null
          name?: string
          nutrition_basis_qty?: number | null
          nutrition_is_estimated?: boolean
          nutrition_source?: string | null
          package_qty_base?: number
          package_unit?: string
          protein_g?: number | null
          serving_label?: string | null
          serving_qty_base?: number | null
          serving_unit?: string | null
          servings_per_package?: number | null
          sodium_mg?: number | null
          sugar_g?: number | null
          updated_at?: string
          use_count?: number
        }
        Relationships: [
          {
            foreignKeyName: "products_food_fkey"
            columns: ["food"]
            isOneToOne: false
            referencedRelation: "base_foods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "products_merged_into_fkey"
            columns: ["merged_into"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "products_package_unit_fkey"
            columns: ["package_unit"]
            isOneToOne: false
            referencedRelation: "measure_conversions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "products_serving_unit_fkey"
            columns: ["serving_unit"]
            isOneToOne: false
            referencedRelation: "measure_conversions"
            referencedColumns: ["id"]
          },
        ]
      }
      recipe_ingredients: {
        Row: {
          id: string
          ingredient: string
          note: string | null
          pinned_product: string | null
          qty: number
          recipe: string
          sort_order: number
          unit: string
        }
        Insert: {
          id?: string
          ingredient: string
          note?: string | null
          pinned_product?: string | null
          qty: number
          recipe: string
          sort_order?: number
          unit: string
        }
        Update: {
          id?: string
          ingredient?: string
          note?: string | null
          pinned_product?: string | null
          qty?: number
          recipe?: string
          sort_order?: number
          unit?: string
        }
        Relationships: [
          {
            foreignKeyName: "recipe_ingredients_ingredient_fkey"
            columns: ["ingredient"]
            isOneToOne: false
            referencedRelation: "base_foods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recipe_ingredients_pinned_product_fkey"
            columns: ["pinned_product"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recipe_ingredients_recipe_fkey"
            columns: ["recipe"]
            isOneToOne: false
            referencedRelation: "recipes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recipe_ingredients_unit_fkey"
            columns: ["unit"]
            isOneToOne: false
            referencedRelation: "measure_conversions"
            referencedColumns: ["id"]
          },
        ]
      }
      recipes: {
        Row: {
          created_at: string
          emoji: string | null
          id: string
          instructions: Json
          legacy_firebase_id: string | null
          name: string
          output_food: string | null
          override_basis_qty: number | null
          override_carbs_g: number | null
          override_fat_g: number | null
          override_fiber_g: number | null
          override_kcal: number | null
          override_protein_g: number | null
          override_sodium_mg: number | null
          override_sugar_g: number | null
          portions: Json
          preparation_rules: Json
          prompt_for_feedback: boolean
          servings: number
          source_note: string | null
          source_url: string | null
          updated_at: string
          yield_qty: number | null
        }
        Insert: {
          created_at?: string
          emoji?: string | null
          id?: string
          instructions?: Json
          legacy_firebase_id?: string | null
          name: string
          output_food?: string | null
          override_basis_qty?: number | null
          override_carbs_g?: number | null
          override_fat_g?: number | null
          override_fiber_g?: number | null
          override_kcal?: number | null
          override_protein_g?: number | null
          override_sodium_mg?: number | null
          override_sugar_g?: number | null
          portions?: Json
          preparation_rules?: Json
          prompt_for_feedback?: boolean
          servings?: number
          source_note?: string | null
          source_url?: string | null
          updated_at?: string
          yield_qty?: number | null
        }
        Update: {
          created_at?: string
          emoji?: string | null
          id?: string
          instructions?: Json
          legacy_firebase_id?: string | null
          name?: string
          output_food?: string | null
          override_basis_qty?: number | null
          override_carbs_g?: number | null
          override_fat_g?: number | null
          override_fiber_g?: number | null
          override_kcal?: number | null
          override_protein_g?: number | null
          override_sodium_mg?: number | null
          override_sugar_g?: number | null
          portions?: Json
          preparation_rules?: Json
          prompt_for_feedback?: boolean
          servings?: number
          source_note?: string | null
          source_url?: string | null
          updated_at?: string
          yield_qty?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "recipes_output_food_fkey"
            columns: ["output_food"]
            isOneToOne: false
            referencedRelation: "base_foods"
            referencedColumns: ["id"]
          },
        ]
      }
      record_edits: {
        Row: {
          after_state: Json
          before_state: Json
          edited_at: string
          id: string
          record_id: string
          resource: string
        }
        Insert: {
          after_state: Json
          before_state: Json
          edited_at?: string
          id?: string
          record_id: string
          resource: string
        }
        Update: {
          after_state?: Json
          before_state?: Json
          edited_at?: string
          id?: string
          record_id?: string
          resource?: string
        }
        Relationships: []
      }
      shopping_items: {
        Row: {
          checked_at: string | null
          created_at: string
          first_needed_date: string | null
          food: string | null
          free_text: string | null
          id: string
          legacy_firebase_id: string | null
          lot: string | null
          note: string | null
          pinned_product: string | null
          qty_needed: number | null
          quantity_label: string | null
          source: Database["public"]["Enums"]["shopping_source"]
          unit: string | null
        }
        Insert: {
          checked_at?: string | null
          created_at?: string
          first_needed_date?: string | null
          food?: string | null
          free_text?: string | null
          id?: string
          legacy_firebase_id?: string | null
          lot?: string | null
          note?: string | null
          pinned_product?: string | null
          qty_needed?: number | null
          quantity_label?: string | null
          source?: Database["public"]["Enums"]["shopping_source"]
          unit?: string | null
        }
        Update: {
          checked_at?: string | null
          created_at?: string
          first_needed_date?: string | null
          food?: string | null
          free_text?: string | null
          id?: string
          legacy_firebase_id?: string | null
          lot?: string | null
          note?: string | null
          pinned_product?: string | null
          qty_needed?: number | null
          quantity_label?: string | null
          source?: Database["public"]["Enums"]["shopping_source"]
          unit?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "shopping_items_food_fkey"
            columns: ["food"]
            isOneToOne: false
            referencedRelation: "base_foods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "shopping_items_lot_fkey"
            columns: ["lot"]
            isOneToOne: false
            referencedRelation: "inventory_lots"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "shopping_items_pinned_product_fkey"
            columns: ["pinned_product"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "shopping_items_unit_fkey"
            columns: ["unit"]
            isOneToOne: false
            referencedRelation: "measure_conversions"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      daily_nutrition: {
        Row: {
          carbs_g: number | null
          complete_entries: number | null
          entry_count: number | null
          fat_g: number | null
          fiber_g: number | null
          kcal: number | null
          local_date: string | null
          nutrition_is_complete: boolean | null
          partial_entries: number | null
          protein_g: number | null
          sodium_mg: number | null
          sugar_g: number | null
          unknown_entries: number | null
        }
        Relationships: []
      }
      history_quality_issues: {
        Row: {
          details: Json | null
          issue_type: string | null
          record_id: string | null
        }
        Relationships: []
      }
      inventory_event_costs: {
        Row: {
          cost: number | null
          inventory_event_id: string | null
          lot: string | null
          occurred_at: string | null
          reason: Database["public"]["Enums"]["inventory_event_reason"] | null
          voided_at: string | null
        }
        Relationships: [
          {
            foreignKeyName: "inventory_events_lot_fkey"
            columns: ["lot"]
            isOneToOne: false
            referencedRelation: "inventory_lots"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Functions: {
      consume_inventory_lot: {
        Args: { p_lot: string; p_occurred_at?: string; p_quantity: number }
        Returns: string
      }
      consume_planned_meals: {
        Args: {
          p_meal_plans: string[]
          p_occurred_at?: string
          p_servings: number[]
        }
        Returns: string[]
      }
      consume_prepared_batch: {
        Args: {
          p_lot: string
          p_meal_plan?: string
          p_occurred_at?: string
          p_quantity: number
        }
        Returns: string
      }
      consume_prepared_lot: {
        Args: { p_lot: string; p_occurred_at?: string; p_quantity?: number }
        Returns: string
      }
      consume_product_purchase:
        | {
            Args: {
              p_acquisition_type: string
              p_consumed_quantity: number
              p_cost_is_estimated: boolean
              p_cost_source: string
              p_label?: string
              p_location?: string
              p_note?: string
              p_occurred_at?: string
              p_out_of_pocket_cost: number
              p_paid_by: string
              p_price_as_of: string
              p_product: string
              p_purchased_quantity: number
              p_request_id: string
              p_time_precision?: string
              p_total_price: number
            }
            Returns: Json
          }
        | {
            Args: {
              p_acquisition_type: string
              p_consumed_quantity: number
              p_cost_is_estimated: boolean
              p_cost_source: string
              p_label?: string
              p_location?: string
              p_note?: string
              p_occurred_at?: string
              p_out_of_pocket_cost: number
              p_paid_by: string
              p_price_as_of: string
              p_product: string
              p_purchased_quantity: number
              p_quantity_unit: string
              p_request_id: string
              p_time_precision?: string
              p_total_price: number
            }
            Returns: Json
          }
      cook_recipe: {
        Args: {
          p_actual_yield?: number
          p_location?: string
          p_recipe: string
          p_scale?: number
        }
        Returns: string
      }
      cook_recipes: { Args: { p_recipes: string[] }; Returns: string[] }
      food_accepts_unit: {
        Args: { p_food: string; p_unit: string }
        Returns: boolean
      }
      from_base_quantity: {
        Args: { p_base_amount: number; p_food: string; p_unit: string }
        Returns: number
      }
      gpt_add_grocery_lots: {
        Args: { p_items: Json; p_request_id: string; p_source: string }
        Returns: Json
      }
      gpt_archive_definition: {
        Args: { p_id: string; p_reason: string; p_resource: string }
        Returns: Json
      }
      gpt_claim_request: {
        Args: { p_operation: string; p_request_id: string }
        Returns: Json
      }
      gpt_complete_request: {
        Args: { p_request_id: string; p_result: Json }
        Returns: undefined
      }
      gpt_consume_inventory: {
        Args: {
          p_food: string
          p_label?: string
          p_lot?: string
          p_note?: string
          p_occurred_at: string
          p_quantity: number
          p_request_id: string
          p_time_precision: string
          p_unit: string
        }
        Returns: Json
      }
      gpt_consume_prepared: {
        Args: {
          p_label?: string
          p_lot: string
          p_note?: string
          p_occurred_at: string
          p_quantity: number
          p_request_id: string
          p_time_precision: string
        }
        Returns: Json
      }
      gpt_create_manual_prepared_batch: {
        Args: {
          p_acquisition_type: string
          p_components: Json
          p_cost_is_estimated: boolean
          p_cost_source: string
          p_label: string
          p_location: string
          p_note?: string
          p_nutrition: Json
          p_nutrition_estimate: Json
          p_out_of_pocket_cost: number
          p_paid_by: string
          p_prepared_at: string
          p_price_as_of: string
          p_request_id: string
          p_servings: number
          p_time_precision: string
          p_total_price: number
          p_use_by: string
        }
        Returns: Json
      }
      gpt_merge_products: {
        Args: {
          p_archive_source_food: boolean
          p_reason: string
          p_source: string
          p_target: string
        }
        Returns: Json
      }
      gpt_prepare_recipe: {
        Args: {
          p_location: string
          p_note: string
          p_prepared_at: string
          p_recipe: string
          p_request_id: string
          p_servings: number
          p_time_precision: string
          p_use_by: string
        }
        Returns: Json
      }
      gpt_preview_daily_nutrition: {
        Args: { p_candidate: Json; p_date: string }
        Returns: Json
      }
      gpt_reconcile_inventory: {
        Args: { p_replacements: Json; p_request_id: string; p_source: string }
        Returns: Json
      }
      gpt_replace_weekly_plan: {
        Args: { p_entries: Json; p_week_start: string }
        Returns: Json
      }
      gpt_save_plan: {
        Args: { p_entries: Json; p_mode: string; p_week_start: string | null }
        Returns: Json
      }
      gpt_save_recipe: { Args: { p_recipe: Json }; Returns: Json }
      gpt_update_consumption: {
        Args: { p_food_log: string; p_patch: Json }
        Returns: Json
      }
      gpt_update_food: {
        Args: { p_food: string; p_patch: Json }
        Returns: Json
      }
      gpt_update_inventory_lot: {
        Args: { p_lot: string; p_patch: Json }
        Returns: Json
      }
      gpt_update_product: {
        Args: { p_patch: Json; p_product: string }
        Returns: Json
      }
      gpt_update_recipe: {
        Args: { p_patch: Json; p_recipe: string }
        Returns: Json
      }
      gpt_void_consumption: {
        Args: { p_food_log: string; p_reason: string }
        Returns: Json
      }
      is_app_owner: { Args: never; Returns: boolean }
      log_manual_consumption: {
        Args: {
          p_acquisition_type: string
          p_components: Json
          p_cost_is_estimated: boolean
          p_cost_source: string
          p_label: string
          p_note?: string
          p_nutrition: Json
          p_nutrition_estimate: Json
          p_occurred_at: string
          p_out_of_pocket_cost: number
          p_paid_by: string
          p_portion_label: string
          p_price_as_of: string
          p_request_id: string
          p_time_precision: string
          p_total_price: number
        }
        Returns: Json
      }
      lot_nutrition_json: {
        Args: { p_lot: string; p_path?: string[] }
        Returns: Json
      }
      lot_nutrition_per_base_unit: {
        Args: { p_lot: string }
        Returns: {
          carbs_g: number
          fat_g: number
          fiber_g: number
          kcal: number
          protein_g: number
          sodium_mg: number
        }[]
      }
      prep_total_cost: { Args: { p_prep: string }; Returns: number }
      prepare_recipe: {
        Args: {
          p_eaten_servings?: number
          p_location?: string
          p_meal_plan?: string
          p_occurred_at?: string
          p_recipe: string
          p_scale?: number
          p_servings?: number
        }
        Returns: Json
      }
      product_portion_snapshot: {
        Args: { p_product: string; p_servings: number }
        Returns: Json
      }
      product_nutrition_multiplier: {
        Args: { p_product: string; p_quantity: number }
        Returns: number
      }
      product_servings_for_quantity: {
        Args: { p_product: string; p_quantity: number }
        Returns: number
      }
      recipe_portion_snapshot: {
        Args: { p_recipe: string; p_servings: number }
        Returns: Json
      }
      rebuild_shopping_from_plan: {
        Args: { p_from?: string; p_through?: string }
        Returns: number
      }
      refresh_inventory_lot: { Args: { p_lot: string }; Returns: undefined }
      refresh_prepared_lot_provenance: {
        Args: { p_prep: string }
        Returns: undefined
      }
      resolve_measure_conversion: { Args: { p_unit: string }; Returns: string }
      restore_food_log: { Args: { p_food_log: string }; Returns: undefined }
      save_prep_feedback: {
        Args: {
          p_actual_minutes?: number
          p_ease?: number
          p_prep: string
          p_taste?: number
        }
        Returns: undefined
      }
      set_inventory_lot_quantity: {
        Args: { p_discard?: boolean; p_lot: string; p_remaining: number }
        Returns: string
      }
      to_base_quantity: {
        Args: { p_amount: number; p_food: string; p_unit: string }
        Returns: number
      }
      undo_inventory_adjustment: {
        Args: { p_event: string }
        Returns: undefined
      }
      undo_prep: { Args: { p_prep: string }; Returns: undefined }
      void_food_log: { Args: { p_food_log: string }; Returns: undefined }
    }
    Enums: {
      daypart: "breakfast" | "brunch" | "lunch" | "dinner" | "snack" | "dessert"
      inventory_event_reason:
        | "eaten"
        | "prep"
        | "waste"
        | "adjust"
        | "gave_away"
      measure_style: "discrete" | "weight" | "volume"
      plan_status: "planned" | "made" | "skipped" | "moved"
      shopping_source: "generated" | "manual" | "staple"
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
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
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
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
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
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
      daypart: ["breakfast", "brunch", "lunch", "dinner", "snack", "dessert"],
      inventory_event_reason: ["eaten", "prep", "waste", "adjust", "gave_away"],
      measure_style: ["discrete", "weight", "volume"],
      plan_status: ["planned", "made", "skipped", "moved"],
      shopping_source: ["generated", "manual", "staple"],
    },
  },
} as const
