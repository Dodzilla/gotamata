#!/usr/bin/env python3
"""KillaTamata Arcade creator submission client with swappable auth."""

from __future__ import annotations

import abc
import argparse
import json
import mimetypes
import os
import uuid
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib import error, request


JSON = dict[str, Any]
BUNDLE_MANIFEST_PATH = "arcade.release.json"


class SubmissionClientError(RuntimeError):
    """Raised when the creator API returns an error response."""


@dataclass(frozen=True)
class AuthDescription:
    mode: str
    configured: bool
    details: str


class AuthAdapter(abc.ABC):
    """Replaceable creator auth adapter."""

    @abc.abstractmethod
    def ensure_authenticated(self) -> None:
        raise NotImplementedError

    @abc.abstractmethod
    def authenticated_request(
        self,
        req: request.Request,
        *,
        timeout: float,
    ) -> request.addinfourl:
        raise NotImplementedError

    @abc.abstractmethod
    def describe_auth_state(self) -> AuthDescription:
        raise NotImplementedError


class HeaderAuthAdapter(AuthAdapter):
    """Simple header-based auth for development and token-backed flows."""

    def __init__(self, headers: dict[str, str]):
        self._headers = {key: value for key, value in headers.items() if value}

    @classmethod
    def from_environment(cls) -> "HeaderAuthAdapter":
        headers: dict[str, str] = {}
        token = os.getenv("KILLATAMATA_API_TOKEN", "").strip()
        if token:
            headers["Authorization"] = f"Bearer {token}"

        cookie = os.getenv("KILLATAMATA_COOKIE", "").strip()
        if cookie:
            headers["Cookie"] = cookie

        explicit_header = os.getenv("KILLATAMATA_AUTH_HEADER", "").strip()
        explicit_value = os.getenv("KILLATAMATA_AUTH_VALUE", "").strip()
        if explicit_header and explicit_value:
            headers[explicit_header] = explicit_value

        return cls(headers)

    def ensure_authenticated(self) -> None:
        if not self._headers:
            raise SubmissionClientError(
                "No creator auth configured. Set KILLATAMATA_API_TOKEN, "
                "KILLATAMATA_COOKIE, or KILLATAMATA_AUTH_HEADER/KILLATAMATA_AUTH_VALUE."
            )

    def authenticated_request(
        self,
        req: request.Request,
        *,
        timeout: float,
    ) -> request.addinfourl:
        self.ensure_authenticated()
        for key, value in self._headers.items():
            req.add_header(key, value)
        return request.urlopen(req, timeout=timeout)

    def describe_auth_state(self) -> AuthDescription:
        if not self._headers:
            return AuthDescription(
                mode="none",
                configured=False,
                details="No auth headers configured in the environment.",
            )
        redacted = ", ".join(sorted(self._headers.keys()))
        return AuthDescription(
            mode="header",
            configured=True,
            details=f"Configured request headers: {redacted}",
        )


