"""OpenAI-compatible ModelClient that honors ``OPENAI_BASE_URL``.

adalflow's stock ``OpenAIClient`` hardcodes ``base_url`` to
``https://api.openai.com/v1/`` and never reads the ``OPENAI_BASE_URL``
environment variable. That breaks custom / intranet / OpenAI-compatible
gateways (the exact use case DeepWiki supports via ``OPENAI_BASE_URL``).

This subclass reads ``OPENAI_BASE_URL`` (and ``OPENAI_API_KEY``) from the
environment when no explicit value is passed, so both chat generation and
embeddings can target an internal gateway without any code or JSON changes.
"""

import os

from adalflow.components.model_client.openai_client import (
    OpenAIClient as _AdalFlowOpenAIClient,
)

_DEFAULT_BASE_URL = "https://api.openai.com/v1/"


class OpenAIClient(_AdalFlowOpenAIClient):
    """OpenAIClient that falls back to OPENAI_BASE_URL / OPENAI_API_KEY env vars."""

    def __init__(self, api_key=None, base_url=None, **kwargs):
        super().__init__(
            api_key=api_key or os.environ.get("OPENAI_API_KEY"),
            base_url=base_url
            or os.environ.get("OPENAI_BASE_URL", _DEFAULT_BASE_URL),
            **kwargs,
        )
