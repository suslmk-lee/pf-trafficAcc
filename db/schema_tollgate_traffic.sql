-- PlugFest 2025 Traffic Dashboard
-- 요금소별 교통량 데이터 스키마

-- 요금소별 교통량 히스토리 테이블 (15분 단위)
CREATE TABLE IF NOT EXISTS tollgate_traffic_history (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,

    -- 도로 구분
    ex_div_code VARCHAR(10) NOT NULL COMMENT '도공/민자 구분코드 (도공:00, 이외:민자)',
    ex_div_name VARCHAR(50) NOT NULL COMMENT '도공/민자 구분명',

    -- 요금소(영업소) 정보
    unit_code VARCHAR(10) NOT NULL COMMENT '영업소 코드',
    unit_name VARCHAR(100) NOT NULL COMMENT '영업소명',

    -- 진출입 구분
    inout_type VARCHAR(10) NOT NULL COMMENT '입출구 구분코드 (0:입구, 1:출구)',
    inout_name VARCHAR(20) NOT NULL COMMENT '입출구 구분명',

    -- 시간 구분
    tm_type VARCHAR(10) NOT NULL COMMENT '자료구분 (1:1시간, 2:15분)',
    tm_name VARCHAR(20) NOT NULL COMMENT '자료구분명',

    -- 결제수단 구분
    tcs_type VARCHAR(10) NOT NULL COMMENT 'TCS/hi-pass 구분 (1:TCS, 2:hi-pass)',
    tcs_name VARCHAR(30) NOT NULL COMMENT 'TCS/hi-pass 구분명',

    -- 차종 구분
    car_type VARCHAR(10) NOT NULL COMMENT '차종구분코드 (1:1종,2:2종,3:3종,4:4종,5:5종,6:6종,7:7종,8:8종)',

    -- 교통량 (핵심 데이터)
    traffic_amount INT NOT NULL COMMENT '교통량 (단위: 만대)',

    -- 집계 시간 (API 원본 형식)
    sum_date VARCHAR(8) NOT NULL COMMENT '집계 날짜 (YYYYMMDD)',
    sum_tm VARCHAR(4) NOT NULL COMMENT '집계 시간 (HHMM)',

    -- 집계 시간 (파싱된 형식 - 쿼리 최적화용)
    collected_at DATETIME NOT NULL COMMENT '집계 시각 (파싱됨: sum_date + sum_tm)',

    -- 수집 메타 정보
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT '데이터 수집 시각',

    -- 중복 방지: 같은 요금소, 시간, 차종, 진출입, 결제수단 조합은 유니크
    UNIQUE KEY uk_traffic_data (
        unit_code, sum_date, sum_tm,
        car_type, inout_type, tcs_type, ex_div_code
    ),

    -- 조회 성능을 위한 인덱스
    INDEX idx_unit_collected (unit_code, collected_at),
    INDEX idx_collected_at (collected_at),
    INDEX idx_sum_date (sum_date),
    INDEX idx_unit_code (unit_code)

) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='요금소별 교통량 히스토리 (15분 단위 수집)';


-- 요금소별 일별 교통량 집계 테이블
CREATE TABLE IF NOT EXISTS tollgate_traffic_daily_stats (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,

    -- 요금소 정보
    unit_code VARCHAR(10) NOT NULL COMMENT '영업소 코드',
    unit_name VARCHAR(100) NOT NULL COMMENT '영업소명',

    -- 집계 날짜
    stat_date DATE NOT NULL COMMENT '집계 날짜',

    -- 일별 통계 (전체 차종, 전체 진출입, 전체 결제수단 합계)
    total_traffic BIGINT NOT NULL DEFAULT 0 COMMENT '일 총 교통량 (만대)',
    avg_traffic DECIMAL(10,2) DEFAULT 0 COMMENT '평균 교통량 (만대)',
    max_traffic INT DEFAULT 0 COMMENT '최대 교통량 (만대)',
    min_traffic INT DEFAULT 0 COMMENT '최소 교통량 (만대)',
    data_count INT NOT NULL DEFAULT 0 COMMENT '수집된 데이터 수',

    -- 메타 정보
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT '생성 시각',
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '갱신 시각',

    -- 유니크 제약
    UNIQUE KEY uk_unit_date (unit_code, stat_date),

    -- 인덱스
    INDEX idx_stat_date (stat_date),
    INDEX idx_unit_code (unit_code)

) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='요금소별 일별 교통량 통계';


-- 요금소 마스터 테이블 (선택적)
CREATE TABLE IF NOT EXISTS tollgate_master (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,

    unit_code VARCHAR(10) NOT NULL COMMENT '영업소 코드',
    unit_name VARCHAR(100) NOT NULL COMMENT '영업소명',
    ex_div_code VARCHAR(10) NOT NULL COMMENT '도공/민자 구분코드',
    ex_div_name VARCHAR(50) NOT NULL COMMENT '도공/민자 구분명',

    -- 메타 정보
    is_active BOOLEAN DEFAULT TRUE COMMENT '활성 여부',
    first_collected_at DATETIME COMMENT '최초 수집 시각',
    last_collected_at DATETIME COMMENT '최근 수집 시각',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    -- 유니크 제약
    UNIQUE KEY uk_unit_code (unit_code),

    -- 인덱스
    INDEX idx_unit_name (unit_name),
    INDEX idx_is_active (is_active)

) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='요금소(영업소) 마스터';
