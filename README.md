# Ragim Panel Discord 업데이트 공지

Ragim Panel의 [`script.lua`](https://github.com/UserNameOfficial/script/blob/main/script.lua)가 GitHub `main`에 배포되면 Discord에 공지를 보냅니다. Raw URL의 내용이 해당 커밋의 `script.lua`와 일치할 때만 발송합니다.

- `1556669586361811095`: `@everyone`과 해당 커밋에 고정된 loadstring 실행 코드
- `1556669525439549560`: 변경 내용 1~3줄 번호 목록
- `1556669016934973541`: `Lastest update: YYYY-MM-DD` (한국 시간)

## 설치

`notify_discord.py`와 `.github/workflows/notify-discord.yml`을 `UserNameOfficial/script` 저장소의 `main`에 추가합니다. GitHub 저장소의 **Settings → Secrets and variables → Actions → New repository secret**에서 이름이 `DISCORD_BOT_TOKEN`인 비밀값을 등록합니다. 토큰을 코드, 커밋 메시지, 채팅 또는 로그에 넣지 않습니다.

이후 `script.lua`를 변경해 `main`에 푸시하면 Actions가 실행됩니다. 커밋 본문에 다음처럼 최대 세 줄의 변경 내용을 쓰면 그대로 요약 채널에 보냅니다. 목록이 없으면 커밋 제목 한 줄을 사용합니다.

```text
Add Design sound controls

- /soundcustom 추가
- 재생 기록에서 사운드 선택 가능
- 교체한 Sound ID 복원 기능
```

디스코드 봇에는 대상 채널의 메시지 보기·보내기·기록 보기, `@everyone` 멘션, 채널 관리 권한이 필요합니다. 관리자로 초대된 봇이면 일반적으로 충족합니다.

## 수동 실행 및 미리 보기

배포 저장소에서 실행합니다.

```powershell
python notify_discord.py --commit <40자리 커밋 SHA> --change "첫 변경" --change "두 번째 변경" --dry-run
```

실제 전송에서는 `--dry-run`을 빼고 `DISCORD_BOT_TOKEN` 환경 변수를 설정합니다. GitHub Actions에서는 저장소 비밀값을 환경 변수로 제공합니다. 재실행 시 최근 공지와 요약을 확인해 중복 발송을 줄입니다.
