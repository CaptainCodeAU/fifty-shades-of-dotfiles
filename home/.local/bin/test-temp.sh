# test-temp.sh -- a test's own temporary folder, made under TMPDIR and sent to the Trash
# when the test ends, whichever way it ends: on success, on failure, on Ctrl-C, on TERM, on
# HUP and on a broken pipe (Gavin, 25 Oct 2026, record #3989; sessions of another project had
# left 31 test folders, 8.8 GB, in the shared temp folder). One file for bash 3.2 and later
# and for zsh. Source it; never run it. Guide: docs/TEST_TEMP_FOLDERS.md. Proof:
# test-temp --selftest.
#
#   . test-temp.sh new NAME [keep-on-fail] || exit 2   make NAME.XXXXXX; TT is its real path
#   . test-temp.sh adopt DIR [keep-on-fail] || exit 2  a folder the test made itself
#   tt_also PATH [keep-on-fail]                        one more path of the test's own
#   tt_on_end 'COMMAND'                                run COMMAND at the end, before the removal
#
# Keep the `|| exit 2`: when this file is missing (not stowed, a typo), `.` fails and both
# shells carry on with TT empty, so "$TT/work" would be /work.
#
# The folder goes in TMPDIR. With TMPDIR unset (Gavin, 25 Oct 2026): the macOS user temp
# folder (getconf DARWIN_USER_TEMP_DIR), else /tmp; never the shared /tmp/claude-<uid>.
# keep-on-fail keeps that folder when the test exits non-zero, and says where.
# adopt and tt_also take a mktemp-shaped name (NAME.XXXXXX, 6 or more letters or digits after
# the last dot) whose real folder is inside that temp folder, /tmp or the macOS user temp
# folder, and not inside the shared /tmp/claude-<uid> unless it is inside the temp folder too.
#
# Source it at the test's top level, before any trap of the test's own: it owns the EXIT,
# INT, TERM, HUP and PIPE traps. Put your own cleanup in tt_on_end, never in a trap of your
# own: a later `trap ... EXIT` replaces this one, and `test-temp check` then fails the run.
# An `exit` inside a tt_on_end command does not end the shell: it is noted, the removal still
# runs, and the test keeps its own exit status (the rest of that command still runs).
#
# THE END runs from the EXIT trap and from each signal trap; in zsh also from
# zshexit_functions. It acts once, only in the test's own process (a subshell, $(...) or &
# child that ends is not the test ending), and the test's exit status stays its own. After a
# signal it raises the same signal again, with its default action, so the caller sees the
# test die of it, and a bash loop that ran it stops as it does on Ctrl-C (exit 130, 143, 129
# or 141 only if that fails). Measured 25 Oct 2026, zsh 5.9: an EXIT trap alone misses
# Ctrl-C and TERM, and misses a `set -u` abort in `zsh -c` code; zshexit_functions misses an
# ERR_EXIT exit; so zsh gets both. And a zsh signal hands the removal to a fresh shell
# (_tt_sig says why).
#
# REMOVAL is through the Trash only, never for good: the account's ~/.local/bin/rm (the
# dotfiles Trash shim, checked for its marker when this file is sourced), run from / (the
# trash guard refuses a folder that holds the current folder), then `test -e` on each path.
# A path the Trash would not take stays where it is, and nothing else is tried (Gavin's
# ruling A155: Trash only).
#
# THE LIST. One line per event, appended to ${TEST_TEMP_DIR:-<the temp folder>}/.test-temp/list:
#   made|gone|refused|failed|kept <TAB> path <TAB> pid <TAB> epoch seconds <TAB> detail
# refused: the Claude sandbox refused the Trash (SANDBOX_RUNTIME=1, afpAccessDenied); a
# policy decides it. failed: the Trash would not take it anywhere else; check always fails
# that. `test-temp check` reads the list.
#
# REFUSED, with exit 2 (return 2 at a prompt, where nothing is set up): at an interactive
# prompt (its Ctrl-C trap would close the shell); sourced inside a zsh function (an EXIT trap
# set there fires when the function returns, and emulate -L drops the other traps); a trap of
# the test's own already set on EXIT, INT, TERM, HUP or PIPE (it would be replaced; an ignore,
# trap '' SIG, is left alone: bash 5 lists a signal its parent ignored the same way); no temp
# folder; no Trash shim carrying its marker; a name or path outside the rules above.
#
# Tests change the #P line in a COPY of this file, never through the environment (the
# pattern trash-guard uses, A185).

