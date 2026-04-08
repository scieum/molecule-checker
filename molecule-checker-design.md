# 분자 구조 인식 웹앱 — 통합 설계서

> Claude Code 구현 참조용 계획서 | 작성일: 2026-04-07

---

## 1. 작업 컨텍스트

### 배경 및 목적

학생들이 볼-앤-스틱(Ball-and-Stick) 분자 모형 키트로 직접 분자를 조립한 뒤, 카메라로 촬영하면 AI가 두 가지를 즉시 판단해주는 교육용 웹앱을 구축한다.

1. **유효성 판정**: 원자가(valence) 규칙에 맞는 실존 가능한 분자인가?
2. **이름 식별**: 해당 분자의 화학명은 무엇인가?

결과는 **초록색(유효) / 빨간색(무효)** 시각 피드백으로 즉시 제공한다.

---

### 입출력 정의

| 항목 | 내용 |
|------|------|
| **입력** | 볼-앤-스틱 분자 모형 사진 (카메라 실시간 캡처 또는 파일 업로드, JPEG/PNG) |
| **출력** | 유효성(초록/빨강), 분자명(한국어+영어+분자식), 판정 근거 설명, 작용기 목록 |
| **대상 사용자** | 고등학교·대학 입문 수준 화학 수업 학생 |
| **분자 범위** | 고등·대학 입문 수준 유기분자, 주요 작용기 (하이드록시기, 카르복실기, 아민기 등) |

---

### 제약조건

- API 키 노출 방지를 위해 **백엔드 프록시** 필수
- 볼-앤-스틱 모형의 **CPK 표준 색상** 기준으로 원자 판별
- 이미지 크기 제한: 업로드 최대 **10MB**, 전처리 후 API 전송 최대 **1024×1024px**
- 인터넷 연결 필수 (클라우드 AI API 사용)

---

### 용어 정의

| 용어 | 정의 |
|------|------|
| 볼-앤-스틱 모형 | 원자(공)와 결합(막대)으로 표현하는 물리적 분자 모형 키트 |
| CPK 색상 | 원소별 표준 색상 규약 (C=검정, H=흰색, O=빨강, N=파랑 등) |
| 유효 분자 | 각 원자의 원자가 규칙을 완전히 만족하며 실존 가능한 분자 |
| 원자가 규칙 | C:4, H:1, O:2, N:3, S:2(또는 6), Cl:1 등 결합 수 규칙 |
| 작용기 | 유기분자의 화학적 특성을 결정하는 원자단 |
| IUPAC명 | 국제순수응용화학연합 명명법에 따른 공식 화학명 |

---

## 2. 워크플로우

### 전체 흐름도

```
[학생]
   │
   ├─(A) 카메라 열기 → 실시간 프리뷰 → [촬영 버튼] ─┐
   └─(B) 파일 선택 → 미리보기 확인 ─────────────────┘
                                                      │
                                              [이미지 입력 완료]
                                                      │
                                          ┌───────────▼───────────┐
                                          │  Step 1: 이미지 전처리  │  (코드)
                                          │  리사이즈 + Base64 인코딩│
                                          └───────────┬───────────┘
                                                      │ 유효성 검사 통과
                                          ┌───────────▼───────────┐
                                          │  Step 2: API 프록시    │  (코드)
                                          │  백엔드 POST /api/analyze│
                                          └───────────┬───────────┘
                                                      │
                                          ┌───────────▼───────────┐
                                          │  Step 3: 분자 분석     │  (LLM)
                                          │  Gemini Vision API 호출│
                                          │  원자 인식 → 결합 분석  │
                                          │  유효성 판정 → 이름 식별│
                                          └───────────┬───────────┘
                                                      │ JSON 응답
                                          ┌───────────▼───────────┐
                                          │  Step 4: 결과 렌더링   │  (코드)
                                          │  초록/빨강 + 분자명    │
                                          └───────────────────────┘
```

---

### 단계별 상세 정의

#### Step 1 — 이미지 전처리

