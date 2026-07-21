// 분류 골든 세트 생성기 (M4 DoD 1 — 라벨 500건, 정확도 ≥ 0.90 기준선).
// 라벨은 아래 수동 표(BRANDS/UNKNOWNS)에서 나온다 — 분류 규칙과 별도로 관리되는
// '사람 관점 정답'이다. 변형(지점명·결제 접두어)만 기계적으로 늘린다.
// 미지 상호(UNKNOWNS ~10%)는 규칙이 못 잡는 현실 케이스 — 오답으로 집계되어
// 정확도 상한을 현실화한다 (전부 맞히도록 세트를 규칙에 맞추는 것은 공허).
//
// 실행: node fixtures/classify/gen.mjs  →  golden.jsonl 재생성 (diff 검토 후 커밋)

import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

// [상호 표기, 정답 카테고리] — 표기는 정규화 후 형태(소문자·공백축약)
const BRANDS = [
  // 카페·간식
  ['스타벅스', 'cafe'], ['투썸플레이스', 'cafe'], ['이디야커피', 'cafe'],
  ['메가엠지씨커피', 'cafe'], ['컴포즈커피', 'cafe'], ['빽다방', 'cafe'],
  ['할리스', 'cafe'], ['배스킨라빈스', 'cafe'], ['파리바게뜨', 'cafe'], ['뚜레쥬르', 'cafe'],
  // 배달
  ['배달의민족', 'delivery'], ['요기요', 'delivery'], ['쿠팡이츠', 'delivery'],
  // 식비
  ['맥도날드', 'food'], ['버거킹', 'food'], ['롯데리아', 'food'], ['맘스터치', 'food'],
  ['김밥천국', 'food'], ['교촌치킨', 'food'], ['비비큐치킨', 'food'],
  ['명동초밥', 'food'], ['전주국밥', 'food'], ['시골분식', 'food'], ['왕가네식당', 'food'],
  // 편의점
  ['gs25', 'convenience'], ['cu ', 'convenience'], ['세븐일레븐', 'convenience'],
  ['이마트24', 'convenience'], ['미니스톱', 'convenience'],
  // 마트
  ['이마트', 'groceries'], ['홈플러스', 'groceries'], ['롯데마트', 'groceries'],
  ['코스트코', 'groceries'], ['마켓컬리', 'groceries'], ['쿠팡', 'groceries'],
  // 교통
  ['카카오티택시', 'taxi'], ['서울택시', 'taxi'],
  ['서울지하철', 'transport'], ['코레일', 'transport'], ['티머니충전', 'transport'],
  ['경기버스', 'transport'], ['하이패스충전', 'transport'],
  ['sk에너지 강남주유소', 'fuel'], ['gs칼텍스', 'fuel'], ['에쓰오일', 'fuel'],
  // 통신·구독
  ['에스케이텔레콤', 'telecom'], ['엘지유플러스', 'telecom'], ['통신요금납부', 'telecom'],
  ['넷플릭스', 'subscription'], ['netflix.com', 'subscription'], ['유튜브프리미엄', 'subscription'],
  ['스포티파이', 'subscription'], ['멜론정기결제', 'subscription'], ['쿠팡와우멤버십', 'subscription'],
  ['왓챠', 'subscription'], ['티빙', 'subscription'], ['디즈니플러스', 'subscription'],
  // 주거·공과금
  ['한국전력공사', 'utilities'], ['서울도시가스', 'utilities'], ['수도요금자동납부', 'utilities'],
  ['래미안아파트관리비', 'housing'], ['오피스텔월세', 'housing'],
  // 의료
  ['서울대학교병원', 'medical'], ['연세정형외과의원', 'medical'], ['화이트치과', 'medical'],
  ['경희한의원', 'medical'], ['온누리약국', 'pharmacy'], ['메디팜약국', 'pharmacy'],
  // 교육·문화
  ['영단기학원', 'education'], ['수학의정석학원', 'education'],
  ['cgv 용산', 'culture'], ['롯데시네마', 'culture'], ['메가박스', 'culture'],
  ['교보문고', 'culture'], ['예스24', 'culture'], ['알라딘중고서점', 'culture'],
  // 의류·미용
  ['유니클로', 'clothing'], ['무신사스토어', 'clothing'], ['스파오', 'clothing'],
  ['올리브영', 'beauty'], ['준오헤어', 'beauty'], ['블루클럽미용실', 'beauty'],
  // 여행
  ['야놀자', 'travel'], ['여기어때', 'travel'], ['아고다', 'travel'],
  ['에어비앤비', 'travel'], ['신라호텔', 'travel'], ['대한항공', 'travel'], ['제주항공', 'travel'],
  // 보험·금융
  ['삼성생명보험', 'insurance'], ['삼성화재', 'insurance'], ['현대해상', 'insurance'],
  ['송금수수료', 'finance_fee'],
  // 입금 계열 (양수 금액)
  ['급여이체', 'salary'], ['월급입금', 'salary'], ['예금이자', 'interest'],
  // 현금
  ['atm출금', 'atm'], ['현금인출기', 'atm'],
];