_TT_SHIM=""                                                   #P: shim (empty: the account's ~/.local/bin/rm)
_TT_MARK="PATH shim. Deletion goes to the Trash"
_TT_TAB=$(printf '\t')
_TT_NL='
'
# zsh's real pid (sysparams), loaded before the owner is first read, so the owner and the end
# read this process the same way.
if [ -n "${ZSH_VERSION-}" ]; then zmodload zsh/system 2>/dev/null || :; fi
# State, kept across a second source in the same shell (it adds a folder).
_TT_OWNER=${_TT_OWNER-}
_TT_PID=${_TT_PID-}
_TT_REG=${_TT_REG-}
_TT_ONEND=${_TT_ONEND-}
_TT_PROBES=${_TT_PROBES-}
_TT_DONE=${_TT_DONE-}
_TT_BASE=${_TT_BASE-}
_TT_ME=""
_TT_RM=${_TT_RM-}
_TT_LIST=${_TT_LIST-}
_TT_LISTDIR=${_TT_LISTDIR-}
_TT_R=""
_TT_S=""
_TT_P=""
_TT_WHY=""
_TT_KIND=""
_TT_SHARED=""
_TT_PF=""
_TT_ONEND_EXIT=""
TT=${TT-}

_tt_say() { printf 'test-temp: %s\n' "$*" >&2; }

# _tt_walk LIST FUNC: FUNC once per line of LIST (lines each ending in a newline), in order,
# in this very process: no subshell, so FUNC can set the caller's variables, and zsh's signal
# path starts no child. FUNC gets the line as $1; its status is not looked at (errexit).
_tt_walk() {
	local _tt_wrest=$1 _tt_wline
	while [ -n "$_tt_wrest" ]; do
		_tt_wline=${_tt_wrest%%"$_TT_NL"*}
		_tt_wrest=${_tt_wrest#*"$_TT_NL"}
		"$2" "$_tt_wline" || :
	done
}

# _tt_whoami: _TT_ME names this process, read without a subshell (one would change it):
# the real pid (zsh sysparams, bash 4 BASHPID) and the subshell depth (bash 3.2 has only that).
_tt_whoami() {
	if [ -n "${ZSH_VERSION-}" ]; then
		eval 'if (( ${+sysparams} )); then _TT_ME="${sysparams[pid]}:${ZSH_SUBSHELL:-0}"; else _TT_ME="$$:${ZSH_SUBSHELL:-0}"; fi'
	else
		_TT_ME="${BASHPID:-$$}:${BASH_SUBSHELL:-0}"
	fi
}

# _tt_strip PATH: _TT_S is PATH without its trailing slashes (/ stays /).
_tt_strip() {
	_TT_S=$1
	while [ "$_TT_S" != / ] && [ "${_TT_S%/}" != "$_TT_S" ]; do _TT_S=${_TT_S%/}; done
}

# _tt_real DIR: _TT_R is its physical path, empty when it cannot be entered (or is empty:
# cd "" would read as the current folder).
_tt_real() {
	if [ -z "${1-}" ]; then
		_TT_R=""
	elif [ -n "${ZSH_VERSION-}" ]; then
		_TT_R=$(builtin cd -q -P -- "$1" 2>/dev/null && pwd -P) || _TT_R=""
	else
		_TT_R=$(CDPATH='' builtin cd -P -- "$1" 2>/dev/null && pwd -P) || _TT_R=""
	fi
}

# _tt_base: _TT_BASE is the folder temp folders go in: TMPDIR; with TMPDIR unset (Gavin,
# 25 Oct 2026) the macOS user temp folder, else /tmp off macOS; never the shared
# /tmp/claude-<uid>. 1, and _TT_WHY, when there is none. TMPDIR set to the shared root is
# refused too (_TT_SHARED=1), for the helper and for run alike: a session with no folder of
# its own would leave its test folders there, which is record #3989's incident.
_tt_base() {
	local _tt_b=${TMPDIR-} _tt_u
	_TT_SHARED=""
	if [ -n "$_tt_b" ]; then
		_tt_strip "$_tt_b"
		_tt_u=$(id -u)
		_tt_real "$_TT_S"
		case "$_TT_S:$_TT_R" in
			"/tmp/claude-$_tt_u:"* | "/private/tmp/claude-$_tt_u:"* | *":/private/tmp/claude-$_tt_u" | *":/tmp/claude-$_tt_u")   # test-temp: allow the shared root, named to refuse it
				_TT_SHARED=1
				_TT_WHY="TMPDIR is the shared $_TT_S. This session has no temp folder of its own, so a sandboxed run would leave its folders in the shared folder. Run it outside the sandbox, or give the session its own folder"
				return 1
				;;
		esac
	else
		_tt_b=$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null) || _tt_b=""
		if [ -z "$_tt_b" ]; then
			if [ "$(uname -s 2>/dev/null)" = Darwin ]; then
				_TT_WHY="TMPDIR is not set, and getconf DARWIN_USER_TEMP_DIR gave nothing"
				return 1
			fi
			_tt_b=/tmp
		fi
	fi
	_tt_strip "$_tt_b"
	_TT_BASE=$_TT_S
	if [ ! -d "$_TT_BASE" ]; then
		_TT_WHY="the temp folder is not a folder: $_TT_BASE"
		return 1
	fi
	return 0
}

# _tt_resolve_rm: _TT_RM is the Trash shim, or _TT_WHY says why there is none.
_tt_resolve_rm() {
	local _tt_u _tt_h
	_TT_WHY=""
	if [ -n "$_TT_SHIM" ]; then
		_TT_RM=$_TT_SHIM
	else
		# The account's home from the user database, never $HOME: a test may point HOME at a
		# fixture before it sources this, and HOME is one assignment away for anyone.
		_tt_u=$(id -un 2>/dev/null) || _tt_u=""
		case "$_tt_u" in
			'' | *[!A-Za-z0-9._-]*) _TT_WHY="cannot tell this account's name (id -un)"; return 1 ;;
		esac
		_tt_h=$(eval "printf '%s' ~$_tt_u" 2>/dev/null) || _tt_h=""
		case "$_tt_h" in
			/*) ;;
			*) _TT_WHY="cannot find the home folder of $_tt_u"; return 1 ;;
		esac
		_TT_RM="$_tt_h/.local/bin/rm"
	fi
	if [ ! -f "$_TT_RM" ] || [ ! -x "$_TT_RM" ]; then
		_TT_WHY="no Trash shim at $_TT_RM (it ships in the dotfiles at ~/.local/bin/rm)"
		return 1
	fi
	if ! command grep -qF -- "$_TT_MARK" "$_TT_RM" 2>/dev/null; then
		_TT_WHY="$_TT_RM does not carry the Trash shim's marker ($_TT_MARK)"
		return 1
	fi
	return 0
}

# _tt_trash PATH: send PATH to the Trash through the shim, from /; 0 when it is gone after.
# Never any other route: a path the Trash does not take stays where it is. _TT_WHY says why,
# and _TT_KIND is refused (the Claude sandbox: SANDBOX_RUNTIME=1, which Claude Code sets
# there and nowhere else, and an afpAccessDenied) or failed (anything else).
_tt_trash() {
	local _tt_err
	_TT_WHY="" _TT_KIND=""
	if [ ! -e "$1" ] && [ ! -L "$1" ]; then return 0; fi
	if [ -z "$_TT_RM" ]; then
		_TT_KIND=failed _TT_WHY="no Trash shim"
		return 1
	fi
	_tt_err=$( (CDPATH='' builtin cd / && "$_TT_RM" -rf -- "$1") 2>&1 >/dev/null)
	if [ -e "$1" ] || [ -L "$1" ]; then
		_TT_KIND=failed
		case "$_tt_err" in
			*afpAccessDenied* | *"permission to access"*)
				if [ "${SANDBOX_RUNTIME-}" = 1 ]; then
					_TT_KIND=refused _TT_WHY="the sandbox refused the Trash (afpAccessDenied)"
				else
					_TT_WHY="the Trash was refused (afpAccessDenied), and this is not the Claude sandbox"
				fi
				;;
			'') _TT_WHY="still there after the Trash shim, which said nothing" ;;
			*)
				_TT_WHY=${_tt_err%%"$_TT_NL"*}
				_TT_WHY=${_TT_WHY//"$_TT_TAB"/ }
				_TT_WHY=${_TT_WHY:0:200}
				;;
		esac
		return 1
	fi
	return 0
}

# _tt_log_to LIST EVENT PATH PID DETAIL: append one event line.
_tt_log_to() {
	local _tt_d=${5-}
	_tt_d=${_tt_d//"$_TT_TAB"/ }
	_tt_d=${_tt_d//"$_TT_NL"/ }
	if ! printf '%s\t%s\t%s\t%s\t%s\n' "$2" "$3" "$4" "$(command date +%s)" "$_tt_d" >>"$1" 2>/dev/null; then
		_tt_say "cannot write the list $1 ($2 $3)"
		return 1
	fi
	return 0
}
_tt_log() { _tt_log_to "$_TT_LIST" "$1" "$2" "$_TT_PID" "${3-}"; }

# _tt_mktemp_shaped NAME: 0 when NAME looks made by mktemp: NAME.XXXXXX, a letter or digit
# first, 6 or more letters or digits after the last dot.
_tt_mktemp_shaped() {
	local _tt_sfx=${1##*.} _tt_pre=${1%.*}
	case "$1" in *.*) ;; *) return 1 ;; esac
	case "$_tt_sfx$_tt_pre" in *[!A-Za-z0-9._-]*) return 1 ;; esac
	case "$_tt_sfx" in *[!A-Za-z0-9]*) return 1 ;; esac
	case "$_tt_pre" in [A-Za-z0-9]*) ;; *) return 1 ;; esac
	[ "${#_tt_sfx}" -ge 6 ]
}

# _tt_check_path PATH: the rules for adopt and tt_also. _TT_P is the physical path, or the
# reason is said and 1 returned.
_tt_check_path() {
	local _tt_p _tt_b _tt_d _tt_tmp _tt_root _tt_ok _tt_shared
	case "$1" in
		/*) ;;
		*) _tt_say "REFUSED $1: not an absolute path"; return 1 ;;
	esac
	case "$1" in
		*"$_TT_TAB"* | *"$_TT_NL"*) _tt_say "REFUSED a path holding a tab or a newline"; return 1 ;;
	esac
	_tt_strip "$1"
	_tt_p=$_TT_S
	_tt_b=${_tt_p##*/}
	_tt_d=${_tt_p%/*}
	[ -n "$_tt_d" ] || _tt_d=/
	if ! _tt_mktemp_shaped "$_tt_b"; then
		_tt_say "REFUSED $_tt_p: not a mktemp-shaped name (NAME.XXXXXX: 6 or more letters or digits after the last dot)"
		return 1
	fi
	_tt_real "$_tt_d"
	if [ -z "$_TT_R" ]; then
		_tt_say "REFUSED $_tt_p: its folder $_tt_d cannot be entered"
		return 1
	fi
	if [ "$_TT_R" = / ]; then _TT_P="/$_tt_b"; else _TT_P="$_TT_R/$_tt_b"; fi
	# Empty when there is no temp folder; every use below checks, since "$_tt_tmp"/?* would
	# then match any path.
	_tt_real "$_TT_BASE"
	_tt_tmp=$_TT_R
	case "$_tt_tmp" in
		'') ;;
		"$_TT_P" | "$_TT_P"/*) _tt_say "REFUSED $_tt_p: it is the temp folder or holds it"; return 1 ;;
	esac
	_tt_ok=0
	for _tt_root in "$_tt_tmp" /tmp "$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null)"; do
		[ -n "$_tt_root" ] || continue
		_tt_real "$_tt_root"
		[ -n "$_TT_R" ] || continue
		case "$_TT_P" in "$_TT_R"/?*) _tt_ok=1 ;; esac
	done
	if [ "$_tt_ok" != 1 ]; then
		_tt_say "REFUSED $_tt_p: not inside a temp folder (TMPDIR, /tmp or the user temp folder)"
		return 1
	fi
	_tt_real "/tmp/claude-$(id -u)"   # test-temp: allow the shared root, to keep out of it
	_tt_shared=$_TT_R
	if [ -n "$_tt_shared" ]; then
		case "$_TT_P" in
			"$_tt_shared"/*)
				_tt_ok=0
				if [ -n "$_tt_tmp" ]; then
					case "$_TT_P" in "$_tt_tmp"/?*) _tt_ok=1 ;; esac
				fi
				if [ "$_tt_ok" != 1 ]; then
					_tt_say "REFUSED $_tt_p: inside the shared $_tt_shared but outside this test's temp folder"
					return 1
				fi
				;;
		esac
	fi
	return 0
}

# _tt_register FLAG PATH DETAIL: add one path to this process's list of things to remove.
_tt_register() {
	_TT_REG="$_TT_REG$1$_TT_TAB$2$_TT_NL"
	_tt_log made "$2" "$3"
}

# _tt_active: 0 when this file was sourced in this very process.
_tt_active() {
	_tt_whoami
	[ -n "${_TT_OWNER-}" ] && [ "$_TT_ME" = "$_TT_OWNER" ]
}

tt_also() {
	local _tt_k=-
	if ! _tt_active; then _tt_say "REFUSED tt_also: source test-temp.sh first, in this shell"; return 2; fi
	case "${2-}" in
		'') ;;
		keep-on-fail) _tt_k=k ;;
		*) _tt_say "REFUSED tt_also: unknown option '${2-}' (keep-on-fail is the only one)"; return 2 ;;
	esac
	_tt_check_path "${1-}" || return 2
	_tt_register "$_tt_k" "$_TT_P" also
	return 0
}

tt_on_end() {
	if ! _tt_active; then _tt_say "REFUSED tt_on_end: source test-temp.sh first, in this shell"; return 2; fi
	case "${1-}" in
		'') _tt_say "REFUSED tt_on_end: no command given"; return 2 ;;
		*"$_TT_NL"*) _tt_say "REFUSED tt_on_end: one line per command"; return 2 ;;
	esac
	_TT_ONEND="$_TT_ONEND$1$_TT_NL"
	return 0
}

# _tt_onend_one CMD: one tt_on_end command; a `return` in it returns from here, not from
# _tt_onend, so the loop and its clean-up below always finish.
_tt_onend_one() { eval "$1"; }

# _tt_onend RC: the test's own tt_on_end commands, in order; a failing one stops nothing. An
# `exit` in one would end the shell before anything went to the Trash, so while they run,
# exit is a function that notes the code and returns (no child is started: this also runs in
# zsh's signal path). bash in POSIX mode will not let a function take a special builtin's
# name, so POSIX mode is off meanwhile.
_tt_onend() {
	local _tt_posix=""
	[ -n "$_TT_ONEND" ] || return 0
	_TT_ONEND_EXIT=""
	if [ -n "${BASH_VERSION-}" ]; then
		case ":${SHELLOPTS-}:" in *:posix:*) _tt_posix=1; set +o posix ;; esac
	fi
	exit() { _TT_ONEND_EXIT=${1-$?}; return 0; }
	_tt_walk "$_TT_ONEND" _tt_onend_one
	unset -f exit
	[ -z "$_tt_posix" ] || set -o posix
	[ -z "$_TT_ONEND_EXIT" ] || _tt_say "a tt_on_end command called exit $_TT_ONEND_EXIT; the removal runs all the same, and the test keeps its own exit status ($1)"
	return 0
}

# _tt_begin RC: the first half of every end. 0 when this process goes on to remove its
# paths: the test's own process, the first time. It stops the signals and errexit, then runs
# the tt_on_end commands.
_tt_begin() {
	_tt_active || return 1
	[ -z "${_TT_DONE-}" ] || return 1
	_TT_DONE=1
	trap '' INT TERM HUP PIPE
	set +e +u
	_tt_onend "$1"
	return 0
}

# _tt_end [RC]: the end, from the EXIT trap and zshexit_functions. RC is given, or $? is the
# exit status.
_tt_end() {
	local _tt_rc=$?
	[ $# -gt 0 ] && _tt_rc=$1
	_tt_begin "$_tt_rc" || return "$_tt_rc"
	_tt_remove_all "$_tt_rc"
	return "$_tt_rc"
}

# _tt_sig SIG RC: a signal trap. bash runs a trap only between commands, so its end runs
# here. zsh can run a trap inside the builtin the signal interrupted (measured 25 Oct 2026,
# zsh 5.9 and 5.9.2: SIGPIPE during printf every time; INT during printf in 1 of 13 trials),
# and then every program started from there, or from the EXIT trap that follows, hangs for
# good: the forked child waits on a lock the builtin held, and never runs. So zsh runs the
# tt_on_end commands here and hands the removal to a fresh shell with exec, which starts no
# child. Either way the process then ends by SIG (_tt_reraise).
_tt_sig() {
	local _tt_sg=$1 _tt_rc=$2
	# A child that shares this trap (zsh keeps it in a subshell) dies of the signal, as it
	# would without the trap; nothing of the test's is touched.
	_tt_active || _tt_reraise "$_tt_sg" "$_tt_rc"
	_tt_begin "$_tt_rc" || return "$_tt_rc"
	# zsh: the fresh shell gets the two lists whole, as two arguments, and walks them itself.
	if [ -n "${ZSH_VERSION-}" ] && [ -n "$_TT_ENDSH" ] && [ -x "$_TT_ENDSH" ] && [ -f "$_TT_SELF" ]; then
		case "$_TT_ENDSH" in
			*zsh) exec "$_TT_ENDSH" -f -c 'h=$1; shift; . "$h" __end "$@"' test-temp-end "$_TT_SELF" \
				"$_tt_sg" "$_tt_rc" "$_TT_LIST" "$_TT_PID" "$_TT_PROBES" "$_TT_REG" ;;
			*) exec "$_TT_ENDSH" -c 'h=$1; shift; . "$h" __end "$@"' test-temp-end "$_TT_SELF" \
				"$_tt_sg" "$_tt_rc" "$_TT_LIST" "$_TT_PID" "$_TT_PROBES" "$_TT_REG" ;;
		esac
	fi
	_tt_remove_all "$_tt_rc"
	_tt_reraise "$_tt_sg" "$_tt_rc"
}

# _tt_reraise SIG RC: end this process by SIG with its default action, so the caller sees it
# die of the signal; a bash loop that ran it then stops, as it does after Ctrl-C. perl does
# it in place with exec, and can do what the shells will not (measured 25 Oct 2026): bash
# will not reset a signal it was started with ignored; zsh turns kill -HUP $$ into a plain
# exit 1; and bash 3.2 runs the trap with that signal blocked, a block that exec keeps, so
# perl unblocks it first. Without perl, the shell's own kill; RC only if both come back.
_tt_reraise() {
	local _tt_pl="" _tt_self=""
	if [ -x /usr/bin/perl ]; then
		_tt_pl=/usr/bin/perl
	elif [ -n "${ZSH_VERSION-}" ]; then
		eval '_tt_pl=${commands[perl]-}'
	else
		_tt_pl=$(command -v perl 2>/dev/null) || _tt_pl=""
	fi
	if [ -n "$_tt_pl" ]; then
		exec "$_tt_pl" -e 'use POSIX (); my ($s, $rc) = @ARGV;
			my %n = (INT => POSIX::SIGINT(), TERM => POSIX::SIGTERM(), HUP => POSIX::SIGHUP(), PIPE => POSIX::SIGPIPE());
			$SIG{$s} = "DEFAULT";
			POSIX::sigprocmask(POSIX::SIG_UNBLOCK(), POSIX::SigSet->new($n{$s})) if $n{$s};
			kill $s, $$; select(undef, undef, undef, 1); exit $rc' "$1" "$2"
	fi
	trap - "$1"
	if [ -n "${ZSH_VERSION-}" ]; then
		eval 'if (( ${+sysparams} )); then _tt_self=${sysparams[pid]}; else _tt_self=$$; fi'
	elif [ -n "${BASHPID-}" ]; then
		_tt_self=$BASHPID
	else
		_tt_self=$(exec sh -c 'echo "$PPID"' 2>/dev/null) || _tt_self=""
	fi
	[ -z "$_tt_self" ] || kill "-$1" "$_tt_self" 2>/dev/null
	exit "$2"
}

# _tt_end_mode __end SIG RC LIST PID PROBES REG: the removal half of a zsh signal, in the
# fresh shell _tt_sig started, then the re-raise. Internal: never call it. PROBES and REG are
# the two lists as they were; each line must still have its shape (a probe in a .test-temp
# folder; k<TAB>path or -<TAB>path, the path absolute and mktemp-shaped), and the trash guard
# judges every path.
_tt_end_mode() {
	local _tt_sg=${2-INT} _tt_rc=${3-1}
	case "$_tt_sg" in INT | TERM | HUP | PIPE) ;; *) _tt_sg=INT ;; esac
	_TT_LIST=${4-}
	_TT_PID=${5-}
	_TT_REG="" _TT_PROBES="" _TT_ONEND="" _TT_DONE=1
	_tt_walk "${6-}" _tt_take_probe
	_tt_walk "${7-}" _tt_take_reg
	if ! _tt_resolve_rm; then
		_tt_say "the end could not reach the Trash: $_TT_WHY"
		_TT_RM=""
	fi
	_tt_remove_all "$_tt_rc"
	_tt_reraise "$_tt_sg" "$_tt_rc"
}
_tt_take_probe() {
	case "$1" in /?*/.test-temp/trap-probe.*) _TT_PROBES="$_TT_PROBES$1$_TT_NL" ;; esac
	return 0
}
_tt_take_reg() {
	local _tt_p=${1#*"$_TT_TAB"}
	case "$1" in
		k"$_TT_TAB"/?* | -"$_TT_TAB"/?*) ;;
		*) return 0 ;;
	esac
	if _tt_mktemp_shaped "${_tt_p##*/}"; then
		_TT_REG="$_TT_REG$1$_TT_NL"
	else
		_tt_log failed "$_tt_p" "not a test-temp path, so the end left it"
	fi
	return 0
}

