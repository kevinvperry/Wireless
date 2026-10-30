#!/usr/bin/env python3
"""Serve generated AAC and rolling packed-AAC HLS for optional simulator tests.

Run on macOS with Python 3 and Apple's bundled afconvert. This synthetic tone
cannot establish successful song recognition. Nothing is downloaded or recorded.
"""
import http.server
import math
import pathlib
import re
import shutil
import struct
import subprocess
import tempfile
import time
import wave


def syncsafe(value):
    return bytes((value >> shift) & 127 for shift in (21, 14, 7, 0))


def main():
    converter = shutil.which('afconvert')
    if not converter:
        raise SystemExit('This fixture needs macOS afconvert.')
    with tempfile.TemporaryDirectory(prefix='wireless-shazamkit-') as folder:
        root = pathlib.Path(folder)
        second = b''.join(struct.pack('<h', int(5000 * math.sin(2 * math.pi * 440 * i / 44100)))
                          for i in range(44100))
        for name, seconds in [('tone', 60), ('short', 2)]:
            source = root / f'{name}.wav'
            with wave.open(str(source), 'wb') as audio:
                audio.setnchannels(1)
                audio.setsampwidth(2)
                audio.setframerate(44100)
                for _ in range(seconds):
                    audio.writeframesraw(second)
            subprocess.run([converter, '-f', 'adts', '-d', 'aac', str(source), str(root / f'{name}.aac')], check=True)
        aac = (root / 'short.aac').read_bytes()
        direct = (root / 'tone.aac').read_bytes()
        offset = frames = 0
        while offset + 7 <= len(aac):
            if aac[offset] != 255 or aac[offset + 1] & 240 != 240:
                raise ValueError('Unexpected ADTS header')
            length = ((aac[offset + 3] & 3) << 11) | (aac[offset + 4] << 3) | (aac[offset + 5] >> 5)
            if length < 7:
                raise ValueError('Invalid ADTS length')
            frames += 1024 * ((aac[offset + 6] & 3) + 1)
            offset += length
        duration = frames / 44100
        started = time.monotonic() - duration * 5

        def segment(sequence):
            timestamp = round(sequence * duration * 90000) & ((1 << 33) - 1)
            payload = b'com.apple.streaming.transportStreamTimestamp\0' + struct.pack('>Q', timestamp)
            frame = b'PRIV' + syncsafe(len(payload)) + b'\0\0' + payload
            return b'ID3\x04\0\0' + syncsafe(len(frame)) + frame + aac

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                path = self.path.split('?')[0]
                match = re.fullmatch(r'/segment-(\d+)\.aac', path)
                if path == '/tone.m3u8':
                    latest = max(3, int((time.monotonic() - started) / duration))
                    first = latest - 3
                    text = (f'#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:{math.ceil(duration)}\n'
                            f'#EXT-X-MEDIA-SEQUENCE:{first}\n')
                    text += ''.join(f'#EXTINF:{duration:.9f},\n/segment-{n}.aac\n'
                                    for n in range(first, latest + 1))
                    data, kind = text.encode(), 'application/vnd.apple.mpegurl'
                elif match:
                    data, kind = segment(int(match[1])), 'audio/aac'
                elif path == '/tone.aac':
                    data, kind = direct, 'audio/aac'
                else:
                    self.send_error(404)
                    return
                self.send_response(200)
                self.send_header('Content-Type', kind)
                self.send_header('Content-Length', str(len(data)))
                self.send_header('Cache-Control', 'no-store')
                self.end_headers()
                try:
                    self.wfile.write(data)
                except (BrokenPipeError, ConnectionResetError):
                    pass

        server = http.server.ThreadingHTTPServer(('127.0.0.1', 18742), Handler)
        print('Serving synthetic Wireless audio on http://127.0.0.1:18742 (Ctrl-C to stop)', flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
        finally:
            server.server_close()


if __name__ == '__main__':
    main()
