# ubuntu_kakaotalk

Ubuntu에서 카카오톡(KakaoTalk)을 Wine으로 원클릭 설치하고, GNOME Dock과 상단바에 아이콘으로 통합하는 스크립트.

## 설치

### 1. 32비트 KakaoTalk 설치 파일 받기

https://www.kakao.com/talk/download 에서 **반드시 "32비트"** 옵션을 선택해 다운로드하세요.

- 파일 크기: 약 **83MB** (64비트는 ~93MB인데 32비트 Wine prefix에서 실행되지 않습니다)
- 파일 확인: `file KakaoTalk_Setup.exe` 결과가 `PE32 executable (GUI) Intel 80386 ... Nullsoft Installer`여야 합니다

### 2. 원클릭 설치

```bash
git clone git@github.com:201710757/ubuntu_kakaotalk.git
cd ubuntu_kakaotalk
./install.sh ~/Downloads/KakaoTalk_Setup.exe           # GUI 설치 마법사 클릭
# 또는 무인 설치
./install.sh ~/Downloads/KakaoTalk_Setup.exe --silent  # 설치 마법사가 내부 검사로 조기 종료하면 자동 추출 fallback
```

스크립트가 알아서 수행:

- i386 아키텍처 추가
- WineHQ 저장소 등록 + `winehq-stable` 설치
- Ubuntu 20.04의 `focal-updates` 누락 자동 복구 (없으면 의존성 깨짐)
- `winetricks` 최신 버전으로 업데이트 후 `win10 cjkfonts vcrun2019 corefonts` 설치
- 32비트 Wine prefix (`~/.wine_kakao`) 생성
- KakaoTalk 설치 (마법사 실패 시 7zip으로 직접 추출)
- `kakaotalk` 런처 (`~/.local/bin/kakaotalk`) 설치
- `.desktop` 엔트리 + 아이콘 (256x256, 22x22) 설치
- GNOME Dock 즐겨찾기 등록 (dconf 직접 쓰기)
- Argos 확장이 있으면 상단바 토글 스크립트 설치

## 사용

| 명령 | 동작 |
|---|---|
| `kakaotalk` | 실행. 이미 떠 있으면 창 포커스. 트레이로 숨겨진 상태면 검정 화면 방지용으로 자동 재시작 |
| `kakaotalk --restart` | 죽이고 새로 실행 (강제 재시작) |
| `kakaotalk --quit` | 완전 종료 |

Dock 아이콘과 Argos 상단바 아이콘도 동일한 런처를 씁니다.

## 설계 메모

### 왜 32비트인가

KakaoTalk 설치 프로그램은 32비트 NSIS wrapper이지만, 64비트 build는 내부에 64비트 `KakaoTalk.exe`를 들고 있어서 32비트 Wine prefix에서 "Bad EXE format"이 납니다. 반대로 32비트 build는 32비트 prefix에서 잘 돌고 리소스도 적게 씁니다.

### 설치 마법사가 조용히 종료될 때

GUI 마법사가 Windows 환경 검사에서 실패하면 아무 메시지 없이 종료하는데, 이 NSIS 패키지는 7zip으로 그대로 풀 수 있는 구조라서 스크립트가 fallback으로 `Program Files/Kakao/KakaoTalk/`에 직접 추출합니다.

### 트레이 아이콘과 검정 화면

Wine이 호스팅하는 `explorer.exe`가 시스템 트레이 역할로 160x20짜리 창을 띄우는데, 런처가 백그라운드 워처로 이걸 계속 `windowunmap` 처리합니다. 덕분에 화면은 깔끔하지만 카카오톡 X 버튼으로 "트레이로 숨김" 상태가 되면 다시 띄울 방법이 애매해집니다. 런처는 창이 `IsUnMapped` 상태일 때 복원 대신 자동 재시작으로 우회합니다 (로그인 데이터는 prefix에 남아 있어 재로그인 불필요).

### GNOME 즐겨찾기: `gsettings`가 아니라 `dconf`

Ubuntu GNOME 일부 세션에서 `gsettings get org.gnome.shell favorite-apps`가 schema default를 보여주는 반면 실제 dock은 `dconf read /org/gnome/shell/favorite-apps`의 값을 씁니다. 그래서 `dconf write`로 직접 덮어쓰는 쪽이 안정적입니다.

### 상단바 아이콘 (Argos)

[Argos 확장](https://extensions.gnome.org/extension/1176/argos/)이 설치돼 있으면 `~/.config/argos/kakaotalk.5s.sh`가 배치되어 시계 옆에 토글 아이콘이 뜹니다. 5초마다 KakaoTalk 프로세스 유무를 체크해 "실행 중/중지" 상태를 반영합니다.

## 제거

```bash
kakaotalk --quit
rm -rf ~/.wine_kakao
rm -f ~/.local/bin/kakaotalk
rm -f ~/.local/share/applications/kakaotalk.desktop
rm -f ~/.local/share/icons/hicolor/256x256/apps/kakaotalk.png
rm -f ~/.local/share/icons/hicolor/22x22/apps/kakaotalk.png
rm -f ~/.config/argos/kakaotalk.5s.sh
```

Dock 즐겨찾기에서 빼고 싶으면:

```bash
dconf write /org/gnome/shell/favorite-apps \
  "$(dconf read /org/gnome/shell/favorite-apps | sed "s/, 'kakaotalk.desktop'//")"
```

## 테스트 환경

- Ubuntu 20.04 LTS (focal)
- GNOME Shell + Argos 확장
- Wine 10.0 stable (WineHQ)
- KakaoTalk 26.3.1.5062 (32비트)

다른 버전에서도 동작할 가능성이 높지만 검증은 위 조합에서만 했습니다.
