-- Schema for Community Browse / Share Feature
-- Run this in your Supabase SQL Editor

-- Shared outfits table
CREATE TABLE IF NOT EXISTS shared_outfits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  username TEXT NOT NULL DEFAULT 'Anonymous',
  image_url TEXT NOT NULL,
  description TEXT,
  tags TEXT[] DEFAULT '{}',
  likes INTEGER DEFAULT 0,
  face_blurred BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Likes table for tracking who liked what
CREATE TABLE IF NOT EXISTS shared_outfit_likes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  outfit_id UUID NOT NULL REFERENCES shared_outfits(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(outfit_id, user_id)
);

-- Reports table for moderation
CREATE TABLE IF NOT EXISTS outfit_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  outfit_id UUID NOT NULL REFERENCES shared_outfits(id) ON DELETE CASCADE,
  reporter_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reason TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  resolved BOOLEAN DEFAULT false
);

-- Function to increment likes
CREATE OR REPLACE FUNCTION increment_outfit_likes(outfit_id UUID)
RETURNS void AS $$
BEGIN
  UPDATE shared_outfits
  SET likes = likes + 1
  WHERE id = outfit_id;
END;
$$ LANGUAGE plpgsql;

-- Function to decrement likes
CREATE OR REPLACE FUNCTION decrement_outfit_likes(outfit_id UUID)
RETURNS void AS $$
BEGIN
  UPDATE shared_outfits
  SET likes = GREATEST(likes - 1, 0)
  WHERE id = outfit_id;
END;
$$ LANGUAGE plpgsql;

-- Indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_shared_outfits_user_id ON shared_outfits(user_id);
CREATE INDEX IF NOT EXISTS idx_shared_outfits_created_at ON shared_outfits(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_shared_outfits_tags ON shared_outfits USING GIN(tags);
CREATE INDEX IF NOT EXISTS idx_shared_outfit_likes_outfit ON shared_outfit_likes(outfit_id);
CREATE INDEX IF NOT EXISTS idx_shared_outfit_likes_user ON shared_outfit_likes(user_id);

-- Row Level Security (RLS)
ALTER TABLE shared_outfits ENABLE ROW LEVEL SECURITY;
ALTER TABLE shared_outfit_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE outfit_reports ENABLE ROW LEVEL SECURITY;

-- Policies for shared_outfits
-- Anyone can read shared outfits
CREATE POLICY "Shared outfits are viewable by everyone"
  ON shared_outfits FOR SELECT
  USING (true);

-- Users can insert their own outfits
CREATE POLICY "Users can share their own outfits"
  ON shared_outfits FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Users can update their own outfits
CREATE POLICY "Users can update their own outfits"
  ON shared_outfits FOR UPDATE
  USING (auth.uid() = user_id);

-- Users can delete their own outfits
CREATE POLICY "Users can delete their own outfits"
  ON shared_outfits FOR DELETE
  USING (auth.uid() = user_id);

-- Policies for likes
CREATE POLICY "Likes are viewable by everyone"
  ON shared_outfit_likes FOR SELECT
  USING (true);

CREATE POLICY "Users can add their own likes"
  ON shared_outfit_likes FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can remove their own likes"
  ON shared_outfit_likes FOR DELETE
  USING (auth.uid() = user_id);

-- Policies for reports
CREATE POLICY "Users can submit reports"
  ON outfit_reports FOR INSERT
  WITH CHECK (auth.uid() = reporter_id);

-- Create storage bucket for shared outfit images
-- Run this in the Supabase dashboard Storage section:
-- 1. Create a new bucket called "shared-outfits"
-- 2. Make it public (for image URLs to work)
-- Or run:
INSERT INTO storage.buckets (id, name, public)
VALUES ('shared-outfits', 'shared-outfits', true)
ON CONFLICT (id) DO NOTHING;

-- Storage policies
CREATE POLICY "Anyone can view shared outfit images"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'shared-outfits');

CREATE POLICY "Authenticated users can upload outfit images"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'shared-outfits'
    AND auth.role() = 'authenticated'
  );

CREATE POLICY "Users can delete their own outfit images"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'shared-outfits'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );
