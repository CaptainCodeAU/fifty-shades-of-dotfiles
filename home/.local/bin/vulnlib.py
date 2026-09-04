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

# Ask Homebrew, in one process, what it actually applied to every installed keg.
#
# THIS REPLACED A HAND-WRITTEN RUBY PARSER, and the parser was not merely
# redundant -- it was measurably less accurate. It walked the formula text with a
# block stack to guess which `patch do` blocks belonged to this build. Measured
# 2026-09-04 against the answers below: bash has 15 patches and the parser saw 1;
# ollama's `patch :DATA` has no `do` at all so it was invisible; `resolves` is
# variadic (`def resolves(*cves)`) and only the first id was read; GHSA and OSV
# advisory ids were dropped; and `on_macos do` was treated as not-applying when on
# a Mac it plainly does. Every one of those errs toward reporting rather than
# silence, so none was a live hole -- but they were all drift against an evaluator
# that ships on the same machine and answers in 0.4s.
#
# `Formulary.factory` is pointed at the KEG's own copy, not the tap: `opt/<f>/.brew`
# is what was built and installed, while the tap can be many revisions ahead.
# `serialized_patches` is evaluated for the running OS and architecture, which is
# where the scope question the parser fumbled gets answered properly.
#
# Keyed by BOTH the opt directory and the formula's own name: 43 of 274 opt entries
# are alias symlinks whose `.brew` holds a differently-named file (`opt/openssl`
# contains `openssl@3.rb`), and callers may hold either spelling.
_PATCH_RUBY = r"""
require "formulary"
require "json"
out = {}
Dir.glob("#{HOMEBREW_PREFIX}/opt/*/.brew/*.rb").each do |path|
  keg = path.split("/")[-3]
  begin
    f = Formulary.factory(path)
    d = f.serialized_patches
  rescue Exception
    next
  end
  out[keg] = d
  out[f.name] = d unless out.key?(f.name)
end
puts JSON.generate(out)
"""

_PATCH_DATA = None
# Separate from the value, because None IS a meaningful value here -- it is the
# UNDETERMINED answer, and "we have not asked yet" must stay distinguishable from
# "we asked and could not tell". It is also the seam the selftest injects at.
_PATCH_DATA_FETCHED = False
_PATCH_ATTEMPTS = 0
_PATCH_MAX_ATTEMPTS = 2
# Only a comment that ATTRIBUTES the patch counts as naming its commit. Measured
# 2026-09-04 over 231 installed kegs: 12 comment lines cite a commit, and the
# convention splits them exactly 6/6. The 6 `Backport of <url>` lines are all
# libssh2 naming the upstream commit its vendored `file` patch carries -- the only
# place that hash appears, since a `file` patch has no url of its own. The other 6
# are prose citing a commit in a DIFFERENT project (ansible links pyca/bcrypt).
_BACKPORT_OF_RE = re.compile(r"backport of\b", re.IGNORECASE)
_FORMULA_CACHE = {}


def _valid_patch_map(data) -> bool:
    """Is this a whole-inventory answer we may act on?

    A SEPARATE FUNCTION SO IT CAN BE CONTROLLED. Folded inline it was unreachable
    from any test that did not fork a fake `brew`, and a validation nothing
    exercises is indistinguishable from no validation.

    An EMPTY MAP IS A FAILURE, NOT AN ANSWER. The Ruby wraps each keg in
    `rescue Exception; next`, which is right for one broken formula and wrong for
    a systemic break: rename `serialized_patches` upstream, or have the glob match
    nothing, and EVERY keg is skipped, `{}` is printed, and the exit code is 0.
    Accepting that would delete the resolves signal for the whole inventory with
    no diagnostic anywhere. `serialized_patches` is Homebrew internal API with no
    stability contract, so this is a when, not an if.

    The per-patch shape is checked too. Without it a shape change raises out of
    scan_one, and vuln-scan's __main__ catches only KeyboardInterrupt -- so a
    login shell would get a traceback from a module whose whole design is that an
    uncertain answer becomes UNDETERMINED."""
    if not isinstance(data, dict) or not data:
        return False
    return all(isinstance(v, list) and all(isinstance(p, dict) for p in v)
               for v in data.values())


def homebrew_patch_data():
    """{keg_or_formula_name: [patch, ...]} for every installed keg, or None.

    One `brew ruby` for the whole inventory, once per process: it costs ~0.4s to
    boot Homebrew's Ruby and then answers for all 274 kegs at once, so asking per
    formula would be absurd. Nothing on the shell-startup path reaches this --
    `scan_one` is only called for a cache miss, and returns before here unless NVD
    actually reported a CVE.

    None means UNDETERMINED and must never be read as "no patches": brew missing,
    the subprocess failing, an empty map, an unexpected shape, or unparseable
    output all land there, and every caller turns None into "cannot suppress"
    rather than "nothing was backported".

    Retried at most _PATCH_MAX_ATTEMPTS times per process, because one transient
    failure here costs the resolves signal for the ENTIRE inventory -- a
    background sweep is a single process covering all 231 formulae -- while an
    uncapped retry could add minutes to that same sweep. A missing `brew` is
    deterministic and is not retried at all.

    Not on the shell-startup path in the ordinary case: `scan_one` only runs on a
    cache miss and returns before here unless NVD reported a CVE. It IS reached at
    startup when the briefing is rewritten, which happens only when there is
    something actionable to write about."""
    global _PATCH_DATA, _PATCH_DATA_FETCHED, _PATCH_ATTEMPTS
    if _PATCH_DATA_FETCHED or _PATCH_ATTEMPTS >= _PATCH_MAX_ATTEMPTS:
        return _PATCH_DATA
    _PATCH_ATTEMPTS += 1
    brew = shutil.which("brew")
    if not brew:
        _PATCH_DATA_FETCHED = True          # deterministic; do not retry
        return None
    try:
        proc = subprocess.run([brew, "ruby", "-e", _PATCH_RUBY],
                              capture_output=True, text=True, timeout=180)
    except (subprocess.TimeoutExpired, OSError):
        return None
    if proc.returncode != 0:
        return None
    try:
        data = json.loads(proc.stdout)
    except ValueError:
        return None
    if not _valid_patch_map(data):
        return None
    _PATCH_DATA = data
    _PATCH_DATA_FETCHED = True
    return _PATCH_DATA


def homebrew_patches_for(formula: str):
    """The installed patches for one formula, or None if Homebrew did not answer.

    An installed formula with no patches returns `[]`. A formula Homebrew has never
    heard of returns None -- the difference matters, because `[]` is a fact and
    None is an absence of one, and only the fact may be used to silence a CVE."""
    data = homebrew_patch_data()
    if data is None:
        return None
    for key in (formula, formula.rsplit("/", 1)[-1]):
        if key in data:
            return data[key]
    return None


def _security_ids(patch) -> set:
    """The advisory ids a patch declares it fixes.

    Only `type == "security"` counts. Homebrew classifies CVE, GHSA and OSV ids as
    security (`patch.rb` CVE_PATTERN / GHSA_PATTERN / OSV_PATTERN) and everything
    else -- issue links, `defect` entries, bare bug numbers -- as not. Measured
    across 274 installed kegs: 20 patches carry a `resolves`, split 10 security and
    10 defect. Reading a defect id as an advisory id could only ever silence
    something it does not describe."""
    return {r["id"].upper() for r in (patch.get("resolves") or [])
            if r.get("type") == "security" and r.get("id")}


def _read_keg_formula(formula: str):
    """The formula Ruby that Homebrew copied INTO the keg at install time, or None.

    The keg copy, and ONLY the keg copy. There is deliberately no `brew cat`
    fallback: that prints whatever the tap holds right now, and 27 formulae on this
    machine currently have a tap ahead of the installed keg. Crediting a patch the
    tap has to a build that does not have it is a false all-clear, which is the one
    outcome this module exists to prevent."""
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
    # An alias keg holds the real formula under its canonical name (`opt/openssl`
    # contains `openssl@3.rb`). Only when there is exactly ONE candidate: more than
    # that is ambiguous, and guessing would answer about the wrong package.
    try:
        found = [f for f in os.listdir(brew_dir) if f.endswith(".rb")]
    except OSError:
        return None
    return read(os.path.join(brew_dir, found[0])) if len(found) == 1 else None


def formula_text(formula: str):
    """The installed formula's Ruby source, memoised, or None.  See
    `_read_keg_formula` for why the tap is never consulted."""
    if formula not in _FORMULA_CACHE:
        _FORMULA_CACHE[formula] = _read_keg_formula(formula)
    return _FORMULA_CACHE[formula]


def _commits_in(text: str):
    """{sha: url} for every upstream commit URL in `text`.  One canonicalisation
    of "lowercase the hash, strip the .patch suffix", used by every caller."""
    return {sha.lower(): url.split(".patch")[0]
            for url, sha in _PATCH_COMMIT_RE.findall(text or "")}


def backport_commits(formula: str):
    """{sha: url} for commits the keg formula ATTRIBUTES to a patch, or {}.

    Only `# Backport of <url>` lines. A vendored `file` patch has no url of its
    own, so that comment is the only place its upstream commit appears -- 6 of
    libssh2's 10 are exactly that.

    THE NARROWNESS IS THE POINT, and scanning the whole file instead re-opened
    the very scope error that deleting the hand parser removed. Measured
    2026-09-04 over 231 installed formulae, a whole-file scan added 13 commits
    beyond Homebrew's own `url` fields: 6 legitimate `Backport of` lines (all
    libssh2), and 7 that are not patches of the formula at all --

        ansible      -> pyca/bcrypt d50ab05b2b     libunistring -> gnulib bab130878f
        luajit       -> 7110b93567                 ollama       -> 0bb0925920
        ollama       -> 1f92170dc9                 x264         -> b5bc5d69c5
        zstd         -> db104f6e83

    ollama's 1f92170dc9 is the sharp one: it is a `patch do` inside
    `resource "llama.cpp"`, a patch to a BUNDLED DEPENDENCY's source.
    `serialized_patches` correctly excludes it; a whole-file regex put it back."""
    out = {}
    for line in (formula_text(formula) or "").splitlines():
        if _BACKPORT_OF_RE.search(line):
            out.update(_commits_in(line))
    return out


def homebrew_patch_commits(formula: str):
    """{commit_sha: patch_url} for patches applied to the installed formula, or None.

    The URL is kept, not just the hash, so a report can link straight to the real
    upstream commit instead of asking the reader to go and find it.

    Two sources, unioned: Homebrew's own `url` fields, which are exact, and the
    `# Backport of` attribution for vendored `file` patches -- see
    `backport_commits` for why that second source is deliberately narrow.

    A correction to what was recorded here on 2026-09-04: the population this
    second source was said to serve does not exist. "62 patches, 7 with a `file`
    and no `resolves`" double-counted the 43 alias entries in the keg map;
    deduplicated over 231 installed formulae it is 49 patches, of which 5 have
    neither url nor `resolves` (glib, lua, mlx-c, ollama, openldap) -- and NONE of
    them names a commit anywhere in its formula. The scan's real yield is
    libssh2's 6 attributed hashes, which `resolves` already covers. It still earns
    its place: it pins the briefing's "N patch(es) applied" at libssh2's true 10
    rather than 5, and it feeds `commit_is_patched` for any future patch that
    carries an attribution but no `resolves`."""
    patches = homebrew_patches_for(formula)
    text = formula_text(formula)
    if patches is None and text is None:
        return None
    out = {}
    for p in (patches or []):
        out.update(_commits_in(p.get("url")))
    out.update(backport_commits(formula))
    return out


