// Ev1l Designer: public configuration.
// The anon key is designed to be public: what a user can read or write is enforced by the
// row-level security rules in supabase/migrations/001_init.sql.
// NEVER put the service_role key or the Anthropic key in this file.
window.EV1L_CONFIG = {
  supabaseUrl: "https://zhigtwdewkjkmsjwickm.supabase.co",
  supabaseAnonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpoaWd0d2Rld2tqa21zandpY2ttIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE0NDkyMzEsImV4cCI6MjEwNzAyNTIzMX0.LdRHc0z7UAVmfdWEinj4B9XcFP6L-UlEkMt0cL4jWms",
  // After deploying the AI Render function (README step 3), set this to:
  // "https://zhigtwdewkjkmsjwickm.supabase.co/functions/v1/ai-render"
  aiProxyUrl: ""
};
