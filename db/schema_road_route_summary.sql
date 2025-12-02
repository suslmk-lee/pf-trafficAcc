-- 노선별 소통 정보 요약 테이블
CREATE TABLE IF NOT EXISTS road_route_summary (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    route_no VARCHAR(10) NOT NULL COMMENT '노선 번호',
    route_name VARCHAR(50) NOT NULL COMMENT '노선명',
    total_sections INT NOT NULL COMMENT '총 구간 수',
    smooth_sections INT NOT NULL DEFAULT 0 COMMENT '원활 구간 수 (grade=1)',
    slow_sections INT NOT NULL DEFAULT 0 COMMENT '서행 구간 수 (grade=2)',
    congested_sections INT NOT NULL DEFAULT 0 COMMENT '정체 구간 수 (grade=3)',
    avg_speed DECIMAL(5,1) NOT NULL COMMENT '평균 속도 (km/h)',
    avg_traffic_amount DECIMAL(8,1) NOT NULL COMMENT '평균 교통량 (대/시간)',
    collected_at DATETIME NOT NULL COMMENT '수집 시각',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_route_summary (route_no, collected_at),
    INDEX idx_route (route_no, route_name),
    INDEX idx_collected_at (collected_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='노선별 소통 정보 5분 단위 집계';
