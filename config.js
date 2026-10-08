// Ev1l Designer: public configuration.
// The anon key is designed to be public: what a user can read or write is enforced by the
// row-level security rules in supabase/migrations/001_init.sql.
// NEVER put the service_role key or the Anthropic key in this file.
window.EV1L_CONFIG = {
  supabaseUrl: "https://YOUR-PROJECT-ID.supabase.co",
  supabaseAnonKey: "YOUR-ANON-PUBLIC-KEY",
  aiProxyUrl: "https://YOUR-PROJECT-ID.supabase.co/functions/v1/ai-render"
};
