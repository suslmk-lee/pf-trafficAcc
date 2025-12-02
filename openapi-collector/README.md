# OpenAPI Collector

외부 고속도로 공공데이터 API에서 데이터를 수집하여 데이터베이스 캐시 테이블에 저장하는 컬렉터입니다.

## 기능

3개의 API로부터 데이터를 병렬로 수집합니다:

1. **교통사고 정보** (`traffic_accidents_cache`)
   - 실시간 교통사고 현황
   - 기본 수집 주기: 5분

2. **요금소 교통량** (`tollgate_traffic_cache`)
   - 요금소별 차량 통행량
   - 기본 수집 주기: 15분
   - 페이지네이션 처리 (전체 데이터 수집)

3. **도로 소통현황** (`road_traffic_status_cache`)
   - 실시간 도로 소통 상태
   - 기본 수집 주기: 5분

## 로컬 실행

### 사전 요구사항

1. Go 1.21 이상
2. MySQL/MariaDB 접속 가능
3. 캐시 테이블 생성 완료

### 캐시 테이블 생성

```bash
cd ../db
mysql -h 103.218.158.244 -P 30306 -u trafficuser -ptrafficpass --skip-ssl trafficdb < add-cache-tables.sql
```

### 실행 방법

#### 방법 1: 스크립트 사용 (권장)

```bash
cd openapi-collector
./run-local.sh
```

#### 방법 2: 환경 변수 파일 사용

```bash
# .env 파일 생성
cp .env.example .env

# 필요시 .env 파일 수정
vim .env

# 실행
go run main.go
```

#### 방법 3: 직접 환경 변수 설정

```bash
export DB_HOST=103.218.158.244
export DB_PORT=30306
export DB_USER=trafficuser
export DB_PASSWORD=trafficpass
export DB_NAME=trafficdb

export ACCIDENT_API_URL=https://data.ex.co.kr/openapi/burstInfo/realTimeSms
export ACCIDENT_API_KEY=8771969304
export TOLLGATE_API_URL=https://data.ex.co.kr/openapi/trafficapi/trafficIc
export TOLLGATE_API_KEY=8771969304
export ROAD_STATUS_API_URL=https://data.ex.co.kr/openapi/odtraffic/trafficAmountByRealtime
export ROAD_STATUS_API_KEY=8771969304

go run main.go
```

## Docker 빌드 및 실행

### 빌드

```bash
docker build --platform linux/amd64 -t registry.k-paas.org/plugfest/openapi-collector:v2.0.0 .
```

### 푸시

```bash
docker push registry.k-paas.org/plugfest/openapi-collector:v2.0.0
```

### 로컬 Docker 실행

```bash
docker run -d \
  --name openapi-collector \
  -e DB_HOST=103.218.158.244 \
  -e DB_PORT=30306 \
  -e DB_USER=trafficuser \
  -e DB_PASSWORD=trafficpass \
  -e DB_NAME=trafficdb \
  -e ACCIDENT_API_KEY=8771969304 \
  -e TOLLGATE_API_KEY=8771969304 \
  -e ROAD_STATUS_API_KEY=8771969304 \
  registry.k-paas.org/plugfest/openapi-collector:v2.0.0
```

## 환경 변수

| 변수명 | 설명 | 기본값 |
|--------|------|--------|
| `DB_HOST` | 데이터베이스 호스트 | `localhost` |
| `DB_PORT` | 데이터베이스 포트 | `3306` |
| `DB_USER` | 데이터베이스 사용자 | `trafficuser` |
| `DB_PASSWORD` | 데이터베이스 비밀번호 | `trafficpass` |
| `DB_NAME` | 데이터베이스 이름 | `trafficdb` |
| `ACCIDENT_API_URL` | 교통사고 API URL | `https://data.ex.co.kr/openapi/burstInfo/realTimeSms` |
| `ACCIDENT_API_KEY` | 교통사고 API 키 | `8771969304` |
| `ACCIDENT_COLLECT_INTERVAL` | 교통사고 수집 주기 | `5m` |
| `TOLLGATE_API_URL` | 요금소 API URL | `https://data.ex.co.kr/openapi/trafficapi/trafficIc` |
| `TOLLGATE_API_KEY` | 요금소 API 키 | `8771969304` |
| `TOLLGATE_COLLECT_INTERVAL` | 요금소 수집 주기 | `15m` |
| `ROAD_STATUS_API_URL` | 도로현황 API URL | `https://data.ex.co.kr/openapi/odtraffic/trafficAmountByRealtime` |
| `ROAD_STATUS_API_KEY` | 도로현황 API 키 | `8771969304` |
| `ROAD_STATUS_COLLECT_INTERVAL` | 도로현황 수집 주기 | `5m` |

## 수집 주기 조정

수집 주기는 환경 변수로 조정할 수 있습니다:

```bash
# 교통사고: 10분, 요금소: 30분, 도로현황: 5분
export ACCIDENT_COLLECT_INTERVAL=10m
export TOLLGATE_COLLECT_INTERVAL=30m
export ROAD_STATUS_COLLECT_INTERVAL=5m

./run-local.sh
```

또는 스크립트 실행 시:

```bash
ACCIDENT_COLLECT_INTERVAL=10m TOLLGATE_COLLECT_INTERVAL=30m ./run-local.sh
```

## 로그 확인

컬렉터는 다음과 같은 로그를 출력합니다:

```
2025/11/17 15:34:39 ========================================
2025/11/17 15:34:39 OpenAPI Multi-Collector v2.0
2025/11/17 15:34:39 ========================================
2025/11/17 15:34:39 Database: 103.218.158.244:30306/trafficdb
2025/11/17 15:34:39 Accident API: https://data.ex.co.kr/openapi/burstInfo/realTimeSms (Interval: 5m0s)
2025/11/17 15:34:39 Tollgate API: https://data.ex.co.kr/openapi/trafficapi/trafficIc (Interval: 15m0s)
2025/11/17 15:34:39 RoadStatus API: https://data.ex.co.kr/openapi/odtraffic/trafficAmountByRealtime (Interval: 5m0s)
2025/11/17 15:34:39 ========================================
2025/11/17 15:34:39 Connected to database at 103.218.158.244:30306/trafficdb
2025/11/17 15:34:39 [Accident] Collector started (Interval: 5m0s)
2025/11/17 15:34:40 [Accident] Fetched 99 records
2025/11/17 15:34:41 [Accident] Saved 99/99 records to cache
2025/11/17 15:34:41 [Tollgate] Total 1869 records, 19 pages
2025/11/17 15:34:47 [RoadStatus] Saved 1297/1297 records to cache
```

## 데이터 확인

수집된 데이터는 다음 쿼리로 확인할 수 있습니다:

```sql
-- 교통사고 캐시
SELECT COUNT(*) FROM traffic_accidents_cache;
SELECT * FROM traffic_accidents_cache ORDER BY collected_at DESC LIMIT 10;

-- 요금소 캐시
SELECT COUNT(*) FROM tollgate_traffic_cache;
SELECT * FROM tollgate_traffic_cache ORDER BY collected_at DESC LIMIT 10;

-- 도로 소통현황 캐시
SELECT COUNT(*) FROM road_traffic_status_cache;
SELECT * FROM road_traffic_status_cache ORDER BY collected_at DESC LIMIT 10;
```

## 문제 해결

### 데이터베이스 연결 실패

```bash
# SSL 모드 확인
mysql -h 103.218.158.244 -P 30306 -u trafficuser -ptrafficpass --skip-ssl trafficdb -e "SELECT 1;"
```

### 캐시 테이블 없음

```bash
# 테이블 확인
mysql -h 103.218.158.244 -P 30306 -u trafficuser -ptrafficpass --skip-ssl trafficdb -e "SHOW TABLES LIKE '%cache%';"

# 테이블 생성
cd ../db
mysql -h 103.218.158.244 -P 30306 -u trafficuser -ptrafficpass --skip-ssl trafficdb < add-cache-tables.sql
```

### API 키 오류

API 키가 유효한지 확인하세요. 고속도로 공공데이터 포털에서 발급받은 키를 사용해야 합니다.

## 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                    External Environment                      │
│                                                               │
│  ┌─────────────────────┐         ┌──────────────────────┐   │
│  │ openapi-collector   │────────▶│ MariaDB              │   │
│  │ (로컬 또는 외부)      │         │ Cache Tables:        │   │
│  │                     │         │ - accidents_cache    │   │
│  │ - Accident API      │         │ - tollgate_cache     │   │
│  │ - Tollgate API      │         │ - road_status_cache  │   │
│  │ - RoadStatus API    │         │                      │   │
│  └─────────────────────┘         └──────────────────────┘   │
│           │                                   ▲              │
│           │ Collect from                      │              │
│           │ External APIs                     │ Read cache   │
│           ▼                                   │              │
│  ┌───────────────────────────────────────────┼──────┐       │
│  │ https://data.ex.co.kr/openapi/*           │      │       │
│  └───────────────────────────────────────────┼──────┘       │
└────────────────────────────────────────────────┼─────────────┘
                                                 │
┌────────────────────────────────────────────────┼─────────────┐
│              Kubernetes Cluster (tf-monitor)   │             │
│                                                 │             │
│  ┌──────────────────────┐         ┌────────────┴─────────┐  │
│  │ openapi-proxy-api    │◀────────│ data-collector       │  │
│  │ (Proxy 3 APIs)       │         │                      │  │
│  └──────────────────────┘         └──────────────────────┘  │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

## 라이센스

MIT
