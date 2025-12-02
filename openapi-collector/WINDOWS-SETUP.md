# OpenAPI Collector - Windows 설치 및 실행 가이드

## 사전 요구사항

### 1. Go 설치

1. [Go 공식 다운로드 페이지](https://golang.org/dl/)에서 Windows 인스톨러 다운로드
2. 다운로드한 `.msi` 파일 실행하여 설치
3. 설치 완료 후 명령 프롬프트나 PowerShell에서 확인:
   ```cmd
   go version
   ```

### 2. MySQL Client 설치 (선택사항)

MySQL 클라이언트는 데이터베이스 연결을 테스트하는 데 사용됩니다. 설치하지 않아도 collector는 실행되지만, 사전 테스트를 할 수 없습니다.

#### MySQL Client 설치 방법:

1. [MySQL Community Server 다운로드 페이지](https://dev.mysql.com/downloads/mysql/)에서 Windows용 설치 파일 다운로드
2. 설치 시 "Custom" 선택 후 "MySQL Command Line Client" 만 선택
3. 또는 [Chocolatey](https://chocolatey.org/) 사용:
   ```powershell
   choco install mysql-cli
   ```

### 3. Git 설치 (선택사항)

코드를 다운로드하려면 Git이 필요합니다.

1. [Git for Windows 다운로드](https://git-scm.com/download/win)
2. 설치 후 Git Bash 또는 명령 프롬프트에서 확인:
   ```cmd
   git --version
   ```

## 소스 코드 다운로드

### Git 사용:
```cmd
git clone <repository-url>
cd pf-trafficAcc\openapi-collector
```

### 또는 ZIP 파일 다운로드:
프로젝트를 ZIP으로 다운로드 후 압축 해제하여 `openapi-collector` 폴더로 이동합니다.

## 데이터베이스 설정

### 캐시 테이블 생성 (MySQL Client 필요)

**PowerShell:**
```powershell
cd ..\db
Get-Content add-cache-tables.sql | mysql -h 103.218.158.244 -P 30306 -u trafficuser -ptrafficpass --skip-ssl trafficdb
```

**명령 프롬프트:**
```cmd
cd ..\db
mysql -h 103.218.158.244 -P 30306 -u trafficuser -ptrafficpass --skip-ssl trafficdb < add-cache-tables.sql
```

## 실행 방법

### 방법 1: PowerShell 스크립트 (권장)

1. PowerShell을 **관리자 권한**으로 실행
2. 실행 정책 변경 (처음 한 번만):
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```
3. collector 폴더로 이동:
   ```powershell
   cd openapi-collector
   ```
4. 스크립트 실행:
   ```powershell
   .\run-local.ps1
   ```

### 방법 2: 배치 파일

1. 명령 프롬프트 실행
2. collector 폴더로 이동:
   ```cmd
   cd openapi-collector
   ```
3. 배치 파일 실행:
   ```cmd
   run-local.bat
   ```

### 방법 3: 직접 Go 실행

1. 환경 변수 설정:
   ```powershell
   $env:DB_HOST="103.218.158.244"
   $env:DB_PORT="30306"
   $env:DB_USER="trafficuser"
   $env:DB_PASSWORD="trafficpass"
   $env:DB_NAME="trafficdb"
   $env:ACCIDENT_API_KEY="8771969304"
   $env:TOLLGATE_API_KEY="8771969304"
   $env:ROAD_STATUS_API_KEY="8771969304"
   ```

2. Go 실행:
   ```powershell
   go run main.go
   ```

## 환경 변수 커스터마이징

수집 주기나 API 설정을 변경하려면 실행 전에 환경 변수를 설정하세요.

### PowerShell:
```powershell
# 수집 주기 변경 (교통사고: 10분, 요금소: 30분)
$env:ACCIDENT_COLLECT_INTERVAL="10m"
$env:TOLLGATE_COLLECT_INTERVAL="30m"
$env:ROAD_STATUS_COLLECT_INTERVAL="5m"

# 스크립트 실행
.\run-local.ps1
```

### 명령 프롬프트:
```cmd
set ACCIDENT_COLLECT_INTERVAL=10m
set TOLLGATE_COLLECT_INTERVAL=30m
set ROAD_STATUS_COLLECT_INTERVAL=5m

run-local.bat
```

## 실행 확인

collector가 정상적으로 실행되면 다음과 같은 로그가 출력됩니다:

```
========================================
OpenAPI Multi-Collector v2.0
========================================
Database: 103.218.158.244:30306/trafficdb
Accident API: https://data.ex.co.kr/openapi/burstInfo/realTimeSms (Interval: 5m0s)
Tollgate API: https://data.ex.co.kr/openapi/trafficapi/trafficIc (Interval: 15m0s)
RoadStatus API: https://data.ex.co.kr/openapi/odtraffic/trafficAmountByRealtime (Interval: 5m0s)
========================================
Connected to database at 103.218.158.244:30306/trafficdb
[Accident] Collector started (Interval: 5m0s)
[Accident] Fetched 99 records
[Accident] Saved 99/99 records to cache
[Tollgate] Total 1869 records, 19 pages
[RoadStatus] Saved 1297/1297 records to cache
```

## 중지 방법

collector를 중지하려면 `Ctrl + C`를 눌러주세요.

## 문제 해결

### Go 명령을 찾을 수 없음

**에러:**
```
'go'은(는) 내부 또는 외부 명령, 실행할 수 있는 프로그램, 또는 배치 파일이 아닙니다.
```

**해결:**
1. Go가 설치되어 있는지 확인
2. 환경 변수 PATH에 Go 경로가 추가되어 있는지 확인
   - 일반적으로: `C:\Program Files\Go\bin`
3. 명령 프롬프트나 PowerShell을 재시작

### PowerShell 실행 정책 오류

**에러:**
```
이 시스템에서 스크립트를 실행할 수 없으므로...
```

**해결:**
PowerShell을 관리자 권한으로 실행 후:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### MySQL 연결 실패

**에러:**
```
Failed to connect to database
```

**확인 사항:**
1. 데이터베이스 호스트가 접근 가능한지 확인
2. 방화벽에서 30306 포트가 열려 있는지 확인
3. 데이터베이스 자격 증명이 올바른지 확인

### 캐시 테이블이 없음

**에러:**
```
traffic_accidents_cache not found
```

**해결:**
캐시 테이블 생성 스크립트를 실행하세요:
```powershell
cd ..\db
Get-Content add-cache-tables.sql | mysql -h 103.218.158.244 -P 30306 -u trafficuser -ptrafficpass --skip-ssl trafficdb
```

## 백그라운드 실행

Windows에서 collector를 백그라운드로 실행하려면:

### 방법 1: Task Scheduler 사용

1. "작업 스케줄러" 열기
2. "기본 작업 만들기" 선택
3. 작업 이름: "OpenAPI Collector"
4. 트리거: "컴퓨터를 시작할 때"
5. 동작: "프로그램 시작"
   - 프로그램: `powershell.exe`
   - 인수: `-ExecutionPolicy Bypass -File "C:\path\to\openapi-collector\run-local.ps1"`
6. 마침

### 방법 2: NSSM (Non-Sucking Service Manager) 사용

1. [NSSM 다운로드](https://nssm.cc/download)
2. NSSM을 설치할 폴더에 압축 해제
3. 관리자 권한 명령 프롬프트에서:
   ```cmd
   nssm install OpenAPICollector "C:\Program Files\Go\bin\go.exe" "run main.go"
   nssm set OpenAPICollector AppDirectory "C:\path\to\openapi-collector"
   nssm set OpenAPICollector AppEnvironmentExtra DB_HOST=103.218.158.244 DB_PORT=30306 DB_USER=trafficuser DB_PASSWORD=trafficpass DB_NAME=trafficdb
   nssm start OpenAPICollector
   ```

## 로그 확인

collector는 표준 출력으로 로그를 출력합니다. 로그를 파일로 저장하려면:

### PowerShell:
```powershell
.\run-local.ps1 | Tee-Object -FilePath collector.log
```

### 명령 프롬프트:
```cmd
run-local.bat > collector.log 2>&1
```

## 지원

문제가 발생하면 다음 정보와 함께 문의하세요:
- Windows 버전
- Go 버전 (`go version` 출력)
- 에러 메시지 전체
- collector 로그
