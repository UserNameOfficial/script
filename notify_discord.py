"""Publish a verified Ragim Panel release to the Discord server.

Requires DISCORD_BOT_TOKEN. No third-party Python packages are needed.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path


REPOSITORY = "UserNameOfficial/script"
SCRIPT_NAME = "script.lua"
ANNOUNCEMENT_CHANNEL = "1556669586361811095"
SUMMARY_CHANNEL = "1556669525439549560"
LATEST_CHANNEL = "1556669016934973541"
API_ROOT = "https://discord.com/api/v10"


def release_url(commit: str) -> str:
    if not re.fullmatch(r"[0-9a-fA-F]{40}", commit):
        raise ValueError("배포 커밋은 40자리 Git SHA여야 합니다.")
    return f"https://raw.githubusercontent.com/{REPOSITORY}/{commit}/{SCRIPT_NAME}"


def make_payloads(commit: str, changes: list[str], date: str) -> tuple[str, str, str]:
    if not 1 <= len(changes) <= 3:
        raise ValueError("변경 내용은 1~3개 입력하세요.")
    if any(not item.strip() or "\n" in item for item in changes):
        raise ValueError("변경 내용은 비어 있지 않은 한 줄이어야 합니다.")
    datetime.strptime(date, "%Y-%m-%d")
    url = release_url(commit)
    announcement = (
        "@everyone Ragim Panel 업데이트\n"
        f"loadstring(game:HttpGet(\"{url}\"))()"
    )
    summary = "\n".join(f"{n}. {item.strip()}" for n, item in enumerate(changes, 1))
    channel_name = f"Lastest update: {date}"
    if len(announcement) > 2000 or len(summary) > 2000:
        raise ValueError("Discord 메시지 길이 제한을 초과했습니다.")
    return announcement, summary, channel_name


def changes_from_commit(commit: str) -> list[str]:
    message = subprocess.check_output(
        ["git", "show", "-s", "--format=%B", commit], text=True, encoding="utf-8"
    )
    lines = [line.strip() for line in message.splitlines() if line.strip()]
    bullets = [line[2:].strip() for line in lines[1:] if line.startswith(("- ", "* "))]
    return bullets[:3] if bullets else lines[:1]


def request(method: str, path: str, token: str, payload: dict | None = None):
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8") if payload else None
    for attempt in range(4):
        req = urllib.request.Request(
            API_ROOT + path,
            data=data,
            method=method,
            headers={
                "Authorization": f"Bot {token}",
                "Content-Type": "application/json",
                "User-Agent": "RagimPanelRelease/1.0",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=20) as response:
                body = response.read()
                return json.loads(body) if body else None
        except urllib.error.HTTPError as exc:
            if exc.code == 429 and attempt < 3:
                details = json.loads(exc.read() or b"{}")
                time.sleep(min(max(float(details.get("retry_after", 1)), 0.1), 60))
                continue
            details = exc.read().decode("utf-8", errors="replace")[:500]
            raise RuntimeError(f"Discord API {method} {path}: HTTP {exc.code}: {details}") from exc
    raise RuntimeError("Discord rate limit 재시도 횟수를 초과했습니다.")


def matching_message(channel: str, token: str, exact_content: str) -> dict | None:
    messages = request("GET", f"/channels/{channel}/messages?limit=100", token)
    return next((message for message in messages if message.get("content") == exact_content), None)


def verify_release(url: str, local_script: Path) -> None:
    expected = local_script.read_bytes()
    for attempt in range(5):
        try:
            with urllib.request.urlopen(url, timeout=30) as response:
                if response.read() == expected:
                    return
        except urllib.error.HTTPError as exc:
            if exc.code != 404:
                raise
        if attempt < 4:
            time.sleep(3)
    raise RuntimeError("GitHub Raw 배포본이 현재 script.lua와 일치하지 않습니다.")


def publish(commit: str, changes: list[str], date: str, token: str) -> None:
    announcement, summary, channel_name = make_payloads(commit, changes, date)
    verify_release(release_url(commit), Path(SCRIPT_NAME))

    # Read recent messages before posting so reruns do not ping everyone twice.
    announcement_message = matching_message(ANNOUNCEMENT_CHANNEL, token, announcement)
    if announcement_message is None:
        announcement_message = request(
            "POST",
            f"/channels/{ANNOUNCEMENT_CHANNEL}/messages",
            token,
            {"content": announcement, "allowed_mentions": {"parse": ["everyone"]}},
        )
        print("업데이트 공지 전송 완료")
    else:
        print("업데이트 공지가 이미 있어 건너뜀")

    summary_message = matching_message(SUMMARY_CHANNEL, token, summary)
    if summary_message is None or int(summary_message["id"]) < int(announcement_message["id"]):
        request(
            "POST",
            f"/channels/{SUMMARY_CHANNEL}/messages",
            token,
            {"content": summary, "allowed_mentions": {"parse": []}},
        )
        print("변경 내용 전송 완료")
    else:
        print("변경 내용이 이미 있어 건너뜀")

    channel = request("GET", f"/channels/{LATEST_CHANNEL}", token)
    if channel.get("name") != channel_name:
        request("PATCH", f"/channels/{LATEST_CHANNEL}", token, {"name": channel_name})
        print("최신 업데이트 채널 이름 변경 완료")
    else:
        print("최신 업데이트 채널 이름이 이미 최신 상태임")


def check_access(commit: str, token: str) -> None:
    verify_release(release_url(commit), Path(SCRIPT_NAME))
    channels = [request("GET", f"/channels/{channel_id}", token) for channel_id in (
        ANNOUNCEMENT_CHANNEL, SUMMARY_CHANNEL, LATEST_CHANNEL
    )]
    if any(str(channel.get("id")) != channel_id for channel, channel_id in zip(
        channels, (ANNOUNCEMENT_CHANNEL, SUMMARY_CHANNEL, LATEST_CHANNEL)
    )):
        raise RuntimeError("Discord 채널 ID가 예상과 다릅니다.")
    if len({channel.get("guild_id") for channel in channels}) != 1:
        raise RuntimeError("세 채널이 같은 Discord 서버에 속하지 않습니다.")
    for channel_id in (ANNOUNCEMENT_CHANNEL, SUMMARY_CHANNEL):
        request("GET", f"/channels/{channel_id}/messages?limit=1", token)
    print("Raw 배포본과 Discord 채널 읽기 권한 확인 완료")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--commit", required=True, help="배포된 Git commit SHA")
    parser.add_argument("--change", action="append", help="간략한 변경 내용 (최대 3개)")
    parser.add_argument("--from-commit", action="store_true", help="커밋 본문의 목록이나 제목을 변경 내용으로 사용")
    parser.add_argument("--date", default=datetime.now(timezone(timedelta(hours=9))).date().isoformat())
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--check", action="store_true", help="배포본과 채널 접근만 확인하고 전송하지 않음")
    args = parser.parse_args()
    try:
        if args.from_commit and args.change:
            raise ValueError("--from-commit과 --change는 함께 사용할 수 없습니다.")
        changes = changes_from_commit(args.commit) if args.from_commit else args.change or []
        announcement, summary, channel_name = make_payloads(args.commit, changes, args.date)
        if args.dry_run and args.check:
            raise ValueError("--dry-run과 --check는 함께 사용할 수 없습니다.")
        if args.dry_run:
            print(json.dumps({"announcement": announcement, "summary": summary, "channel_name": channel_name}, ensure_ascii=False, indent=2))
            return 0
        token = os.environ.get("DISCORD_BOT_TOKEN", "")
        if not token:
            raise RuntimeError("DISCORD_BOT_TOKEN 환경 변수가 없습니다.")
        if args.check:
            check_access(args.commit, token)
            return 0
        publish(args.commit, changes, args.date, token)
    except (OSError, RuntimeError, ValueError, subprocess.CalledProcessError) as exc:
        print(f"오류: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