| 항목 | 내용 |
|------|------|
| **처리 방식** | 코드 처리 (프론트엔드) |
| **세부 동작** | 카메라: `getUserMedia()` → canvas 캡처 → Base64 추출 / 업로드: FileReader API → Base64 변환 / 공통: 이미지 1024×1024 이하로 리사이즈 |
| **LLM 판단 영역** | 없음 |
| **성공 기준** | 유효 이미지 형식(JPEG/PNG), 10MB 이하, Base64 문자열 정상 생성 |
| **검증 방법** | 규칙 기반 (파일 타입·크기 체크) |
| **실패 시 처리** | 스킵 불가 → 사용자에게 즉시 오류 메시지 표시 + 재시도 유도 |

---

#### Step 2 — 백엔드 API 프록시

| 항목 | 내용 |
|------|------|
| **처리 방식** | 코드 처리 (백엔드) |
| **세부 동작** | 프론트엔드 → 백엔드 `POST /api/analyze` (Base64 이미지 페이로드) → 백엔드에서 환경변수 API 키 주입 → Gemini API 호출 |
| **LLM 판단 영역** | 없음 |
| **성공 기준** | HTTP 200 응답 + Gemini 응답 JSON 수신 |
| **검증 방법** | 규칙 기반 (HTTP 상태 코드 확인) |
| **실패 시 처리** | 자동 재시도 1회 → 재실패 시 사용자에게 "서버 오류" 메시지 표시 |

---

#### Step 3 — Gemini Vision 분자 분석 ⟨LLM 판단 핵심 단계⟩

| 항목 | 내용 |
|------|------|
| **처리 방식** | LLM 직접 수행 (Gemini 2.0 Flash (Vision)) |
| **LLM이 수행하는 판단** | ① CPK 색상 기반 원소 식별, ② 결합 수·패턴 분석, ③ 원자가 규칙 충족 여부 판정, ④ 분자 이름(IUPAC + 관용명) 식별, ⑤ 주요 작용기 추출 |
| **코드가 처리하는 부분** | API 요청/응답 직렬화, 응답 JSON 파싱 |
| **성공 기준** | 필수 필드 포함 유효 JSON 반환: `is_valid`, `molecule_name_kr`, `molecule_name_en`, `formula`, `explanation` |
| **검증 방법** | 스키마 검증 (필수 필드 존재 + 타입 체크) |
| **실패 시 처리** | 스키마 검증 실패 → 자동 재시도 1회 (동일 프롬프트 재전송) → 재실패 시 `"분석 불가"` 안내 메시지 표시 |

**LLM 분석 서브 단계 (Gemini 내부 추론 흐름):**

```
이미지 수신
   │
   ├─ [판단] 볼-앤-스틱 모형이 이미지에 존재하는가?
   │         NO → { is_valid: null, explanation: "분자 모형 미감지" }
   │
   ├─ [판단] CPK 색상으로 원자 종류 식별
   │         (C=검정/회색, H=흰색, O=빨강, N=파랑, S=노랑, Cl=연두)
   │
   ├─ [판단] 각 원자의 결합 수 계산
   │
   ├─ [판단] 원자가 규칙 위반 원자 존재 여부 확인
   │         위반 있음 → is_valid: false + 위반 원자·이유 설명
   │
   ├─ [판단] 전체 구조 기반 분자 이름 식별
   │         (IUPAC명 우선, 관용명 병기)
   │
   └─ [판단] 주요 작용기 목록 추출
              → 구조화된 JSON 반환
```

---

#### Step 4 — 결과 렌더링

| 항목 | 내용 |
|------|------|
| **처리 방식** | 코드 처리 (프론트엔드) |
| **세부 동작** | `is_valid: true` → 초록색 테두리·배경 + 분자명·분자식·작용기 표시 / `is_valid: false` → 빨간색 테두리·배경 + 오류 원인 설명 |
| **LLM 판단 영역** | 없음 |
| **성공 기준** | 화면에 결과 카드 정상 렌더링, 색상 피드백 표시 |
| **검증 방법** | 규칙 기반 (DOM 렌더링 완료 확인) |
| **실패 시 처리** | Fallback UI 표시 ("결과를 표시할 수 없습니다") |

