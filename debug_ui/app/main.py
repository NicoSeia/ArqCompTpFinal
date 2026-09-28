"""
main.py
API REST minima para controlar el pipeline RISC-V via la Debug Unit (UART).

Arranque:
    uvicorn app.main:app --reload
Docs interactivas (Swagger) en http://localhost:8000/docs
"""
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import serial.tools.list_ports

from .serial_link import link, DebugUnitError
from .schemas import ConnectRequest, LoadProgramRequest, HaltResult, StatusResponse

app = FastAPI(title="RISC-V Debug Unit API", version="0.1.0")

# CORS abierto: lo vamos a necesitar apenas agreguemos un frontend en otro puerto
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


def _wrap(fn, *args, **kwargs):
    """Convierte errores del link serie en HTTP 409 con el motivo, en vez
    de un 500 generico."""
    try:
        return fn(*args, **kwargs)
    except DebugUnitError as e:
        raise HTTPException(status_code=409, detail=str(e))


@app.get("/ports")
def list_ports():
    """Puertos serie disponibles en esta PC, para elegir cual usar en /connect."""
    return [p.device for p in serial.tools.list_ports.comports()]


@app.post("/connect")
def connect(req: ConnectRequest):
    _wrap(link.connect, req.port, req.timeout)
    return {"connected": True, "port": req.port}


@app.post("/disconnect")
def disconnect():
    link.disconnect()
    return {"connected": False}


@app.get("/status", response_model=StatusResponse)
def status():
    return StatusResponse(connected=link.is_open, port=link.port)


@app.post("/reset")
def reset():
    _wrap(link.reset)
    return {"ok": True}


@app.post("/load")
def load_program(req: LoadProgramRequest):
    """Llamar despues de /reset: RESET reinicia el contador de carga a 0,
    y cada LOAD_WORD escribe en la siguiente direccion de instruccion."""
    _wrap(link.load_program, req.words)
    return {"loaded": len(req.words)}


@app.post("/run", response_model=HaltResult)
def run():
    return _wrap(link.run)


@app.post("/step", response_model=HaltResult)
def step():
    return _wrap(link.step)


@app.get("/regs")
def dump_regs():
    return {"registers": _wrap(link.dump_regs)}


@app.get("/mem")
def dump_mem(addr: int, length: int):
    raw = _wrap(link.dump_mem, addr, length)
    return {"addr": addr, "length": length, "bytes": raw.hex()}


@app.get("/latches")
def dump_latches():
    return _wrap(link.dump_latches)