class SubmissionClient:
    def __init__(self, base_url: str, auth: AuthAdapter, timeout: float = 30.0):
        if not base_url:
            raise SubmissionClientError("--base-url is required")
        self.base_url = base_url.rstrip("/")
        self.auth = auth
        self.timeout = timeout

    def describe_auth_state(self) -> JSON:
        state = self.auth.describe_auth_state()
        return {
            "mode": state.mode,
            "configured": state.configured,
            "details": state.details,
        }

    def list_my_games(self) -> JSON:
        return self._request_json("GET", "/api/v1/arcade/games/mine")

    def create_game(self, payload: JSON) -> JSON:
        return self._request_json("POST", "/api/v1/arcade/games", json_body=payload)

    def upload_release(
        self,
        *,
        game_id: str,
        manifest: JSON,
        bundle_path: Path,
        cover_image_path: Path | None = None,
    ) -> JSON:
        if not bundle_path.is_file():
            raise SubmissionClientError(f"Bundle not found: {bundle_path}")

        files = {
            "bundle": bundle_path,
        }
        if cover_image_path is not None:
            if not cover_image_path.is_file():
                raise SubmissionClientError(f"Cover image not found: {cover_image_path}")
            files["coverImage"] = cover_image_path

        fields = {
            "gameId": game_id,
            "manifestJson": json.dumps(manifest, separators=(",", ":")),
        }
        return self._request_multipart("/api/v1/arcade/releases/upload", fields, files)

    def submit_release(self, release_id: str) -> JSON:
        return self._request_json(
            "PATCH",
            "/api/v1/arcade/releases/submit",
            json_body={"releaseId": release_id},
        )

    def resolve_game(self, *, game_id: str = "", game_slug: str = "") -> JSON:
        if game_id:
            return {"gameId": game_id, "resolution": "explicit_id"}

        games_payload = self.list_my_games()
        games = self._extract_games(games_payload)
        if game_slug:
            for game in games:
                if str(game.get("slug", "")) == game_slug:
                    return {
                        "gameId": game.get("id"),
                        "game": game,
                        "resolution": "slug_lookup",
                    }
            raise SubmissionClientError(f"Could not find creator game with slug {game_slug!r}")

        raise SubmissionClientError("Either game_id or game_slug is required to resolve a game")

    def publish_new_game(
        self,
        *,
        metadata: JSON,
        manifest: JSON,
        bundle_path: Path,
        cover_image_path: Path | None = None,
    ) -> JSON:
        game_payload = {
            "slug": metadata["slug"],
            "title": metadata["title"],
            "shortDescription": metadata["shortDescription"],
            "description": metadata["description"],
            "tags": metadata.get("tags", []),
        }
        game_result = self.create_game(game_payload)
        game_id = self._extract_game_id(game_result)
        upload_result = self.upload_release(
            game_id=game_id,
            manifest=manifest,
            bundle_path=bundle_path,
            cover_image_path=cover_image_path,
        )
        release_id = self._extract_release_id(upload_result)
        submit_result = self.submit_release(release_id)
        return {
            "game": game_result,
            "upload": upload_result,
            "submit": submit_result,
            "gameId": game_id,
            "releaseId": release_id,
        }

    def publish_existing_game(
        self,
        *,
        manifest: JSON,
        bundle_path: Path,
        cover_image_path: Path | None = None,
        game_id: str = "",
        game_slug: str = "",
    ) -> JSON:
        resolved = self.resolve_game(game_id=game_id, game_slug=game_slug)
        resolved_game_id = str(resolved.get("gameId", "")).strip()
        upload_result = self.upload_release(
            game_id=resolved_game_id,
            manifest=manifest,
            bundle_path=bundle_path,
            cover_image_path=cover_image_path,
        )
        release_id = self._extract_release_id(upload_result)
        submit_result = self.submit_release(release_id)
        return {
            "resolvedGame": resolved,
            "upload": upload_result,
            "submit": submit_result,
            "gameId": resolved_game_id,
            "releaseId": release_id,
        }

    def _request_json(
        self,
        method: str,
        path: str,
        *,
        json_body: JSON | None = None,
    ) -> JSON:
        body: bytes | None = None
        headers = {"Accept": "application/json"}
        if json_body is not None:
            body = json.dumps(json_body).encode("utf-8")
            headers["Content-Type"] = "application/json"
        req = request.Request(
            self.base_url + path,
            data=body,
            method=method,
            headers=headers,
        )
        return self._open_json(req)

    def _request_multipart(
        self,
        path: str,
        fields: dict[str, str],
        files: dict[str, Path],
    ) -> JSON:
        boundary = f"codex-{uuid.uuid4().hex}"
        body = build_multipart_body(boundary, fields, files)
        req = request.Request(
            self.base_url + path,
            data=body,
            method="POST",
            headers={
                "Accept": "application/json",
                "Content-Type": f"multipart/form-data; boundary={boundary}",
                "Content-Length": str(len(body)),
            },
        )
        return self._open_json(req)

    def _open_json(self, req: request.Request) -> JSON:
        try:
            with self.auth.authenticated_request(req, timeout=self.timeout) as resp:
                payload = resp.read().decode("utf-8")
        except error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")
            raise SubmissionClientError(
                f"HTTP {exc.code} for {req.method} {req.full_url}: {detail}"
            ) from exc
        except error.URLError as exc:
            raise SubmissionClientError(f"Failed to reach {req.full_url}: {exc}") from exc

        try:
            decoded = json.loads(payload) if payload else {}
        except json.JSONDecodeError as exc:
            raise SubmissionClientError(
                f"Response from {req.full_url} was not valid JSON: {payload!r}"
            ) from exc
        if not isinstance(decoded, dict):
            raise SubmissionClientError(
                f"Expected object JSON response from {req.full_url}, got {type(decoded).__name__}"
            )
        return decoded

    @staticmethod
    def _extract_games(payload: JSON) -> list[JSON]:
        if isinstance(payload.get("games"), list):
            return [item for item in payload["games"] if isinstance(item, dict)]
        if isinstance(payload.get("result"), dict) and isinstance(payload["result"].get("games"), list):
            return [item for item in payload["result"]["games"] if isinstance(item, dict)]
        return []

    @staticmethod
    def _extract_game_id(payload: JSON) -> str:
        candidates = [
            payload.get("gameId"),
            payload.get("id"),
            payload.get("game", {}).get("id") if isinstance(payload.get("game"), dict) else None,
            payload.get("result", {}).get("gameId") if isinstance(payload.get("result"), dict) else None,
            payload.get("result", {}).get("id") if isinstance(payload.get("result"), dict) else None,
        ]
        for candidate in candidates:
            if candidate:
                return str(candidate)
        raise SubmissionClientError(f"Could not extract game id from response: {json.dumps(payload)}")

    @staticmethod
    def _extract_release_id(payload: JSON) -> str:
        candidates = [
            payload.get("releaseId"),
            payload.get("id"),
            payload.get("release", {}).get("id") if isinstance(payload.get("release"), dict) else None,
            payload.get("result", {}).get("releaseId") if isinstance(payload.get("result"), dict) else None,
            payload.get("result", {}).get("id") if isinstance(payload.get("result"), dict) else None,
        ]
        for candidate in candidates:
            if candidate:
                return str(candidate)
        raise SubmissionClientError(
            f"Could not extract release id from response: {json.dumps(payload)}"
        )


