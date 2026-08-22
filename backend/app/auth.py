from __future__ import annotations

import base64
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import asyncpg
import jwt
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi import HTTPException, status

from .config import settings
from .models import AccountChoice, LoginResponse, PrincipalContext

TOKEN_TTL_SECONDS = 900
KEY_ID = "telecom-demo-rs256-1"


def _b64url_uint(value: int) -> str:
    size = (value.bit_length() + 7) // 8
    return base64.urlsafe_b64encode(value.to_bytes(size, "big")).rstrip(b"=").decode()


class AuthService:
    def __init__(self) -> None:
        key_path = Path(settings.jwt_key_path)
        self._private_key = self._load_or_create_key(key_path)
        self._public_key = self._private_key.public_key()
        public_path = key_path.with_name("jwt-public.pem")
        public_path.write_bytes(
            self._public_key.public_bytes(
                encoding=serialization.Encoding.PEM,
                format=serialization.PublicFormat.SubjectPublicKeyInfo,
            )
        )
        public_path.chmod(0o644)

    @staticmethod
    def _load_or_create_key(path: Path) -> rsa.RSAPrivateKey:
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists():
            return serialization.load_pem_private_key(path.read_bytes(), password=None)
        key = rsa.generate_private_key(public_exponent=65537, key_size=3072)
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
        descriptor = os.open(path, flags, 0o600)
        try:
            with os.fdopen(descriptor, "wb") as handle:
                handle.write(
                    key.private_bytes(
                        encoding=serialization.Encoding.PEM,
                        format=serialization.PrivateFormat.PKCS8,
                        encryption_algorithm=serialization.NoEncryption(),
                    )
                )
        except Exception:
            path.unlink(missing_ok=True)
            raise
        return key

    def jwks(self) -> dict[str, Any]:
        numbers = self._public_key.public_numbers()
        return {
            "keys": [
                {
                    "kty": "RSA",
                    "use": "sig",
                    "kid": KEY_ID,
                    "alg": "RS256",
                    "n": _b64url_uint(numbers.n),
                    "e": _b64url_uint(numbers.e),
                }
            ]
        }

    def issue(self, row: asyncpg.Record) -> tuple[str, LoginResponse]:
        now = datetime.now(timezone.utc)
        claims = {
            "iss": settings.jwt_issuer,
            "aud": list(settings.jwt_audiences),
            "sub": str(row["principal_id"]),
            "tenant_id": str(row["account_id"]),
            "name": row["display_name"],
            "account_name": row["account_name"],
            "account_number": row["account_number"],
            "role": row["membership_role"],
            "scope": "synapsor.explore synapsor.plan",
            "iat": now,
            "nbf": now - timedelta(seconds=5),
            "exp": now + timedelta(seconds=TOKEN_TTL_SECONDS),
        }
        token = jwt.encode(claims, self._private_key, algorithm="RS256", headers={"kid": KEY_ID})
        response = LoginResponse(
            expires_in=TOKEN_TTL_SECONDS,
            principal_id=str(row["principal_id"]),
            display_name=row["display_name"],
            account=AccountChoice(
                account_id=str(row["account_id"]),
                account_number=row["account_number"],
                account_name=row["account_name"],
                membership_role=row["membership_role"],
            ),
        )
        return token, response

    def decode(self, token: str) -> PrincipalContext:
        try:
            claims = jwt.decode(
                token,
                self._public_key,
                algorithms=["RS256"],
                audience=list(settings.jwt_audiences),
                issuer=settings.jwt_issuer,
                options={"require": ["exp", "iat", "iss", "aud", "sub", "tenant_id"]},
            )
        except jwt.PyJWTError as exc:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or expired access token",
                headers={"WWW-Authenticate": "Bearer"},
            ) from exc
        return PrincipalContext(
            principal_id=claims["sub"],
            tenant_id=claims["tenant_id"],
            display_name=claims.get("name", "Customer"),
            account_name=claims.get("account_name", "Customer account"),
            membership_role=claims.get("role", "member"),
            raw_token=token,
        )


auth_service = AuthService()