---

### 에러 처리 매트릭스

| 상황 | 감지 위치 | 처리 방식 |
|------|----------|----------|
| 이미지에 분자 모형 없음 | Gemini 판단 | `is_valid: null` + "분자 모형이 보이지 않습니다" 안내 |
| 사진 품질 불량 (흐림·역광) | Gemini 판단 | `confidence: "low"` 반환 → "더 밝고 선명하게 촬영해 주세요" 안내 |
| 파일 형식·크기 오류 | Step 1 코드 | 즉시 오류 메시지, 재업로드 유도 |
| API 호출 타임아웃·실패 | Step 2 코드 | 자동 재시도 1회 → 실패 시 오류 표시 |
| 응답 JSON 스키마 오류 | Step 3 코드 | 자동 재시도 1회 → 실패 시 "분석 불가" 표시 |
| 미지의 분자 (구조는 유효) | Gemini 판단 | `is_valid: true` + `molecule_name_kr: "미확인 분자 (구조 유효)"` |

---

## 3. 구현 스펙

### 폴더 구조

```
/molecule-checker
  ├── CLAUDE.md                              # 메인 에이전트 지침 (전체 맥락·스킬 사용법)
  ├── /.claude
  │   └── /skills
  │       ├── /image-processor               # 이미지 전처리 스킬
  │       │   ├── SKILL.md
  │       │   └── /scripts
  │       │       └── imageProcessor.js      # 리사이즈·Base64·유효성 검사
  │       ├── /molecule-analyzer             # Gemini Vision 분석 스킬
  │       │   ├── SKILL.md
  │       │   └── /references
  │       │       ├── cpk-colors.md          # CPK 원자 색상 기준표
  │       │       ├── valence-rules.md       # 원자가 규칙 참조
  │       │       ├── ring-structures.md     # 고리 구조 판단 가이드 ← 추가
  │       │       └── functional-groups.md   # 주요 작용기 목록
  │       └── /result-renderer               # UI 결과 렌더링 스킬
  │           └── SKILL.md
  ├── /frontend
  │   ├── index.html
  │   ├── vite.config.js
  │   ├── tailwind.config.js
  │   └── /src
  │       ├── App.jsx                        # 루트 컴포넌트·상태 관리
  │       ├── /components
  │       │   ├── CameraCapture.jsx          # 카메라 스트림·촬영 버튼
  │       │   ├── FileUpload.jsx             # 파일 선택·미리보기
  │       │   ├── ResultDisplay.jsx          # 초록/빨강 결과 카드
  │       │   └── LoadingSpinner.jsx         # 분석 중 로딩 UI
  │       └── /services
  │           └── apiService.js              # 백엔드 /api/analyze 호출
  ├── /backend
  │   ├── server.js                          # Express 서버 진입점
  │   ├── /routes
  │   │   └── analyze.js                     # POST /api/analyze 라우트
  │   ├── /services
  │   │   └── geminiService.js               # Gemini API 호출·프롬프트 관리
  │   ├── .env.example                       # GEMINI_API_KEY 환경변수 예시
  │   └── package.json
  ├── /output                                # (선택) 분석 로그·샘플 이미지
  └── /docs
      ├── cpk-color-reference.md             # CPK 색상 참조표
      └── valence-rules-reference.md         # 원자가 규칙 참조
```

---

### CLAUDE.md 핵심 섹션 목록

1. 프로젝트 개요 및 목적
2. 기술 스택 요약 (React + Vite, Node.js + Express, Gemini 2.0 Flash)
3. 폴더 구조 안내
4. 스킬 호출 순서: `image-processor` → `molecule-analyzer` → `result-renderer`
5. Gemini Vision 프롬프트 작성 지침 (CPK 색상·원자가 규칙 명시 방법)
6. API 응답 JSON 스키마 정의
7. 에러 처리 패턴 요약
8. 배포 체크리스트 (환경변수, CORS 설정)