// 규칙이 모를 수밖에 없는 개인·지역 상호 — 사람 라벨은 있으나 규칙 미커버 (오답 예상)
const UNKNOWNS = [
  ['달빛곱창', 'food'], ['제이네과일가게', 'groceries'], ['동네빨래방', 'unknown'],
  ['행운세탁소', 'unknown'], ['초록화원', 'unknown'], ['별밤포차', 'food'],
  ['우리들공방', 'culture'], ['골목떡볶이', 'food'], ['하늘꽃집', 'unknown'],
  ['정든이발관', 'beauty'], ['소소한잡화점', 'unknown'], ['달려라철물', 'unknown'],
  ['바다낚시프라자', 'unknown'], ['그린테니스장', 'unknown'], ['한솔문구', 'unknown'],
  ['늘푸른청과', 'groceries'], ['만복부동산', 'unknown'], ['제일열쇠', 'unknown'],
  ['희망세차장', 'unknown'], ['둥지공인중개사', 'unknown'],
];

const SUFFIXES = ['', ' 강남점', ' 서울역점', ' 홍대점', ' 역삼점', ' 판교점'];

const rows = [];
let i = 0;
// 브랜드 × 지점 변형으로 ~460건
outer:
for (const [name, label] of BRANDS) {
  for (const sfx of SUFFIXES) {
    // 입금 계열은 지점 변형이 어색 — 원형만
    if ((label === 'salary' || label === 'interest' || label === 'atm') && sfx !== '') continue;
    const amount =
      label === 'salary' ? '3200000'
      : label === 'interest' ? '1250'
      : String(-(1000 + ((i * 7919) % 89000)));
    rows.push({ merchant: (name + sfx).trim(), amount_minor: amount, expected: label });
    i += 1;
    if (rows.length >= 460) break outer;
  }
}
// 미지 상호 ×2 변형으로 ~40건
for (const [name, label] of UNKNOWNS) {
  for (const sfx of ['', ' 본점']) {
    rows.push({ merchant: (name + sfx).trim(), amount_minor: String(-(3000 + ((i * 733) % 50000))), expected: label });
    i += 1;
  }
}

const out = rows.slice(0, 500);
if (out.length !== 500) {
  console.error(`생성 건수 ${out.length} ≠ 500`);
  process.exit(1);
}
const here = dirname(fileURLToPath(import.meta.url));
writeFileSync(join(here, 'golden.jsonl'), out.map((r) => JSON.stringify(r)).join('\n') + '\n');
const unknownCount = out.filter((r) => UNKNOWNS.some(([n]) => r.merchant.startsWith(n))).length;
console.log(`golden.jsonl: ${out.length}건 (미지 상호 ${unknownCount}건 포함)`);