def build_multipart_body(
    boundary: str,
    fields: dict[str, str],
    files: dict[str, Path],
) -> bytes:
    parts: list[bytes] = []
    boundary_bytes = boundary.encode("utf-8")

    for key, value in fields.items():
        parts.extend(
            [
                b"--" + boundary_bytes + b"\r\n",
                f'Content-Disposition: form-data; name="{key}"\r\n\r\n'.encode("utf-8"),
                str(value).encode("utf-8"),
                b"\r\n",
            ]
        )

    for key, path in files.items():
        mime_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        payload = path.read_bytes()
        parts.extend(
            [
                b"--" + boundary_bytes + b"\r\n",
                (
                    f'Content-Disposition: form-data; name="{key}"; filename="{path.name}"\r\n'
                    f"Content-Type: {mime_type}\r\n\r\n"
                ).encode("utf-8"),
                payload,
                b"\r\n",
            ]
        )

    parts.append(b"--" + boundary_bytes + b"--\r\n")
    return b"".join(parts)


def load_json(path: Path) -> JSON:
    payload = json.loads(path.read_text())
    if not isinstance(payload, dict):
        raise SubmissionClientError(f"Expected JSON object in {path}")
    return payload


def read_bundle_manifest(bundle_path: Path) -> JSON:
    if not bundle_path.is_file():
        raise SubmissionClientError(f"Bundle not found: {bundle_path}")

    try:
        with zipfile.ZipFile(bundle_path) as archive:
            try:
                payload = archive.read(BUNDLE_MANIFEST_PATH)
            except KeyError as exc:
                raise SubmissionClientError(
                    f"Bundle must include {BUNDLE_MANIFEST_PATH} at the ZIP root: {bundle_path}"
                ) from exc
    except zipfile.BadZipFile as exc:
        raise SubmissionClientError(f"Bundle is not a valid ZIP archive: {bundle_path}") from exc

    try:
        decoded = json.loads(payload.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SubmissionClientError(
            f"Embedded bundle manifest is not valid JSON: {bundle_path}::{BUNDLE_MANIFEST_PATH}"
        ) from exc

    if not isinstance(decoded, dict):
        raise SubmissionClientError(
            f"Embedded bundle manifest must be a JSON object: {bundle_path}::{BUNDLE_MANIFEST_PATH}"
        )
    return decoded


def resolve_upload_manifest(bundle_path: Path, manifest_path: Path | None = None) -> JSON:
    bundle_manifest = read_bundle_manifest(bundle_path)
    if manifest_path is None:
        return bundle_manifest

    explicit_manifest = load_json(manifest_path)
    if explicit_manifest != bundle_manifest:
        raise SubmissionClientError(
            f"Manifest file does not match {BUNDLE_MANIFEST_PATH} embedded in the bundle: {manifest_path}"
        )
    return bundle_manifest


def metadata_from_manifest(manifest: JSON) -> JSON:
    return {
        "slug": str(manifest["gameSlug"]),
        "title": str(manifest["title"]),
        "shortDescription": str(manifest["shortDescription"]),
        "description": str(manifest["description"]),
        "tags": manifest.get("tags", []),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="KillaTamata Arcade creator submission client")
    parser.add_argument("--base-url", required=True, help="Creator API base URL, e.g. https://creator.example.com")
    parser.add_argument("--timeout", type=float, default=30.0, help="HTTP timeout in seconds")

    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("auth-state")
    subparsers.add_parser("list-games")

    create_game = subparsers.add_parser("create-game")
    create_game.add_argument("--metadata-file", required=True)

    upload = subparsers.add_parser("upload-release")
    upload.add_argument("--game-id", required=True)
    upload.add_argument("--manifest-file", help="Optional manifest JSON. If provided, it must match arcade.release.json inside the ZIP.")
    upload.add_argument("--bundle", required=True)
    upload.add_argument("--cover-image")

    submit = subparsers.add_parser("submit-release")
    submit.add_argument("--release-id", required=True)

    publish_new = subparsers.add_parser("publish-new")
    publish_new.add_argument("--metadata-file", help="Optional game metadata JSON. Defaults to fields derived from arcade.release.json in the ZIP.")
    publish_new.add_argument("--manifest-file", help="Optional manifest JSON. If provided, it must match arcade.release.json inside the ZIP.")
    publish_new.add_argument("--bundle", required=True)
    publish_new.add_argument("--cover-image")

    publish_existing = subparsers.add_parser("publish-existing")
    publish_existing.add_argument("--manifest-file", help="Optional manifest JSON. If provided, it must match arcade.release.json inside the ZIP.")
    publish_existing.add_argument("--bundle", required=True)
    publish_existing.add_argument("--cover-image")
    publish_existing.add_argument("--game-id", default="")
    publish_existing.add_argument("--game-slug", default="")

    return parser.parse_args()


def build_client(args: argparse.Namespace) -> SubmissionClient:
    return SubmissionClient(
        base_url=args.base_url,
        auth=HeaderAuthAdapter.from_environment(),
        timeout=args.timeout,
    )


def run_command(args: argparse.Namespace) -> JSON:
    client = build_client(args)

    if args.command == "auth-state":
        return client.describe_auth_state()
    if args.command == "list-games":
        return client.list_my_games()
    if args.command == "create-game":
        metadata = load_json(Path(args.metadata_file))
        return client.create_game(
            {
                "slug": metadata["slug"],
                "title": metadata["title"],
                "shortDescription": metadata["shortDescription"],
                "description": metadata["description"],
                "tags": metadata.get("tags", []),
            }
        )
    if args.command == "upload-release":
        bundle_path = Path(args.bundle)
        return client.upload_release(
            game_id=args.game_id,
            manifest=resolve_upload_manifest(bundle_path, Path(args.manifest_file) if args.manifest_file else None),
            bundle_path=bundle_path,
            cover_image_path=Path(args.cover_image) if args.cover_image else None,
        )
    if args.command == "submit-release":
        return client.submit_release(args.release_id)
    if args.command == "publish-new":
        bundle_path = Path(args.bundle)
        manifest = resolve_upload_manifest(bundle_path, Path(args.manifest_file) if args.manifest_file else None)
        return client.publish_new_game(
            metadata=load_json(Path(args.metadata_file)) if args.metadata_file else metadata_from_manifest(manifest),
            manifest=manifest,
            bundle_path=bundle_path,
            cover_image_path=Path(args.cover_image) if args.cover_image else None,
        )
    if args.command == "publish-existing":
        bundle_path = Path(args.bundle)
        manifest = resolve_upload_manifest(bundle_path, Path(args.manifest_file) if args.manifest_file else None)
        return client.publish_existing_game(
            manifest=manifest,
            bundle_path=bundle_path,
            cover_image_path=Path(args.cover_image) if args.cover_image else None,
            game_id=args.game_id,
            game_slug=args.game_slug or str(manifest.get("gameSlug", "")).strip(),
        )
    raise SubmissionClientError(f"Unsupported command {args.command!r}")


def main() -> int:
    args = parse_args()
    result = run_command(args)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except SubmissionClientError as exc:
        print(str(exc), file=os.sys.stderr)
        raise SystemExit(2) from exc
