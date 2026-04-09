# Molecule Checker

볼-앤-스틱(Ball-and-Stick) 분자 모형 사진을 올리면 AI가 **유효성**과 **분자명**을
판정해주는 교육용 웹앱입니다. 고등학교·대학 입문 수준의 화학 수업에서 학생들이 직접
조립한 분자 모형의 원자가 규칙 충족 여부를 즉시 확인할 수 있도록 설계되었습니다.

사이음(sci_eum) — 과학의 사이, 사람을 잇다.

## 주요 기능

- **카메라 촬영 / 파일 업로드** — `getUserMedia()` 실시간 캡처와 JPG/PNG 업로드(최대 10MB) 지원
- **AI 유효성 판정** — Gemini Vision이 CPK 색상으로 원자를 식별하고 원자가 규칙 위반 여부를 판정
- **결과 시각 피드백** — 유효(초록) / 무효(빨강) / 감지 실패(크림) 색상 카드
- **분자 도감(Catalog)** — 모형 키트로 조립 가능한 분자 목록
- **명예의 전당(Hall of Fame)** — 전체 사용자가 제출한 거대 분자 기록 공유 (Supabase 저장)
- **프로필 & 갤러리** — 닉네임·학교(NEIS API), 내가 저장한 분자 (Supabase 저장)

## 폴더 구조

```
molecule-checker/
├── index.html                         # 단일 HTML + Tailwind CDN + Supabase JS
├── .github/workflows/pages.yml        # GitHub Pages 자동 배포 워크플로
├── supabase/
│   ├── config.toml                    # Supabase CLI 로컬 설정
│   ├── functions/analyze/index.ts     # Gemini Vision 프록시 Edge Function
│   └── migrations/
│       └── 20260409000000_initial_schema.sql
├── README.md
└── molecule-checker-design.md         # 전체 설계서 (워크플로·프롬프트·스키마)
```

## 로컬 실행

정적 파일이므로 별도 빌드 단계가 없습니다. 간단한 HTTP 서버로 열면 됩니다.

```bash
python3 -m http.server 8000
# → http://localhost:8000
```

`file://`로 직접 열면 카메라 권한이 차단될 수 있으므로 HTTP 서버 사용을 권장합니다.

## GitHub Pages 배포

