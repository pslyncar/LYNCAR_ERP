import unittest
from unittest.mock import patch

import jwt

from app.core.security import create_access_token, decode_access_token


class TokenClaimsTest(unittest.TestCase):
    @patch("app.core.security.get_settings")
    def test_new_access_tokens_have_issuer_audience_and_jti(self, get_settings) -> None:
        settings = get_settings.return_value
        settings.secret_key = "test-secret"
        settings.access_token_expire_minutes = 60
        settings.jwt_issuer = "lyncar-api"
        settings.jwt_audience = "lyncar-clients"

        token = create_access_token("7")
        payload = decode_access_token(token)

        self.assertEqual(payload["iss"], "lyncar-api")
        self.assertEqual(payload["aud"], "lyncar-clients")
        self.assertTrue(payload["jti"])

    @patch("app.core.security.get_settings")
    def test_wrong_audience_is_rejected(self, get_settings) -> None:
        settings = get_settings.return_value
        settings.secret_key = "test-secret"
        settings.jwt_issuer = "lyncar-api"
        settings.jwt_audience = "lyncar-clients"
        token = jwt.encode(
            {
                "sub": "7",
                "type": "access",
                "iss": "lyncar-api",
                "aud": "another-service",
            },
            "test-secret",
            algorithm="HS256",
        )

        with self.assertRaises(jwt.InvalidTokenError):
            decode_access_token(token)


if __name__ == "__main__":
    unittest.main()
