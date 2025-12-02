# 실시간 고속도로 교통정보 대시보드
## PlugFest 2025 - High Availability Demo

고가용성(HA) 실시간 데이터 파이프라인 시연용 프로젝트입니다. Karmada 멀티클러스터 오케스트레이션, Istio 서비스 메시, Redis Stream 기반 이벤트 처리, MariaDB를 활용한 완전한 이중화 아키텍처를 구현합니다.

## 🎯 핵심 시연 시나리오

### 아키텍처 개요

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Karmada Control Plane                        │
│                  (Multi-Cluster Orchestration)                       │
└─────────────────────────────────────────────────────────────────────┘
                              │
                ┌─────────────┴─────────────┐
                │                           │
        ┌───────▼────────┐          ┌──────▼─────────┐
        │ Member1 Cluster│          │ Member2 Cluster│
        │  (Naver Cloud) │          │  (NHN Cloud)   │
        └────────────────┘          └────────────────┘
                │                           │
                └──────────┬────────────────┘
                           │
                ┌──────────▼──────────┐
                │  Central Cluster    │
                │  - MariaDB          │
                │  - Redis Stream     │
                │  - Simulator        │
                └─────────────────────┘
```

### 시연 흐름

1. **정상 상태** (Mode: real)
   - `data-collector` (Member1)가 10초마다 실제 OpenAPI를 호출
   - `openapi-proxy-api`를 통해 3개 API 호출: 사고정보, 요금소 교통량, 도로 소통정보
   - Redis Stream (`traffic-stream`)에 데이터 XADD
   - `data-processor` (Member1/Member2)가 Consumer Group으로 데이터 수신
   - 중복 체크 후 MariaDB에 INSERT
   - Frontend에서 10초마다 갱신되는 지도와 사고 목록 표시

2. **OpenAPI 장애 시** (Mode: sim으로 전환)
   - `DATA_SOURCE_MODE`를 `sim`으로 변경
   - 내부 `traffic-simulator`로 자동 전환
   - 시연 중단 없이 가상 데이터로 계속 갱신

3. **클러스터 장애 발생**
   - Member1 클러스터 강제 중단

4. **자동 복구**
   - **Istio Failover**: Frontend API 요청이 즉시 Member2로 전환
   - **Karmada Failover**: data-collector Pod를 Member2에 재배포
   - **Redis Failover**: data-processor(Member2)가 즉시 Stream 처리 계속
   - **결과**: 관객은 데이터 수집과 조회 모두 중단되지 않음을 목격

## 📦 구성요소

### 마이크로서비스 (7개)

1. **traffic-simulator** (Go)
   - 가짜 OpenAPI 서버
   - `/api/traffic` 엔드포인트 제공
   - 샘플 사고 데이터 생성

2. **openapi-proxy-api** (Go) - **Active-Active**
   - 외부 OpenAPI 호출을 캐싱하여 중복 호출 방지
   - 3개 테이블에 원본 데이터 저장: cache_accidents, cache_tollgate, cache_road_status

3. **data-collector** (Go) - **Singleton (Active-Standby)**
   - 15분/5분 간격으로 openapi-proxy-api에서 데이터 수집
   - 환경변수로 실제 OpenAPI 또는 Simulator 선택
   - Redis Stream에 데이터 전송

4. **data-processor** (Go) - **Active-Active**
   - Redis Stream Consumer Group 구독
   - 중복 체크 후 MariaDB에 저장 (traffic_accidents, tollgate_traffic_history, road_traffic_status, road_route_summary)
   - 양쪽 클러스터에서 동시 실행

5. **data-api-service** (Go) - **Active-Active**
   - REST API로 교통 데이터 제공
   - `/api/accidents/latest`, `/api/accidents/stats`
   - `/api/tollgate/traffic` - 요금소별 교통량 (15분 단위)
   - `/api/road/status` - VDS별 실시간 소통정보 (5분 단위)
   - `/api/road/summary` - 노선별 소통 요약 (5분 단위)

6. **api-gateway** (Go) - **Active-Active**
   - Frontend 요청을 data-api-service로 라우팅

7. **frontend** (React + Tailwind CSS) - **Active-Active**
   - 실시간 대한민국 지도 (Leaflet)
   - 사고 마커 및 목록
   - 4개 탭: 대시보드, 교통사고, 요금소 교통량, 실시간 도로 소통
   - K-PaaS 로고 포함

### 인프라 구성요소

- **MariaDB** (중앙 클러스터): 사고 데이터 저장소
- **Redis** (중앙 클러스터): Stream 기반 이벤트 큐
- **Karmada**: 멀티클러스터 오케스트레이션 (member1, member2)
- **Istio**: 서비스 메시, 트래픽 관리, mTLS, IngressGateway

## 🚀 배포 가이드

### 사전 요구사항

- Kubernetes 클러스터 3개 (Central, Member1, Member2)
- Karmada Control Plane 설치
- Istio 설치 (각 멤버 클러스터)
- Docker 이미지 레지스트리 (registry.k-paas.org)

### 1. 자동 배포 (권장)

deploy.sh 스크립트를 사용한 자동 배포:

```bash
# 전체 배포
./deploy.sh all

