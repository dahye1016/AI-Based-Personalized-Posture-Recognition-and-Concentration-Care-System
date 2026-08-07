"""
PoseLab Core 보드 Serial(Lite) 프로토콜 파서.

★ 왜 파서를 갈아끼울 수 있게 만들었나
   벤더 wiki 의 '소스코드 다운로드(Lite)' zip 안에 있는 .ino 를 봐야
   정확한 출력 포맷이 확정됩니다. 그런데 wiki 설명에
   "Serial Monitor baud = 2,000,000 / 센서를 누르면 출력값이 변합니다"
   라고 되어 있으므로 사람이 읽을 수 있는 ASCII 텍스트 출력이 거의 확실합니다.
   그래서 ASCII 파서를 기본으로 두고, 아니면 바이너리로 자동 전환합니다.

   → 일요일에 실물 붙였을 때 포맷이 다르면 이 파일의 클래스 하나만 고치면 됩니다.
     나머지 코드(features / server / app)는 전혀 건드릴 필요 없습니다.
"""

import re
import struct
from typing import Iterator, List, Optional

from layout import N_CHANNELS

BAUDRATE = 2_000_000  # wiki 명시값. 절대 115200 아님.

_NUM = re.compile(rb"-?\d+")


class ParserBase:
    name = "base"

    def feed(self, chunk: bytes) -> Iterator[List[int]]:
        raise NotImplementedError


class AsciiParser(ParserBase):
    """
    한 줄에 32개 숫자가 구분자(콤마/공백/탭)로 오는 형식.
    예)  "12,0,340,1201,...,88\n"
    앞에 'DATA:' 같은 접두어가 붙어도 숫자만 뽑아내므로 상관없습니다.
    """

    name = "ascii"

    def __init__(self, n: int = N_CHANNELS):
        self.n = n
        self._buf = bytearray()

    def feed(self, chunk: bytes) -> Iterator[List[int]]:
        self._buf.extend(chunk)
        while True:
            idx = self._buf.find(b"\n")
            if idx < 0:
                if len(self._buf) > 1 << 16:      # 개행이 안 오면 버퍼 폭주 방지
                    del self._buf[:-4096]
                break
            line = bytes(self._buf[:idx])
            del self._buf[: idx + 1]
            nums = [int(m.group()) for m in _NUM.finditer(line)]
            if len(nums) == self.n:
                yield nums
            elif len(nums) == self.n + 1:
                # 맨 앞에 프레임 카운터가 붙는 형식이면 그것만 버림
                yield nums[1:]


class BinaryParser(ParserBase):
    """
    헤더(2바이트) + uint16 little-endian * 32 형식.
    Lite 가 바이너리였을 경우를 위한 대비책입니다.
    """

    name = "binary"

    def __init__(self, header: bytes = b"\xaa\x55", n: int = N_CHANNELS):
        self.header = header
        self.n = n
        self.frame_len = len(header) + 2 * n
        self._buf = bytearray()

    def feed(self, chunk: bytes) -> Iterator[List[int]]:
        self._buf.extend(chunk)
        while True:
            idx = self._buf.find(self.header)
            if idx < 0 or len(self._buf) - idx < self.frame_len:
                if idx > 0:
                    del self._buf[:idx]
                break
            body = bytes(self._buf[idx + len(self.header): idx + self.frame_len])
            del self._buf[: idx + self.frame_len]
            yield list(struct.unpack("<%dH" % self.n, body))


def sniff(sample: bytes) -> ParserBase:
    """
    초기 수신 바이트를 보고 ASCII / Binary 를 자동 판별합니다.
    출력 가능 문자 비율이 85% 넘으면 ASCII 로 봅니다.
    """
    if not sample:
        return AsciiParser()
    printable = sum(1 for b in sample if 32 <= b < 127 or b in (9, 10, 13))
    return AsciiParser() if printable / len(sample) > 0.85 else BinaryParser()


def find_port(hint: Optional[str] = None) -> Optional[str]:
    """
    Core 보드가 꽂힌 시리얼 포트를 찾습니다.
    ESP32-S3 는 보통 USB CDC(303a:1001) 또는 CH340/CP210x 로 잡힙니다.
    """
    try:
        from serial.tools import list_ports
    except ImportError:
        return hint

    ports = list(list_ports.comports())
    if hint:
        for p in ports:
            if hint.lower() in (p.device or "").lower():
                return p.device
        return hint

    KEYWORDS = ("usb single serial", "esp32", "cp210", "ch340",
                "usb serial", "usbmodem", "wchusbserial", "slab")
    for p in ports:
        blob = " ".join(filter(None, [p.device, p.description, p.manufacturer])).lower()
        if any(k in blob for k in KEYWORDS):
            return p.device
    return ports[0].device if ports else None
