import hashlib
import os
import sys
import threading
import urllib.request
import urllib.error

PROXY = "http://localhost:7890"
URL = "https://storage.googleapis.com/download.flutter.io/io/flutter/arm64_v8a_debug/1.0.0-4c525dac5ebe5971c5708ef73558ed8edcf4a362/arm64_v8a_debug-1.0.0-4c525dac5ebe5971c5708ef73558ed8edcf4a362.jar"
OUTPUT = r"C:\Users\15941\.gradle\caches\modules-2\files-2.1\io.flutter\arm64_v8a_debug\1.0.0-4c525dac5ebe5971c5708ef73558ed8edcf4a362\11c8d30e007f03e4475aaebfb3947267db83fd4d\arm64_v8a_debug-1.0.0-4c525dac5ebe5971c5708ef73558ed8edcf4a362.jar"
EXPECTED_SHA1 = "11c8d30e007f03e4475aaebfb3947267db83fd4d"
NUM_THREADS = 8

os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)

proxy_handler = urllib.request.ProxyHandler({
    "http": PROXY,
    "https": PROXY,
})
opener = urllib.request.build_opener(proxy_handler)
urllib.request.install_opener(opener)


def get_file_size():
    req = urllib.request.Request(URL, method="HEAD")
    with urllib.request.urlopen(req, timeout=30) as resp:
        size = int(resp.headers["Content-Length"])
        print(f"Total file size: {size} bytes ({size / 1024 / 1024:.2f} MB)")
        return size


def download_segment(seg_id: int, start: int, end: int, results: list):
    seg_path = OUTPUT + f".part{seg_id}"
    range_header = f"bytes={start}-{end}" if end else f"bytes={start}-"
    req = urllib.request.Request(URL, headers={"Range": range_header})
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            data = resp.read()
        with open(seg_path, "wb") as f:
            f.write(data)
        results[seg_id] = seg_path
        size_kb = len(data) / 1024
        print(f"  Segment {seg_id}: OK ({size_kb:.1f} KB)")
    except Exception as e:
        print(f"  Segment {seg_id}: FAILED - {e}")
        results[seg_id] = None


def main():
    print("Getting file size...")
    total = get_file_size()

    chunk = total // NUM_THREADS
    segments = []
    for i in range(NUM_THREADS):
        start = i * chunk
        end = (i + 1) * chunk - 1 if i < NUM_THREADS - 1 else total - 1
        segments.append((i, start, end))

    print(f"Downloading {NUM_THREADS} segments in parallel...")
    results = [None] * NUM_THREADS
    threads = []
    for seg_id, start, end in segments:
        t = threading.Thread(target=download_segment, args=(seg_id, start, end, results))
        threads.append(t)
        t.start()

    for t in threads:
        t.join()

    failures = [i for i, r in enumerate(results) if r is None]
    if failures:
        print(f"Failed segments: {failures}")
        sys.exit(1)

    print("Merging segments...")
    with open(OUTPUT, "wb") as out:
        for i in range(NUM_THREADS):
            seg_path = results[i]
            with open(seg_path, "rb") as f:
                out.write(f.read())
            os.remove(seg_path)

    print("Verifying SHA1...")
    sha1 = hashlib.sha1()
    with open(OUTPUT, "rb") as f:
        while True:
            chunk_data = f.read(8192)
            if not chunk_data:
                break
            sha1.update(chunk_data)
    actual = sha1.hexdigest()
    if actual == EXPECTED_SHA1:
        print(f"SHA1: {actual}  VERIFIED OK")
        print("Done!")
    else:
        print(f"SHA1: actual={actual}")
        print(f"SHA1: expected={EXPECTED_SHA1}")
        print("MISMATCH! File may be corrupted.")
        sys.exit(1)


if __name__ == "__main__":
    main()
