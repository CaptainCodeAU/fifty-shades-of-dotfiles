"""Shared vulnerability-lookup library for toolchain-cve-check and vuln-scan.

WHY THIS EXISTS
    Both tools ask NVD "is <package> <version> vulnerable?" and both must answer
    UNKNOWN rather than "clean" whenever they cannot actually tell. Two copies of
    that logic would drift, and the half that drifted would be the one quietly
    reporting a false all-clear.

    toolchain-cve-check -- ad-hoc, prints everything, no state.
    vuln-scan           -- incremental, SQLite-backed, built for shell startup.

    STATUS: vuln-scan uses this module. toolchain-cve-check still carries its own
    copy of the NVD/CPE/brew code, so RIGHT NOW THE DUPLICATION IS REAL and a fix
    applied to one will not reach the other. Collapsing toolchain-cve-check onto
    this module is deliberately a separate change with its own verification pass,
    because that file is load-bearing in the SessionStart hook and the five
    behavioural controls (positive, negative, false-all-clear, false-positive,
    version-suffix) are what make such a refactor safe to attempt.
    Until then: a change here must be mirrored there, or the drift begins.

THE FALSE ALL-CLEAR (the failure mode neither tool may ever have)
    Four ways an NVD answer silently lies, all measured 2026-08-03:
      1. an unknown CPE returns 0 CVEs, byte-identical to a clean package
      2. past the rate limit NVD returns an EMPTY BODY, which parses as 0
      3. `vulnerable: false` context matches count as hits if you trust totalResults
      4. Homebrew version suffixes (`1.11.1_3`, `openssl@3`) match no CPE at all
    Each is closed below. A tool that is trusted and silently wrong is worse than
    no tool, so every uncertain path returns None and every None becomes UNKNOWN.

ZERO DEPENDENCIES -- pure stdlib (urllib, sqlite3, subprocess).
"""

import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

# --------------------------------------------------------------------------- #
#  NVD                                                                        #
# --------------------------------------------------------------------------- #
# OSV cannot answer for Homebrew: its `Homebrew` ecosystem is accepted but EMPTY,
# and OSV name-only queries were measured wrong in BOTH directions (a false
# positive on libssh 0.11.1, then zero on every known-vulnerable control, then an
# outright error). NVD 2.0 by CPE is authoritative and honours version ranges.
NVD_CVE_URL = "https://services.nvd.nist.gov/rest/json/cves/2.0"
NVD_CPE_URL = "https://services.nvd.nist.gov/rest/json/cpes/2.0"

# OVERRIDES ONLY -- not the coverage mechanism. NvdClient.resolve_cpe discovers the
# vendor for almost everything. This map is for the cases resolution CANNOT reach:
# where the upstream CPE PRODUCT is not the formula name, which is the one
# assumption the resolver makes. Every entry was confirmed against the CPE
# dictionary, never guessed; the bracketed number is its CPE record count.
FORMULA_CPE = {
    "gh": ("github", "cli"),                            # product is "cli"
    "node": ("nodejs", "node.js"),                      # product is "node.js"
    "docker-compose": ("docker", "compose"),
    "nginx": ("f5", "nginx"),                           # f5 and nginx both publish
    "curl": ("haxx", "curl"),                           # haxx is where the CVEs land
    "git": ("git-scm", "git"),
    "webp": ("webmproject", "libwebp"),                 # [39]
    "krb5": ("mit", "kerberos_5"),                      # [141]
    "libnghttp2": ("nghttp2", "nghttp2"),               # [134]
    "jpeg-turbo": ("libjpeg-turbo", "libjpeg-turbo"),   # [50]
    "little-cms2": ("littlecms", "little_cms"),         # [64]
    "zstd": ("facebook", "zstandard"),                  # [67]
}

# Products genuinely absent from NVD's dictionary and always will be. Listing one
# converts a permanent UNKNOWN into an explicit, intentional SKIP so the real
# unknowns stay visible. Add only after confirming absence, never to silence a hit.
CPE_ABSENT_OK = set()

# NAMESAKE COLLISIONS -- the resolver's one failure mode that yields a FALSE
# POSITIVE rather than an UNKNOWN. "Vendor with the most CPE records wins" cannot
# tell a namesake from the real upstream. Caught in the wild 2026-08-03: Homebrew
# `lux` is a video downloader at 0.24.1; NVD's only `lux` is luxcore:lux, a
# cryptocurrency whose CVE-2018-19159 covers "through 5.2.2" -- so 0.24.1 fell
# inside a range belonging to software that is not installed.
# Listed formulae report UNKNOWN: never clean, never exposed.
CPE_NAMESAKE_BLOCK = {
    "lux": "NVD's luxcore:lux is a cryptocurrency; brew's lux is a video downloader",
}


