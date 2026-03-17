-- ================================================
-- Add missing columns for products & categories
-- Run on easytech_v2 database
-- Phase 1: Discount module (category + product + stock condition)
-- ================================================
USE easytech_v2;

-- Products base columns
ALTER TABLE products ADD COLUMN IF NOT EXISTS stock INT DEFAULT 0;
ALTER TABLE products ADD COLUMN IF NOT EXISTS is_featured TINYINT(1) DEFAULT 0;
ALTER TABLE products ADD COLUMN IF NOT EXISTS original_price DECIMAL(12,2) NULL;

-- Products discount columns
ALTER TABLE products ADD COLUMN IF NOT EXISTS discount_percent DECIMAL(5,2) DEFAULT 0;
ALTER TABLE products ADD COLUMN IF NOT EXISTS discount_amount DECIMAL(12,2) DEFAULT 0;
ALTER TABLE products ADD COLUMN IF NOT EXISTS discount_min_stock INT DEFAULT 0;

-- Categories extra columns
ALTER TABLE categories ADD COLUMN IF NOT EXISTS description TEXT NULL;
ALTER TABLE categories ADD COLUMN IF NOT EXISTS image_url TEXT NULL;
ALTER TABLE categories ADD COLUMN IF NOT EXISTS discount_percent DECIMAL(5,2) DEFAULT 0;
ALTER TABLE categories ADD COLUMN IF NOT EXISTS discount_amount DECIMAL(12,2) DEFAULT 0;

-- Set default stock for all existing products
UPDATE products SET stock = 10 WHERE stock = 0 OR stock IS NULL;
