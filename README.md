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
- **명예의 전당(Hall of Fame)** — 학생이 만든 거대 분자 기록 공유
- **프로필 & 갤러리** — 닉네임·학교(NEIS API 연동) 설정, 저장한 분자 모음

## 폴더 구조

```
molecule-checker/
├── index.html                  # 단일 HTML + Tailwind CDN으로 동작하는 SPA
├── .github/workflows/
│   └── pages.yml               # GitHub Pages 자동 배포 워크플로
├── README.md
└── molecule-checker-design.md  # 전체 설계서 (워크플로·프롬프트·스키마)
```

## 실행 및 배포

### 로컬 실행

정적 파일이므로 별도 빌드 단계가 없습니다. 간단한 HTTP 서버로 열면 됩니다.

```bash
python3 -m http.server 8000
# → http://localhost:8000
```

`file://`로 직접 열면 카메라 권한이 차단될 수 있으므로 HTTP 서버 사용을 권장합니다.

### GitHub Pages 배포

`master` 브랜치에 푸시되면 `.github/workflows/pages.yml`이 리포 루트를 Pages
아티팩트로 업로드하고 자동 배포합니다. 리포지토리 **Settings → Pages**에서
**Source**를 **GitHub Actions**로 설정해 주세요. (기본값인 "Deploy from a
branch"로 두어도 `index.html`이 리포 루트에 있어서 동작합니다.)

배포 후 404가 계속 뜬다면 다음을 확인해 보세요.

1. Settings → Pages에서 Source가 **GitHub Actions** 또는 **Deploy from a
   branch: master / (root)** 둘 중 하나로 설정되어 있는지
2. Actions 탭에서 "Deploy frontend to GitHub Pages" 워크플로가 성공했는지
3. 접속 URL이 `https://<org>.github.io/molecule-checker/` 인지 (끝 슬래시 포함)

## 백엔드 연결

실제 AI 분석은 API 키 노출 방지를 위해 **백엔드 프록시**를 거칩니다. 백엔드가
배포되기 전에는 분석 버튼이 "데모 모드" 안내 카드를 보여주도록 되어 있습니다.

백엔드를 배포한 뒤 `index.html` 상단의 `BACKEND_URL` 값을 설정하세요.

```js
// index.html
const BACKEND_URL = "https://your-backend.example.com/api/analyze";
```

백엔드는 `POST /api/analyze`로 아래 형식의 JSON을 받아 Gemini Vision에 전달한 뒤,
응답 스키마에 맞춰 JSON을 반환해야 합니다.

**요청**

```json
{ "image": "<base64>", "mimeType": "image/jpeg" }
```

**응답**

```json
{
  "is_valid": true,
  "molecule_name_kr": "에탄올",
  "molecule_name_en": "Ethanol",
  "formula": "C₂H₅OH",
  "explanation": "탄소 2개가 각각 4개의 결합을 형성하여 원자가 규칙을 충족합니다.",
  "functional_groups": ["하이드록시기 (-OH)"],
  "confidence": "high"
}
```

전체 스키마·프롬프트·에러 처리 매트릭스는 [`molecule-checker-design.md`](./molecule-checker-design.md)를 참고하세요.

## NEIS 학교 검색 (선택)

프로필 탭의 학교 검색은 [NEIS 교육정보 개방 포털](https://open.neis.go.kr)의
`schoolInfo` API를 사용합니다. 호출량이 많아질 경우 API 키를 발급받아
`index.html`의 `NEIS_API_KEY` 값에 설정해 주세요.

## 기술 스택

| 영역 | 기술 |
|------|------|
| 프론트엔드 | 단일 HTML + Tailwind CDN + Vanilla JS |
| 폰트 | Black Han Sans, Noto Sans KR (Google Fonts) |
| AI 모델 | Gemini 2.0 Flash (Vision) |
| 백엔드 (예정) | Node.js + Express + `@google/generative-ai` |
| 호스팅 | GitHub Pages (프론트) |

## 라이선스

© 2026 사이음(sci_eum).
