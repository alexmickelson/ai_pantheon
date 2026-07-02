CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT NOT NULL UNIQUE,
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ai_providers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  endpoint TEXT NOT NULL,
  auth_token TEXT NOT NULL,
  deleted_at TIMESTAMPTZ,
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns WHERE table_name = 'ai_providers' AND column_name = 'deleted_at'
  ) THEN
    ALTER TABLE ai_providers ADD COLUMN deleted_at TIMESTAMPTZ;
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_indexes WHERE indexname = 'ai_providers_name_key'
  ) THEN
    DROP INDEX ai_providers_name_key;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_ai_providers_name_unique ON ai_providers(name) WHERE deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS user_api_keys (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  key_hash BYTEA NOT NULL,
  key_prefix TEXT NOT NULL,
  expires_at TIMESTAMPTZ,
  last_used_at TIMESTAMPTZ,
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_api_keys_user_id ON user_api_keys(user_id);
CREATE INDEX IF NOT EXISTS idx_user_api_keys_key_hash ON user_api_keys(key_hash);

CREATE TABLE IF NOT EXISTS completion_metrics (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id),
  provider_id UUID NOT NULL REFERENCES ai_providers(id),
  model TEXT NOT NULL,
  status_code INTEGER NOT NULL,

  -- usage
  prompt_tokens INTEGER,
  completion_tokens INTEGER,
  total_tokens INTEGER,
  cached_tokens INTEGER DEFAULT 0,

  -- timings (provider-reported, NULL for non-llama.cpp providers)
  prompt_ms DOUBLE PRECISION,
  predicted_ms DOUBLE PRECISION,
  prompt_per_token_ms DOUBLE PRECISION,
  predicted_per_token_ms DOUBLE PRECISION,
  prompt_per_second DOUBLE PRECISION,
  predicted_per_second DOUBLE PRECISION,
  cache_n INTEGER,
  draft_n INTEGER,
  draft_n_accepted INTEGER,

  -- proxy-side
  response_latency_ms DOUBLE PRECISION NOT NULL,
  error_message TEXT,

  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  api_key_id UUID REFERENCES user_api_keys(id)
);

CREATE INDEX IF NOT EXISTS idx_completion_metrics_provider ON completion_metrics(provider_id);
CREATE INDEX IF NOT EXISTS idx_completion_metrics_user ON completion_metrics(user_id);
CREATE INDEX IF NOT EXISTS idx_completion_metrics_model ON completion_metrics(model);
CREATE INDEX IF NOT EXISTS idx_completion_metrics_created ON completion_metrics(inserted_at DESC);
CREATE INDEX IF NOT EXISTS idx_completion_metrics_api_key ON completion_metrics(api_key_id);