# _tt_remove_all RC: zsh's trap-table probes into the first folder (so they leave with it),
# then each registered path to the Trash, kept (keep-on-fail and RC not 0), refused (the
# sandbox) or failed. The three walks below read RC and the first folder from here.
_tt_remove_all() {
	local _tt_rc=$1 _tt_first=""
	_tt_walk "$_TT_REG" _tt_find_first
	_tt_walk "$_TT_PROBES" _tt_move_probe
	_tt_walk "$_TT_REG" _tt_remove_one
	return 0
}
_tt_find_first() {
	local _tt_p=${1#*"$_TT_TAB"}
	if [ -z "$_tt_first" ] && [ -d "$_tt_p" ] && [ ! -L "$_tt_p" ]; then _tt_first=$_tt_p; fi
	return 0
}
_tt_move_probe() {
	[ -e "$1" ] || return 0
	[ -n "$_tt_first" ] && command mv -n -- "$1" "$_tt_first/.test-temp-trap-probe.${1##*.}" 2>/dev/null
	[ -e "$1" ] && _tt_trash "$1"
	return 0
}
_tt_remove_one() {
	local _tt_k=${1%%"$_TT_TAB"*} _tt_p=${1#*"$_TT_TAB"}
	if [ ! -e "$_tt_p" ] && [ ! -L "$_tt_p" ]; then
		_tt_log gone "$_tt_p" "already gone"
	elif [ "$_tt_k" = k ] && [ "$_tt_rc" != 0 ]; then
		_tt_log kept "$_tt_p" "keep-on-fail, exit $_tt_rc"
		_tt_say "kept $_tt_p for the failed test (exit $_tt_rc)"
	elif _tt_trash "$_tt_p"; then
		_tt_log gone "$_tt_p" "to the Trash"
	else
		_tt_log "$_TT_KIND" "$_tt_p" "$_TT_WHY"
		_tt_say "$_tt_p stays where it is: $_TT_WHY"
	fi
	return 0
}

# _tt_prepare ACTION ARG [keep-on-fail]: every check that needs no trap and makes no folder.
_tt_prepare() {
	case "${1-}" in
		new | adopt) ;;
		*) _tt_say "REFUSED: usage: . test-temp.sh new NAME [keep-on-fail] | adopt DIR [keep-on-fail]"; return 1 ;;
	esac
	if [ $# -lt 2 ] || [ $# -gt 3 ]; then
		_tt_say "REFUSED: usage: . test-temp.sh $1 $([ "$1" = new ] && echo NAME || echo DIR) [keep-on-fail]"
		return 1
	fi
	case "${3-}" in
		'' | keep-on-fail) ;;
		*) _tt_say "REFUSED: unknown option '$3' (keep-on-fail is the only one)"; return 1 ;;
	esac
	if [ "$_TT_INFN" = 1 ]; then
		_tt_say "REFUSED: sourced inside a zsh function; source it at the test's top level (an EXIT trap set in a function fires when the function returns)"
		return 1
	fi
	if ! _tt_base; then
		_tt_say "REFUSED: $_TT_WHY"
		return 1
	fi
	_tt_whoami
	if [ "$_TT_ME" != "${_TT_OWNER-}" ]; then
		# First source in this process (or in a subshell of a test that has one): start clean,
		# so a subshell never removes its parent's folders.
		_TT_OWNER=$_TT_ME
		_TT_PID=${_TT_ME%%:*}
		_TT_REG=""
		_TT_ONEND=""
		_TT_PROBES=""
		_TT_DONE=""
	fi
	if ! _tt_resolve_rm; then
		_tt_say "REFUSED: $_TT_WHY; nothing would remove the folder"
		return 1
	fi
	_tt_strip "${TEST_TEMP_DIR:-$_TT_BASE}"
	_TT_LISTDIR="$_TT_S/.test-temp"
	_TT_LIST="$_TT_LISTDIR/list"
	if ! command mkdir -p -- "$_TT_LISTDIR" 2>/dev/null || ! command touch -- "$_TT_LIST" 2>/dev/null; then
		_tt_say "REFUSED: cannot write the list $_TT_LIST"
		return 1
	fi
	# zsh shows its trap table neither to a subshell nor inside a function (measured: a
	# function sees no EXIT trap of the top level), so the top level writes it into a probe
	# file made here, and _tt_traps_free reads it.
	_TT_PF=""
	if [ -n "${ZSH_VERSION-}" ]; then
		_TT_PF=$(command mktemp "$_TT_LISTDIR/trap-probe.XXXXXX" 2>/dev/null) || _TT_PF=""
		if [ -z "$_TT_PF" ]; then
			_tt_say "REFUSED: cannot read zsh's trap table (no probe file in $_TT_LISTDIR)"
			return 1
		fi
		_TT_PROBES="$_TT_PROBES$_TT_PF$_TT_NL"
	fi
	return 0
}

