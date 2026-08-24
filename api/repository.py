import os
import shutil
import subprocess
from functools import wraps
from collections.abc import Callable
from urllib.parse import quote, urlparse, urlunparse

from git import Repo as GitRepo, GIT_OK, GitCommandError

from api.logger import get_logger
from api.utils import deepwiki_root

logger = get_logger(__name__)


# Never let git prompt interactively for credentials. In a headless container
# there is no /dev/tty, so a credential prompt would fail with the confusing
# "could not read Username for '<url>': No such device or address" instead of a
# clear auth error. With this set, git fails fast with "Authentication failed".
os.environ.setdefault("GIT_TERMINAL_PROMPT", "0")

CLONE_REPO_ROOT = os.path.join(deepwiki_root(), "repo")


def _exception_cleanup(func: Callable) -> Callable:
    @wraps(func)
    def wrapper(*args, **kwargs):
        try:
            return func(*args, **kwargs)
        except (subprocess.CalledProcessError, GitCommandError) as e:
            err_msg: str | bytes = e.stderr
            if isinstance(err_msg, bytes):
                err_msg = err_msg.decode("utf-8")
            token = kwargs.get("access_token", None)
            if token:
                token_mask = "***TOKEN***"
                err_msg = err_msg.replace(token, token_mask)
                encoded_token = quote(token, safe="")
                err_msg = err_msg.replace(encoded_token, token_mask)
            raise ValueError(err_msg)

    return wrapper


@_exception_cleanup
def _clone_from_gitlab(
    remote_url: str,
    local_path: str,
    *,
    access_token: str | None = None,
    **kwargs,
) -> GitRepo:
    if access_token:
        parsed = urlparse(remote_url)
        if ":" in access_token:
            # username:password (HTTP basic auth) for self-hosted/internal GitLab.
            username, password = access_token.split(":", 1)
            creds = f"{quote(username, safe='')}:{quote(password, safe='')}"
        else:
            # OAuth2 personal access token (gitlab.com cloud).
            creds = f"oauth2:{quote(access_token, safe='')}"

        remote_url = urlunparse(
            (
                parsed.scheme,
                f"{creds}@{parsed.netloc}",
                parsed.path,
                "",
                "",
                "",
            )
        )
    return GitRepo.clone_from(url=remote_url, to_path=local_path, **kwargs)


@_exception_cleanup
def _clone_from_github(
    remote_url: str,
    local_path: str,
    *,
    access_token: str | None = None,
    **kwargs,
) -> GitRepo:
    if access_token:
        parsed = urlparse(remote_url)
        if ":" in access_token:
            # username:password (HTTP basic auth) for enterprise/internal GitHub.
            username, password = access_token.split(":", 1)
            creds = f"{quote(username, safe='')}:{quote(password, safe='')}"
        else:
            # Personal access token used as the username.
            creds = quote(access_token, safe="")

        remote_url = urlunparse(
            (
                parsed.scheme,
                f"{creds}@{parsed.netloc}",
                parsed.path,
                "",
                "",
                "",
            )
        )
    return GitRepo.clone_from(url=remote_url, to_path=local_path, **kwargs)


@_exception_cleanup
def _clone_from_bitbucket(
    remote_url: str,
    local_path: str,
    *,
    access_token: str | None = None,
    **kwargs,
) -> GitRepo:
    if access_token:
        parsed = urlparse(remote_url)
        # Bitbucket has two token formats with different auth schemes:
        #   - HTTP access tokens (prefix "ATCTT") use x-bitbucket-api-token-auth
        #   - App passwords (deprecated, EOL June 2026) use x-token-auth
        # Detect by token prefix so existing app password users keep working.
        auth_scheme = (
            "x-bitbucket-api-token-auth"
            if access_token.startswith("ATCTT")
            else "x-token-auth"
        )
        access_token = quote(access_token, safe="")

        remote_url = urlunparse(
            (
                parsed.scheme,
                f"{auth_scheme}:{access_token}@{parsed.netloc}",
                parsed.path,
                "",
                "",
                "",
            )
        )
    return GitRepo.clone_from(url=remote_url, to_path=local_path, **kwargs)