# 또는 단계별 배포
./deploy.sh prereq    # 사전 요구사항 확인
./deploy.sh build     # Docker 이미지 빌드
./deploy.sh central   # 중앙 클러스터 배포
./deploy.sh karmada   # Karmada를 통한 서비스 배포
./deploy.sh istio     # Istio 설정 배포
./deploy.sh verify    # 배포 확인
```

### 2. 수동 배포

#### 2-1. Docker 이미지 빌드

```bash
# Build all services with platform specification
REGISTRY="registry.k-paas.org/plugfest"
SERVICES=("traffic-simulator" "openapi-proxy-api" "data-collector" "data-processor" "data-api-service" "api-gateway" "frontend")

for service in "${SERVICES[@]}"; do
  docker build --platform linux/amd64 -t ${REGISTRY}/${service}:v1.0.0 ${service}/
  docker push ${REGISTRY}/${service}:v1.0.0
done
```

#### 2-2. 중앙 클러스터 배포

```bash
# Switch to central cluster
kubectl config use-context central-ctx

# Deploy MariaDB
kubectl apply -f k8s/central/mariadb-central.yaml

# Deploy Redis
kubectl apply -f k8s/central/redis-central.yaml

# Wait for MariaDB to be ready
kubectl wait --for=condition=ready pod -l app=mariadb-central --timeout=120s

# Initialize database schema
kubectl apply -f k8s/central/mariadb-schema-init.yaml

# Deploy traffic simulator
kubectl apply -f k8s/central/traffic-simulator.yaml
```

#### 2-3. Karmada 클러스터 확인

```bash
# Switch to Karmada context
kubectl config use-context karmada-api-ctx

# Check registered clusters (should show member1 and member2)
kubectl get clusters
```

#### 2-4. Istio ServiceEntry 설정

각 멤버 클러스터에서 중앙 서비스에 접근하기 위해 ServiceEntry를 업데이트합니다.

```bash
# Get central cluster IPs
MARIADB_IP=$(kubectl --context central-ctx get svc mariadb-central -o jsonpath='{.spec.clusterIP}')
REDIS_IP=$(kubectl --context central-ctx get svc redis-central -o jsonpath='{.spec.clusterIP}')
SIMULATOR_IP=$(kubectl --context central-ctx get svc traffic-simulator -o jsonpath='{.spec.clusterIP}')

# Update ServiceEntry manifests
sed -i "s/MARIADB_CENTRAL_IP/$MARIADB_IP/g" k8s/istio/service-entry.yaml
sed -i "s/REDIS_CENTRAL_IP/$REDIS_IP/g" k8s/istio/service-entry.yaml
sed -i "s/TRAFFIC_SIMULATOR_IP/$SIMULATOR_IP/g" k8s/istio/service-entry.yaml
```

#### 2-5. Karmada를 통한 서비스 배포

```bash
# Switch to Karmada context
kubectl config use-context karmada-api-ctx