# _tt_traps_free: 0 when no trap but this file's own is set on EXIT, INT, TERM, HUP or PIPE.
# One of the test's own would be replaced, so refuse instead, naming each. An ignore
# (trap '' SIG) is left alone: bash 5 lists a signal its parent ignored the same way
# (measured), and refusing that would refuse every test such a parent runs. bash shows the
# traps to $(trap -p); zsh's are in the probe file.
_tt_traps_free() {
	local _tt_t _tt_e=""
	if [ -n "${ZSH_VERSION-}" ]; then
		_tt_t=$(<"$_TT_PF")
	else
		_tt_t=$(trap -p EXIT INT TERM HUP PIPE)
	fi
	_tt_walk "$_tt_t$_TT_NL" _tt_trap_line
	[ -z "$_tt_e" ] && return 0
	_tt_say "REFUSED: a trap of the test's own is already set on $_tt_e, and this file would replace it; source test-temp.sh first and move that cleanup into tt_on_end"
	if [ -n "$_TT_PF" ] && _tt_trash "$_TT_PF"; then
		_TT_PROBES=${_TT_PROBES%"$_TT_PF$_TT_NL"}
	fi
	return 1
}
_tt_trap_line() {
	local _tt_s
	case "$1" in
		*_tt_end* | *_tt_sig*) return 0 ;;
		"trap -- '' "*) return 0 ;;
		"TRAPEXIT ("* | "TRAPINT ("* | "TRAPTERM ("* | "TRAPHUP ("* | "TRAPPIPE ("*)
			_tt_s=${1%% (*}
			_tt_s=${_tt_s#TRAP}
			;;
		*" EXIT" | *" INT" | *" SIGINT" | *" TERM" | *" SIGTERM" | *" HUP" | *" SIGHUP" | *" PIPE" | *" SIGPIPE")
			_tt_s=${1##* }
			_tt_s=${_tt_s#SIG}
			;;
		*) return 0 ;;
	esac
	case " $_tt_e " in *" $_tt_s "*) ;; *) _tt_e="${_tt_e:+$_tt_e }$_tt_s" ;; esac
	return 0
}

