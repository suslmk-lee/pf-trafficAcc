-- Traffic Accidents Database Schema
-- 고속도로 공공데이터 포털 실시간 교통정보 저장

CREATE DATABASE IF NOT EXISTS trafficdb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE trafficdb;

-- Traffic accidents table
CREATE TABLE IF NOT EXISTS traffic_accidents (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,

  -- Lane information
  lane_yn1 CHAR(1) COMMENT '1차로 여부',
  lane_yn2 CHAR(1) COMMENT '2차로 여부',
  lane_yn3 CHAR(1) COMMENT '3차로 여부',
  lane_yn4 CHAR(1) COMMENT '4차로 여부',
  lane_yn5 CHAR(1) COMMENT '5차로 여부',
  lane_yn6 CHAR(1) COMMENT '6차로 여부',
  late_length VARCHAR(50) COMMENT '지체길이',

  -- Accident information
  acc_hour VARCHAR(10) NOT NULL COMMENT '사고시간',
  acc_date VARCHAR(20) NOT NULL COMMENT '사고날짜',
  acc_type_code VARCHAR(10) COMMENT '사고유형코드',
  acc_type VARCHAR(50) COMMENT '사고유형',
  start_end_type_code VARCHAR(50) COMMENT '시종점유형코드',
  sms_text TEXT NOT NULL COMMENT 'SMS문자내용',
  acc_process_code VARCHAR(10) COMMENT '사고처리코드',
  acc_point_nm VARCHAR(100) COMMENT '사고지점명',

  -- Road information
  nosun_nm VARCHAR(20) COMMENT '노선명',
  road_nm VARCHAR(50) COMMENT '도로명',
  acc_process_nm VARCHAR(20) COMMENT '사고처리명',

  -- Location information
  latitude DECIMAL(10, 6) COMMENT '위도',
  altitude DECIMAL(10, 6) COMMENT '경도',

  -- Additional information
  series_nm INT COMMENT '순번',
  shldr_road_yn CHAR(1) COMMENT '갓길도로여부',

  -- Timestamps
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT '생성일시',
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '수정일시',

  -- Unique constraint to prevent duplicates
  UNIQUE KEY uk_accident (acc_date, acc_hour, nosun_nm, road_nm, sms_text(255)),

  -- Indexes for performance
  INDEX idx_date_time (acc_date, acc_hour),
  INDEX idx_created (created_at DESC),
  INDEX idx_road (road_nm),
  INDEX idx_acc_type (acc_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='고속도로 실시간 교통사고 정보';

-- Daily accident statistics aggregation table
CREATE TABLE IF NOT EXISTS daily_accident_stats (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,

  -- Date for this statistics record
  stat_date DATE NOT NULL COMMENT '통계 날짜',

  -- Accident type
  acc_type VARCHAR(50) NOT NULL COMMENT '사고유형',

  -- Count for this type on this date
  accident_count INT NOT NULL DEFAULT 0 COMMENT '사고 건수',

  -- Timestamps
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT '생성일시',
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '수정일시',

  -- Unique constraint - one record per date per type
  UNIQUE KEY uk_daily_stats (stat_date, acc_type),

  -- Indexes
  INDEX idx_stat_date (stat_date DESC),
  INDEX idx_acc_type (acc_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='일별 사고 유형별 통계';

-- Simulator seed data table - stores real collected data for simulation
CREATE TABLE IF NOT EXISTS simulator_seed_data (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,

  -- Lane information
  lane_yn1 CHAR(1) COMMENT '1차로 여부',
  lane_yn2 CHAR(1) COMMENT '2차로 여부',
  lane_yn3 CHAR(1) COMMENT '3차로 여부',
  lane_yn4 CHAR(1) COMMENT '4차로 여부',
  lane_yn5 CHAR(1) COMMENT '5차로 여부',
  lane_yn6 CHAR(1) COMMENT '6차로 여부',
  late_length VARCHAR(50) COMMENT '지체길이',

  -- Accident information
  acc_hour VARCHAR(10) NOT NULL COMMENT '사고시간',
  acc_date VARCHAR(20) NOT NULL COMMENT '사고날짜',
  acc_type_code VARCHAR(10) COMMENT '사고유형코드',
  acc_type VARCHAR(50) COMMENT '사고유형',
  start_end_type_code VARCHAR(50) COMMENT '시종점유형코드',
  sms_text TEXT NOT NULL COMMENT 'SMS문자내용',
  acc_process_code VARCHAR(10) COMMENT '사고처리코드',
  acc_point_nm VARCHAR(100) COMMENT '사고지점명',

  -- Road information
  nosun_nm VARCHAR(20) COMMENT '노선명',
  road_nm VARCHAR(50) COMMENT '도로명',
  acc_process_nm VARCHAR(20) COMMENT '사고처리명',

  -- Location information
  latitude DECIMAL(10, 6) COMMENT '위도',
  altitude DECIMAL(10, 6) COMMENT '경도',

  -- Additional information
  series_nm INT COMMENT '순번',
  shldr_road_yn CHAR(1) COMMENT '갓길도로여부',

  -- Original collection timestamp (for reference)
  original_collected_at TIMESTAMP NULL COMMENT '원본 수집일시',

  -- Timestamps
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT '생성일시',
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '수정일시',

  -- Indexes for performance
  INDEX idx_acc_type (acc_type),
  INDEX idx_road (road_nm)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='시뮬레이터용 실제 데이터 Seed';