# Create namespace in member clusters
kubectl apply -f k8s/karmada/namespace.yaml

# Deploy config and secrets
kubectl apply -f k8s/karmada/config-and-secrets.yaml
kubectl apply -f k8s/karmada/config-propagation.yaml

# Deploy services
kubectl apply -f k8s/karmada/openapi-proxy-api.yaml
kubectl apply -f k8s/karmada/data-collector.yaml
kubectl apply -f k8s/karmada/data-processor.yaml
kubectl apply -f k8s/karmada/data-api-service.yaml
kubectl apply -f k8s/karmada/api-gateway.yaml
kubectl apply -f k8s/karmada/frontend.yaml

# Apply propagation policies
kubectl apply -f k8s/karmada/propagation-policy.yaml
kubectl apply -f k8s/karmada/openapi-proxy-propagation.yaml
```

#### 2-6. Istio 설정 적용

```bash
# Apply Istio configurations to each member cluster
for cluster in karmada-member1-ctx karmada-member2-ctx; do
  kubectl --context ${cluster} apply -f k8s/istio/gateway.yaml -n tf-monitor
  kubectl --context ${cluster} apply -f k8s/istio/virtual-service.yaml -n tf-monitor
  kubectl --context ${cluster} apply -f k8s/istio/destination-rule.yaml -n tf-monitor
  kubectl --context ${cluster} apply -f k8s/istio/service-entry.yaml -n tf-monitor
done
```

#### 2-7. OpenAPI Key 설정 (Optional - Real Mode)

실제 OpenAPI를 사용하려면:

```bash
kubectl --context karmada-api-ctx create secret generic traffic-secret \
  --from-literal=REAL_OPENAPI_KEY=YOUR_ACTUAL_API_KEY \
  --from-literal=TOLLGATE_API_KEY=YOUR_TOLLGATE_KEY \
  --from-literal=ROAD_STATUS_API_KEY=YOUR_ROAD_STATUS_KEY \
  -n tf-monitor
```

## 🌐 접속 정보

### IngressGateway URL

배포 완료 후 다음 URL로 접속 가능합니다:

```bash
# Member1 (Naver Cloud)
kubectl --context karmada-member1-ctx get svc istio-ingressgateway -n istio-system

# Member2 (NHN Cloud)
kubectl --context karmada-member2-ctx get svc istio-ingressgateway -n istio-system
```

브라우저에서 IngressGateway의 EXTERNAL-IP로 접속하면 대시보드가 표시됩니다.

## 🎬 시연 시나리오 실행

### 시나리오 1: 정상 운영 확인

```bash
# Check all pods are running
kubectl --context karmada-api-ctx get resourcebinding -n tf-monitor

# Check pods in member clusters
kubectl --context karmada-member1-ctx get pods -n tf-monitor
kubectl --context karmada-member2-ctx get pods -n tf-monitor

# Check data collection logs
kubectl --context karmada-member1-ctx logs -l app=data-collector -n tf-monitor -f

# Check data processing logs
kubectl --context karmada-member2-ctx logs -l app=data-processor -n tf-monitor -f

# Access dashboard via IngressGateway
# Open browser: http://<INGRESS_EXTERNAL_IP>
```

### 시나리오 2: Simulator Mode 전환

```bash
# Update data-collector to use simulator
kubectl --context karmada-api-ctx -n tf-monitor set env deployment/data-collector DATA_SOURCE_MODE=sim

# Watch pod restart
kubectl --context karmada-member1-ctx get pods -n tf-monitor -w

# Verify new data is coming from simulator
kubectl --context karmada-member1-ctx logs -l app=data-collector -n tf-monitor -f
```

### 시나리오 3: 클러스터 Failover 테스트

```bash
# Terminal 1: Monitor Karmada resources
watch kubectl --context karmada-api-ctx get resourcebinding -n tf-monitor