# _tt_make ACTION ARG [keep-on-fail]: make (new) or take (adopt) the folder; TT is its path.
_tt_make() {
	local _tt_k=- _tt_d
	[ "${3-}" = keep-on-fail ] && _tt_k=k
	if [ "$1" = adopt ]; then
		# Without its trailing slashes first: [ -L "link/" ] follows the link (bash, measured).
		_tt_strip "$2"
		if [ ! -d "$_TT_S" ] || [ -L "$_TT_S" ]; then
			_tt_say "REFUSED adopt $2: not a folder, or a link"
			return 1
		fi
		_tt_check_path "$_TT_S" || return 1
		TT=$_TT_P
		_tt_register "$_tt_k" "$TT" adopt
		return 0
	fi
	case "$2" in
		'' | [!A-Za-z0-9]* | *[!A-Za-z0-9._-]*)
			_tt_say "REFUSED new '$2': a name is letters, digits, dot, underscore and hyphen, starting with a letter or digit"
			return 1
			;;
	esac
	if [ "${#2}" -gt 64 ]; then
		_tt_say "REFUSED new: the name is longer than 64 characters"
		return 1
	fi
	# An explicit template: bare `mktemp -d` and `mktemp -d -t` ignore TMPDIR on macOS.
	_tt_d=$(command mktemp -d "$_TT_BASE/$2.XXXXXX" 2>/dev/null) || _tt_d=""
	if [ -z "$_tt_d" ] || [ ! -d "$_tt_d" ]; then
		_tt_say "REFUSED new: cannot make a folder in $_TT_BASE"
		return 1
	fi
	_tt_real "$_tt_d"
	if [ -z "$_TT_R" ]; then
		_tt_say "REFUSED new: cannot enter the folder just made, $_tt_d"
		return 1
	fi
	TT=$_TT_R
	_tt_register "$_tt_k" "$TT" new
	return 0
}