---

### 에이전트 구조

**단일 에이전트** 채택 (서브에이전트 분리 불필요)

- 워크플로우가 선형적 (이미지 입력 → AI 분석 → 결과 출력)
- 핵심 AI 판단이 Gemini Vision API 단일 호출로 완결
- 지침 문서가 짧고 컨텍스트 윈도우 부담 없음

---

### 스킬 목록

| 스킬명 | 역할 | 트리거 조건 | 처리 방식 |
|--------|------|------------|----------|
| `image-processor` | 이미지 유효성 검사, 리사이즈, Base64 인코딩 | 카메라 캡처 또는 파일 업로드 발생 직후 | 코드 (스크립트) |
| `molecule-analyzer` | Gemini Vision API 호출, 프롬프트 구성, 응답 JSON 파싱 및 스키마 검증 | `image-processor` 완료 후 유효 이미지 수신 시 | LLM + 코드 혼합 |
| `result-renderer` | `is_valid` 값 기반 색상 전환, 분자명·분자식·작용기·설명 렌더링 | `molecule-analyzer`에서 유효 JSON 응답 수신 시 | 코드 (UI 렌더링) |

---

### 기술 스택 (추천)

| 영역 | 기술 | 선택 이유 |
|------|------|----------|
| 프론트엔드 프레임워크 | React + Vite | 컴포넌트 재사용성, 빠른 빌드·HMR |
| 스타일링 | Tailwind CSS | 색상 피드백 UI 구현에 최적, 반응형 지원 |
| 백엔드 | Node.js + Express | 경량, @google/generative-ai SDK 공식 지원 |
| AI 모델 | Gemini 2.0 Flash (Vision) | 이미지 분석 + 화학 도메인 지식, 무료 티어 제공 |
| 프론트 배포 | Vercel | Git 연동 자동 배포, 무료 티어 |
| 백엔드 배포 | Railway 또는 Render | 환경변수 관리, 무료 티어 |

---

### Gemini Vision 프롬프트 전략

**SDK**: `@google/generative-ai` (Node.js)
**모델**: `gemini-2.0-flash`
**이미지 전달 방식**: inlineData (Base64 + mimeType)

**시스템 프롬프트 구조:**
```
역할: 고등·대학 입문 수준 화학 교육 전문가
참조 기준: CPK 색상 규칙, IUPAC 명명법, 원자가 규칙
출력 형식: 반드시 JSON만 반환 (Markdown 코드블록, 설명 불가)
```

**사용자 프롬프트 구조:**
```
[이미지: inlineData Base64]

아래 순서로 분석하고 JSON으로만 응답하시오.
1. 볼-앤-스틱 분자 모형이 이미지에 존재하는지 확인
2. CPK 색상으로 각 원자 종류 식별
3. 각 원자의 결합 수 계산
4. 원자가 규칙 위반 여부 판정
5. 분자 이름(IUPAC명 + 관용명) 식별
6. 주요 작용기 추출

응답 JSON 스키마:
{
  "is_valid": boolean | null,
  "molecule_name_kr": string,
  "molecule_name_en": string,
  "formula": string,
  "explanation": string,
  "functional_groups": string[],
  "confidence": "high" | "medium" | "low"
}
```

**geminiService.js 핵심 호출 구조:**
```js
import { GoogleGenerativeAI } from "@google/generative-ai";
const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
const model = genAI.getGenerativeModel({ model: "gemini-2.0-flash" });

const result = await model.generateContent([
  { inlineData: { data: base64Image, mimeType: "image/jpeg" } },
  promptText
]);
```

---

### 고리 구조 판단 가이드 (참조)

평면 사진에서 고리 구조 분자는 원자가 겹쳐 보여 결합 수 계산이 부정확할 수 있다. 아래 보완 전략을 프롬프트 및 `references/valence-rules.md`에 명시한다.

