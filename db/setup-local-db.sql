-- Local Development Database Setup
-- Run this script with: mysql -u root -p < db/setup-local-db.sql

-- Create database
CREATE DATABASE IF NOT EXISTS trafficdb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Create user for localhost
CREATE USER IF NOT EXISTS 'trafficuser'@'localhost' IDENTIFIED BY 'trafficpass';

-- Create user for remote access (optional)
CREATE USER IF NOT EXISTS 'trafficuser'@'%' IDENTIFIED BY 'trafficpass';

-- Grant all privileges on trafficdb
GRANT ALL PRIVILEGES ON trafficdb.* TO 'trafficuser'@'localhost';
GRANT ALL PRIVILEGES ON trafficdb.* TO 'trafficuser'@'%';

-- Flush privileges to apply changes
FLUSH PRIVILEGES;

-- Verify user creation
SELECT user, host FROM mysql.user WHERE user='trafficuser';

-- Show databases
SHOW DATABASES LIKE 'trafficdb';
