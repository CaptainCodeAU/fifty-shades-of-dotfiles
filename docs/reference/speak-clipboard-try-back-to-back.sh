#!/usr/bin/env bash
# PROTOTYPE, throwaway (dotfiles-main Q3): hear what a second press with a
# different profile should do while the first is still speaking.
#   1  replace          : B cuts A off after 3 s
#   2  queue, plain     : B starts after A ends, rendered from scratch
#   3  queue, prepared  : B rendered while A plays, played the moment A ends
#   4  overlap          : A and B start together and talk over each other
#   5  one player       : A then B through one ffplay, so the speakers never reopen
# Usage: try-back-to-back [1|2|3|4|all] [--swap] [--silent]   (--silent: no sound, for checking)
set -u
A_VOICE=en-US:natural:male:Aaron:premium:5030;   A_RATE=440; A_VOL=70
B_VOICE=en-US:natural:female:Simone:premium:5029; B_RATE=380; B_VOL=60
TEXT1="This is profile A. Aaron, at four hundred and forty words a minute. This is the first piece of text, long enough that there is time to cut it off part way through. Here is one more sentence, so it runs a little longer."
TEXT2="And this is profile B. Simone, a little slower and a little quieter. This is the second piece of text."
PREP="${TMPDIR:-/tmp}/try-back-to-back.prepared.pcm"   # overwritten each run

silent=0; which=all; swap=0
for a in "$@"; do case "$a" in --silent) silent=1 ;; --swap) swap=1 ;; 1|2|3|4|5|6|all) which="$a" ;; esac; done

if [ "$swap" = 1 ]; then   # Simone first, Aaron second; each keeps its own text
    tv=$A_VOICE; A_VOICE=$B_VOICE; B_VOICE=$tv; tr=$A_RATE; A_RATE=$B_RATE; B_RATE=$tr
    tl=$A_VOL; A_VOL=$B_VOL; B_VOL=$tl; tt=$TEXT1; TEXT1=$TEXT2; TEXT2=$tt
fi

now() { perl -MTime::HiRes=time -e 'printf "%.0f", time*1000'; }
t0=$(now)
log() { local ms=$(( $(now) - t0 )); printf '%3d.%02ds  %s\n' $((ms / 1000)) $(((ms % 1000) / 10)) "$*"; }

play() {   # PCM on stdin, volume $1
    if [ "$silent" = 1 ]; then cat >/dev/null; return; fi
    ffplay -nodisp -autoexit -infbuf -loglevel error -volume "$1" \
        -f s16le -ar 48000 -ch_layout mono -i -
}
render() { say2 -v "$1" -r "$2" --engine siri --format pcm -o - -- "$3" 2>/dev/null; }
speak_a() { render "$A_VOICE" "$A_RATE" "$TEXT1" | play "$A_VOL"; }
speak_b() { render "$B_VOICE" "$B_RATE" "$TEXT2" | play "$B_VOL"; }

demo1() {
    t0=$(now); echo; echo "== 1 REPLACE: second press cuts the first off =="
    log "press 1: profile A starts"
    set -m; ( speak_a ) & local pg=$!; set +m
    sleep 3
    log "press 2: profile B cuts A off"
    kill -KILL -- "-$pg" 2>/dev/null; wait "$pg" 2>/dev/null
    speak_b
    log "done"
}
demo2() {
    t0=$(now); echo; echo "== 2 QUEUE, PLAIN: B waits, then renders from scratch =="
    log "press 1: profile A starts (press 2 is waiting)"
    speak_a
    log "A ended: B starts rendering now"
    speak_b
    log "done"
}
demo3() {
    t0=$(now); echo; echo "== 3 QUEUE, PREPARED: B rendered while A plays =="
    log "press 1: profile A starts; B renders in the background"
    render "$B_VOICE" "$B_RATE" "$TEXT2" >"$PREP" & local r=$!
    speak_a
    wait "$r"
    log "A ended: B plays from the prepared audio"
    play "$B_VOL" <"$PREP"
    log "done"
}

demo4() {
    t0=$(now); echo; echo "== 4 OVERLAP: A and B at the same time =="
    log "press 1 and press 2 together"
    speak_a & local a=$!
    speak_b
    wait "$a"
    log "done"
}

demo5() {
    t0=$(now); echo; echo "== 5 ONE PLAYER: both voices through one ffplay, volume 70 =="
    log "first voice starts; second follows in the same stream"
    { render "$A_VOICE" "$A_RATE" "$TEXT1"; render "$B_VOICE" "$B_RATE" "$TEXT2"; } | play 70
    log "done"
}

# Volume inside the stream: samples times VOL/100, so one player (at 100) can
# carry voices at different volumes. Carries an odd byte across reads.
scale() { perl -e '$|=1; my $f=$ARGV[0]/100; my $c=""; while (sysread(STDIN, my $b, 8192)) { $b=$c.$b; my $n=length($b) & ~1; $c=substr($b,$n); syswrite(STDOUT, pack("s<*", map { int($_*$f) } unpack("s<*", substr($b,0,$n)))) }' "$1"; }
D6_TEXT1="This is Simone, at volume seventy. This is the first piece of text."
D6_TEXT2="And this is Aaron, at volume forty, at the same speed. This is the second piece of text."
demo6() {
    t0=$(now); echo; echo "== 6 ONE PLAYER, OWN VOLUMES: Simone 440 wpm vol 70, then Aaron 440 wpm vol 40 =="
    log "Simone starts; Aaron follows in the same stream"
    { render "$B_VOICE_S" 440 "$D6_TEXT1" | scale 70; render "$A_VOICE_A" 440 "$D6_TEXT2" | scale 40; } | play 100
    log "done"
}
A_VOICE_A=en-US:natural:male:Aaron:premium:5030; B_VOICE_S=en-US:natural:female:Simone:premium:5029

echo "first:  $(echo $A_VOICE | cut -d: -f4) $A_RATE wpm  volume $A_VOL"
echo "second: $(echo $B_VOICE | cut -d: -f4) $B_RATE wpm  volume $B_VOL"
case "$which" in
    1) demo1 ;; 2) demo2 ;; 3) demo3 ;; 4) demo4 ;; 5) demo5 ;; 6) demo6 ;;
    all) demo1; sleep 2; demo2; sleep 2; demo3; sleep 2; demo4 ;;
esac
