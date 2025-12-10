# Deployment Guide

시연을 위한 전체 시스템 배포 가이드입니다.

## 사전 요구사항

### 필수 도구
- kubectl (v1.28+)
- 클러스터 접근 권한

### 필수 클러스터 컨텍스트
다음 4개의 클러스터 컨텍스트가 설정되어 있어야 합니다:
- `karmada-api-ctx` - Karmada 컨트롤 플레인
- `karmada-member1-ctx` - Member1 클러스터 (cp-plugfest-member1)
- `karmada-member2-ctx` - Member2 클러스터 (cp-plugfest-member2)
- `central-ctx` - Central 클러스터 (MariaDB, Redis)

컨텍스트 확인:
```bash
kubectl config get-contexts
```

## 빠른 시작

### 1. 전체 배포

```bash
./deploy.sh
```

배포 스크립트는 다음 작업을 자동으로 수행합니다:
1. Central 클러스터에 MariaDB, Redis 배포
2. DB 스키마 초기화 (history, cache, tollgate 테이블)
3. Karmada에 namespace, configmap, secret 생성
4. Member2 클러스터에 taint 적용 (Active-Standby)
5. 모든 서비스를 Karmada에 배포
6. PropagationPolicy 적용
7. Istio Gateway, VirtualService, DestinationRule 배포
8. 배포 상태 확인

**예상 소요 시간**: 약 5-10분

### 2. 전체 삭제

```bash
./undeploy.sh
```

삭제 스크립트는 배포된 모든 리소스를 제거합니다.

**주의**: PVC는 자동으로 삭제되지 않습니다. 완전히 삭제하려면:
```bash
kubectl --context=central-ctx delete pvc mariadb-pvc redis-pvc -n default
```

## 배포 확인

### Central 클러스터 확인

```bash
# MariaDB, Redis 상태 확인
kubectl --context=central-ctx get pods -n default

# DB 테이블 확인
kubectl --context=central-ctx exec -it <mariadb-pod> -n default -- mysql -uroot -prootpass123 -e "USE trafficdb; SHOW TABLES;"
```

### Karmada 배포 확인

```bash
# ResourceBinding 확인 (어느 클러스터에 배포되었는지)
kubectl --context=karmada-api-ctx get resourcebinding -n tf-monitor

# PropagationPolicy 확인
kubectl --context=karmada-api-ctx get pp -n tf-monitor
```

### Member1 클러스터 확인 (Active)

```bash
# 모든 pods 확인
kubectl --context=karmada-member1-ctx get pods -n tf-monitor

# 예상 결과: 11개 pods (모두 Running)
# - frontend: 2
# - api-gateway: 2
# - data-api-service: 2
# - data-processor: 2
# - data-collector: 1
# - openapi-proxy-api: 2
```

### Member2 클러스터 확인 (Standby)

```bash
# pods 확인 (비어있어야 함)
kubectl --context=karmada-member2-ctx get pods -n tf-monitor
```

### Frontend 접속

```bash
# Ingress Gateway External IP 확인
kubectl --context=karmada-member1-ctx get svc istio-ingressgateway -n istio-system

# 브라우저에서 접속
# http://<EXTERNAL-IP>/
```

## 배포 구조

```
┌─────────────────────────────────────────┐
│         Central Cluster                 │
│  - MariaDB (210.109.14.158:30306)      │
│  - Redis (210.109.14.158:30379)        │
└─────────────────────────────────────────┘
                  ↑
                  │ (DB/Redis 접근)
                  │
┌─────────────────┴────────────────────────┐
│         Karmada Control Plane            │
│  - PropagationPolicy (Active-Standby)    │
│  - spreadConstraints (maxGroups: 1)      │
└────────┬─────────────────────────┬────────┘
         │                         │
┌────────▼────────┐      ┌────────▼────────┐
│  Member1 (Active)│      │Member2 (Standby)│
│  - All services  │      │  - Empty         │
│  - 11 pods       │      │  - Tainted       │
└──────────────────┘      └──────────────────┘
```

## Active-Standby 동작

### 정상 상태
- **Member1**: 모든 워크로드 실행 (Active)
- **Member2**: 워크로드 없음 (Standby)
  - Taint: `role=standby:NoSchedule`
  - Weight: Member1=10000, Member2=1
  - spreadConstraints: maxGroups=1 (단일 클러스터에만 배포)