@_exception_cleanup
def _checkout_from_svn(
    remote_url: str,
    local_path: str,
    *,
    access_token: str | None = None,
    **kwargs,
) -> None:
    """Checkout a Subversion (SVN) repository using the system ``svn`` CLI.

    SVN has no shallow-clone equivalent to git's ``--depth=1``, so this performs
    a full checkout. ``--non-interactive`` + ``--no-auth-cache`` keeps the
    process from hanging on credential prompts inside a headless/container env.

    SVN authenticates with a username/password rather than a PAT, so we reuse
    the request ``token`` field flexibly:

    * ``username:password`` -> split into SVN credentials
    * a bare password -> used with ``SVN_USERNAME`` (or a username embedded in
      the URL, e.g. ``svn+ssh://user@host/...``)
    """
    cmd = ["svn", "checkout", "--non-interactive", "--no-auth-cache"]

    username: str | None = None
    password: str | None = None
    if access_token:
        if ":" in access_token and not access_token.startswith(("http", "svn")):
            username, password = access_token.split(":", 1)
        else:
            password = access_token
    username = username or os.environ.get("SVN_USERNAME")
    password = password or os.environ.get("SVN_PASSWORD")
    if username:
        cmd += ["--username", username]
    if password:
        cmd += ["--password", password]

    cmd += [remote_url, local_path]
    subprocess.run(cmd, check=True, capture_output=True, text=True)


def _path_is_url(path: str) -> bool:
    """Check if the given path is a URL, or local path string.

    Parameters
    ----------
    path: str
        The path to be checked

    Returns
    -------
    bool. True if is a URL, False otherwise
    """
    try:
        result = urlparse(path)
        return result.scheme in {
            "http",
            "https",
            "ftp",
            "svn",
            "svn+ssh",
        } and bool(result.netloc)
    except Exception:
        return False


class Repo:
    def __init__(
        self,
        repo_url: str,
        repo_type: str | None,
        root_path: str = CLONE_REPO_ROOT,
        access_token: str | None = None,
    ):
        """

        Parameters
        ----------
        repo_url
        repo_type
        root_path
        access_token : str, optional
            The access token to use when cloning repository from a private git service.
        """
        self.repo_url = repo_url
        self.repo_type = repo_type

        os.makedirs(root_path, exist_ok=True)
        self.root_path = root_path
        self.access_token = access_token

    @property
    def name(self):
        return self._extract_repo_name(self.repo_url, repo_type=self.repo_type)

    @property
    def is_local(self) -> bool:
        return not _path_is_url(self.repo_url)

    @staticmethod
    def _extract_repo_name(repo_url: str, repo_type: str | None) -> str:
        if _path_is_url(repo_url):
            url_parts = repo_url.rstrip("/").split("/")
            if repo_type == "svn":
                # SVN repos don't follow the owner/repo convention and often
                # point at a subdirectory (e.g. .../project/trunk). Name the
                # checkout after the full host+path so two projects never
                # collide on a generic segment like "trunk".
                parsed = urlparse(repo_url)
                segments: list[str] = []
                if parsed.hostname:
                    segments.extend(parsed.hostname.split("."))
                segments.extend(seg for seg in parsed.path.split("/") if seg)
                repo_name = "_".join(segments).replace(".git", "")
            elif repo_type in ["github", "gitlab", "bitbucket"] and len(url_parts) >= 5:
                # GitHub URL format: https://github.com/owner/repo
                # GitLab URL format: https://gitlab.com/owner/repo or https://gitlab.com/group/subgroup/repo
                # Bitbucket URL format: https://bitbucket.org/owner/repo
                owner = url_parts[-2]
                repo = url_parts[-1].replace(".git", "")
                repo_name = f"{owner}_{repo}"
            else:
                repo_name = url_parts[-1].replace(".git", "")
        else:
            # This is a local repository
            repo_name = os.path.basename(repo_url)
        return repo_name

    def download(self, force: bool = False) -> None:
        if force or (not self.downloaded and not self.is_local):
            os.makedirs(self.save_path, exist_ok=True)

            if self.repo_type == "svn":
                if shutil.which("svn") is None:
                    raise RuntimeError("Missing `svn` in current environment")
                _checkout_from_svn(
                    remote_url=self.repo_url,
                    local_path=self.save_path,
                    access_token=self.access_token,
                )
            else:
                if not GIT_OK:
                    raise RuntimeError("Missing `git` in current environment")

                kwargs = {
                    "remote_url": self.repo_url,
                    "local_path": self.save_path,
                    "access_token": self.access_token,
                    "multi_options": ["--depth=1", "--single-branch"],
                }

                if self.repo_type == "github":
                    _clone_from_github(**kwargs)

                elif self.repo_type == "gitlab":
                    _clone_from_gitlab(**kwargs)

                elif self.repo_type == "bitbucket":
                    _clone_from_bitbucket(**kwargs)
                else:
                    raise NotImplementedError(f"Unknown repo type: {self.repo_type}")

            logger.info("Repository %s downloaded successfully", self.name)

    @property
    def save_path(self) -> str:
        if self.is_local:
            return self.repo_url
        return os.path.join(self.root_path, self.name)

    @property
    def downloaded(self) -> bool:
        return os.path.exists(self.save_path) and bool(os.listdir(self.save_path))

    def __repr__(self) -> str:
        return f"{self.repo_type}: {self.name}"
