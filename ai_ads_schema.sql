CREATE TABLE IF NOT EXISTS ai_ads (
 id TEXT PRIMARY KEY,
 nome TEXT NOT NULL,
 briefing JSONB NOT NULL,
 copy JSONB NOT NULL,
 image_b64 TEXT,
 video_request_id TEXT,
 video_status TEXT DEFAULT 'NOT_STARTED',
 video_url TEXT,
 status TEXT NOT NULL DEFAULT 'DRAFT',
 meta_campaign_id TEXT,
 meta_adset_id TEXT,
 meta_ad_id TEXT,
 latest_insights JSONB,
 created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ai_ads_active_idx ON ai_ads(status);
CREATE INDEX IF NOT EXISTS ai_ads_video_idx ON ai_ads(video_status);