### Failover 시나리오
Member1 장애 발생 시:
1. Karmada가 Member1 클러스터 비정상 감지 (30초 이내)
2. 자동으로 Member2로 워크로드 재배포
3. Member2에서 모든 서비스 시작
4. Istio Ingress Gateway로 트래픽 자동 전환

## 수동 작업

### DB 데이터 확인

```bash
# Cache 테이블 데이터 (openapi-collector가 수집)
kubectl --context=central-ctx exec -it <mariadb-pod> -n default -- \
  mysql -uroot -prootpass123 -e "USE trafficdb; SELECT COUNT(*) FROM traffic_accidents_cache;"

# History 테이블 데이터 (data-processor가 수집)
kubectl --context=central-ctx exec -it <mariadb-pod> -n default -- \
  mysql -uroot -prootpass123 -e "USE trafficdb; SELECT COUNT(*) FROM traffic_accidents;"
```

### Failover 테스트

```bash
# Member1 클러스터 다운 시뮬레이션
kubectl --context=karmada-api-ctx patch cluster cp-plugfest-member1 \
  --type=merge -p '{"spec":{"taints":[{"key":"test","value":"down","effect":"NoSchedule"}]}}'

# 30초 후 Member2로 워크로드 이동 확인
kubectl --context=karmada-member2-ctx get pods -n tf-monitor

# 복구
kubectl --context=karmada-api-ctx patch cluster cp-plugfest-member1 \
  --type=json -p='[{"op": "remove", "path": "/spec/taints"}]'
```

### 수동 Failback

```bash
# Member1 복구 후 수동 failback
./k8s/karmada/rebalance-services.sh
```

## 트러블슈팅

### Pod이 Pending 상태

```bash
# 원인 확인
kubectl --context=karmada-member1-ctx describe pod <pod-name> -n tf-monitor

# PVC 상태 확인
kubectl --context=central-ctx get pvc -n default
```

### DB 연결 실패

```bash
# 방화벽 확인: Member 클러스터에서 Central 클러스터로 접근 가능한지
kubectl --context=karmada-member1-ctx run test --image=busybox --rm -it --restart=Never -- \
  nc -zv 210.109.14.158 30306

# DB 로그 확인
kubectl --context=central-ctx logs <mariadb-pod> -n default
```

### Frontend에 데이터가 안 보임

```bash
# 1. openapi-proxy-api DB 연결 확인
kubectl --context=karmada-member1-ctx logs -l app=openapi-proxy-api -c openapi-proxy-api -n tf-monitor

# 2. cache 테이블 데이터 확인
kubectl --context=central-ctx exec <mariadb-pod> -n default -- \
  mysql -uroot -prootpass123 -e "USE trafficdb; SELECT COUNT(*) FROM traffic_accidents_cache;"

# 3. data-collector 로그 확인
kubectl --context=karmada-member1-ctx logs -l app=data-collector -n tf-monitor
```

## 로그 수집

```bash
# 모든 서비스 로그 수집
for svc in frontend api-gateway data-api-service data-processor data-collector openapi-proxy-api; do
  echo "=== $svc logs ===" >> logs.txt
  kubectl --context=karmada-member1-ctx logs -l app=$svc -n tf-monitor --tail=100 >> logs.txt
done
```

## 참고 문서

- [ARCHITECTURE.md](./ARCHITECTURE.md) - 시스템 아키텍처 상세 설명
- [README.md](./README.md) - 프로젝트 개요

## Karmada 이중화 정책 (Active-Standby)

### PropagationPolicy 설정

배포 스크립트는 자동으로 Active-Standby 이중화 정책을 적용합니다.

#### 핵심 설정 (`propagation-policy.yaml`)