# Terminal 2: Monitor Member1 cluster
watch kubectl --context karmada-member1-ctx get pods -n tf-monitor

# Terminal 3: Monitor Member2 cluster
watch kubectl --context karmada-member2-ctx get pods -n tf-monitor

# Simulate Member1 cluster failure
kubectl --context karmada-member1-ctx drain --all --ignore-daemonsets --force

# Observe:
# 1. Karmada detects Member1 cluster down
# 2. data-collector migrates to Member2 cluster (via failover policy)
# 3. Frontend continues serving from Member2
# 4. Data pipeline continues without interruption
```

### 시나리오 4: 복구

```bash
# Restore Member1 cluster
kubectl --context karmada-member1-ctx uncordon --all

# Karmada will automatically rebalance workloads
```

## 📊 모니터링

### 배포 상태 확인

```bash
# Karmada cluster status
kubectl --context karmada-api-ctx get clusters

# Karmada resource distribution
kubectl --context karmada-api-ctx get resourcebinding -n tf-monitor
kubectl --context karmada-api-ctx get work -n karmada-es-member1
kubectl --context karmada-api-ctx get work -n karmada-es-member2

# Service status per cluster
kubectl --context karmada-member1-ctx get pods,svc -n tf-monitor
kubectl --context karmada-member2-ctx get pods,svc -n tf-monitor
kubectl --context central-ctx get pods,svc
```

### 데이터 파이프라인 확인

```bash
# Redis Stream monitoring
kubectl --context central-ctx exec -it deploy/redis-central -- redis-cli
> XINFO STREAM traffic-stream
> XINFO GROUPS traffic-stream

# MariaDB data check
kubectl --context central-ctx exec -it deploy/mariadb-central -- mysql -u trafficuser -ptrafficpass trafficdb
> SELECT COUNT(*) FROM traffic_accidents;
> SELECT COUNT(*) FROM tollgate_traffic_history;
> SELECT COUNT(*) FROM road_traffic_status;
> SELECT COUNT(*) FROM road_route_summary;
> SELECT * FROM traffic_accidents ORDER BY created_at DESC LIMIT 10;
```

### Istio 메트릭

```bash
# Service mesh metrics
istioctl --context karmada-member1-ctx dashboard kiali
istioctl --context karmada-member2-ctx dashboard kiali