def homebrew_resolved_cves(formula: str):
    """{advisory ids} Homebrew says its applied patches fix, or None.

    THIS IS HOMEBREW ANSWERING THE QUESTION DIRECTLY, and until 2026-09-04 it was
    read past and thrown away. The scanner inferred backports by scraping a commit
    hash out of hand-written NVD prose, which missed all three CVEs reported
    against libssh2 1.11.1_4 even though the formula said, under each patch,
    `resolves "CVE-2026-7598"`, `resolves "CVE-2026-58050"` and
    `resolves "CVE-2026-58051"`. Three HIGH false positives in one banner, and a
    banner that cries wolf stops being read.

    None, never an empty set, when Homebrew could not be asked -- see
    `homebrew_patch_data`."""
    patches = homebrew_patches_for(formula)
    if patches is None:
        return None
    return set().union(*[_security_ids(p) for p in patches]) if patches else set()


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

    1. Homebrew's own `resolves`, evaluated against the installed keg for the
       running platform. AUTHORITATIVE.
    2. the CVE description's fix-commit hash appearing among the patch URLs.
       Best-effort, and kept because 7 installed patches carry no `resolves` at
       all, so signal 1 cannot speak for them.

    Neither subsumes the other and neither can invent a fix that is not installed:
    both read the keg, never the tap.

    Do NOT gate this on the Homebrew revision. `revision > 0` looks like a proxy
    for "something was backported" and is wrong in both directions: 12 of 231
    installed formulae carry patches at revision 0, and ffmpeg carries revision 1
    with no patches at all."""
    if commit_is_patched(fix_commit, patch_commits):
        return True
    resolved = homebrew_resolved_cves(formula)
    return bool(cve_id and resolved and cve_id.upper() in resolved)


def annotate_hits(formula, hits, hypothetical=False):
    """Stamp `patched` on every hit, or None if Homebrew could not be asked.

    ONE implementation, because this exact block lived in both scanners before and
    THE COPIES DIVERGED: every false-positive fix after 2026-08-05 went into
    vulnlib only, so toolchain-cve-check kept reporting already-backported formulae
    such as libssh2 as EXPOSED. It happened a second time on 2026-09-04 -- vuln-scan
    gained the undetermined guard below and toolchain-cve-check did not, so one
    failed `brew ruby` there would have turned every backported formula in a
    231-formula sweep into EXPOSED. Twice is a pattern, so the decision lives here.

    None means UNDETERMINED, and the caller must report UNKNOWN. It must never be
    read as "not patched": a single failed subprocess covers the whole inventory,
    and a cry-wolf storm is how an alert stops being read.

    `hypothetical` is for a version that is NOT the one on disk (--brew-version).
    The installed formula describes a different artifact, so it is not consulted at
    all and every hit comes back unpatched -- the loud direction, and the only way a
    negative control proves anything. Decided PER FORMULA by the caller: asking
    about the version that IS installed is not hypothetical, and treating it so
    would throw away real backport detection."""
    if hypothetical:
        for h in hits:
            h["patched"] = False
        return hits
    if homebrew_patch_data() is None:
        return None
    patches = homebrew_patch_commits(formula)
    for h in hits:
        h["patched"] = is_patched_by_homebrew(
            formula, h["id"], h.get("fix_commit"), patches)
    return hits


def unclaimed_patches(formula, patch_commits, claimed_commits):
    """Patch URLs nothing has explained -- neither a CVE's named fix commit nor
    Homebrew's own `resolves` -- sorted, for the briefing to hand to a human.

    A patch Homebrew HAS labelled must never appear here: printing it would ask the
    reader to go and re-derive an answer the formula already gave them. When EVERY
    installed patch carries a security `resolves`, nothing about the formula is
    unexplained and the list is empty regardless of which hashes were matched --
    that is libssh2, whose ten patches all declare their CVE."""
    if not patch_commits:
        return []
    patches = homebrew_patches_for(formula)
    labelled, labelled_file_patch = set(), False
    for p in (patches or []):
        if not _security_ids(p):
            continue
        if p.get("url"):
            labelled |= set(_commits_in(p["url"]))
        else:
            labelled_file_patch = True
    # A vendored `file` patch has no url, so the ONLY place its upstream commit
    # appears is the `# Backport of <url>` comment above it -- 5 of libssh2's 10
    # are exactly that. Reading Homebrew's answer alone would leave those hashes
    # unlabelled and send the briefing off to ask a human about patches the
    # formula has already explained, which is what this function exists to stop.
    if labelled_file_patch:
        labelled |= set(backport_commits(formula))
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

    def known(self, subject, name, version, revision, max_age=None):
        """The cached row, or None if there is none -- or it is older than `max_age`.

        `max_age` (seconds) exists because THE KEY IS NOT ENOUGH. It is
        (subject, name, version, revision) with no time in it, so a row was reused
        for as long as the installed version held, and NVD is not a fixed
        function of a version: it re-analyses, corrects ranges, and publishes new
        CVEs against versions that have not moved.

        Measured 2026-09-04 on this machine: the python@3.14 row was written
        2026-08-18; NVD bounded CVE-2026-15308 at `versionEndExcluding 3.14.7` on
        2026-08-20; the banner went on reporting a fixed CVE as live for 17 days.
        97 of 231 rows were from 2026-08-03. The false positive is what got
        noticed, but the false NEGATIVE is the same bug and worse: a CVE published
        tomorrow against libssh2 1.11.1_4 would never be found, because nothing
        about that row changes. Without an age, this scanner can only discover a
        CVE at the moment a package version changes.

        None or 0 means never expire, which is the pre-2026-09-04 behaviour and is
        what a caller that has its own freshness policy should pass."""
        cur = self.conn.execute(
            "SELECT * FROM scanned WHERE subject=? AND name=? AND version=? AND revision=?",
            (subject, name, version, revision))
        row = cur.fetchone()
        if row is None or not max_age:
            return row
        return row if (time.time() - row["scanned_at"]) <= max_age else None

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