```yaml
placement:
  clusterAffinity:
    clusterNames:
      - cp-plugfest-member1  # Active
      - cp-plugfest-member2  # Standby
  
  # Standby 클러스터 taint 허용 (failover 시에만)
  clusterTolerations:
    - key: role
      operator: Equal
      value: standby
      effect: NoSchedule
  
  # Weight 기반 우선순위
  replicaScheduling:
    replicaSchedulingType: Divided
    replicaDivisionPreference: Weighted
    weightPreference:
      staticWeightList:
        - targetCluster:
            clusterNames: [cp-plugfest-member1]
          weight: 10000  # 압도적 우선순위
        - targetCluster:
            clusterNames: [cp-plugfest-member2]
          weight: 1
  
  # 단일 클러스터에만 배포 (자동 rebalancing 방지)
  spreadConstraints:
    - spreadByField: cluster
      maxGroups: 1  # 최대 1개 클러스터에만 배포
      minGroups: 1  # 최소 1개 클러스터 필요

# 자동 Failover 설정
failover:
  application:
    decisionConditions:
      tolerationSeconds: 30  # 30초 후 failover
    purgeMode: Gracefully
    gracePeriodSeconds: 600
```

### 동작 시나리오

#### 1. 정상 상태
```
Member1 (Active): ✅ 모든 워크로드 실행 (11 pods)
Member2 (Standby): ⏸️  대기 상태 (0 pods, taint로 차단)
```

#### 2. Member1 장애 발생 → 자동 Failover
```
시간: T+0s
└─ Member1 클러스터 장애 발생

시간: T+30s
└─ Karmada가 Member1 비정상 감지 (tolerationSeconds: 30)
   └─ 자동으로 Member2로 워크로드 재스케줄링 시작

시간: T+30s ~ T+2m
└─ Member2에서 Pod 시작 및 준비
   └─ 11개 pods 순차적으로 Running 상태

시간: T+2m
└─ Member2 (Active): ✅ 모든 워크로드 실행
   Member1 (Down): ❌ 장애 상태
```

**자동 Failover - 사용자 개입 불필요**

#### 3. Member1 복구 → 수동 Failback
```
시간: T+10m
└─ Member1 클러스터 복구됨

현재 상태:
└─ Member1 (Ready): ⏸️  대기 중 (0 pods)
   Member2 (Active): ✅ 모든 워크로드 실행 중

⚠️ spreadConstraints (maxGroups: 1)로 인해 자동 rebalancing 안됨!
```

**수동 Failback 필요:**
```bash
# Member1으로 워크로드 되돌리기
cd k8s/karmada
./rebalance-services.sh
```

### rebalance-services.sh 스크립트

Member1 복구 후 워크로드를 다시 Member1으로 옮기는 스크립트입니다.

#### 실행 방법
```bash
cd /Users/suslmk/workspace/pf-trafficAcc/k8s/karmada
./rebalance-services.sh
```

#### 동작 원리
1. **ResourceBinding 정리**: 기존 eviction tasks 제거
2. **순차적 Rebalance**: 각 서비스마다 WorkloadRebalancer 생성
   ```
   data-collector → 2초 대기
   data-processor → 2초 대기
   data-api-service → 2초 대기
   api-gateway → 2초 대기
   frontend → 2초 대기
   openapi-proxy-api
   ```
3. **Karmada 처리 대기**: 30초 대기
4. **결과 확인**: ResourceBinding 분산 현황 출력

#### 예상 출력
```bash
Starting sequential workload rebalancing...
Context: karmada-api-ctx
Namespace: tf-monitor
Delay: 2s between services
==========================================

Step 1: Cleaning up ResourceBindings...
==========================================
...

==========================================
Step 2: Sequential Workload Rebalancing
==========================================

[16:30:01] Rebalancing 1/6: data-collector
  → Waiting 2s before next service...

[16:30:03] Rebalancing 2/6: data-processor
  → Waiting 2s before next service...

...

Waiting 30s for Karmada to process...

Current ResourceBinding distribution:
data-collector-deployment: cp-plugfest-member1=1
data-processor-deployment: cp-plugfest-member1=2
data-api-service-deployment: cp-plugfest-member1=2
api-gateway-deployment: cp-plugfest-member1=2
frontend-deployment: cp-plugfest-member1=2
openapi-proxy-api-deployment: cp-plugfest-member1=2

Done!
```

### Failover/Failback 시연 시나리오

#### 시나리오 1: Member1 장애 시뮬레이션

