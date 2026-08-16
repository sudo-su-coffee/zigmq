#!/usr/bin/env python3
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "python"))
from zigmq import ZigmqCore


core = ZigmqCore()
assert core.version == "0.2.0"
assert core.validate_subject("sensors.*", allow_wildcards=True)
assert core.matches("sensors.*", "sensors.room")
assert not core.matches("sensors.*", "sensors.room.temp")
assert core.hash64("hello") == 11831194018420276491
assert core.encode_pub("bench", b"hello") == b"PUB 5 5\r\nbenchhello\r\n"
print("PYTHON_FFI_OK")
