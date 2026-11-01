# XDR Boost

M1 Pro/Max 이후 맥북프로(Liquid Retina XDR)에서 **일반 화면(SDR)을 HDR 밝기 영역까지** 끌어올리는 메뉴바 앱
SDR 최대 500nit에 묶여 있는 화면을, 야외처럼 밝은 곳에서 더 잘 보이게 합니다.

## 원리

1. 화면 구석에 1포인트짜리 투명 창을 띄우고 EDR(값 > 1.0) 콘텐츠를 그립니다. macOS는 이를 HDR 콘텐츠로 보고 디스플레이를 EDR 모드로 전환합니다.
2. EDR 모드에서 생긴 여유(headroom, M1 Pro 최대 약 3.2×)만큼 내장 디스플레이의 감마 테이블(`CGSetDisplayTransferByTable`)을 배율로 키웁니다.
3. 적용 배율은 `min(설정 배율, 현재 여유)`이며 1초마다 다시 맞춥니다. 앱이 꺼지면 원래 ColorSync 설정으로 복원합니다.

공개 API만 씁니다.

## 빌드

Xcode(Command Line Tools 포함)가 필요합니다.

```bash
./build.sh            # XDRBoost.app 생성
./build.sh install    # ~/Applications 에 설치 ("로그인 시 실행"에 필요)
./build.sh release    # 유니버설 빌드를 dist/ 에 zip
```

디버그 로그: `XDR_DEBUG=1 ./XDRBoost.app/Contents/MacOS/XDRBoost`

## 메뉴

- **XDR 부스트** (⌘B): 켜기/끄기
- **밝기 배율**: 1.0× ~ 3.0× (시스템 여유를 넘으면 자동으로 제한)
- **발열 시 자동 일시정지**: `thermalState`가 serious 이상이면 잠시 끔
- **로그인 시 실행**

## 주의

- 밝기를 올리는 만큼 배터리 소모와 발열이 늘어납니다.
- 내장 XDR 디스플레이에만 적용됩니다. 외부 모니터는 건드리지 않습니다.
- 흰 영역은 배율이 클수록 클리핑(색 날아감)이 생길 수 있습니다.