NVD_KEY_FILE = "~/.config/dotfiles/nvd-api-key"


def nvd_api_key():
    """The NVD key, from the first source that has it, else None.

      1. $NVD_API_KEY          -- exported by _claude_launch, or ~/.zshrc.private
      2. ~/.config/dotfiles/nvd-api-key   -- the portable path (Linux/WSL)
      3. macOS Keychain `nvd-api-key`     -- the Mac path, no file on disk

    Three sources rather than one because the Mac has a Keychain and Linux does
    not, and a Linux box silently falling back to anonymous means a 231-package
    sweep takes 20 minutes instead of 4 -- slow enough that the tool gets
    disabled, which is the real failure.

    NOT a credential: it authorises nothing and only lifts the anonymous
    5 req/30s limit to 50. A miss is a slowdown, never a wrong answer, which is
    why every lookup here fails quietly to None."""
    env = (os.environ.get("NVD_API_KEY") or "").strip()
    if env:
        return env

    path = os.path.expanduser(NVD_KEY_FILE)
    try:
        with open(path, "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                # Tolerate `NVD_API_KEY=...` as well as a bare key, because both
                # are what someone actually types into a file called this.
                if not line or line.startswith("#"):
                    continue
                return line.split("=", 1)[1].strip().strip("'\"") if "=" in line else line
    except OSError:
        pass

    if sys.platform != "darwin" or not shutil.which("security"):
        return None
    try:
        proc = subprocess.run(
            ["security", "find-generic-password", "-a", os.environ.get("USER", ""),
             "-s", "nvd-api-key", "-w"],
            capture_output=True, text=True, timeout=6)
        out = proc.stdout.strip()
        return out if proc.returncode == 0 and out else None
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return None


def state_dir():
    """Durable state (the scan database). XDG_STATE_HOME, else ~/.local/state."""
    base = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return _ensure(os.path.join(base, "dotfiles"))


def cache_dir():
    """Discardable cache (CPE resolutions, verdict text)."""
    base = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return _ensure(os.path.join(base, "dotfiles", "nvd"))


def _ensure(path):
    try:
        os.makedirs(path, exist_ok=True)
    except OSError:
        return None
    return path


def _unbounded(match: dict) -> bool:
    """True when an NVD cpeMatch carries no version bounds at all: criteria version
    is `*` and no versionStart*/versionEnd* is set. NVD's way of saying "all
    versions", which in practice means there is no fixed release to upgrade to."""
    if any(match.get(k) for k in ("versionStartIncluding", "versionStartExcluding",
                                  "versionEndIncluding", "versionEndExcluding")):
        return False
    parts = (match.get("criteria") or "").split(":")
    return len(parts) > 5 and parts[5] == "*"


class NvdClient:
    """Throttled NVD reader.

    THE RATE LIMIT IS A CORRECTNESS PROBLEM, NOT A SPEED ONE. Past the cap NVD
    returns an EMPTY BODY rather than an HTTP error, so a naive
    `.get("totalResults", 0)` reads a throttle as "0 CVEs" -- a false all-clear.
    Every fetch returns None on any doubt, and None propagates as UNKNOWN."""

    def __init__(self, api_key, timeout=25.0):
        self.api_key = api_key
        self.timeout = timeout
        # NVD publishes 5 req/30s anonymous, 50 with a key. Leave headroom: a burst
        # that trips the limit costs far more than the pause it saves.
        self.delay = 0.72 if api_key else 6.5
        self._last = 0.0
        self.requests = 0
        self.failures = 0

    def _get(self, url, params):
        wait = self.delay - (time.monotonic() - self._last)
        if wait > 0:
            time.sleep(wait)
        full = url + "?" + urllib.parse.urlencode(params, safe=":*-")
        headers = {"User-Agent": "dotfiles-vuln-scan"}
        if self.api_key:
            headers["apiKey"] = self.api_key
        req = urllib.request.Request(full, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as r:
                raw = r.read().decode("utf-8")
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, OSError):
            self._last = time.monotonic()
            self.requests += 1
            self.failures += 1
            return None
        self._last = time.monotonic()
        self.requests += 1
        if not raw.strip():
            self.failures += 1          # empty body == throttled. NOT zero results.
            return None
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            self.failures += 1
            return None
        if "totalResults" not in data:
            self.failures += 1
            return None
        return data

    def resolve_cpe(self, name):
        """(vendor, product) / False (no such product) / None (undetermined).

        Guessing vendor == product is right often enough to look like it works and
        wrong often enough to be useless: measured, it left 177 of 231 formulae
        UNVERIFIED, because upstream publishes as gnu:coreutils, thekelleys:dnsmasq,
        cairographics:cairo, gnome:glib. Instead ask the CPE dictionary who
        publishes this product, using a WILDCARD-VENDOR match string that filters
        server-side on an exact product match, then take the vendor with the most
        records (upstream always dwarfs a coincidental namesake).

        `keywordSearch` was tried first and rejected: it matches descriptions too,
        so short names drown -- `go` returned 200 unrelated products and resolved to
        nothing, silently losing coverage on a CVE-heavy toolchain.

        A successful resolution PROVES the product exists, which is what licenses
        reading 0 CVEs as clean. A hard 0 here is final: nothing is published under
        that product name (zstd, webp, krb5, htop are genuinely absent)."""
        cpe = f"cpe:2.3:a:*:{name}:*:*:*:*:*:*:*:*"
        data = self._get(NVD_CPE_URL, {"cpeMatchString": cpe, "resultsPerPage": 200})
        if data is None:
            return None
        tally = {}
        for entry in (data.get("products") or []):
            c = entry.get("cpe") or {}
            if c.get("deprecated"):
                continue
            parts = (c.get("cpeName") or "").split(":")
            if len(parts) > 5 and parts[2] == "a" and parts[4] == name:
                tally[parts[3]] = tally.get(parts[3], 0) + 1
        if not tally:
            return False
        return (max(tally.items(), key=lambda kv: kv[1])[0], name)

    def cves_for(self, vendor, product, version):
        """(hits, truncated) | None.  hits = [{"id", "unbounded", "fix_commit"}]

        A cpeName query returns every CVE whose configuration MENTIONS this CPE,
        including as non-vulnerable context -- NVD marks that `"vulnerable": false`.
        Ignoring the flag produces confident nonsense: gnutls 3.8.13 (2025) matched
        CVE-2009-1390, a Mutt bug that merely lists gnutls as the TLS library.

        `fix_commit` is the commit hash named in the CVE description when there is
        one ("fixed in commit a2ed82d"). It is what lets a caller notice that a
        distro has already backported the fix -- see homebrew_patch_commits."""
        cpe = f"cpe:2.3:a:{vendor}:{product}:{version}:*:*:*:*:*:*:*"
        data = self._get(NVD_CVE_URL, {"cpeName": cpe, "resultsPerPage": 200})
        if data is None:
            return None
        marker = f":{vendor}:{product}:"
        hits, vulns = [], (data.get("vulnerabilities") or [])
        for v in vulns:
            cve = v.get("cve") or {}
            cid = cve.get("id")
            if not cid:
                continue
            applicable = [m
                          for c in (cve.get("configurations") or [])
                          for n in (c.get("nodes") or [])
                          for m in (n.get("cpeMatch") or [])
                          if marker in (m.get("criteria") or "") and m.get("vulnerable")]
            if not applicable:
                continue
            desc = next((d.get("value", "") for d in cve.get("descriptions", [])
                         if d.get("lang") == "en"), "")
            score, severity = _cvss(cve)
            hits.append({
                "id": cid,
                "unbounded": all(_unbounded(m) for m in applicable),
                "fix_commit": _fix_commit(desc),
                "score": score,
                "severity": severity,
                "description": desc[:400],
            })
        return (hits, int(data.get("totalResults") or 0) > len(vulns))


def _cvss(cve: dict):
    """(base_score, severity). Prefers v4.0, then v3.1, then v3.0. CVEs awaiting
    analysis carry no metrics at all -- those return (None, "UNRATED") rather than
    a fabricated 0.0, because an unscored CVE is not a harmless one."""
    m = cve.get("metrics") or {}
    for key in ("cvssMetricV40", "cvssMetricV31", "cvssMetricV30"):
        entries = m.get(key)
        if entries:
            d = entries[0].get("cvssData") or {}
            return (d.get("baseScore"), (d.get("baseSeverity") or "UNRATED").upper())
    return (None, "UNRATED")


_FIX_COMMIT_RE = re.compile(r"\bcommit\s+([0-9a-f]{7,40})\b", re.IGNORECASE)


def _fix_commit(description: str):
    m = _FIX_COMMIT_RE.search(description or "")
    return m.group(1).lower() if m else None


# --------------------------------------------------------------------------- #
#  Homebrew                                                                    #
# --------------------------------------------------------------------------- #
def brew_version_for_cpe(v: str) -> str:
    """Homebrew appends a bottle-revision suffix upstream has never heard of
    (`libssh2 1.11.1_3`); it must be stripped or the CPE matches nothing and the
    formula reads as clean. Also drops an epoch prefix (`2:1.2.3`)."""
    v = (v or "").strip()
    if ":" in v:
        v = v.split(":", 1)[1]
    return re.sub(r"_\d+$", "", v)


def brew_revision(v: str) -> int:
    """The `_N` Homebrew revision, or 0. This is NOT cosmetic: a revision bump is
    how Homebrew ships backported security patches while keeping the upstream
    version string, so it belongs in any cache key -- see homebrew_patch_commits."""
    m = re.search(r"_(\d+)$", (v or "").strip())
    return int(m.group(1)) if m else 0


def formula_key(formula: str) -> str:
    """The name to look up upstream. Tap-qualified names reduce to their leaf and
    Homebrew's versioned-formula suffix is dropped (`openssl@3` -> `openssl`): the
    @N is packaging convention that upstream CPEs know nothing about."""
    leaf = formula.rsplit("/", 1)[-1]
    return leaf.split("@", 1)[0] or leaf


def brew_formulae():
    """[(formula, raw_version)] for everything installed, or None if brew absent."""
    if not shutil.which("brew"):
        return None
    try:
        proc = subprocess.run(["brew", "list", "--formula", "--versions"],
                              capture_output=True, text=True, timeout=120)
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return None
    if proc.returncode != 0:
        return None
    out = []
    for line in proc.stdout.splitlines():
        parts = line.split()
        if len(parts) >= 2:
            # Several versions can be kegged at once; the LAST is current.
            out.append((parts[0], parts[-1]))
    return out


_PATCH_COMMIT_RE = re.compile(r"(https://[^\s\"']*?/commit/([0-9a-f]{40}))")
_RESOLVES_CVE_RE = re.compile(
    r"^[ \t]*resolves[ \t]+[\"'](CVE-\d{4}-\d{4,})[\"']", re.MULTILINE)
_END_RE = re.compile(r"^end\b")
# Only a comment that ATTRIBUTES the patch counts as naming its commit. Measured
# 2026-09-04 over 231 installed kegs: 12 comment lines cite a commit, and the
# convention splits them exactly 6/6. The 6 `Backport of <url>` lines are all
# libssh2 naming the upstream commit its vendored `file` patch carries -- the only
# place that hash appears. The other 6 are explanatory prose citing a commit in a
# DIFFERENT project (ansible's comment links pyca/bcrypt; also x264, gnulib, zstd,
# ollama, LuaJIT). Crediting those to the formula records a patch it never applied.
_BACKPORT_OF_RE = re.compile(r"backport of\b", re.IGNORECASE)
_DO_BLOCK_RE = re.compile(r"^(\w+)\b.*?\bdo\b(?:[ \t]*\|[^|]*\|)?[ \t]*$")
_KEYWORD_BLOCK_RE = re.compile(r"^(if|unless|case|begin|def|class|module|while|until)\b")

# Blocks that do NOT narrow which build a patch belongs to. `class`/`module` are
# just the formula file's own frame -- every patch is inside one, and omitting
# them here silently stopped top-level patches from being detected at all, which
# is the regression this module's selftest was written to catch. `stable do` is
# the spec actually built when we scan an installed keg.
#
# Everything else DOES narrow it -- `head do`, `on_linux do`, `on_intel do`, an
# `if` guard, or a `resource "x" do` (which patches a VENDORED dependency, not
# this formula) -- so a `resolves` under one of those is not trusted. Fail toward
# reporting the CVE: a false alarm costs a minute, a false all-clear costs the
# whole point of the tool.
_APPLIES_ANYWAY = frozenset({"class", "module", "stable"})

_FORMULA_CACHE = {}   # formula -> (text|None, "keg"|"tap"|None)
# Keyed on the formula TEXT, not its name. Both per-hit callers land on
# homebrew_patch_blocks -- homebrew_resolved_cves and unclaimed_patches -- so a
# formula with several CVE hits re-walks identical source once per hit (measured
# 2026-09-04: 19 parses for 8 formulae on a full scan). Keying on the text rather
# than the name means a re-read, or a test fixture swapped in under the same
# name, gets a fresh parse instead of a stale one.
_BLOCKS_CACHE = {}


def _commits_in(text: str):
    """{sha: url} for every upstream commit URL in `text`.  One canonicalisation
    of "lowercase the hash, strip the .patch suffix", used by every caller."""
    return {sha.lower(): url.split(".patch")[0]
            for url, sha in _PATCH_COMMIT_RE.findall(text)}


def _read_keg_formula(formula: str):
    """The formula Ruby that Homebrew copied INTO the keg at install time, or None."""
    leaf = formula.rsplit("/", 1)[-1]
    # `HOMEBREW_PREFIX` first: it is set by `brew shellenv` and answers directly,
    # so the PATH walk in shutil.which() is only paid when it is absent.
    # dirname twice, WITHOUT realpath: `<prefix>/bin/brew` is itself a symlink into
    # `<prefix>/Homebrew/bin/`, so resolving it would land two levels too deep.
    prefix = os.environ.get("HOMEBREW_PREFIX")
    if not prefix:
        brew = shutil.which("brew")
        prefix = os.path.dirname(os.path.dirname(brew)) if brew else None
    if not prefix:
        return None
    brew_dir = os.path.join(prefix, "opt", leaf, ".brew")

    def read(path):
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as fh:
                return fh.read()
        except OSError:
            return None

    text = read(os.path.join(brew_dir, leaf + ".rb"))
    if text is not None:
        return text
    # An alias keg holds the real formula under its canonical name: `opt/openssl`
    # contains `openssl@3.rb`, `opt/python3` contains `python@3.14.rb`, `opt/rg`
    # contains `ripgrep.rb` (43 of 274 opt entries on this machine are aliases).
    # Only when there is exactly ONE candidate -- more than that is ambiguous, and
    # guessing here would answer about the wrong package. Without this the alias
    # falls through to `brew cat`, whose tap text is refused for suppression, so
    # the answer would silently weaken for a keg whose formula was sitting there.
    try:
        found = [f for f in os.listdir(brew_dir) if f.endswith(".rb")]
    except OSError:
        return None
    return read(os.path.join(brew_dir, found[0])) if len(found) == 1 else None


def _formula(formula: str):
    """(ruby_text, source) where source is "keg", "tap" or None.  Memoised.

    THE SOURCE IS PART OF THE ANSWER, not bookkeeping. The keg's own copy is what
    was actually built and installed. `brew cat` prints whatever the tap holds
    RIGHT NOW, which after any `brew update` can be a newer revision carrying
    patches this machine does not have. Crediting those to the installed build is
    a FALSE ALL-CLEAR, so callers that suppress a finding must check the source
    and refuse to act on "tap" -- see homebrew_resolved_cves.

    A transient `brew cat` failure is deliberately NOT memoised. Caching None
    there would turn one timeout into "this formula has no patches" for the rest
    of the run, and vuln-scan would persist that verdict to SQLite."""
    if formula in _FORMULA_CACHE:
        return _FORMULA_CACHE[formula]

    text = _read_keg_formula(formula)
    if text is not None:
        result = (text, "keg")
    else:
        brew = shutil.which("brew")
        if not brew:
            result = (None, None)
        else:
            try:
                proc = subprocess.run([brew, "cat", "--formula", formula],
                                      capture_output=True, text=True, timeout=30)
            except (subprocess.TimeoutExpired, OSError):
                return (None, None)   # transient: the ONE path that does not cache
            result = (proc.stdout, "tap") if proc.returncode == 0 else (None, None)
    _FORMULA_CACHE[formula] = result
    return result


def formula_text(formula: str):
    """The installed formula's Ruby source, or None.  See `_formula`."""
    return _formula(formula)[0]


def formula_source(formula: str):
    """"keg", "tap" or None -- WHERE the text came from.  Named rather than reached
    by index because the one line that must consult it decides whether a CVE is
    allowed to be silenced; see `homebrew_resolved_cves`."""
    return _formula(formula)[1]


def _block_label(stripped: str):
    """The kind of Ruby block this line opens, or None."""
    m = _DO_BLOCK_RE.match(stripped) or _KEYWORD_BLOCK_RE.match(stripped)
    return m.group(1) if m else None


def _parse_patch_blocks(text: str):
    """[(ancestors, header, body)] for every `patch do` in the formula.

    `header` is the comment run directly above the patch, kept SEPARATE from the
    body because prose is not evidence -- see `_BACKPORT_OF_RE`.

    Line-based with an explicit block stack rather than one regex, because WHAT
    ENCLOSES A PATCH DECIDES WHETHER IT APPLIES HERE and a regex cannot see that.
    Measured 2026-09-04 across 231 installed formulae: 6 kegs already nest
    `patch do` one level down -- llvm, libzen and ollama inside `stable do` (which
    does apply), ansible inside `resource "passlib" do` (which patches a vendored
    dependency, not ansible). A platform guard such as `on_linux do` would be the
    same class and would be crediting a Linux-only patch to a macOS build.

    The comment run directly above a patch is included in the returned source,
    because a patch applied from a vendored file names its upstream commit ONLY
    there:

        # Backport of https://github.com/libssh2/libssh2/commit/3449752...
        patch do
          file "Patches/libssh2/CVE-2026-58050.patch"
          resolves "CVE-2026-58050"
        end
    """
    lines = text.splitlines(keepends=True)
    stack, out, open_patch, comment_start = [], [], None, None
    for i, raw in enumerate(lines):
        s = raw.strip()
        if not s:
            comment_start = None
            continue
        if s.startswith("#"):
            if comment_start is None:
                comment_start = i
            continue
        if _END_RE.match(s):
            if stack:
                stack.pop()
                if open_patch is not None and len(stack) == len(open_patch[0]):
                    anc, hstart, bstart = open_patch
                    out.append((anc, "".join(lines[hstart:bstart]),
                                "".join(lines[bstart:i + 1])))
                    open_patch = None
            comment_start = None
            continue
        label = _block_label(s)
        if label is not None:
            if label == "patch" and open_patch is None:
                start = comment_start if comment_start is not None else i
                open_patch = (tuple(stack), start, i)
            stack.append(label)
        comment_start = None
    return out


def homebrew_patch_blocks(formula: str):
    """[{"ancestors", "applies", "commits", "cves"}] per `patch do`, or None.

    `applies` is False when the patch sits inside a block that may not have been
    built here; such a block's `resolves` must not suppress anything."""
    text = formula_text(formula)
    if text is None:
        return None
    if text in _BLOCKS_CACHE:
        return _BLOCKS_CACHE[text]
    blocks = []
    for ancestors, header, body in _parse_patch_blocks(text):
        commits = _commits_in(body)
        for line in header.splitlines():
            if _BACKPORT_OF_RE.search(line):
                for sha, url in _commits_in(line).items():
                    commits.setdefault(sha, url)
        blocks.append({
            "ancestors": ancestors,
            "applies": all(a in _APPLIES_ANYWAY for a in ancestors),
            "commits": commits,
            "cves": {c.upper() for c in _RESOLVES_CVE_RE.findall(body)},
        })
    _BLOCKS_CACHE[text] = blocks
    return blocks


def homebrew_patch_commits(formula: str):
    """{commit_sha: patch_url} for patches applied to the installed formula, or None.

    The URL is kept, not just the hash, so a report can link straight to the real
    upstream commit instead of asking the reader to go and find it.

    THIS IS WHAT STOPS THE WORST FALSE POSITIVE THIS TOOL CAN PRODUCE.
    Homebrew backports security fixes as a REVISION bump while keeping the
    upstream version string, so NVD -- which knows nothing about Homebrew
    revisions -- keeps reporting the package vulnerable after it has been fixed.
    Measured 2026-08-03: libssh2 1.11.1_4 carries 10 upstream patches, and 6 of
    the 9 CVEs NVD reports against 1.11.1 name a fix commit that is one of them.
    Telling someone to upgrade a package they just upgraded is how a security
    alert stops being read.

    Scans the whole formula rather than just `patch do` blocks: that scan SCOPE is
    unchanged from before 2026-09. The source did change, from `brew cat` to the
    keg copy -- see `_formula`."""
    text = formula_text(formula)
    if text is None:
        return None
    return _commits_in(text)


def homebrew_resolved_cves(formula: str):
    """{CVE ids} the INSTALLED formula declares its applied patches resolve, or None.

    THIS IS HOMEBREW ANSWERING THE QUESTION DIRECTLY, and until 2026-09-04 it was
    read past and thrown away. `commit_is_patched` scrapes a hash out of
    hand-written NVD prose and matches it against patch URLs; that is inference,
    and it missed all three CVEs reported against libssh2 1.11.1_4 even though the
    formula said, on the line under each patch, `resolves "CVE-2026-7598"`,
    `resolves "CVE-2026-58050"` and `resolves "CVE-2026-58051"`. Three HIGH false
    positives in one banner, and a banner that cries wolf stops being read.

    Three guards, because this is the one function here that can SILENCE a real
    finding:
      1. tap-sourced text is refused outright (None), since the tap can be ahead
         of what is installed;
      2. only patches whose enclosing blocks all apply to this build count;
      3. only quoted `CVE-YYYY-NNNN` values count -- `resolves` also carries
         non-CVE references, python@3.14 has `resolves
         "https://bugs.python.org/issue43976"`, and reading one of those as a CVE
         match would suppress a real finding."""
    if formula_source(formula) != "keg":
        return None
    blocks = homebrew_patch_blocks(formula)
    if blocks is None:
        return None
    return {c for b in blocks if b["applies"] for c in b["cves"]}


def _commit_matches(claimed, full) -> bool:
    """Does a hash claimed somewhere match a full 40-char patch commit?

    ONE definition, because the rule is subtle and a second copy would drift.
    Matching is substring-tolerant IN BOTH DIRECTIONS because NVD descriptions are
    hand-written and unreliable: CVE-2026-55200 says "fixed in commit 7acf3df"
    while the real hash is 97acf3dfda80... -- a dropped leading digit. Requiring a
    clean prefix match would miss it and leave a CRITICAL falsely flagged.
    Hashes shorter than 7 chars are ignored: too collision-prone to trust."""
    if not claimed or len(claimed) < 7:
        return False
    c = claimed.lower()
    return c in full or full.startswith(c)


def commit_is_patched(fix_commit, patch_commits) -> bool:
    """Is a CVE's fix commit among the formula's patches?  See `_commit_matches`."""
    if not fix_commit or not patch_commits:
        return False
    return any(_commit_matches(fix_commit, full) for full in patch_commits)


def is_patched_by_homebrew(formula, cve_id, fix_commit, patch_commits) -> bool:
    """Has Homebrew already backported the fix for `cve_id`?  Two signals, ORed.

    1. `resolves "CVE-..."` in the installed formula. AUTHORITATIVE: written by a
       maintainer beside a patch that must apply cleanly or the build fails.
    2. the CVE description's fix-commit hash appearing among the patch URLs.
       Best-effort, because it depends on NVD prose naming the hash at all.

    Signal 1 was added 2026-09-04, after signal 2 alone reported three
    already-patched libssh2 CVEs as live. Neither subsumes the other: a patch can
    carry a commit URL and no `resolves`, or a `resolves` and no URL.

    Do NOT gate this on the Homebrew revision. `revision > 0` looks like a proxy
    for "something was backported", and it is wrong: measured 2026-09-04, 12 of
    231 installed formulae carry `patch do` blocks at revision 0, openssl@3 and
    python@3.14 among them. A formula that bumps its version and its patch set in
    one commit resets the revision, and gating there would report exactly the
    false positive this function exists to remove."""
    if commit_is_patched(fix_commit, patch_commits):
        return True
    resolved = homebrew_resolved_cves(formula)
    return bool(cve_id and resolved and cve_id.upper() in resolved)


def unclaimed_patches(formula, patch_commits, claimed_commits):
    """Patch URLs nothing has explained -- neither a CVE's named fix commit nor the
    formula's own `resolves` field -- sorted, for the briefing to hand to a human.

    A patch Homebrew HAS labelled must never appear here: printing it would ask
    the reader to go and re-derive an answer the formula already gave them. A
    patch in a block that does not apply to this build stays in the list, because
    there the open question is real."""
    if not patch_commits:
        return []
    labelled = set()
    for b in (homebrew_patch_blocks(formula) or []):
        if b["cves"] and b["applies"]:
            labelled |= set(b["commits"])
    claimed = {c for c in (claimed_commits or []) if c}
    return sorted(url for sha, url in patch_commits.items()
                  if sha not in labelled
                  and not any(_commit_matches(c, sha) for c in claimed))


# --------------------------------------------------------------------------- #
#  Scan store (SQLite)                                                         #
# --------------------------------------------------------------------------- #
SCHEMA_VERSION = 1

_SCHEMA = """
CREATE TABLE IF NOT EXISTS meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS scanned (
    subject     TEXT NOT NULL,   -- "brew" | "pnpm" | "nvm" | "bun" | "claude"
    name        TEXT NOT NULL,
    version     TEXT NOT NULL,   -- upstream version, suffix stripped
    revision    INTEGER NOT NULL DEFAULT 0,
    cpe         TEXT,
    status      TEXT NOT NULL,   -- clean|exposed|unfixed|unknown|skipped|patched
    worst_score REAL,
    findings    TEXT NOT NULL DEFAULT '[]',
    scanned_at  INTEGER NOT NULL,
    PRIMARY KEY (subject, name, version, revision)
);
CREATE TABLE IF NOT EXISTS acks (
    subject TEXT NOT NULL,
    name    TEXT NOT NULL,
    cve_id  TEXT NOT NULL,
    until   INTEGER NOT NULL,
    reason  TEXT NOT NULL DEFAULT '',
    PRIMARY KEY (subject, name, cve_id)
);
CREATE TABLE IF NOT EXISTS cpe_absent (
    name       TEXT PRIMARY KEY,   -- formula_key(), confirmed to publish no CPE
    checked_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS scanned_status ON scanned(status);
"""
# cpe_absent is additive: CREATE TABLE IF NOT EXISTS runs on every connection
# regardless of SCHEMA_VERSION, so an existing database picks it up without a
# migration or a version bump -- bumping SCHEMA_VERSION would WIPE the acks and
# scan history a mismatch triggers a rebuild for (see ScanStore._connect).


class ScanStore:
    """Durable record of what has already been checked.

    THE KEY INCLUDES `revision` ON PURPOSE. A Homebrew revision bump is a content
    change -- it is how backported security patches ship -- so 1.11.1_3 and
    1.11.1_4 are different rows and a bump forces a rescan. Keying on version
    alone would mean a security update never gets re-examined.

    Opened with a busy timeout because two terminal tabs can start at the same
    moment; SQLite serialises them instead of one failing."""

    def __init__(self, path=None):
        if path is None:
            d = state_dir()
            path = os.path.join(d, "vuln-scan.db") if d else ":memory:"
        self.path = path
        self.conn = self._connect()

    def _connect(self):
        try:
            conn = sqlite3.connect(self.path, timeout=15.0)
            conn.row_factory = sqlite3.Row
            conn.executescript(_SCHEMA)
            cur = conn.execute("SELECT value FROM meta WHERE key='schema_version'")
            row = cur.fetchone()
            if row is None:
                conn.execute("INSERT INTO meta(key,value) VALUES('schema_version',?)",
                             (str(SCHEMA_VERSION),))
                conn.commit()
            elif int(row["value"]) != SCHEMA_VERSION:
                # Schema moved on. Rebuild rather than guess at a migration: the
                # data is a cache of a re-derivable fact, and a shell that cannot
                # start because of a stale database is a far worse outcome.
                conn.close()
                os.replace(self.path, self.path + ".old")
                return self._connect()
            return conn
        except (sqlite3.DatabaseError, OSError):
            # Corrupt or unwritable -> fall back to memory. The scan still works,
            # it just cannot remember; it must never take the shell down with it.
            conn = sqlite3.connect(":memory:")
            conn.row_factory = sqlite3.Row
            conn.executescript(_SCHEMA)
            self.path = ":memory:"
            return conn

    def known(self, subject, name, version, revision):
        cur = self.conn.execute(
            "SELECT * FROM scanned WHERE subject=? AND name=? AND version=? AND revision=?",
            (subject, name, version, revision))
        return cur.fetchone()

    def record(self, subject, name, version, revision, cpe, status, worst_score, findings):
        self.conn.execute(
            "INSERT OR REPLACE INTO scanned"
            " (subject,name,version,revision,cpe,status,worst_score,findings,scanned_at)"
            " VALUES (?,?,?,?,?,?,?,?,?)",
            (subject, name, version, revision, cpe, status, worst_score,
             json.dumps(findings), int(time.time())))

    def reap(self, subject, live_keys):
        """Drop rows for packages no longer installed (or downgraded).

        Without this an uninstalled package haunts the table forever, and a
        downgrade leaves the newer, cleaner row sitting alongside the older
        vulnerable one -- so a report built from the table would show a version
        that is not on the machine."""
        cur = self.conn.execute(
            "SELECT name,version,revision FROM scanned WHERE subject=?", (subject,))
        stale = [(subject, r["name"], r["version"], r["revision"]) for r in cur.fetchall()
                 if (r["name"], r["version"], r["revision"]) not in live_keys]
        if stale:
            self.conn.executemany(
                "DELETE FROM scanned WHERE subject=? AND name=? AND version=? AND revision=?",
                stale)
        return len(stale)

    def acked(self, subject, name, cve_id) -> bool:
        cur = self.conn.execute(
            "SELECT until FROM acks WHERE subject=? AND name=? AND cve_id=?",
            (subject, name, cve_id))
        row = cur.fetchone()
        return bool(row) and int(row["until"]) > int(time.time())

    def ack(self, subject, name, cve_id, days, reason=""):
        """Acknowledgements EXPIRE. A permanent mute is how a finding disappears
        for good; a 30-day one resurfaces so the decision gets made again."""
        self.conn.execute(
            "INSERT OR REPLACE INTO acks(subject,name,cve_id,until,reason) VALUES (?,?,?,?,?)",
            (subject, name, cve_id, int(time.time()) + days * 86400, reason))
        self.conn.commit()

    def absent_names(self) -> set:
        """Formula keys confirmed, by a live re-probe, to publish no CPE anywhere.
        A dynamic, DB-backed extension of the source-level CPE_ABSENT_OK set --
        see triage_unknowns() in vuln-scan for how a name gets in here. Kept in
        the DB rather than hand-curated in source: ~90 such facts is too many to
        maintain by hand without some of them going stale silently."""
        cur = self.conn.execute("SELECT name FROM cpe_absent")
        return {r["name"] for r in cur.fetchall()}

    def confirm_absent(self, name):
        self.conn.execute(
            "INSERT OR REPLACE INTO cpe_absent(name, checked_at) VALUES (?, ?)",
            (name, int(time.time())))

    def all_rows(self, subject=None):
        if subject:
            cur = self.conn.execute("SELECT * FROM scanned WHERE subject=? ORDER BY name", (subject,))
        else:
            cur = self.conn.execute("SELECT * FROM scanned ORDER BY subject, name")
        return cur.fetchall()

    def set_meta(self, key, value):
        self.conn.execute("INSERT OR REPLACE INTO meta(key,value) VALUES (?,?)",
                          (key, str(value)))

    def get_meta(self, key, default=None):
        cur = self.conn.execute("SELECT value FROM meta WHERE key=?", (key,))
        row = cur.fetchone()
        return row["value"] if row else default

    def commit(self):
        try:
            self.conn.commit()
        except sqlite3.DatabaseError:
            pass

    def close(self):
        try:
            self.conn.commit()
            self.conn.close()
        except sqlite3.DatabaseError:
            pass