`master` 브랜치에 푸시되면 `.github/workflows/pages.yml`이 리포 루트를 Pages
아티팩트로 업로드하고 자동 배포합니다. 리포지토리 **Settings → Pages**에서
**Source**를 **GitHub Actions**로 설정해 주세요. (기본값인 "Deploy from a
branch"로 두어도 `index.html`이 리포 루트에 있어서 동작합니다.)

배포 후 404가 계속 뜬다면:

1. Settings → Pages에서 Source가 **GitHub Actions** 또는 **Deploy from a
   branch: master / (root)** 둘 중 하나인지
2. Actions 탭에서 "Deploy frontend to GitHub Pages" 워크플로가 성공했는지
3. 접속 URL이 `https://<org>.github.io/molecule-checker/` 인지 (끝 슬래시 포함)

## Supabase 백엔드 설정

Supabase가 분석 프록시(Edge Function), DB(Postgres + RLS), 이미지 저장소(Storage)
역할을 모두 담당합니다. 설정 완료 전까지 앱은 **데모 모드**로 동작합니다.

### 1. Supabase 프로젝트 생성

[app.supabase.com](https://app.supabase.com)에서 새 프로젝트를 만들고,
**Settings → API** 에서 다음 두 값을 복사해 둡니다.

- `Project URL` → `SUPABASE_URL`
- `anon public` 키 → `SUPABASE_ANON_KEY`

### 2. Supabase CLI 설치 및 로그인

```bash
# macOS
brew install supabase/tap/supabase

# 또는 npx 사용
npx supabase --version

supabase login
supabase link --project-ref <your-project-ref>
```

### 3. 데이터베이스 마이그레이션 적용

`supabase/migrations/20260409000000_initial_schema.sql` 이 다음을 생성합니다.

- `profiles`, `gallery_entries`, `hall_of_fame` 테이블
- 각 테이블의 RLS 정책 (소유자 단위 접근 제어)
- `molecule-images` 스토리지 버킷과 `{uid}/...` 경로 업로드 정책
- `profiles.updated_at` 자동 갱신 트리거

```bash
supabase db push
```

### 4. 익명 로그인 활성화

학교 시연 환경에서 별도 회원가입 없이 바로 사용할 수 있도록 익명 사인인을 켭니다.

- **Authentication → Providers → Anonymous Sign-Ins → Enable**

각 방문자는 고유한 `auth.uid()`를 가진 익명 세션으로 접속되며, RLS 정책이
`auth.uid()` 기준으로 본인 데이터만 접근하도록 강제합니다.

### 5. Edge Function 배포

```bash
supabase functions deploy analyze
supabase secrets set GEMINI_API_KEY=<your-gemini-api-key>
```

Edge Function은 `supabase/functions/analyze/index.ts` 의 Deno 런타임으로
실행되며, 다음을 수행합니다.

1. 클라이언트가 보낸 base64 이미지 수신 (인증 필수, JWT 자동 검증)
2. Gemini 2.0 Flash `generativelanguage.googleapis.com`에 REST 호출
3. 응답을 파싱해 고정 스키마 JSON으로 반환

Gemini API 키는 `GEMINI_API_KEY` 시크릿에만 보관되며 브라우저에는 절대 노출되지
않습니다.

### 6. index.html 설정 값 채우기

`index.html` 최상단의 설정 상수를 채워 주세요.

```js
const SUPABASE_URL = "https://<project-ref>.supabase.co";
const SUPABASE_ANON_KEY = "<anon-public-key>";
```

페이지 로드 시 자동으로 익명 사인인이 수행되고, 모든 데이터 I/O가
Supabase로 연결됩니다.

## 데이터 모델

### `profiles`
| 컬럼 | 타입 | 비고 |
|------|------|------|
| `user_id` | `uuid` PK | `auth.users(id)` 참조 |
| `nickname` | `text` | 1-40자 |
| `school_code`, `school_name`, `school_kind`, `region_code` | `text` | NEIS 학교 정보 |

### `gallery_entries`
| 컬럼 | 타입 | 비고 |
|------|------|------|
| `id` | `uuid` PK | |
| `user_id` | `uuid` | 소유자만 SELECT/INSERT/DELETE |
| `molecule_name_kr/en`, `formula`, `is_valid`, `atoms`, `confidence`, `explanation` | | 분석 결과 |
| `image_path` | `text` | `molecule-images` 버킷 경로 |

### `hall_of_fame`
| 컬럼 | 타입 | 비고 |
|------|------|------|
| `id` | `uuid` PK | |
| `user_id` | `uuid` | 작성자 (RLS로 본인만 INSERT/DELETE) |
| `nickname`, `school`, `molecule`, `formula`, `atoms` | | 표시용 필드 |
| `image_path` | `text` | `molecule-images` 버킷 경로 |

**읽기 권한**: `hall_of_fame`은 모두 공개 SELECT, `profiles`/`gallery_entries`는
소유자 전용.

### Storage: `molecule-images`
- 공개 버킷, 10MB 제한, `image/jpeg|png|webp` 허용
- 업로드 경로 규칙: `{auth.uid()}/{uuid}.{ext}` — RLS가 첫 세그먼트를 검사

## NEIS 학교 검색 (선택)

프로필 탭의 학교 검색은 [NEIS 교육정보 개방 포털](https://open.neis.go.kr)의
`schoolInfo` API를 사용합니다. 호출량이 많아질 경우 API 키를 발급받아
`index.html` 의 `NEIS_API_KEY` 값에 설정해 주세요.

## 기술 스택

| 영역 | 기술 |
|------|------|
| 프론트엔드 | 단일 HTML + Tailwind CDN + Vanilla JS (ES modules) |
| 폰트 | Black Han Sans, Noto Sans KR (Google Fonts) |
| AI 모델 | Gemini 2.0 Flash (Vision) — REST 호출 |
| 백엔드 | Supabase Edge Functions (Deno/TypeScript) |
| 데이터베이스 | Supabase Postgres + Row Level Security |
| 스토리지 | Supabase Storage (공개 버킷) |
| 인증 | Supabase Auth (Anonymous Sign-Ins) |
| 호스팅 | GitHub Pages (프론트) |

## 라이선스

© 2026 사이음(sci_eum).
