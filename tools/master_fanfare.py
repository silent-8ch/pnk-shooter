"""Masters the fanfare (assets/music/k620-overture-the-magic-flute-motif.wav)
into k620-fanfare.wav: trims the silence at the start, brings it up to about
the loudness of the other tracks (GAIN) and soft-limits the peaks so nothing
clips. Run: python3 -I tools/master_fanfare.py"""
import array, math, os, wave

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "assets", "music", "k620-overture-the-magic-flute-motif.wav")
DST = os.path.join(HERE, "..", "assets", "music", "k620-fanfare.wav")
GAIN = 3.6  # about +11 dB
KNEE = 0.7  # of full scale: above this the limiter rounds peaks off
SILENCE = 200  # samples quieter than this count as silence
LEAD_IN = 0.02  # s of the silence kept before the first note


def limit(x: float) -> float:
    m = abs(x)
    if m <= KNEE:
        return x
    return math.copysign(KNEE + (1.0 - KNEE) * math.tanh((m - KNEE) / (1.0 - KNEE)), x)


def main() -> None:
    src = wave.open(SRC, "rb")
    ch, width, rate = src.getnchannels(), src.getsampwidth(), src.getframerate()
    assert width == 2, "16-bit only"
    data = array.array("h", src.readframes(src.getnframes()))
    src.close()
    first = next(i for i, v in enumerate(data) if abs(v) > SILENCE)
    first = max(0, first - first % ch - int(LEAD_IN * rate) * ch)
    out = array.array("h", (int(round(limit(v / 32768.0 * GAIN) * 32767)) for v in data[first:]))
    dst = wave.open(DST, "wb")
    dst.setnchannels(ch)
    dst.setsampwidth(2)
    dst.setframerate(rate)
    dst.writeframes(out.tobytes())
    dst.close()
    print("trimmed %.2f s, wrote %s" % (first / ch / rate, DST))


if __name__ == "__main__":
    main()
