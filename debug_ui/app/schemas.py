from typing import List, Optional
from pydantic import BaseModel


class ConnectRequest(BaseModel):
    port: str
    timeout: float = 5.0


class LoadProgramRequest(BaseModel):
    words: List[int]  # instrucciones de 32 bits, ej. [0x00000013, 0x00100093, ...]


class HaltResult(BaseModel):
    halt_code: int
    halt_name: str


class StatusResponse(BaseModel):
    connected: bool
    port: Optional[str] = None