# Gateway status
kubectl --context karmada-member1-ctx get gateway -n tf-monitor
kubectl --context karmada-member1-ctx get virtualservice -n tf-monitor
```

## 🔧 환경 변수

### data-collector
- `DATA_SOURCE_MODE`: `real` 또는 `sim`
- `REDIS_ADDR`: Redis 주소
- `SIMULATOR_API_URL`: Simulator URL
- `REAL_OPENAPI_URL`: 실제 OpenAPI URL (사고정보)
- `REAL_OPENAPI_KEY`: OpenAPI 키
- `TOLLGATE_API_URL`: 요금소 API URL
- `TOLLGATE_API_KEY`: 요금소 API 키
- `ROAD_STATUS_API_URL`: 도로 소통정보 API URL
- `ROAD_STATUS_API_KEY`: 도로 소통정보 API 키
- `COLLECT_INTERVAL`: 사고정보 수집 간격 (기본: 10s)
- `TOLLGATE_COLLECT_INTERVAL`: 요금소 수집 간격 (기본: 15m)
- `ROAD_STATUS_COLLECT_INTERVAL`: 도로 소통정보 수집 간격 (기본: 5m)

### data-processor
- `DB_HOST`: MariaDB 호스트
- `DB_USER`: DB 사용자
- `DB_PASSWORD`: DB 비밀번호
- `DB_NAME`: DB 이름
- `REDIS_ADDR`: Redis 주소

### data-api-service
- `DB_HOST`: MariaDB 호스트
- `DB_USER`: DB 사용자
- `DB_PASSWORD`: DB 비밀번호
- `DB_NAME`: DB 이름
- `PORT`: 서비스 포트

### api-gateway
- `DATA_API_SERVICE_URL`: data-api-service URL
- `PORT`: 서비스 포트

### frontend
- `REACT_APP_API_GATEWAY_URL`: API Gateway URL

## 🏗️ 아키텍처 특징

### Active-Active 이중화
- frontend, api-gateway, data-api-service, data-processor, openapi-proxy-api는 양쪽 클러스터(member1, member2)에서 동시 실행
- Istio VirtualService를 통한 자동 로드 밸런싱 및 페일오버
- IngressGateway를 통한 외부 접근 제공

### Active-Standby 단일화
- data-collector는 Karmada PropagationPolicy를 통해 member1에만 배포
- 클러스터 장애 시 failover policy에 의해 자동으로 member2로 이동 (tolerationSeconds: 30)

### 3-API 프록시 아키텍처
- openapi-proxy-api가 외부 API 호출을 중앙화하여 관리
- 캐시 테이블에 원본 데이터 저장으로 중복 호출 방지
- data-collector는 프록시 API만 호출

### Redis Stream Consumer Group
- data-processor 여러 인스턴스가 동일 Consumer Group (`traffic-processor-group`)에 참여
- 메시지 분산 처리 및 중복 방지
- 한 인스턴스 장애 시 다른 인스턴스가 자동 처리

### 중복 방지 메커니즘
- MariaDB에서 각 테이블마다 UNIQUE KEY 설정
  - traffic_accidents: `(acc_date, acc_hour, acc_point_nm)`
  - tollgate_traffic_history: `(unit_code, collected_at)`
  - road_traffic_status: `(vds_id, collected_at)`
  - road_route_summary: `(route_no, collected_at)`
- data-processor가 INSERT 시 중복 자동 스킵
- Active-Active 환경에서도 데이터 일관성 보장

### Istio 서비스 메시
- Gateway: 외부 트래픽 진입점
- VirtualService: 라우팅 규칙 (/, /api/*)
- DestinationRule: 버전 기반 트래픽 분산 (v1 subset)
- ServiceEntry: 외부 서비스 접근 (MariaDB, Redis, Simulator)

## 📝 데이터 구조

### 수집 데이터 종류
1. **교통사고 정보** (10초 간격): 실시간 사고/고장/정체 정보
2. **요금소 교통량** (15분 간격): 467개 요금소별 통행량
3. **도로 소통정보** (5분 단위): VDS 기반 실시간 속도/교통량
4. **노선별 소통 요약** (5분 단위): 67개 노선의 원활/서행/정체 구간 통계

## 🔍 트러블슈팅

### Pod가 시작되지 않는 경우
```bash
# ConfigMap/Secret 확인
kubectl --context karmada-member1-ctx get cm,secret -n tf-monitor

# Pod 이벤트 확인
kubectl --context karmada-member1-ctx describe pod <pod-name> -n tf-monitor
```

### IngressGateway 접속 안 되는 경우
```bash
# Gateway 확인
kubectl --context karmada-member1-ctx get gateway -n tf-monitor

# VirtualService 확인
kubectl --context karmada-member1-ctx get virtualservice -n tf-monitor

# Istio 설정 재적용
kubectl --context karmada-member1-ctx apply -f k8s/istio/ -n tf-monitor
```

### Karmada 전파 안 되는 경우
```bash
# PropagationPolicy 확인
kubectl --context karmada-api-ctx get propagationpolicy -n tf-monitor

# ResourceBinding 확인
kubectl --context karmada-api-ctx get resourcebinding -n tf-monitor

# Work 객체 확인
kubectl --context karmada-api-ctx get work -n karmada-es-member1
kubectl --context karmada-api-ctx get work -n karmada-es-member2
```

## 📝 라이센스

PlugFest 2025 Demo Project

## 👥 기여

프로젝트에 대한 질문이나 제안사항은 이슈로 등록해주세요.