# ---------------------------------------------------------------------------- top level
# The traps are set here, at the file's top level, never inside a function: in zsh an EXIT
# trap set inside a function fires when that function returns.
_tt_t=""
_TT_INFN=0
_TT_ENDSH=""
if [ -n "${ZSH_VERSION-}" ]; then
	# Read here, at the top level and never through eval: a function or an eval adds an entry.
	_tt_t=${zsh_eval_context[-1]-}
	[ "$_tt_t" = file ] || _tt_t=run
	case " ${zsh_eval_context[*]-} " in *" shfunc "*) _TT_INFN=1 ;; esac
	_TT_SELF=${(%):-%x}
	# The shell a zsh signal hands the removal to (_tt_sig): either shell runs this file.
	for _TT_ENDSH in /bin/zsh /usr/bin/zsh "${commands[zsh]-}" /bin/bash /usr/bin/bash ""; do
		[ -n "$_TT_ENDSH" ] && [ -x "$_TT_ENDSH" ] && break
	done
else
	[ "${BASH_SOURCE[0]-}" = "$0" ] && _tt_t=run
	_TT_SELF=${BASH_SOURCE[0]-}
fi
case "$_TT_SELF" in /*) ;; *) _TT_SELF="$PWD/$_TT_SELF" ;; esac
if [ "$_tt_t" = run ]; then
	_tt_say "source this file (. test-temp.sh new NAME), do not run it"
	exit 2
fi
unset _tt_t
if [ "${1-}" = lib ]; then
	# For the test-temp command: the functions, and the shim when there is one (_TT_RM is
	# empty and _TT_WHY says why when not); no folder and no trap.
	_tt_resolve_rm || _TT_RM=""
	return 0
fi
if [ "${1-}" = __end ]; then
	_tt_end_mode "$@"
	exit $?
fi
case $- in
	*i*)
		_tt_say "REFUSED at an interactive prompt: its Ctrl-C trap would close this shell; source it in a test script"
		return 2
		;;
esac
_tt_prepare "$@" || exit 2
[ -n "$_TT_PF" ] && trap >>"$_TT_PF"
_tt_traps_free || exit 2
trap '_tt_end' EXIT
trap '_tt_sig INT 130; exit 130' INT
trap '_tt_sig TERM 143; exit 143' TERM
trap '_tt_sig HUP 129; exit 129' HUP
trap '_tt_sig PIPE 141; exit 141' PIPE
if [ -n "${ZSH_VERSION-}" ]; then
	# Also from zshexit_functions: it runs on a `set -u` abort in `zsh -c` code, where zsh's
	# EXIT trap does not.
	eval '(( ${zshexit_functions[(Ie)_tt_end]-0} )) || zshexit_functions+=(_tt_end)'
fi
_tt_make "$@" || exit 2