```bash
# 1. 현재 상태 확인
kubectl --context=karmada-member1-ctx get pods -n tf-monitor
# 출력: 11개 pods Running

kubectl --context=karmada-member2-ctx get pods -n tf-monitor
# 출력: No resources found (standby)

# 2. Member1에 장애 taint 추가 (장애 시뮬레이션)
kubectl --context=karmada-api-ctx patch cluster cp-plugfest-member1 \
  --type=merge -p '{"spec":{"taints":[{"key":"node.kubernetes.io/unreachable","value":"","effect":"NoExecute"}]}}'

# 3. 30초 대기 후 Member2 확인
sleep 35
kubectl --context=karmada-member2-ctx get pods -n tf-monitor
# 출력: 11개 pods Running (자동 failover 완료!)

# 4. ResourceBinding 확인
kubectl --context=karmada-api-ctx get resourcebinding -n tf-monitor \
  -o custom-columns=NAME:.metadata.name,CLUSTERS:.spec.clusters[*].name

# 5. Member1 복구 (taint 제거)
kubectl --context=karmada-api-ctx patch cluster cp-plugfest-member1 \
  --type=json -p='[{"op": "remove", "path": "/spec/taints"}]'

# 6. 확인: 자동으로 Member1으로 안 돌아감
kubectl --context=karmada-member1-ctx get pods -n tf-monitor
# 출력: No resources found (spreadConstraints로 인해)

# 7. 수동 Failback 실행
cd k8s/karmada
./rebalance-services.sh

# 8. 확인: Member1으로 복귀 완료
kubectl --context=karmada-member1-ctx get pods -n tf-monitor
# 출력: 11개 pods Running

kubectl --context=karmada-member2-ctx get pods -n tf-monitor
# 출력: No resources found (다시 standby)
```

#### 시나리오 2: 전체 클러스터 상태 확인

```bash
# Karmada cluster 상태
kubectl --context=karmada-api-ctx get clusters

# ResourceBinding 분산 현황
kubectl --context=karmada-api-ctx get resourcebinding -n tf-monitor

# 각 클러스터 pods 수 비교
echo "=== Member1 ==="
kubectl --context=karmada-member1-ctx get pods -n tf-monitor --no-headers | wc -l

echo "=== Member2 ==="
kubectl --context=karmada-member2-ctx get pods -n tf-monitor --no-headers | wc -l
```

### 왜 수동 Failback인가?

#### spreadConstraints의 영향

```yaml
spreadConstraints:
  - spreadByField: cluster
    maxGroups: 1
    minGroups: 1
```

이 설정은:
- ✅ **장점**: Split-brain 방지 (워크로드가 양쪽 클러스터에 동시 실행 안됨)
- ✅ **장점**: 데이터 일관성 보장 (data-collector singleton)
- ❌ **단점**: 자동 rebalancing 안됨 (Member1 복구 후 수동 개입 필요)

#### Weight만으로는 부족

```yaml
weight:
  member1: 10000
  member2: 1
```

- Weight는 **초기 배포** 시 우선순위 결정
- **이미 배포된 후**에는 spreadConstraints가 우선
- Member2에서 실행 중인 워크로드는 maxGroups=1로 인해 Member1으로 자동 이동 안함

#### 해결책: WorkloadRebalancer

```yaml
apiVersion: apps.karmada.io/v1alpha1
kind: WorkloadRebalancer
metadata:
  name: service-rebalance
spec:
  workloads:
    - apiVersion: apps/v1
      kind: Deployment
      name: <service-name>
      namespace: tf-monitor
```

- WorkloadRebalancer를 생성하면 Karmada가 강제로 재스케줄링
- Weight 기반으로 다시 계산 → Member1 선택
- `rebalance-services.sh`가 모든 서비스에 대해 자동 실행

### 정책 커스터마이징

#### Active-Active로 변경하려면?

`propagation-policy.yaml` 수정:
```yaml
spreadConstraints:
  - spreadByField: cluster
    maxGroups: 2  # 양쪽 클러스터에 분산
    minGroups: 1
```

단, data-collector는 singleton이므로 별도 정책 필요.

#### 자동 Failback을 원한다면?

spreadConstraints 제거 또는 maxGroups=2로 변경하되:
- ⚠️ data-collector가 양쪽에서 동시 실행될 수 있음
- ⚠️ Redis Stream 중복 처리 가능성

**권장**: 현재 수동 Failback 방식 유지

