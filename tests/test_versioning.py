"""Tests for shared package-version comparison semantics."""

import pytest

from notebooklm_tools.utils.versioning import is_newer_version


@pytest.mark.parametrize(
    ("current", "latest", "expected"),
    [
        ("1.0.0", "1.0.1", True),
        ("1.0.0", "1.0.0", False),
        ("1.0.0rc1", "1.0.0", True),
        ("1.0.0", "1.0.1rc1", True),
        ("1.0.1", "1.0.1rc1", False),
        ("1.0.0.dev1", "1.0.0", True),
        ("1.0.0+local", "1.0.0", False),
        ("1!1.0.0", "2.0.0", False),
        ("not-a-version", "1.0.0", False),
        ("1.0.0", "also-invalid", False),
    ],
)
def test_is_newer_version_uses_pep440(current, latest, expected):
    assert is_newer_version(current, latest) is expected
