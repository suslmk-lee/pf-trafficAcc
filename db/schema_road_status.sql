-- 고속도로 실시간 소통정보 테이블
CREATE TABLE IF NOT EXISTS road_traffic_status (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    route_no VARCHAR(10) NOT NULL COMMENT '노선번호',
    route_name VARCHAR(50) NOT NULL COMMENT '도로명',
    conzone_id VARCHAR(20) NOT NULL COMMENT '콘존ID',
    conzone_name VARCHAR(100) NOT NULL COMMENT '콘존명',
    vds_id VARCHAR(20) NOT NULL COMMENT 'VDS_ID',
    updown_type_code CHAR(1) NOT NULL COMMENT '방향(S:기점/E:종점)',
    traffic_amount INT NOT NULL COMMENT '교통량(대)',
    speed INT NOT NULL COMMENT '속도(km/h)',
    share_ratio INT NOT NULL COMMENT '점유율',
    time_avg INT NOT NULL COMMENT '통행시간',
    grade TINYINT NOT NULL COMMENT '소통등급(0:판정불가,1:원활,2:서행,3:정체)',
    std_date VARCHAR(8) NOT NULL COMMENT '수집일자(YYYYMMDD)',
    std_hour VARCHAR(4) NOT NULL COMMENT '수집시각(HHMM)',
    collected_at DATETIME NOT NULL COMMENT '수집 시각',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_traffic_status (vds_id, std_date, std_hour),
    INDEX idx_route (route_no, route_name),
    INDEX idx_collected_at (collected_at),
    INDEX idx_grade (grade)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='고속도로 실시간 소통정보';

-- 최근 데이터만 유지 (1시간 이상 된 데이터 삭제 위한 이벤트)
-- 필요시 활성화
-- CREATE EVENT IF NOT EXISTS cleanup_road_traffic_status
-- ON SCHEDULE EVERY 1 HOUR
-- DO DELETE FROM road_traffic_status WHERE collected_at < DATE_SUB(NOW(), INTERVAL 1 HOUR);
