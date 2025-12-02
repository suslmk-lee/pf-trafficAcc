-- PlugFest 2025 Traffic Dashboard
-- Database Schema Initialization

-- Create database if not exists
CREATE DATABASE IF NOT EXISTS pf2005 DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE pf2005;

-- Drop table if exists (for clean testing)
DROP TABLE IF EXISTS accidents;

-- Create accidents table
CREATE TABLE accidents (
  id INT AUTO_INCREMENT PRIMARY KEY,
  acc_date VARCHAR(8) NOT NULL COMMENT 'YYYYMMDD format',
  acc_hour VARCHAR(4) NOT NULL COMMENT 'HHMM format',
  acc_point_nm VARCHAR(255) NOT NULL COMMENT 'Accident location name',
  link_id VARCHAR(50) NOT NULL,
  acc_info VARCHAR(255) NOT NULL COMMENT 'Accident information',
  acc_type VARCHAR(50) NOT NULL COMMENT 'Accident type',
  latitude VARCHAR(20) NOT NULL,
  longitude VARCHAR(20) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_acc_date (acc_date),
  INDEX idx_acc_hour (acc_hour),
  INDEX idx_acc_point (acc_point_nm),
  INDEX idx_created_at (created_at),
  UNIQUE KEY uk_accident (acc_date, acc_hour, acc_point_nm)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='Traffic accident records';

-- Verify table creation
SHOW CREATE TABLE accidents;

SELECT 'Schema initialization completed successfully!' as status;