| 상황 | 보완 전략 |
|------|----------|
| 원자가 겹쳐 결합 수 불분명 | 분자식(원자 총 수)을 먼저 세고, 고리 패턴(5각형/6각형)을 함께 고려해 판단 |
| 5각형 고리 | 푸라노스 형태 (예: 리보스, 프럭토스) |
| 6각형 고리 | 피라노스 형태 (예: 포도당, 갈락토스) |
| 고리 내 산소 포함 여부 | 고리 내 O 원자가 1개면 헤미아세탈 결합, 정상 원자가 판정 가능 |
| 분자식과 구조가 일치하는 경우 | 겹침이 있어도 분자식 기준으로 유효성 판정 허용 |

**프롬프트 추가 지침 (geminiService.js에 반영):**
> "고리 구조에서 원자가 겹쳐 보일 경우, 이미지에서 보이는 원자 총 수(분자식)와 고리 패턴(5각형/6각형)을 함께 고려하여 원자가 규칙을 판정하라. 단순 2D 투영 한계로 결합 수가 불명확한 경우, 해당 원자의 판정을 confidence: 'medium'으로 표시하라."

---

### CPK 색상 기준표 (참조)

| 원소 | 색상 | 원자가 |
|------|------|--------|
| 수소 (H) | 흰색 | 1 |
| 탄소 (C) | 검정/짙은 회색 | 4 |
| 산소 (O) | 빨간색 | 2 |
| 질소 (N) | 파란색 | 3 |
| 황 (S) | 노란색 | 2 또는 6 |
| 인 (P) | 주황색 | 3 또는 5 |
| 염소 (Cl) | 연두색 | 1 |
| 브롬 (Br) | 갈색/어두운 빨강 | 1 |

---

### API 응답 JSON 스키마 (주요 산출물)

```json
{
  "is_valid": true,
  "molecule_name_kr": "에탄올",
  "molecule_name_en": "Ethanol",
  "formula": "C₂H₅OH",
  "explanation": "탄소 원자 2개가 각각 4개의 결합을 정확히 형성하고, 산소가 2개의 결합을 만족하며, 수소가 모두 단일 결합입니다. 원자가 규칙을 모두 충족하는 유효한 분자입니다.",
  "functional_groups": ["하이드록시기 (-OH)"],
  "confidence": "high"
}
```

```json
{
  "is_valid": false,
  "molecule_name_kr": "알 수 없음",
  "molecule_name_en": "Unknown",
  "formula": "?",
  "explanation": "중앙의 탄소 원자가 5개의 결합을 형성하고 있습니다. 탄소의 최대 원자가는 4이므로 이 구조는 실존할 수 없습니다.",
  "functional_groups": [],
  "confidence": "high"
}
```

---

## 4. 구현 우선순위 (Phase)

| Phase | 목표 | 주요 산출물 |
|-------|------|-----------|
| **Phase 1** | 백엔드 + Gemini Vision 연동 검증 | `POST /api/analyze` 정상 동작, JSON 응답 확인 |
| **Phase 2** | 파일 업로드 + 결과 표시 UI | `FileUpload.jsx` + `ResultDisplay.jsx` |
| **Phase 3** | 카메라 실시간 캡처 기능 | `CameraCapture.jsx` (모바일 우선) |
| **Phase 4** | UI 완성도 향상 | 색상 애니메이션, 모바일 반응형, 재촬영 버튼 |

---

## 5. 핵심 설계 결정 근거

| 결정 | 선택 | 근거 |
|------|------|------|
| 에이전트 구조 | 단일 에이전트 | 워크플로우가 선형적, 판단 로직이 Gemini Vision 단일 호출로 완결 |
| 백엔드 필요 여부 | 필요 (프록시) | API 키를 클라이언트에 노출하면 학생 환경에서 보안 취약 |
| 이미지 전처리 위치 | 프론트엔드 | 서버 부하 분산, 네트워크 전송량 최소화 |
| 모델 선택 | gemini-2.0-flash | 이미지 분석 능력 + 화학 도메인 지식의 균형, 비용 적정 |
| 응답 형식 | JSON 강제 | 프론트엔드 파싱 안정성, 스키마 검증 가능 |
